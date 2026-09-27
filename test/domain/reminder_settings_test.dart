import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';

void main() {
  final allTopics = ReminderScope.allTopics();

  test('accepts all-day, same-day, and cross-midnight window representations', () {
    expect(ActiveWindow.allDay().mode, ActiveWindowMode.allDay);
    expect(
      ActiveWindow.bounded(startMinute: 8 * 60, endMinute: 23 * 60).mode,
      ActiveWindowMode.bounded,
    );
    expect(
      ActiveWindow.bounded(startMinute: 22 * 60, endMinute: 60).mode,
      ActiveWindowMode.bounded,
    );
  });

  test('rejects invalid bounded window values', () {
    expect(
      () => ActiveWindow.bounded(startMinute: -1, endMinute: 60),
      throwsArgumentError,
    );
    expect(
      () => ActiveWindow.bounded(startMinute: 60, endMinute: 1440),
      throwsArgumentError,
    );
    expect(
      () => ActiveWindow.bounded(startMinute: 60, endMinute: 60),
      throwsArgumentError,
    );
  });

  test('enforces 15-minute production reminder minimum', () {
    expect(
      () => ReminderSettings(
        enabled: true,
        activeWindow: ActiveWindow.allDay(),
        reminderInterval: const Duration(minutes: 14),
        repeatCooldown: Duration.zero,
        scope: allTopics,
      ),
      throwsArgumentError,
    );

    final settings = ReminderSettings(
      enabled: true,
      activeWindow: ActiveWindow.allDay(),
      reminderInterval: const Duration(minutes: 15),
      repeatCooldown: const Duration(hours: 24),
      scope: allTopics,
    );
    expect(settings.reminderInterval, const Duration(minutes: 15));
  });

  test('rejects negative cooldown', () {
    expect(
      () => ReminderSettings(
        enabled: true,
        activeWindow: ActiveWindow.allDay(),
        reminderInterval: const Duration(minutes: 15),
        repeatCooldown: const Duration(seconds: -1),
        scope: allTopics,
      ),
      throwsArgumentError,
    );
  });
  test('initial settings match the authoritative Spec defaults', () {
    final settings = ReminderSettings.initial();

    expect(settings.enabled, isFalse);
    expect(settings.activeWindow.mode, ActiveWindowMode.allDay);
    expect(settings.reminderInterval, const Duration(minutes: 60));
    expect(settings.repeatCooldown, const Duration(hours: 24));
    expect(settings.scope.mode, ReminderScopeMode.allTopics);
    expect(settings.scope.topicIds, isEmpty);
  });}
