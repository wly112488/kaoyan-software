import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_runtime_state_repository.dart';
import 'package:kaoyan_review/data/local/reminder_settings_repository.dart';
import 'package:kaoyan_review/data/local/review_item_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/review_item.dart';
import 'package:kaoyan_review/runtime/foreground_status.dart';
import 'package:kaoyan_review/runtime/reminder_execution_service.dart';
import 'package:kaoyan_review/runtime/review_notification_gateway.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String path;
  late AppDatabase store;
  late ReminderSettingsRepository settings;
  late ReviewItemRepository items;
  late ReminderRuntimeStateRepository runtime;
  late ReviewItem item;
  late DateTime now;
  late _FakeForegroundStatus foreground;
  late _FakeNotifications notifications;
  late _FixedClock clock;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kaoyan-reminder-execution-');
    path = '${dir.path}${Platform.pathSeparator}app.db';
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    settings = ReminderSettingsRepository(store);
    items = ReviewItemRepository(store);
    runtime = ReminderRuntimeStateRepository(store);
    now = DateTime.utc(2026, 9, 28, 4);
    clock = _FixedClock(now, DateTime(2026, 9, 28, 12));
    foreground = _FakeForegroundStatus();
    notifications = _FakeNotifications();
    final topic = await TopicRepository(store)
        .createTopic(name: '医学', now: now);
    item = await items.createReviewItem(
      content: '复习当前持久化内容',
      topicId: topic.id,
      enabled: true,
      now: now.subtract(const Duration(days: 1)),
    );
  });

  tearDown(() async {
    await store.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ReminderExecutionService createService() => ReminderExecutionService(
    store: store,
    foregroundStatus: foreground,
    notifications: notifications,
    clock: clock,
  );

  Future<void> saveSettings({
    bool enabled = true,
    Duration interval = const Duration(minutes: 15),
    ActiveWindow? activeWindow,
    Duration repeatCooldown = const Duration(hours: 24),
    Map<int, Set<int>> weeklyTopicIds = const <int, Set<int>>{},
  }) => settings.saveSettings(
    ReminderSettings(
      enabled: enabled,
      activeWindow: activeWindow ?? ActiveWindow.allDay(),
      reminderInterval: interval,
      repeatCooldown: repeatCooldown,
      scope: ReminderScope.allTopics(),
      weeklyTopicIds: weeklyTopicIds,
    ),
  );

  test('disabled settings do not query notification capability', () async {
    await saveSettings(enabled: false);

    final outcome = await createService().runOnce();

    expect(outcome, ReminderRunOutcome.reminderDisabled);
    expect(foreground.calls, 0);
    expect(notifications.canPostCalls, 0);
    expect(notifications.submitCalls, 0);
  });

  test('outside window skips foreground and notification checks', () async {
    await saveSettings(
      activeWindow: ActiveWindow.bounded(
        startMinute: 8 * 60,
        endMinute: 9 * 60,
      ),
    );

    final outcome = await createService().runOnce();

    expect(outcome, ReminderRunOutcome.outsideActiveWindow);
    expect(foreground.calls, 0);
    expect(notifications.canPostCalls, 0);
  });

  test(
    'foreground execution skips capability and does not consume history',
    () async {
      await saveSettings();
      foreground.result = true;

      final outcome = await createService().runOnce();

      expect(outcome, ReminderRunOutcome.foregroundSuppressed);
      expect(notifications.canPostCalls, 0);
      expect((await items.getReviewItem(item.id))!.lastShownAt, isNull);
    },
  );

  test('unavailable notifications do not consume history', () async {
    await saveSettings();
    notifications.available = false;

    final outcome = await createService().runOnce();

    expect(outcome, ReminderRunOutcome.notificationUnavailable);
    expect(notifications.canPostCalls, 1);
    expect(notifications.submitCalls, 0);
    expect((await items.getReviewItem(item.id))!.lastShownAt, isNull);
  });

  test('no eligible item does not submit or update history', () async {
    await saveSettings();
    await items.updateReviewItem(
      id: item.id,
      content: item.content,
      topicId: item.topicId,
      enabled: false,
      now: now,
    );

    final outcome = await createService().runOnce();

    expect(outcome, ReminderRunOutcome.noEligibleItem);
    expect(notifications.submitCalls, 0);
    expect((await items.getReviewItem(item.id))!.lastShownAt, isNull);
  });

  test('failed submission rolls back staged last-shown timestamp', () async {
    await saveSettings();
    notifications.submitError = StateError('notification submission failed');

    final outcome = await createService().runOnce();

    expect(outcome, ReminderRunOutcome.notificationSubmissionFailed);
    final persistedItem = (await items.getReviewItem(item.id))!;
    expect(persistedItem.lastShownAt, isNull);
    expect(persistedItem.reminderCount, 0);
    expect(
      (await TopicRepository(store).listTopics()).single.lastRemindedAt,
      isNull,
    );
    final state = await runtime.loadState();
    expect(state.lastEvaluationOutcome, 'notification_submission_failed');
    expect(state.lastDispatchAt, isNull);
  });

  test('successful submission commits history and dispatch evidence', () async {
    await saveSettings();

    final outcome = await createService().runOnce();

    expect(outcome, ReminderRunOutcome.notificationSubmitted);
    expect(notifications.submitCalls, 1);
    expect(foreground.calls, 2);
    expect(notifications.canPostCalls, 2);
    final persistedItem = (await items.getReviewItem(item.id))!;
    expect(persistedItem.lastShownAt, now);
    expect(persistedItem.reminderCount, 1);
    expect(
      (await TopicRepository(store).listTopics()).single.lastRemindedAt,
      now,
    );
    final state = await runtime.loadState();
    expect(state.lastEvaluationOutcome, 'notification_submitted');
    expect(state.lastDispatchAt, now);
    expect(state.lastDispatchItemId, item.id);
    expect(state.lastDispatchTopicId, item.topicId);
  });

  test(
    'weekly plan filters candidates to the current weekday topics',
    () async {
      final otherTopic = await TopicRepository(store)
          .createTopic(name: '外科', now: now);
      final selectedItem = await items.createReviewItem(
        content: '周一主题内容',
        topicId: otherTopic.id,
        enabled: true,
        now: now.subtract(const Duration(days: 2)),
      );
      await saveSettings(
        weeklyTopicIds: <int, Set<int>>{
          DateTime.monday: <int>{otherTopic.id},
          DateTime.tuesday: <int>{item.topicId},
        },
      );

      final outcome = await createService().runOnce();

      expect(outcome, ReminderRunOutcome.notificationSubmitted);
      expect(notifications.submittedIds, [selectedItem.id]);
    },
  );

  test('weekday with no plan entry submits no notification', () async {
    final otherTopic = await TopicRepository(store)
        .createTopic(name: '外科', now: now);
    await items.createReviewItem(
      content: '周二主题内容',
      topicId: otherTopic.id,
      enabled: true,
      now: now.subtract(const Duration(days: 2)),
    );
    await saveSettings(
      weeklyTopicIds: <int, Set<int>>{
        DateTime.tuesday: <int>{item.topicId, otherTopic.id},
      },
    );

    final outcome = await createService().runOnce();

    expect(outcome, ReminderRunOutcome.noEligibleItem);
    expect(notifications.submitCalls, 0);
  });

  test('concurrent runs submit one unchanged candidate only once', () async {
    await saveSettings();
    final submitStarted = Completer<void>();
    final allowSubmitToFinish = Completer<void>();
    notifications.onSubmit = (_) async {
      if (!submitStarted.isCompleted) submitStarted.complete();
      await allowSubmitToFinish.future;
    };

    final firstRun = createService().runOnce();
    await submitStarted.future;
    final secondRun = createService().runOnce();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notifications.submitCalls, 1);
    allowSubmitToFinish.complete();

    expect(await firstRun, ReminderRunOutcome.notificationSubmitted);
    expect(await secondRun, ReminderRunOutcome.noEligibleItem);
    expect(notifications.submitCalls, 1);
  });
  test('diagnostics can read while a twelve-item notification submission is pending', () async {
    final sameTopicItems = <ReviewItem>[item];
    for (var index = 2; index <= 12; index++) {
      sameTopicItems.add(
        await items.createReviewItem(
          content: '同一主题下的第$index条内容',
          topicId: item.topicId,
          enabled: true,
          now: now.add(Duration(minutes: index)),
        ),
      );
    }
    await saveSettings(
      interval: const Duration(minutes: 1),
      repeatCooldown: const Duration(minutes: 1),
    );
    final submitStarted = Completer<void>();
    final allowSubmitToFinish = Completer<void>();
    notifications.onSubmit = (_) async {
      if (!submitStarted.isCompleted) submitStarted.complete();
      await allowSubmitToFinish.future;
    };
    final dispatch = createService().runOnce();
    await submitStarted.future;

    Object? readError;
    AppDatabase? diagnosticStore;
    try {
      diagnosticStore = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: path,
        singleInstance: false,
      ).timeout(const Duration(milliseconds: 500));
      await ReminderSettingsRepository(diagnosticStore)
          .loadSettings()
          .timeout(const Duration(milliseconds: 500));
    } catch (error) {
      readError = error;
    } finally {
      allowSubmitToFinish.complete();
    }

    expect(await dispatch, ReminderRunOutcome.notificationSubmitted);
    if (diagnosticStore != null) await diagnosticStore.close();
    expect(readError, isNull);
    expect(notifications.submittedIds, [item.id]);
    expect((await items.listReviewItems()), hasLength(12));
    expect(
      (await items.listReviewItems()).every(
        (record) => record.topicId == item.topicId,
      ),
      isTrue,
    );
    expect(
      (await items.listReviewItems()).every(
        (record) => record.id == item.id || record.reminderCount == 0,
      ),
      isTrue,
    );
  });
}

final class _FixedClock implements ReminderClock {
  _FixedClock(this.utcNow, this.localNow);

  final DateTime utcNow;
  final DateTime localNow;

  @override
  DateTime nowUtc() => utcNow;

  @override
  DateTime nowLocal() => localNow;
}

final class _FakeForegroundStatus implements ForegroundStatus {
  bool result = false;
  int calls = 0;

  @override
  Future<bool> isForeground() async {
    calls++;
    return result;
  }
}

final class _FakeNotifications implements ReviewNotificationGateway {
  bool available = true;
  int canPostCalls = 0;
  int submitCalls = 0;
  final List<int> submittedIds = <int>[];
  Object? submitError;
  Future<void> Function(ReviewItem item)? onSubmit;

  @override
  Future<void> initialize({void Function(int itemId)? onTap}) async {}

  @override
  Future<bool> canPost() async {
    canPostCalls++;
    return available;
  }

  @override
  Future<bool> requestPermission() async => false;

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
  Future<void> sendTestNotification() async {}

  @override
  Future<void> submit(ReviewItem item) async {
    submitCalls++;
    submittedIds.add(item.id);
    await onSubmit?.call(item);
    if (submitError case final error?) throw error;
  }
}
