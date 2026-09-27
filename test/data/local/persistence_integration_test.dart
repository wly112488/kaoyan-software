import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_settings_repository.dart';
import 'package:kaoyan_review/data/local/review_item_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('persistent state remains valid across reopen and selected Topic deletion', () async {
    final tempDir = await Directory.systemTemp.createTemp('kaoyan-integration-');
    final path = '${tempDir.path}${Platform.pathSeparator}app.db';
    final createdAt = DateTime.utc(2026, 9, 27, 8);
    final shownAt = createdAt.add(const Duration(hours: 1));

    var store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    var topics = TopicRepository(store);
    var items = ReviewItemRepository(store);
    var settings = ReminderSettingsRepository(store);

    final medicine = await topics.createTopic(name: '医学', now: createdAt);
    final biology = await topics.createTopic(name: '生物', now: createdAt);
    final item = await items.createReviewItem(
      content: '需要复习的段落',
      topicId: biology.id,
      enabled: true,
      now: createdAt,
    );
    await items.recordShownAt(id: item.id, shownAt: shownAt);
    await settings.saveSettings(ReminderSettings(
      enabled: true,
      activeWindow: ActiveWindow.allDay(),
      reminderInterval: const Duration(minutes: 60),
      repeatCooldown: const Duration(hours: 24),
      scope: ReminderScope.selectedTopics(<int>{medicine.id, biology.id}),
    ));

    await store.close();
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    topics = TopicRepository(store);
    items = ReviewItemRepository(store);
    settings = ReminderSettingsRepository(store);

    final reloadedItem = await items.getReviewItem(item.id);
    expect(reloadedItem?.lastShownAt, shownAt);
    expect((await settings.loadSettings()).scope.topicIds, <int>{medicine.id, biology.id});

    await items.updateReviewItem(
      id: item.id,
      content: reloadedItem!.content,
      topicId: medicine.id,
      enabled: reloadedItem.enabled,
      now: createdAt.add(const Duration(hours: 2)),
    );
    expect((await items.getReviewItem(item.id))?.lastShownAt, shownAt);

    await topics.deleteTopic(biology.id);
    expect((await settings.loadSettings()).scope.topicIds, <int>{medicine.id});

    await store.close();
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    settings = ReminderSettingsRepository(store);
    items = ReviewItemRepository(store);

    expect((await settings.loadSettings()).scope.topicIds, <int>{medicine.id});
    expect((await items.getReviewItem(item.id))?.lastShownAt, shownAt);

    final db = await store.database;
    final columns = await db.rawQuery('PRAGMA table_info(review_items)');
    expect(columns.map((row) => row['name']), isNot(contains('next_eligible_at')));

    await store.close();
    await tempDir.delete(recursive: true);
  });
}
