import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_evaluator.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';

ReminderSettings settings({bool enabled = true}) {
  return ReminderSettings(
    enabled: enabled,
    activeWindow: ActiveWindow.allDay(),
    reminderInterval: const Duration(minutes: 15),
    repeatCooldown: const Duration(hours: 24),
    scope: ReminderScope.allTopics(),
  );
}

void main() {
  final evaluator = ReminderEvaluator();

  test('disabled reminders take precedence over other blockers', () {
    expect(
      evaluator.blockingOutcome(
        settings: settings(enabled: false),
        withinActiveWindow: false,
        isForeground: true,
        notificationAvailable: false,
      ),
      ReminderEvaluationOutcome.reminderDisabled,
    );
  });

  test('outside active window takes precedence over later checks', () {
    expect(
      evaluator.blockingOutcome(
        settings: settings(),
        withinActiveWindow: false,
        isForeground: true,
        notificationAvailable: false,
      ),
      ReminderEvaluationOutcome.outsideActiveWindow,
    );
  });

  test('foreground suppression takes precedence over notification status', () {
    expect(
      evaluator.blockingOutcome(
        settings: settings(),
        withinActiveWindow: true,
        isForeground: true,
        notificationAvailable: false,
      ),
      ReminderEvaluationOutcome.foregroundSuppressed,
    );
  });

  test('unavailable notifications block submission', () {
    expect(
      evaluator.blockingOutcome(
        settings: settings(),
        withinActiveWindow: true,
        isForeground: false,
        notificationAvailable: false,
      ),
      ReminderEvaluationOutcome.notificationUnavailable,
    );
  });

  test('returns null when no blocking condition applies', () {
    expect(
      evaluator.blockingOutcome(
        settings: settings(),
        withinActiveWindow: true,
        isForeground: false,
        notificationAvailable: true,
      ),
      isNull,
    );
  });
}
