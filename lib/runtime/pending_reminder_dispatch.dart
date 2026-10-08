import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

// Shared with the native receiver. Only undo values and IDs are persisted;
// learning content is always read from review_items.
const pendingDispatchLease = Duration(minutes: 3);

Future<String?> readPendingDispatch(DatabaseExecutor db) async {
  final rows = await db.query(
    'reminder_runtime_state',
    columns: ['pending_dispatch_json'],
    where: 'id = 1',
  );
  return rows.single['pending_dispatch_json'] as String?;
}

DateTime pendingDispatchRetryAt(String encoded) {
  final row = jsonDecode(encoded) as Map<String, dynamic>;
  return DateTime.fromMicrosecondsSinceEpoch(
    row['dispatch_at_us'] as int,
    isUtc: true,
  ).add(pendingDispatchLease);
}

bool pendingDispatchWasAccepted(String encoded) {
  final row = jsonDecode(encoded) as Map<String, dynamic>;
  return row['notification_accepted'] == true;
}

Future<bool> markPendingDispatchAccepted(Database db, String token) async {
  return db.transaction((txn) async {
    final encoded = await readPendingDispatch(txn);
    if (encoded == null) return false;
    final row = jsonDecode(encoded) as Map<String, dynamic>;
    if (row['dispatch_token'] != token) return false;
    row['notification_accepted'] = true;
    return await txn.update(
          'reminder_runtime_state',
          {'pending_dispatch_json': jsonEncode(row)},
          where: 'id = 1 AND pending_dispatch_json = ?',
          whereArgs: [encoded],
        ) ==
        1;
  });
}

Future<bool> markPendingDispatchFenced(
  Database db,
  String token, {
  required bool submitted,
}) async {
  return db.transaction((txn) async {
    final encoded = await readPendingDispatch(txn);
    if (encoded == null) return false;
    final row = jsonDecode(encoded) as Map<String, dynamic>;
    if (row['dispatch_token'] != token) return false;
    row['dispatch_fenced'] = true;
    row['notification_accepted'] =
        submitted || row['notification_accepted'] == true;
    return await txn.update(
          'reminder_runtime_state',
          {'pending_dispatch_json': jsonEncode(row)},
          where: 'id = 1 AND pending_dispatch_json = ?',
          whereArgs: [encoded],
        ) ==
        1;
  });
}

bool pendingDispatchIsLive(String encoded, DateTime now) {
  final row = jsonDecode(encoded) as Map<String, dynamic>;
  return row['owner_pid'] == pid &&
      now.isBefore(pendingDispatchRetryAt(encoded));
}

Future<void> recoverPendingDispatch(
  Database db,
  String encoded, {
  required bool submitted,
  required DateTime now,
}) async {
  final row = jsonDecode(encoded) as Map<String, dynamic>;
  final accepted = submitted || row['notification_accepted'] == true;
  await db.transaction((txn) async {
    if (await readPendingDispatch(txn) != encoded) return;
    if (!accepted) {
      await txn.update(
        'review_items',
        {
          'last_shown_at_us': row['previous_item_at_us'],
          'reminder_count': row['previous_count'],
        },
        where: 'id = ? AND last_shown_at_us = ?',
        whereArgs: [row['item_id'], row['dispatch_at_us']],
      );
      await txn.update(
        'topics',
        {'last_reminded_at_us': row['previous_topic_at_us']},
        where: 'id = ? AND last_reminded_at_us = ?',
        whereArgs: [row['topic_id'], row['dispatch_at_us']],
      );
    }
    await txn.update('reminder_runtime_state', {
      'pending_dispatch_json': null,
      'last_evaluation_at_us': now.microsecondsSinceEpoch,
      'last_evaluation_outcome': accepted
          ? 'notification_submitted'
          : 'dispatch_recovered',
      if (!submitted) ...{
        'last_dispatch_at_us': row['previous_dispatch_at_us'],
        'last_dispatch_item_id': row['previous_dispatch_item_id'],
        'last_dispatch_topic_id': row['previous_dispatch_topic_id'],
      },
    }, where: 'id = 1');
  });
}
