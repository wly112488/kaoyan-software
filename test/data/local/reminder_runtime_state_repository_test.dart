import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_runtime_state_repository.dart';
import 'package:kaoyan_review/data/local/reminder_settings_repository.dart';
import 'package:kaoyan_review/data/local/review_item_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kaoyan-runtime-state-');
    path = '${dir.path}${Platform.pathSeparator}app.db';
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('fresh database creates exactly one runtime state row', () async {
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: path,
    );
    final repo = ReminderRuntimeStateRepository(store);
    final state = await repo.loadState();
    final db = await store.database;
    final rows = await db.query('reminder_runtime_state');

    expect(rows, hasLength(1));
    expect(state.scheduleStatus, ReminderScheduleStatus.notScheduled);
    expect(state.lastEvaluationAt, isNull);
    expect(state.lastDispatchAt, isNull);
    expect(state.lastWorkerStartedAt, isNull);
    expect(state.lastWorkerCompletedAt, isNull);
    expect(state.lastWorkerOutcome, isNull);
    await store.close();
  });

  test(
    'runtime state persists evaluation, dispatch, and schedule evidence',
    () async {
      final store = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: path,
      );
      final repo = ReminderRuntimeStateRepository(store);
      final now = DateTime.utc(2026, 9, 28, 3);

      final db = await store.database;
      await repo.recordEvaluation(
        db,
        at: now,
        outcome: 'notification_submitted',
        source: 'workmanager',
        dispatchItemId: 7,
        dispatchTopicId: 3,
        dispatchAt: now,
      );
      await repo.recordSchedule(
        db,
        at: now,
        status: ReminderScheduleStatus.scheduled,
        error: null,
      );
      await repo.recordWorkerStarted(
        db,
        at: now.add(const Duration(seconds: 2)),
      );
      await repo.recordWorkerCompleted(
        db,
        at: now.add(const Duration(seconds: 5)),
        outcome: 'notificationSubmitted',
      );

      final loaded = await repo.loadState();
      expect(loaded.lastEvaluationAt, now);
      expect(loaded.lastEvaluationOutcome, 'notification_submitted');
      expect(loaded.lastEvaluationSource, 'workmanager');
      expect(loaded.lastDispatchAt, now);
      expect(loaded.lastDispatchItemId, 7);
      expect(loaded.lastDispatchTopicId, 3);
      expect(loaded.lastScheduleAttemptAt, now);
      expect(loaded.scheduleStatus, ReminderScheduleStatus.scheduled);
      expect(loaded.scheduleError, isNull);
      expect(loaded.lastWorkerStartedAt, now.add(const Duration(seconds: 2)));
      expect(loaded.lastWorkerCompletedAt, now.add(const Duration(seconds: 5)));
      expect(loaded.lastWorkerOutcome, 'notificationSubmitted');
      await store.close();
    },
  );

  test(
    'worker failure details survive a later successful schedule update',
    () async {
      final store = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: path,
      );
      final repo = ReminderRuntimeStateRepository(store);
      final failedAt = DateTime.utc(2026, 9, 30, 12, 10);
      final db = await store.database;

      await repo.recordWorkerFailure(
        db,
        at: failedAt,
        details: '阶段：执行提醒\n异常类型：DatabaseException\n信息：database is locked',
      );
      await repo.recordSchedule(
        db,
        at: failedAt.add(const Duration(seconds: 3)),
        status: ReminderScheduleStatus.scheduled,
        error: null,
      );

      final state = await repo.loadState();
      expect(state.lastEvaluationOutcome, 'workerFailure');
      expect(state.lastWorkerErrorAt, failedAt);
      expect(state.lastWorkerErrorDetails, contains('database is locked'));
      expect(state.scheduleStatus, ReminderScheduleStatus.scheduled);
      expect(state.scheduleError, isNull);
      await store.close();
    },
  );

  test(
    'v7 database upgrade adds background execution evidence fields',
    () async {
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE reminder_runtime_state (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              last_evaluation_at_us INTEGER,
              last_evaluation_outcome TEXT,
              last_dispatch_at_us INTEGER,
              last_dispatch_item_id INTEGER,
              last_dispatch_topic_id INTEGER,
              last_schedule_attempt_at_us INTEGER,
              schedule_status TEXT NOT NULL,
              schedule_error TEXT,
              last_worker_error_at_us INTEGER,
              last_worker_error_details TEXT
            )
          ''');
            await db.insert('reminder_runtime_state', <String, Object?>{
              'id': 1,
              'schedule_status': 'scheduled',
            });
          },
        ),
      );
      await legacy.close();

      final store = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: path,
      );
      final state = await ReminderRuntimeStateRepository(store).loadState();

      expect(state.scheduleStatus, ReminderScheduleStatus.scheduled);
      expect(state.lastWorkerStartedAt, isNull);
      expect(state.lastWorkerCompletedAt, isNull);
      expect(state.lastWorkerOutcome, isNull);
      expect(state.lastEvaluationSource, isNull);
      await store.close();
    },
  );

  test(
    'v1 migration preserves existing product data and adds one runtime row',
    () async {
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE topics (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              name_key TEXT NOT NULL UNIQUE,
              created_at_us INTEGER NOT NULL,
              updated_at_us INTEGER NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE review_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              content TEXT NOT NULL,
              topic_id INTEGER NOT NULL,
              enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
              created_at_us INTEGER NOT NULL,
              updated_at_us INTEGER NOT NULL,
              last_shown_at_us INTEGER,
              FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE RESTRICT
            )
          ''');
            await db.execute('''
            CREATE TABLE reminder_settings (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
              active_window_mode TEXT NOT NULL,
              start_minute INTEGER,
              end_minute INTEGER,
              reminder_interval_ms INTEGER NOT NULL,
              repeat_cooldown_ms INTEGER NOT NULL,
              scope_mode TEXT NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE reminder_scope_topics (
              topic_id INTEGER PRIMARY KEY,
              FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE RESTRICT
            )
          ''');
            await db.insert('topics', <String, Object?>{
              'id': 3,
              'name': '医学',
              'name_key': '医学',
              'created_at_us': 100,
              'updated_at_us': 200,
            });
            await db.insert('review_items', <String, Object?>{
              'id': 7,
              'content': '保留这条复习内容',
              'topic_id': 3,
              'enabled': 1,
              'created_at_us': 300,
              'updated_at_us': 400,
              'last_shown_at_us': 500,
            });
            await db.insert('reminder_settings', <String, Object?>{
              'id': 1,
              'enabled': 1,
              'active_window_mode': 'bounded',
              'start_minute': 480,
              'end_minute': 1320,
              'reminder_interval_ms': 3600000,
              'repeat_cooldown_ms': 86400000,
              'scope_mode': 'selected_topics',
            });
            await db.insert('reminder_scope_topics', <String, Object?>{
              'topic_id': 3,
            });
          },
        ),
      );
      await legacy.close();

      final store = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: path,
      );
      final db = await store.database;
      final topics = await db.query('topics');
      final items = await db.query('review_items');
      final settings = await db.query('reminder_settings');
      final scope = await db.query('reminder_scope_topics');
      final runtime = await db.query('reminder_runtime_state');

      expect(topics.single['id'], 3);
      expect(items.single['id'], 7);
      expect(items.single['last_shown_at_us'], 500);
      expect(settings.single['enabled'], 1);
      expect(settings.single['scope_mode'], 'selected_topics');
      expect(scope.single['topic_id'], 3);
      expect(runtime, hasLength(1));
      expect(runtime.single['schedule_status'], 'not_scheduled');
      expect(await db.getVersion(), AppDatabase.schemaVersion);
      await store.close();
    },
  );

  test('repository operations use the caller transaction executor', () async {
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: path,
    );
    final topicRepository = TopicRepository(store);
    final itemRepository = ReviewItemRepository(store);
    final settingsRepository = ReminderSettingsRepository(store);
    final topic = await topicRepository.createTopic(
      name: '医学',
      now: DateTime.utc(2026, 9, 28),
    );
    final item = await itemRepository.createReviewItem(
      content: '验证事务内仓储操作',
      topicId: topic.id,
      enabled: true,
      now: DateTime.utc(2026, 9, 28),
    );
    final shownAt = DateTime.utc(2026, 9, 28, 3);
    final db = await store.database;

    await db.transaction((txn) async {
      final settings = await settingsRepository.loadSettingsFrom(txn);
      final items = await itemRepository.listReviewItemsFrom(txn);
      expect(settings.enabled, isFalse);
      expect(items, hasLength(1));
      await itemRepository.recordShownAtWith(
        txn,
        id: item.id,
        shownAt: shownAt,
      );
    });

    expect((await itemRepository.getReviewItem(item.id))!.lastShownAt, shownAt);
    await store.close();
  });
}
