import 'package:android_process_state/android_process_state.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_runtime_state_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/review_item.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/runtime/reminder_runtime_bootstrap.dart';
import 'package:kaoyan_review/runtime/review_notification_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android runtime foreground and notification adapters work', (
    tester,
  ) async {
    expect(await const AndroidProcessState().isForeground(), isTrue);

    await ReminderRuntimeBootstrap.initialize();
    final store = await AppDatabase.openProduction();
    late int topicId;
    try {
      final services = AppServices(store: store);
      final now = DateTime.now();
      final topic = await services.topics.createTopic(
        name: 'Android runtime test ${now.microsecondsSinceEpoch}',
        now: now,
      );
      topicId = topic.id;
      await services.reviewItems.createReviewItem(
        content: 'Android reminder integration smoke',
        topicId: topic.id,
        enabled: true,
        now: now,
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
      await services.rescheduleReminders();
    } finally {
      await store.close();
    }
    final runtimeStore = await AppDatabase.openProduction();
    try {
      final state = await ReminderRuntimeStateRepository(runtimeStore)
          .loadState();
      expect(state.scheduleStatus, ReminderScheduleStatus.scheduled);
    } finally {
      await runtimeStore.close();
    }

    final gateway = AndroidReviewNotificationGateway();
    await gateway.initialize();
    expect(await gateway.canPost(), isTrue);

    final item = ReviewItem(
      id: 9001,
      content: 'Android reminder integration smoke',
      topicId: topicId,
      enabled: true,
      createdAt: DateTime.utc(2026, 9, 28),
      updatedAt: DateTime.utc(2026, 9, 28),
    );
    await gateway.submit(item);

    var active = await FlutterLocalNotificationsPlugin()
        .getActiveNotifications();
    for (var attempt = 0; attempt < 10; attempt++) {
      if (active.any((notification) => notification.id == 9001)) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      active = await FlutterLocalNotificationsPlugin().getActiveNotifications();
    }
    expect(active.any((notification) => notification.id == 9001), isTrue);
  });
}
