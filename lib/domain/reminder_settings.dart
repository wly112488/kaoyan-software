import 'active_window.dart';
import 'reminder_scope.dart';

const minimumProductionReminderInterval = Duration(minutes: 1);
const maximumProductionReminderInterval = Duration(hours: 24);
const maximumRepeatCooldown = Duration(days: 30);

final class ReminderSettings {
  ReminderSettings({
    required this.enabled,
    required this.activeWindow,
    required this.reminderInterval,
    required this.repeatCooldown,
    required this.scope,
    Map<int, Set<int>> weeklyTopicIds = const <int, Set<int>>{},
  }) {
    if (reminderInterval < minimumProductionReminderInterval) {
      throw ArgumentError.value(
        reminderInterval,
        'reminderInterval',
        'Production reminder interval must be at least 1 minute',
      );
    }
    if (reminderInterval > maximumProductionReminderInterval) {
      throw ArgumentError.value(
        reminderInterval,
        'reminderInterval',
        'Reminder interval must not exceed 24 hours',
      );
    }
    if (repeatCooldown < reminderInterval) {
      throw ArgumentError.value(
        repeatCooldown,
        'repeatCooldown',
        'Repeat cooldown must be at least the global reminder interval',
      );
    }
    if (repeatCooldown > maximumRepeatCooldown) {
      throw ArgumentError.value(
        repeatCooldown,
        'repeatCooldown',
        'Repeat cooldown must not exceed 30 days',
      );
    }
    for (final entry in weeklyTopicIds.entries) {
      if (entry.key < DateTime.monday ||
          entry.key > DateTime.sunday ||
          entry.value.isEmpty ||
          entry.value.any((id) => id <= 0)) {
        throw ArgumentError.value(
          weeklyTopicIds,
          'weeklyTopicIds',
          'Weekly topic plan needs weekdays 1–7 and non-empty positive Topic IDs',
        );
      }
    }
    this.weeklyTopicIds = Map<int, Set<int>>.unmodifiable(
      weeklyTopicIds.map(
        (day, ids) => MapEntry(day, Set<int>.unmodifiable(ids)),
      ),
    );
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
  late final Map<int, Set<int>> weeklyTopicIds;

  bool get hasWeeklyTopicPlan => weeklyTopicIds.isNotEmpty;

  Set<int>? topicsForWeekday(int weekday) => weeklyTopicIds[weekday];
}
