import '../domain/reminder_settings.dart';
import 'reminder_execution_service.dart';

Duration retryDelayAfterReminderRun(
  ReminderRunOutcome outcome,
  ReminderSettings settings,
) {
  return switch (outcome) {
    ReminderRunOutcome.foregroundSuppressed ||
    ReminderRunOutcome.notificationUnavailable => settings.reminderInterval,
    _ => Duration.zero,
  };
}
