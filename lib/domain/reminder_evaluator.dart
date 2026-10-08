import 'reminder_candidate_selector.dart';
import 'reminder_settings.dart';
import 'review_item.dart';

enum ReminderEvaluationOutcome {
  reminderDisabled,
  outsideActiveWindow,
  foregroundSuppressed,
  notificationUnavailable,
  noEligibleItem,
  candidateSelected,
}

final class ReminderEvaluationResult {
  const ReminderEvaluationResult._({required this.outcome, this.candidate});

  const ReminderEvaluationResult.withoutCandidate(
    ReminderEvaluationOutcome outcome,
  ) : this._(outcome: outcome);

  const ReminderEvaluationResult.withCandidate(ReviewItem candidate)
    : this._(
        outcome: ReminderEvaluationOutcome.candidateSelected,
        candidate: candidate,
      );

  final ReminderEvaluationOutcome outcome;
  final ReviewItem? candidate;
}

final class ReminderEvaluator {
  ReminderEvaluator({ReminderCandidateSelector? selector})
    : _selector = selector ?? ReminderCandidateSelector();

  final ReminderCandidateSelector _selector;

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

  ReminderEvaluationResult evaluate({
    required ReminderSettings settings,
    required List<ReviewItem> items,
    required DateTime now,
    required bool withinActiveWindow,
    required bool isForeground,
    required bool notificationAvailable,
  }) {
    final blocked = blockingOutcome(
      settings: settings,
      withinActiveWindow: withinActiveWindow,
      isForeground: isForeground,
      notificationAvailable: notificationAvailable,
    );
    if (blocked != null) {
      return ReminderEvaluationResult.withoutCandidate(blocked);
    }

    final candidate = _selector.selectNext(
      items: items,
      scope: settings.scope,
      repeatCooldown: settings.repeatCooldown,
      globalInterval: settings.reminderInterval,
      now: now,
    );
    if (candidate == null) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.noEligibleItem,
      );
    }

    return ReminderEvaluationResult.withCandidate(candidate);
  }
}
