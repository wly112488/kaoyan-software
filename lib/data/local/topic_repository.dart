import 'package:sqflite/sqflite.dart';

import '../../domain/topic.dart';
import 'app_database.dart';

final class TopicRepository {
  TopicRepository(this._store);

  final AppDatabase _store;

  Future<List<Topic>> listTopics() async {
    final db = await _store.database;
    return listTopicsFrom(db);
  }

  Future<List<Topic>> listTopicsFrom(DatabaseExecutor executor) async {
    final rows = await executor.query('topics', orderBy: 'id ASC');
    return List<Topic>.unmodifiable(rows.map(_topicFromRow));
  }

  Future<Topic> createTopic({
    required String name,
    required DateTime now,
  }) async {
    final normalized = normalizeTopicName(name);
    final key = topicNameKey(normalized);
    final timestamp = now.toUtc().microsecondsSinceEpoch;
    final db = await _store.database;

    return db.transaction((txn) async {
      final duplicate = await txn.query(
        'topics',
        columns: <String>['id'],
        where: 'name_key = ?',
        whereArgs: <Object?>[key],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Topic name already exists: $normalized');
      }

      final id = await txn.insert('topics', <String, Object?>{
        'name': normalized,
        'name_key': key,
        'created_at_us': timestamp,
        'updated_at_us': timestamp,
      });
      return Topic(
        id: id,
        name: normalized,
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );
    });
  }

  Future<Topic> renameTopic({
    required int id,
    required String name,
    required DateTime now,
  }) async {
    final normalized = normalizeTopicName(name);
    final key = topicNameKey(normalized);
    final db = await _store.database;

    return db.transaction((txn) async {
      final current = await txn.query(
        'topics',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (current.isEmpty) {
        throw StateError('Topic $id does not exist');
      }
      final duplicate = await txn.query(
        'topics',
        columns: <String>['id'],
        where: 'name_key = ? AND id <> ?',
        whereArgs: <Object?>[key, id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Topic name already exists: $normalized');
      }

      final timestamp = now.toUtc().microsecondsSinceEpoch;
      await txn.update(
        'topics',
        <String, Object?>{
          'name': normalized,
          'name_key': key,
          'updated_at_us': timestamp,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      final row = Map<String, Object?>.from(current.single)
        ..['name'] = normalized
        ..['name_key'] = key
        ..['updated_at_us'] = timestamp;
      return _topicFromRow(row);
    });
  }

  Future<void> deleteTopic(int id) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      final topicRows = await txn.query(
        'topics',
        columns: <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (topicRows.isEmpty) {
        throw StateError('Topic $id does not exist');
      }

      final itemCount =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM review_items WHERE topic_id = ?',
              <Object?>[id],
            ),
          ) ??
          0;
      if (itemCount > 0) {
        throw StateError('Topic $id still owns ReviewItems');
      }

      final settings = await txn.query(
        'reminder_settings',
        columns: <String>['scope_mode'],
        where: 'id = 1',
        limit: 1,
      );
      if (settings.length != 1) {
        throw StateError('ReminderSettings singleton is missing');
      }

      if (settings.single['scope_mode'] == 'selected_topics') {
        final selected = await txn.query(
          'reminder_scope_topics',
          columns: <String>['topic_id'],
          orderBy: 'topic_id ASC',
        );
        final isSelected = selected.any((row) => row['topic_id'] == id);
        if (isSelected && selected.length == 1) {
          throw StateError('Cannot delete the last selected Topic');
        }
        if (isSelected) {
          await txn.delete(
            'reminder_scope_topics',
            where: 'topic_id = ?',
            whereArgs: <Object?>[id],
          );
        }
      }

      final weekdayAssignments = await txn.query(
        'reminder_weekday_topics',
        columns: <String>['weekday'],
        where: 'topic_id = ?',
        whereArgs: <Object?>[id],
        orderBy: 'weekday ASC',
      );
      for (final assignment in weekdayAssignments) {
        final weekday = assignment['weekday']! as int;
        final remaining =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM reminder_weekday_topics WHERE weekday = ? AND topic_id <> ?',
                <Object?>[weekday, id],
              ),
            ) ??
            0;
        if (remaining == 0) {
          throw StateError('Cannot delete the last Topic for weekday $weekday');
        }
      }
      if (weekdayAssignments.isNotEmpty) {
        await txn.delete(
          'reminder_weekday_topics',
          where: 'topic_id = ?',
          whereArgs: <Object?>[id],
        );
      }

      final deleted = await txn.delete(
        'topics',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (deleted != 1) {
        throw StateError('Expected to delete exactly one Topic $id');
      }
    });
  }

  Future<void> setReminderInterval({
    required int id,
    required Duration? interval,
    required DateTime now,
  }) async {
    final db = await _store.database;
    final updated = await db.update(
      'topics',
      <String, Object?>{
        'reminder_interval_ms': interval?.inMilliseconds,
        'updated_at_us': now.toUtc().microsecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (updated != 1) throw StateError('Topic $id does not exist');
  }

  Future<void> recordRemindedAtWith(
    DatabaseExecutor executor, {
    required int topicId,
    required DateTime remindedAt,
  }) async {
    final updated = await executor.update(
      'topics',
      <String, Object?>{
        'last_reminded_at_us': remindedAt.toUtc().microsecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[topicId],
    );
    if (updated != 1) throw StateError('Topic $topicId does not exist');
  }

  Topic _topicFromRow(Map<String, Object?> row) {
    final interval = row['reminder_interval_ms'] as int?;
    final reminded = row['last_reminded_at_us'] as int?;
    return Topic(
      id: row['id']! as int,
      name: row['name']! as String,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        row['created_at_us']! as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        row['updated_at_us']! as int,
        isUtc: true,
      ),
      reminderInterval: interval == null
          ? null
          : Duration(milliseconds: interval),
      lastRemindedAt: reminded == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(reminded, isUtc: true),
    );
  }
}
