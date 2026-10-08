import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppDatabase store;
  late TopicRepository topics;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-topic-test-');
    store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    topics = TopicRepository(store);
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'create trims name, list persists it, and rename keeps stable identity',
    () async {
      final createdAt = DateTime.utc(2026, 9, 27, 1);
      final topic = await topics.createTopic(name: '  医学  ', now: createdAt);
      expect(topic.name, '医学');

      final renamedAt = createdAt.add(const Duration(hours: 1));
      final renamed = await topics.renameTopic(
        id: topic.id,
        name: '临床医学',
        now: renamedAt,
      );

      expect(renamed.id, topic.id);
      expect(renamed.createdAt, createdAt);
      expect(renamed.updatedAt, renamedAt);
      expect((await topics.listTopics()).single.name, '临床医学');
    },
  );

  test('duplicate normalized Topic name is rejected', () async {
    final now = DateTime.utc(2026, 9, 27);
    await topics.createTopic(name: 'Biology', now: now);

    expect(
      () => topics.createTopic(name: ' biology ', now: now),
      throwsStateError,
    );
  });

  test('topic interval override and last-reminded time persist', () async {
    final now = DateTime.utc(2026, 9, 27, 12);
    final topic = await topics.createTopic(name: '医学', now: now);
    await topics.setReminderInterval(
      id: topic.id,
      interval: const Duration(hours: 3),
      now: now,
    );
    final remindedAt = now.add(const Duration(minutes: 15));
    final db = await store.database;
    await db.transaction(
      (txn) => topics.recordRemindedAtWith(
        txn,
        topicId: topic.id,
        remindedAt: remindedAt,
      ),
    );

    final loaded = (await topics.listTopics()).single;
    expect(loaded.reminderInterval, const Duration(hours: 3));
    expect(loaded.lastRemindedAt, remindedAt);
  });

  test('Topic with ReviewItems cannot be deleted', () async {
    final now = DateTime.utc(2026, 9, 27);
    final topic = await topics.createTopic(name: '医学', now: now);
    final db = await store.database;
    await db.insert('review_items', <String, Object?>{
      'content': 'content',
      'topic_id': topic.id,
      'enabled': 1,
      'created_at_us': now.microsecondsSinceEpoch,
      'updated_at_us': now.microsecondsSinceEpoch,
      'last_shown_at_us': null,
    });

    expect(() => topics.deleteTopic(topic.id), throwsStateError);
  });

  test(
    'deleting one selected empty Topic keeps the remaining selected Topic',
    () async {
      final now = DateTime.utc(2026, 9, 27);
      final a = await topics.createTopic(name: '医学', now: now);
      final b = await topics.createTopic(name: '生物', now: now);
      final db = await store.database;
      await db.update('reminder_settings', <String, Object?>{
        'scope_mode': 'selected_topics',
      }, where: 'id = 1');
      await db.insert('reminder_scope_topics', <String, Object?>{
        'topic_id': a.id,
      });
      await db.insert('reminder_scope_topics', <String, Object?>{
        'topic_id': b.id,
      });

      await topics.deleteTopic(b.id);

      final scopeRows = await db.query('reminder_scope_topics');
      expect(scopeRows, <Map<String, Object?>>[
        <String, Object?>{'topic_id': a.id},
      ]);
      expect((await topics.listTopics()).map((topic) => topic.id), <int>[a.id]);
    },
  );

  for (final enabled in <int>[0, 1]) {
    test(
      'last selected Topic deletion is blocked when enabled=$enabled',
      () async {
        final now = DateTime.utc(2026, 9, 27);
        final topic = await topics.createTopic(name: '医学', now: now);
        final db = await store.database;
        await db.update('reminder_settings', <String, Object?>{
          'scope_mode': 'selected_topics',
          'enabled': enabled,
        }, where: 'id = 1');
        await db.insert('reminder_scope_topics', <String, Object?>{
          'topic_id': topic.id,
        });

        expect(() => topics.deleteTopic(topic.id), throwsStateError);
      },
    );
  }
}
