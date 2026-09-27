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
  const ReminderEvaluationResult._({
    required this.outcome,
    this.candidate,
  });

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

  ReminderEvaluationResult evaluate({
    required ReminderSettings settings,
    required List<ReviewItem> items,
    required DateTime now,
    required bool withinActiveWindow,
    required bool isForeground,
    required bool notificationAvailable,
  }) {
    if (!settings.enabled) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.reminderDisabled,
      );
    }
    if (!withinActiveWindow) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.outsideActiveWindow,
      );
    }
    if (isForeground) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.foregroundSuppressed,
      );
    }
    if (!notificationAvailable) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.notificationUnavailable,
      );
    }

    final candidate = _selector.selectNext(
      items: items,
      scope: settings.scope,
      repeatCooldown: settings.repeatCooldown,
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
