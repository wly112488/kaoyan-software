import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_process_state/android_process_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_runtime_state_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/runtime/reminder_runtime_bootstrap.dart';
import 'package:kaoyan_review/runtime/review_notification_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WorkManager posts after a foreground due time when backgrounded', (
    tester,
  ) async {
    expect(await const AndroidProcessState().isForeground(), isTrue);
    await ReminderRuntimeBootstrap.initialize();

    final store = await AppDatabase.openProduction();
    final services = AppServices(store: store);
    try {
      final now = DateTime.now();
      final topic = await services.topics.createTopic(
        name: '后台通知验收主题 ${now.microsecondsSinceEpoch}',
        now: now,
      );
      final first = await services.reviewItems.createReviewItem(
        content: '后台通知验收内容 A ${now.microsecondsSinceEpoch}',
        topicId: topic.id,
        enabled: true,
        now: now,
      );
      final second = await services.reviewItems.createReviewItem(
        content: '后台通知验收内容 B ${now.microsecondsSinceEpoch}',
        topicId: topic.id,
        enabled: true,
        now: now.add(const Duration(seconds: 1)),
      );
      final configuredAt = DateTime.now();
      await services.reminderSettings.saveSettings(
        ReminderSettings(
          enabled: true,
          activeWindow: ActiveWindow.allDay(),
          reminderInterval: const Duration(minutes: 1),
          repeatCooldown: const Duration(minutes: 1),
          scope: ReminderScope.selectedTopics(<int>{topic.id}),
        ),
      );

      final db = await store.database;
      await db.update('reminder_runtime_state', <String, Object?>{
        'last_evaluation_at_us': null,
        'last_evaluation_outcome': null,
        'last_dispatch_at_us': null,
        'last_dispatch_item_id': null,
        'last_dispatch_topic_id': null,
        'last_worker_error_at_us': null,
        'last_worker_error_details': null,
        'last_evaluation_source': null,
        'last_worker_started_at_us': null,
        'last_worker_completed_at_us': null,
        'last_worker_outcome': null,
      }, where: 'id = 1');

      final gateway = AndroidReviewNotificationGateway();
      await gateway.initialize();
      var permissionGranted = await gateway.canPost();
      final permissionDeadline = DateTime.now().add(
        const Duration(seconds: 20),
      );
      while (!permissionGranted &&
          DateTime.now().isBefore(permissionDeadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        permissionGranted = await gateway.canPost();
      }
      expect(permissionGranted, isTrue);
      await services.scheduler.reconcile(
        await services.reminderSettings.loadSettings(),
        minimumDelay: const Duration(minutes: 1),
      );

      // Reproduce the reported flow exactly: leave the app visible for one
      // minute after saving, then let the host press HOME at the marker.
      final configuredDeadline = configuredAt.add(const Duration(minutes: 1));
      var state = await ReminderRuntimeStateRepository(store).loadState();
      while (DateTime.now().isBefore(configuredDeadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        state = await ReminderRuntimeStateRepository(store).loadState();
      }
      debugPrint(
        'EXIT_NOW configuredAt=${configuredAt.toIso8601String()} '
        'target=${configuredDeadline.toIso8601String()} '
        'actual=${DateTime.now().toIso8601String()} '
        'topic=${topic.id} '
        'itemIds=${first.id},${second.id} '
        'lastOutcome=${state.lastEvaluationOutcome} '
        'nextDue=${await services.scheduler.nextOpportunityAt()}',
      );

      // The host test runner sends HOME after seeing the marker above. Keep
      // this instrumentation run alive so Android does not uninstall or
      // force-stop the package before the real WorkManager delivery occurs.
      final backgroundDeadline = DateTime.now().add(
        const Duration(seconds: 130),
      );
      while ((state.lastEvaluationOutcome != 'notification_submitted' ||
              state.lastWorkerCompletedAt == null) &&
          DateTime.now().isBefore(backgroundDeadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        state = await ReminderRuntimeStateRepository(store).loadState();
      }
      expect(state.lastEvaluationOutcome, 'notification_submitted');
      expect(state.lastEvaluationSource, 'workmanager');
      expect(state.lastWorkerStartedAt, isNotNull);
      expect(state.lastWorkerCompletedAt, isNotNull);
      expect(state.lastWorkerOutcome, 'notificationSubmitted');
      final activeNotifications = await FlutterLocalNotificationsPlugin()
          .getActiveNotifications();
      expect(
        activeNotifications.any(
          (notification) =>
              notification.id == first.id || notification.id == second.id,
        ),
        isTrue,
        reason: 'The reminder must be active in Android NotificationManager',
      );
      debugPrint(
        'ANDROID_NOTIFICATION_ACTIVE ids=${activeNotifications.map((item) => item.id).join(',')}',
      );
    } finally {
      await services.close();
    }
  });
}
