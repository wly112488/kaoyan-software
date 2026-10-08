import 'package:sqflite/sqflite.dart';

import '../../domain/review_item.dart';
import 'app_database.dart';

final class ReviewItemRepository {
  ReviewItemRepository(this._store);

  final AppDatabase _store;

  Future<List<ReviewItem>> listReviewItems() async {
    final db = await _store.database;
    return listReviewItemsFrom(db);
  }

  Future<List<ReviewItem>> listReviewItemsFrom(
    DatabaseExecutor executor,
  ) async {
    final rows = await executor.query('review_items', orderBy: 'id ASC');
    return List<ReviewItem>.unmodifiable(rows.map(_itemFromRow));
  }

  Future<ReviewItem?> getReviewItem(int id) async {
    final db = await _store.database;
    final rows = await db.query(
      'review_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _itemFromRow(rows.single);
  }

  Future<ReviewItem> createReviewItem({
    required String content,
    required int topicId,
    required bool enabled,
    required DateTime now,
  }) async {
    if (content.trim().isEmpty) {
      throw ArgumentError.value(
        content,
        'content',
        'ReviewItem content must not be blank',
      );
    }
    final db = await _store.database;
    final timestamp = now.toUtc().microsecondsSinceEpoch;

    return db.transaction((txn) async {
      await _requireTopic(txn, topicId);
      final id = await txn.insert('review_items', <String, Object?>{
        'content': content,
        'topic_id': topicId,
        'enabled': enabled ? 1 : 0,
        'created_at_us': timestamp,
        'updated_at_us': timestamp,
        'last_shown_at_us': null,
        'reminder_count': 0,
      });
      return ReviewItem(
        id: id,
        content: content,
        topicId: topicId,
        enabled: enabled,
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );
    });
  }

  Future<ReviewItem> updateReviewItem({
    required int id,
    required String content,
    required int topicId,
    required bool enabled,
    required DateTime now,
  }) async {
    if (content.trim().isEmpty) {
      throw ArgumentError.value(
        content,
        'content',
        'ReviewItem content must not be blank',
      );
    }
    final db = await _store.database;

    return db.transaction((txn) async {
      final current = await txn.query(
        'review_items',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (current.isEmpty) {
        throw StateError('ReviewItem $id does not exist');
      }
      await _requireTopic(txn, topicId);
      await txn.update(
        'review_items',
        <String, Object?>{
          'content': content,
          'topic_id': topicId,
          'enabled': enabled ? 1 : 0,
          'updated_at_us': now.toUtc().microsecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      final updated = await txn.query(
        'review_items',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return _itemFromRow(updated.single);
    });
  }

  Future<ReviewItem> recordShownAt({
    required int id,
    required DateTime shownAt,
  }) async {
    final db = await _store.database;
    await recordShownAtWith(db, id: id, shownAt: shownAt);
    return (await getReviewItem(id))!;
  }

  Future<void> recordShownAtWith(
    DatabaseExecutor executor, {
    required int id,
    required DateTime shownAt,
  }) async {
    final updated = await executor.rawUpdate(
      'UPDATE review_items SET last_shown_at_us = ?, reminder_count = reminder_count + 1 WHERE id = ?',
      <Object?>[shownAt.toUtc().microsecondsSinceEpoch, id],
    );
    if (updated != 1) {
      throw StateError('ReviewItem $id does not exist');
    }
  }

  Future<void> deleteReviewItem(int id) async {
    final db = await _store.database;
    final deleted = await db.delete(
      'review_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (deleted != 1) {
      throw StateError('ReviewItem $id does not exist');
    }
  }

  Future<void> _requireTopic(DatabaseExecutor executor, int topicId) async {
    final rows = await executor.query(
      'topics',
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[topicId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Topic $topicId does not exist');
    }
  }

  ReviewItem _itemFromRow(Map<String, Object?> row) {
    final lastShown = row['last_shown_at_us'] as int?;
    return ReviewItem(
      id: row['id']! as int,
      content: row['content']! as String,
      topicId: row['topic_id']! as int,
      enabled: (row['enabled']! as int) == 1,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        row['created_at_us']! as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        row['updated_at_us']! as int,
        isUtc: true,
      ),
      lastShownAt: lastShown == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(lastShown, isUtc: true),
      reminderCount: row['reminder_count'] as int? ?? 0,
    );
  }
}
