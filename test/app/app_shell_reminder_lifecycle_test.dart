import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/app/app_shell.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/domain/review_item.dart';
import 'package:kaoyan_review/runtime/foreground_status.dart';
import 'package:kaoyan_review/runtime/reminder_execution_service.dart';
import 'package:kaoyan_review/runtime/reminder_scheduler.dart';
import 'package:kaoyan_review/runtime/review_notification_gateway.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppServices services;
  late _FakeForegroundStatus foreground;
  late _FakeNotifications notifications;
  late _FakeWorkPort workPort;
  late _FixedClock clock;
  late ReviewItem item;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-lifecycle-test-');
    final now = DateTime.now();
    final sentAt = now.subtract(const Duration(minutes: 3));
    clock = _FixedClock(now.toUtc(), now);
    foreground = _FakeForegroundStatus()..result = true;
    notifications = _FakeNotifications();
    workPort = _FakeWorkPort();
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    services = AppServices(
      store: store,
      notifications: notifications,
      periodicWork: workPort,
      foregroundStatus: foreground,
      clock: clock,
    );
    final topic = await services.topics.createTopic(
      name: '内科',
      now: clock.nowUtc(),
    );
    item = await services.reviewItems.createReviewItem(
      content: '退出应用后应按间隔提醒',
      topicId: topic.id,
      enabled: true,
      now: sentAt.subtract(const Duration(days: 1)),
    );
    await services.reviewItems.recordShownAt(id: item.id, shownAt: sentAt);
    await services.topics.setReminderInterval(
      id: topic.id,
      interval: null,
      now: sentAt,
    );
    final db = await store.database;
    await db.transaction(
      (txn) => services.topics.recordRemindedAtWith(
        txn,
        topicId: topic.id,
        remindedAt: sentAt,
      ),
    );
    await services.reminderSettings.saveSettings(
      ReminderSettings(
        enabled: true,
        activeWindow: ActiveWindow.allDay(),
        reminderInterval: const Duration(minutes: 1),
        repeatCooldown: const Duration(minutes: 1),
        scope: ReminderScope.allTopics(),
      ),
    );
    await db.transaction(
      (txn) => services.runtimeState.recordEvaluation(
        txn,
        at: sentAt,
        outcome: 'notification_submitted',
        dispatchItemId: item.id,
        dispatchTopicId: topic.id,
        dispatchAt: sentAt,
      ),
    );
  });

  tearDown(() async {
    await services.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets(
    'paused app schedules the next reminder one interval after exit',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: AppShell(services: services)));
      await _flushDatabaseWork(tester, times: 3);
      expect(find.text(item.content), findsOneWidget);

      // Place the foreground suppression just under one configured interval
      // ago. The next opportunity must be based on that skipped evaluation,
      // and pausing must rebase it from the foreground exit.
      clock.advanceTo(DateTime.now().subtract(const Duration(seconds: 58)));
      final outcome = await tester.runAsync(services.executionService.runOnce);
      expect(outcome, ReminderRunOutcome.foregroundSuppressed);
      expect(notifications.submittedItems, isEmpty);

      final nextOpportunity = await tester.runAsync(
        services.scheduler.nextOpportunityAt,
      );
      expect(nextOpportunity, isNotNull);
      expect(
        nextOpportunity!.isAfter(DateTime.now()),
        isTrue,
      );

      foreground.result = false;
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(workPort.registeredDelays, isNotEmpty);
      expect(
        workPort.registeredDelays.last,
        const Duration(minutes: 1),
      );
      expect(notifications.submittedItems, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _FakeForegroundStatus implements ForegroundStatus {
  bool result = false;

  @override
  Future<bool> isForeground() async => result;
}

final class _FakeNotifications implements ReviewNotificationGateway {
  final List<int> submittedItems = <int>[];

  @override
  Future<bool> canPost() async => true;

  @override
  Future<NotificationChannelStatus> channelStatus() async =>
      const NotificationChannelStatus(
        appEnabled: true,
        channelExists: true,
        importance: Importance.high,
      );

  @override
  Future<List<int>> activeReviewItemNotificationIds() async => const <int>[];

  @override
  Future<void> initialize({void Function(int itemId)? onTap}) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> sendTestNotification() async {}

  @override
  Future<void> submit(ReviewItem item) async {
    submittedItems.add(item.id);
  }
}

final class _FakeWorkPort implements ReminderWorkPort {
  final List<Duration> registeredDelays = <Duration>[];

  @override
  Future<void> cancel() async {}

  @override
  Future<void> register({required Duration initialDelay}) async {
    registeredDelays.add(initialDelay);
  }
}

final class _FixedClock implements ReminderClock {
  _FixedClock(this.utc, this.local);

  DateTime utc;
  DateTime local;

  void advanceTo(DateTime localTime) {
    local = localTime;
    utc = localTime.toUtc();
  }

  @override
  DateTime nowLocal() => local;

  @override
  DateTime nowUtc() => utc;
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
