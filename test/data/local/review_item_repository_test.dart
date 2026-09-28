import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/review_item_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppDatabase store;
  late TopicRepository topics;
  late ReviewItemRepository items;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-item-test-');
    store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    topics = TopicRepository(store);
    items = ReviewItemRepository(store);
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('create/list round-trips a ReviewItem', () async {
    final now = DateTime.utc(2026, 9, 27, 8);
    final topic = await topics.createTopic(name: '医学', now: now);

    final created = await items.createReviewItem(
      content: '心输出量相关知识',
      topicId: topic.id,
      enabled: true,
      now: now,
    );

    final loaded = (await items.listReviewItems()).single;
    expect(loaded.id, created.id);
    expect(loaded.content, '心输出量相关知识');
    expect(loaded.topicId, topic.id);
    expect(loaded.enabled, isTrue);
    expect(loaded.createdAt, now);
    expect(loaded.updatedAt, now);
    expect(loaded.lastShownAt, isNull);
  });

  test('create rejects a missing Topic and blank content', () async {
    final now = DateTime.utc(2026, 9, 27);
    expect(
      () => items.createReviewItem(
        content: 'text',
        topicId: 999,
        enabled: true,
        now: now,
      ),
      throwsStateError,
    );

    final topic = await topics.createTopic(name: '医学', now: now);
    expect(
      () => items.createReviewItem(
        content: '   ',
        topicId: topic.id,
        enabled: true,
        now: now,
      ),
      throwsArgumentError,
    );
  });

  test('editing preserves creation time and lastShownAt', () async {
    final createdAt = DateTime.utc(2026, 9, 27, 8);
    final firstTopic = await topics.createTopic(name: '医学', now: createdAt);
    final secondTopic = await topics.createTopic(name: '生物', now: createdAt);
    final created = await items.createReviewItem(
      content: 'old',
      topicId: firstTopic.id,
      enabled: true,
      now: createdAt,
    );
    final shownAt = createdAt.add(const Duration(hours: 1));
    await items.recordShownAt(id: created.id, shownAt: shownAt);

    final updatedAt = createdAt.add(const Duration(hours: 2));
    final updated = await items.updateReviewItem(
      id: created.id,
      content: 'new',
      topicId: secondTopic.id,
      enabled: false,
      now: updatedAt,
    );

    expect(updated.createdAt, createdAt);
    expect(updated.updatedAt, updatedAt);
    expect(updated.lastShownAt, shownAt);
    expect(updated.topicId, secondTopic.id);
    expect(updated.enabled, isFalse);
  });

  test('delete removes exactly the requested ReviewItem', () async {
    final now = DateTime.utc(2026, 9, 27);
    final topic = await topics.createTopic(name: '医学', now: now);
    final a = await items.createReviewItem(
      content: 'a',
      topicId: topic.id,
      enabled: true,
      now: now,
    );
    final b = await items.createReviewItem(
      content: 'b',
      topicId: topic.id,
      enabled: true,
      now: now,
    );

    await items.deleteReviewItem(a.id);

    expect(await items.getReviewItem(a.id), isNull);
    expect((await items.getReviewItem(b.id))?.content, 'b');
  });
}
