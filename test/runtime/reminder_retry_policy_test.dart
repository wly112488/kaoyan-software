import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/runtime/reminder_execution_service.dart';
import 'package:kaoyan_review/runtime/reminder_retry_policy.dart';

void main() {
  ReminderSettings settings(Duration interval) => ReminderSettings(
    enabled: true,
    activeWindow: ActiveWindow.allDay(),
    reminderInterval: interval,
    repeatCooldown: interval,
    scope: ReminderScope.allTopics(),
  );

  test('foreground suppression retry follows the configured interval', () {
    expect(
      retryDelayAfterReminderRun(
        ReminderRunOutcome.foregroundSuppressed,
        settings(const Duration(minutes: 1)),
      ),
      const Duration(minutes: 1),
    );
  });

  test('notification-unavailable retry follows the configured interval', () {
    expect(
      retryDelayAfterReminderRun(
        ReminderRunOutcome.notificationUnavailable,
        settings(const Duration(minutes: 7)),
      ),
      const Duration(minutes: 7),
    );
  });

  test('successful and terminal outcomes add no artificial retry delay', () {
    expect(
      retryDelayAfterReminderRun(
        ReminderRunOutcome.notificationSubmitted,
        settings(const Duration(minutes: 1)),
      ),
      Duration.zero,
    );
    expect(
      retryDelayAfterReminderRun(
        ReminderRunOutcome.noEligibleItem,
        settings(const Duration(minutes: 1)),
      ),
      Duration.zero,
    );
  });
}
