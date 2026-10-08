import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/features/topics/topic_management_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppServices services;
  late int referencedTopicId;
  late int emptyTopicId;
  late int reviewItemId;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-topics-ui-');
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    services = AppServices(store: store);
    final referenced = await services.topics.createTopic(
      name: '数学',
      now: DateTime.utc(2026, 9, 28),
    );
    final empty = await services.topics.createTopic(
      name: '英语',
      now: DateTime.utc(2026, 9, 28),
    );
    referencedTopicId = referenced.id;
    emptyTopicId = empty.id;
    final item = await services.reviewItems.createReviewItem(
      content: 'topic reference',
      topicId: referenced.id,
      enabled: true,
      now: DateTime.utc(2026, 9, 28),
    );
    reviewItemId = item.id;
    await services.reminderSettings.saveSettings(
      ReminderSettings(
        enabled: false,
        activeWindow: ReminderSettings.initial().activeWindow,
        reminderInterval: const Duration(minutes: 60),
        repeatCooldown: const Duration(hours: 24),
        scope: ReminderScope.selectedTopics(<int>{referenced.id, empty.id}),
      ),
    );
  });

  tearDown(() async {
    await services.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('Topic names are unique and protected deletions explain why', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: TopicManagementPage(services: services)),
    );
    await _flushDatabaseWork(tester, times: 3);

    await tester.tap(find.byTooltip('重命名').first);
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('topic-name-field')),
      '英语',
    );
    await tester.tap(find.text('保存'));
    await _flushDatabaseWork(tester, times: 2);
    expect(find.text('已存在同名主题'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();

    await _confirmDelete(tester, 0);
    await _flushDatabaseWork(tester, times: 2);
    expect(find.text('该主题下还有复习内容，请先移动或删除这些内容。'), findsOneWidget);

    await tester.runAsync(
      () => services.reviewItems.deleteReviewItem(reviewItemId),
    );
    await _confirmDelete(tester, 0);
    await _flushDatabaseWork(tester, times: 3);
    expect(await _topicExists(tester, services, referencedTopicId), isFalse);

    await _waitFor(tester, find.byTooltip('删除'));
    await _confirmDelete(tester, 0);
    await _flushDatabaseWork(tester, times: 2);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('它是提醒范围内最后一个主题，请先调整提醒范围。'), findsOneWidget);
    expect(await _topicExists(tester, services, emptyTopicId), isTrue);
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 20 && finder.evaluate().isEmpty; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

Future<void> _confirmDelete(WidgetTester tester, int index) async {
  await tester.tap(find.byTooltip('删除').at(index));
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, '删除'));
  await tester.pump();
}

Future<bool> _topicExists(
  WidgetTester tester,
  AppServices services,
  int id,
) async {
  final topics = await tester.runAsync(() => services.topics.listTopics());
  return topics!.any((topic) => topic.id == id);
}

Future<void> _flushDatabaseWork(
  WidgetTester tester, {
  required int times,
}) async {
  for (var index = 0; index < times; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }
}
