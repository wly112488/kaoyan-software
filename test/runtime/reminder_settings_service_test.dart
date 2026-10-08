import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_settings_repository.dart';
import 'package:kaoyan_review/data/local/review_item_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/runtime/reminder_scheduler.dart';
import 'package:kaoyan_review/runtime/reminder_settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppDatabase store;
  late ReminderSettingsService service;
  late _FakeWork work;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-settings-service-');
    store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    work = _FakeWork();
    service = ReminderSettingsService(
      repository: ReminderSettingsRepository(store),
      scheduler: ReminderScheduler(store: store, work: work),
    );
  });

  tearDown(() async {
    await store.close();
    await tempDir.delete(recursive: true);
  });

  test('settings write failures identify the persistence stage', () async {
    final db = await store.database;
    await db.execute('''
      CREATE TRIGGER reject_reminder_settings_update
      BEFORE UPDATE ON reminder_settings
      BEGIN SELECT RAISE(ABORT, 'simulated settings write failure'); END
    ''');

    await expectLater(
      service.save(ReminderSettings.initial()),
      throwsA(
        predicate<Object>(
          (error) =>
              error is Exception &&
              error.toString().contains('reminder settings write'),
        ),
      ),
    );
  });

  test('scheduler failures identify the scheduling stage', () async {
    final db = await store.database;
    await db.execute('''
      CREATE TRIGGER reject_runtime_state_update
      BEFORE UPDATE ON reminder_runtime_state
      BEGIN SELECT RAISE(ABORT, 'simulated schedule state failure'); END
    ''');

    await expectLater(
      service.save(ReminderSettings.initial()),
      throwsA(
        predicate<Object>(
          (error) =>
              error is Exception &&
              error.toString().contains('reminder scheduling'),
        ),
      ),
    );
  });

  test(
    'saving enabled reminders waits one interval before first dispatch',
    () async {
      final now = DateTime.now().toUtc();
      final topic = await TopicRepository(store)
          .createTopic(name: '内科', now: now);
      await ReviewItemRepository(store).createReviewItem(
        content: '保存后不应立刻弹出',
        topicId: topic.id,
        enabled: true,
        now: now,
      );

      await service.save(
        ReminderSettings(
          enabled: true,
          activeWindow: ActiveWindow.allDay(),
          reminderInterval: const Duration(minutes: 1),
          repeatCooldown: const Duration(minutes: 1),
          scope: ReminderScope.allTopics(),
        ),
      );

      expect(work.registeredInitialDelay, const Duration(minutes: 1));
    },
  );
}

final class _FakeWork implements ReminderWorkPort {
  Duration? registeredInitialDelay;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> register({
    required Duration initialDelay,
    ReminderWorkPolicy policy = ReminderWorkPolicy.replace,
  }) async {
    registeredInitialDelay = initialDelay;
  }
}
