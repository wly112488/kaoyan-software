import 'reminder_settings.dart';

enum ReminderEvaluationOutcome {
  reminderDisabled,
  outsideActiveWindow,
  foregroundSuppressed,
  notificationUnavailable,
}

final class ReminderEvaluator {
  ReminderEvaluationOutcome? blockingOutcome({
    required ReminderSettings settings,
    required bool withinActiveWindow,
    required bool isForeground,
    required bool notificationAvailable,
  }) {
    if (!settings.enabled) {
      return ReminderEvaluationOutcome.reminderDisabled;
    }
    if (!withinActiveWindow) {
      return ReminderEvaluationOutcome.outsideActiveWindow;
    }
    if (isForeground) {
      return ReminderEvaluationOutcome.foregroundSuppressed;
    }
    if (!notificationAvailable) {
      return ReminderEvaluationOutcome.notificationUnavailable;
    }
    return null;
  }
}
