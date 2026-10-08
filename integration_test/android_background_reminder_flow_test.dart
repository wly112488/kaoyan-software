import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:android_process_state/android_process_state.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/app/app_shell.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/runtime/android_reminder_alarm_port.dart';
import 'package:kaoyan_review/runtime/reminder_runtime_bootstrap.dart';
import 'package:kaoyan_review/runtime/reminder_scheduler.dart';

// Host sends HOME / briefly launches MainActivity at the markers. No host
// command starts a job or alarm. Save/settings and actual OS callbacks drive
// every reminder under test. Run with --dart-define=REMINDER_FALLBACK=true
// and deny SCHEDULE_EXACT_ALARM on the emulator for the WorkManager case.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fallback = bool.fromEnvironment('REMINDER_FALLBACK');
  testWidgets(
    'two topic contents continue after foreground suppression and a brief visit',
    (tester) async {
      await ReminderRuntimeBootstrap.initialize();
      final services = AppServices(store: await AppDatabase.openProduction());
      final label = fallback ? 'fallback' : 'native';
      try {
        await AndroidReminderAlarmPort().cancel();
        await WorkmanagerOneOffWorkPort().cancel();
        debugPrint('REMINDER_TEST_PREPARE $label');
        final permissionDeadline = DateTime.now().add(
          const Duration(seconds: 30),
        );
        while (DateTime.now().isBefore(permissionDeadline) &&
            ((await AndroidReminderAlarmPort().canScheduleExactAlarms()) !=
                    !fallback ||
                !await services.notifications.canPost())) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        await services.notifications.initialize();
        expect(
          await AndroidReminderAlarmPort().canScheduleExactAlarms(),
          !fallback,
        );
        expect(await services.notifications.canPost(), isTrue);
        final now = DateTime.now().toUtc();
        final topic = await services.topics.createTopic(
          name: '后台回归 $label $now',
          now: now,
        );
        final ids = <int>{};
        for (var i = 0; i < 2; i++) {
          final item = await services.reviewItems.createReviewItem(
            content: '实际主题复习内容 $label ${i + 1}',
            topicId: topic.id,
            enabled: true,
            now: now.add(Duration(seconds: i)),
          );
          ids.add(item.id);
        }
        await (await services.store.database).update(
          'reminder_runtime_state',
          <String, Object?>{
            'last_evaluation_at_us': null,
            'last_evaluation_outcome': null,
            'last_dispatch_at_us': null,
            'last_dispatch_item_id': null,
            'last_dispatch_topic_id': null,
          },
          where: 'id = 1',
        );
        await tester.pumpWidget(
          MaterialApp(home: AppShell(services: services)),
        );
        expect(
          await services.settingsService.save(
            ReminderSettings(
              enabled: true,
              activeWindow: ActiveWindow.allDay(),
              reminderInterval: const Duration(minutes: 1),
              repeatCooldown: const Duration(minutes: 1),
              scope: ReminderScope.selectedTopics(<int>{topic.id}),
            ),
          ),
          isTrue,
        );

        final foregroundDeadline = DateTime.now().add(
          const Duration(seconds: 110),
        );
        var state = await services.runtimeState.loadState();
        while (state.lastEvaluationOutcome != 'foregroundSuppressed' &&
            DateTime.now().isBefore(foregroundDeadline)) {
          await Future<void>.delayed(const Duration(seconds: 1));
          state = await services.runtimeState.loadState();
        }
        expect(state.lastEvaluationOutcome, 'foregroundSuppressed');
        expect(state.lastDispatchAt, isNull);
        debugPrint(
          'REMINDER_TEST_HOME $label ${DateTime.now().toIso8601String()}',
        );
        final observedIds = <int>{};
        final dispatches = <DateTime>[];
        final backgroundDeadline = DateTime.now().add(
          const Duration(minutes: 5),
        );
        while (dispatches.length < 3 &&
            DateTime.now().isBefore(backgroundDeadline)) {
          await Future<void>.delayed(const Duration(seconds: 1));
          state = await services.runtimeState.loadState();
          final dispatchedAt = state.lastDispatchAt;
          if (dispatchedAt == null || dispatches.contains(dispatchedAt)) {
            continue;
          }
          expect(await const AndroidProcessState().isForeground(), isFalse);
          expect(ids.contains(state.lastDispatchItemId), isTrue);
          observedIds.add(state.lastDispatchItemId!);
          dispatches.add(dispatchedAt);
          debugPrint(
            'REMINDER_TEST_DISPATCH $label count=${dispatches.length} '
            'item=${state.lastDispatchItemId} at=$dispatchedAt source=${state.lastEvaluationSource}',
          );
          expect(
            await services.notifications.activeReviewItemNotificationIds(),
            contains(state.lastDispatchItemId),
          );
          if (dispatches.length == 1) {
            debugPrint('REMINDER_TEST_REENTER $label');
            final resumeDeadline = DateTime.now().add(
              const Duration(seconds: 15),
            );
            while (!await const AndroidProcessState().isForeground() &&
                DateTime.now().isBefore(resumeDeadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 250));
            }
            expect(await const AndroidProcessState().isForeground(), isTrue);
            await Future<void>.delayed(const Duration(seconds: 2));
            debugPrint('REMINDER_TEST_EXIT_BRIEF $label');
          }
        }
        expect(dispatches.length, 3);
        expect(observedIds, ids);
        for (var i = 1; i < dispatches.length; i++) {
          final gap = dispatches[i].difference(dispatches[i - 1]);
          expect(gap, greaterThanOrEqualTo(const Duration(minutes: 1)));
          // The five-minute observation window proves continuation. WorkManager
          // may run late, so do not assert an exact/short maximum dispatch gap.
        }
        expect(
          state.lastEvaluationSource,
          fallback ? 'workmanager' : 'scheduled_alarm',
        );
      } finally {
        await AndroidReminderAlarmPort().cancel();
        await WorkmanagerOneOffWorkPort().cancel();
        await tester.pumpWidget(const SizedBox.shrink());
        await services.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
