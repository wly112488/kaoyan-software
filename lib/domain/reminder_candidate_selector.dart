import 'reminder_scope.dart';
import 'review_item.dart';

final class ReminderCandidateSelector {
  List<ReviewItem> eligibleItems({
    required List<ReviewItem> items,
    required ReminderScope scope,
    required Duration repeatCooldown,
    required DateTime now,
  }) {
    if (repeatCooldown.isNegative) {
      throw ArgumentError.value(
        repeatCooldown,
        'repeatCooldown',
        'Repeat cooldown must not be negative',
      );
    }

    final eligible = items.where((item) {
      if (!item.enabled) {
        return false;
      }
      if (!scope.allows(item.topicId)) {
        return false;
      }
      final lastShownAt = item.lastShownAt;
      if (lastShownAt == null) {
        return true;
      }
      final nextEligibleAt = lastShownAt.add(repeatCooldown);
      return !now.isBefore(nextEligibleAt);
    }).toList(growable: false);

    final sorted = [...eligible]..sort(_compare);
    return List<ReviewItem>.unmodifiable(sorted);
  }

  ReviewItem? selectNext({
    required List<ReviewItem> items,
    required ReminderScope scope,
    required Duration repeatCooldown,
    required DateTime now,
  }) {
    final eligible = eligibleItems(
      items: items,
      scope: scope,
      repeatCooldown: repeatCooldown,
      now: now,
    );
    return eligible.isEmpty ? null : eligible.first;
  }

  int _compare(ReviewItem a, ReviewItem b) {
    final aNeverShown = a.lastShownAt == null;
    final bNeverShown = b.lastShownAt == null;

    if (aNeverShown != bNeverShown) {
      return aNeverShown ? -1 : 1;
    }

    if (aNeverShown) {
      final createdComparison = a.createdAt.compareTo(b.createdAt);
      if (createdComparison != 0) {
        return createdComparison;
      }
      return a.id.compareTo(b.id);
    }

    final shownComparison = a.lastShownAt!.compareTo(b.lastShownAt!);
    if (shownComparison != 0) {
      return shownComparison;
    }
    return a.id.compareTo(b.id);
  }
}
