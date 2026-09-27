import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_evaluator.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/domain/review_item.dart';

ReminderSettings settings({bool enabled = true}) {
  return ReminderSettings(
    enabled: enabled,
    activeWindow: ActiveWindow.allDay(),
    reminderInterval: const Duration(minutes: 15),
    repeatCooldown: const Duration(hours: 24),
    scope: ReminderScope.allTopics(),
  );
}

ReviewItem eligibleItem(DateTime now) {
  return ReviewItem(
    id: 1,
    content: '有效复习内容',
    topicId: 1,
    enabled: true,
    createdAt: now.subtract(const Duration(days: 1)),
    updatedAt: now.subtract(const Duration(days: 1)),
  );
}

void main() {
  final evaluator = ReminderEvaluator();
  final now = DateTime.utc(2026, 9, 27, 12);

  test('disabled reminders short-circuit first', () {
    final result = evaluator.evaluate(
      settings: settings(enabled: false),
      items: [eligibleItem(now)],
      now: now,
      withinActiveWindow: false,
      isForeground: true,
      notificationAvailable: false,
    );

    expect(result.outcome, ReminderEvaluationOutcome.reminderDisabled);
    expect(result.candidate, isNull);
  });

  test('outside active window precedes foreground and notification checks', () {
    final result = evaluator.evaluate(
      settings: settings(),
      items: [eligibleItem(now)],
      now: now,
      withinActiveWindow: false,
      isForeground: true,
      notificationAvailable: false,
    );

    expect(result.outcome, ReminderEvaluationOutcome.outsideActiveWindow);
  });

  test('foreground suppression precedes notification capability', () {
    final result = evaluator.evaluate(
      settings: settings(),
      items: [eligibleItem(now)],
      now: now,
      withinActiveWindow: true,
      isForeground: true,
      notificationAvailable: false,
    );

    expect(result.outcome, ReminderEvaluationOutcome.foregroundSuppressed);
  });

  test('notification unavailable precedes candidate selection', () {
    final result = evaluator.evaluate(
      settings: settings(),
      items: [eligibleItem(now)],
      now: now,
      withinActiveWindow: true,
      isForeground: false,
      notificationAvailable: false,
    );

    expect(result.outcome, ReminderEvaluationOutcome.notificationUnavailable);
  });

  test('reports noEligibleItem without a candidate', () {
    final result = evaluator.evaluate(
      settings: settings(),
      items: const [],
      now: now,
      withinActiveWindow: true,
      isForeground: false,
      notificationAvailable: true,
    );

    expect(result.outcome, ReminderEvaluationOutcome.noEligibleItem);
    expect(result.candidate, isNull);
  });

  test('returns deterministic candidate without mutating lastShownAt', () {
    final item = eligibleItem(now);
    final result = evaluator.evaluate(
      settings: settings(),
      items: [item],
      now: now,
      withinActiveWindow: true,
      isForeground: false,
      notificationAvailable: true,
    );

    expect(result.outcome, ReminderEvaluationOutcome.candidateSelected);
    expect(result.candidate?.id, item.id);
    expect(item.lastShownAt, isNull);
  });
}
