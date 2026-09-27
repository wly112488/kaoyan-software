import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_settings_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late String dbPath;
  late AppDatabase store;
  late TopicRepository topics;
  late ReminderSettingsRepository settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-settings-test-');
    dbPath = '${tempDir.path}${Platform.pathSeparator}app.db';
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: dbPath);
    topics = TopicRepository(store);
    settings = ReminderSettingsRepository(store);
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fresh load returns canonical initial settings', () async {
    final loaded = await settings.loadSettings();
    expect(loaded.enabled, isFalse);
    expect(loaded.activeWindow.mode, ActiveWindowMode.allDay);
    expect(loaded.reminderInterval, const Duration(minutes: 60));
    expect(loaded.repeatCooldown, const Duration(hours: 24));
    expect(loaded.scope.mode, ReminderScopeMode.allTopics);
  });

  test('selected scope and bounded window survive reopen', () async {
    final now = DateTime.utc(2026, 9, 27);
    final a = await topics.createTopic(name: '医学', now: now);
    final b = await topics.createTopic(name: '生物', now: now);
    await settings.saveSettings(ReminderSettings(
      enabled: true,
      activeWindow: ActiveWindow.bounded(startMinute: 22 * 60, endMinute: 60),
      reminderInterval: const Duration(minutes: 30),
      repeatCooldown: const Duration(hours: 48),
      scope: ReminderScope.selectedTopics(<int>{a.id, b.id}),
    ));

    await store.close();
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: dbPath);
    settings = ReminderSettingsRepository(store);

    final loaded = await settings.loadSettings();
    expect(loaded.enabled, isTrue);
    expect(loaded.activeWindow.mode, ActiveWindowMode.bounded);
    expect(loaded.activeWindow.startMinute, 22 * 60);
    expect(loaded.activeWindow.endMinute, 60);
    expect(loaded.reminderInterval, const Duration(minutes: 30));
    expect(loaded.repeatCooldown, const Duration(hours: 48));
    expect(loaded.scope.mode, ReminderScopeMode.selectedTopics);
    expect(loaded.scope.topicIds, <int>{a.id, b.id});
  });

  test('selected scope rejects missing Topic ids', () async {
    expect(
      () => settings.saveSettings(ReminderSettings(
        enabled: false,
        activeWindow: ActiveWindow.allDay(),
        reminderInterval: const Duration(minutes: 60),
        repeatCooldown: const Duration(hours: 24),
        scope: ReminderScope.selectedTopics(<int>{999}),
      )),
      throwsStateError,
    );
  });

  test('saving ALL_TOPICS clears persisted selected Topic rows', () async {
    final now = DateTime.utc(2026, 9, 27);
    final topic = await topics.createTopic(name: '医学', now: now);
    await settings.saveSettings(ReminderSettings(
      enabled: false,
      activeWindow: ActiveWindow.allDay(),
      reminderInterval: const Duration(minutes: 60),
      repeatCooldown: const Duration(hours: 24),
      scope: ReminderScope.selectedTopics(<int>{topic.id}),
    ));

    await settings.saveSettings(ReminderSettings.initial());

    final db = await store.database;
    expect(await db.query('reminder_scope_topics'), isEmpty);
    expect((await settings.loadSettings()).scope.mode, ReminderScopeMode.allTopics);
  });
}
