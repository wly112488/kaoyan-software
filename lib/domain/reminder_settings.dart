import 'active_window.dart';
import 'reminder_scope.dart';

const minimumProductionReminderInterval = Duration(minutes: 15);

final class ReminderSettings {
  ReminderSettings({
    required this.enabled,
    required this.activeWindow,
    required this.reminderInterval,
    required this.repeatCooldown,
    required this.scope,
  }) {
    if (reminderInterval < minimumProductionReminderInterval) {
      throw ArgumentError.value(
        reminderInterval,
        'reminderInterval',
        'Production reminder interval must be at least 15 minutes',
      );
    }
    if (repeatCooldown.isNegative) {
      throw ArgumentError.value(
        repeatCooldown,
        'repeatCooldown',
        'Repeat cooldown must not be negative',
      );
    }
  }

  factory ReminderSettings.initial() {
    return ReminderSettings(
      enabled: false,
      activeWindow: ActiveWindow.allDay(),
      reminderInterval: const Duration(minutes: 60),
      repeatCooldown: const Duration(hours: 24),
      scope: ReminderScope.allTopics(),
    );
  }
  final bool enabled;
  final ActiveWindow activeWindow;
  final Duration reminderInterval;
  final Duration repeatCooldown;
  final ReminderScope scope;
}
