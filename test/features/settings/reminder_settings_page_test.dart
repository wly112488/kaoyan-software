import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/domain/review_item.dart';
import 'package:kaoyan_review/runtime/review_notification_gateway.dart';
import 'package:kaoyan_review/runtime/reminder_scheduler.dart';
import 'package:kaoyan_review/features/settings/reminder_settings_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppServices services;
  late _FakeNotifications notifications;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-settings-ui-');
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    notifications = _FakeNotifications();
    services = AppServices(
      store: store,
      notifications: notifications,
      periodicWork: _FailingWorkPort(),
    );
  });

  tearDown(() async {
    await services.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets(
    'permission denial preserves enabled intent and shows degraded state',
    (tester) async {
      final topic = await tester.runAsync(
        () => services.topics.createTopic(
          name: '数学',
          now: DateTime.utc(2026, 9, 28),
        ),
      );
      await tester.runAsync(
        () => services.reviewItems.createReviewItem(
          content: '需要提醒的内容',
          topicId: topic!.id,
          enabled: true,
          now: DateTime.utc(2026, 9, 28),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: ReminderSettingsPage(services: services)),
      );
      await _flushDatabaseWork(tester, times: 2);

      await tester.tap(find.byKey(const ValueKey('reminder-enabled-switch')));
      await _flushDatabaseWork(tester);

      expect(notifications.permissionRequests, 1);
      expect(find.text('通知权限未开启'), findsOneWidget);
      expect(find.text('通知权限未开启，提醒意图已保留'), findsOneWidget);

      await tester.tap(find.text('保存提醒设置'));
      await _flushDatabaseWork(tester, times: 10);
      expect(
        find.byKey(const ValueKey('reminder-settings-status')),
        findsOneWidget,
      );
      final savedStatus = tester.widget<Text>(
        find.byKey(const ValueKey('reminder-settings-status')),
      );
      expect(savedStatus.data, anyOf(contains('设置已保存'), '提醒设置已保存'));

      final savedSettings = await tester.runAsync(
        () => services.reminderSettings.loadSettings(),
      );
      expect(savedSettings!.enabled, isTrue);
      expect(find.text('设置已保存，但系统调度失败。请稍后重试。'), findsOneWidget);
    },
  );

  testWidgets('selected Topic scope cannot be saved empty', (tester) async {
    await tester.runAsync(
      () => services.topics.createTopic(
        name: '生物',
        now: DateTime.utc(2026, 9, 28),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: ReminderSettingsPage(services: services)),
    );
    await _flushDatabaseWork(tester, times: 2);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定主题'));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('生物'));
    await tester.pump();
    expect(find.text('指定主题范围至少保留一个主题'), findsOneWidget);

    await tester.tap(find.text('保存提醒设置'));
    await _flushDatabaseWork(tester, times: 3);
    final savedSettings = await tester.runAsync(
      () => services.reminderSettings.loadSettings(),
    );
    expect(savedSettings!.scope.mode.name, 'selectedTopics');
    expect(savedSettings.scope.topicIds, hasLength(1));
  });

  testWidgets('notification status errors show their source and type', (
    tester,
  ) async {
    notifications.channelStatusError = StateError('channel query failed');
    await tester.pumpWidget(
      MaterialApp(home: ReminderSettingsPage(services: services)),
    );
    await _flushDatabaseWork(tester, times: 2);

    await tester.tap(find.byKey(const ValueKey('reminder-enabled-switch')));
    await tester.pump();

    expect(find.textContaining('通知通道状态读取失败（StateError）'), findsOneWidget);
  });
}

Future<void> _flushDatabaseWork(WidgetTester tester, {int times = 1}) async {
  for (var index = 0; index < times; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }
}

final class _FakeNotifications implements ReviewNotificationGateway {
  int permissionRequests = 0;
  Object? channelStatusError;

  @override
  Future<bool> canPost() async => false;

  @override
  Future<void> initialize({void Function(int itemId)? onTap}) async {}

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return false;
  }

  @override
  Future<NotificationChannelStatus> channelStatus() async {
    if (channelStatusError case final error?) throw error;
    return const NotificationChannelStatus(
      appEnabled: false,
      channelExists: false,
      importance: null,
    );
  }

  @override
  Future<List<int>> activeReviewItemNotificationIds() async => const <int>[];

  @override
  Future<void> sendTestNotification() async {}

  @override
  Future<void> submit(ReviewItem item) async {}
}

final class _FailingWorkPort implements PeriodicWorkPort {
  @override
  Future<void> cancel() async {}

  @override
  Future<void> register({required Duration initialDelay}) async {
    throw StateError('work registration failed');
  }
}
