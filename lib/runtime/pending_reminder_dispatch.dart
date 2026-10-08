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
  await db.transaction((txn) async {
    if (await readPendingDispatch(txn) != encoded) return;
    if (!submitted) {
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
      'last_evaluation_outcome': submitted
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
