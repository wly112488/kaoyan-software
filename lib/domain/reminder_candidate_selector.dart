import 'reminder_scope.dart';
import 'repeat_cooldown_policy.dart';
import 'review_item.dart';

final class ReminderCandidateSelector {
  List<ReviewItem> eligibleItems({
    required List<ReviewItem> items,
    required ReminderScope scope,
    required Duration repeatCooldown,
    required DateTime now,
    Duration globalInterval = Duration.zero,
    DateTime? lastDispatchAt,
    Map<int, Duration> topicIntervals = const <int, Duration>{},
    Map<int, DateTime> topicLastRemindedAt = const <int, DateTime>{},
  }) {
    if (repeatCooldown.isNegative) {
      throw ArgumentError.value(
        repeatCooldown,
        'repeatCooldown',
        'Repeat cooldown must not be negative',
      );
    }

    final inScope = items
        .where((item) {
          if (!item.enabled) {
            return false;
          }
          if (!scope.allows(item.topicId)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final effectiveCooldown = effectiveRepeatCooldown(
      maximumCooldown: repeatCooldown,
      globalInterval: globalInterval,
      activeContentCount: inScope.length,
    );

    bool isEligible(ReviewItem item) {
      final topicInterval = _maxDuration(
        globalInterval,
        topicIntervals[item.topicId] ?? globalInterval,
      );
      final globalDue = lastDispatchAt?.add(globalInterval);
      final topicDue = topicLastRemindedAt[item.topicId]?.add(topicInterval);
      final itemDue = item.lastShownAt?.add(
        _maxDuration(effectiveCooldown, topicInterval),
      );
      return <DateTime?>[
        globalDue,
        topicDue,
        itemDue,
      ].whereType<DateTime>().every((due) => !now.isBefore(due));
    }

    final unseen = inScope.where((item) => item.lastShownAt == null).toList();
    // Intervals decide eligibility first. FIFO then chooses among eligible
    // never-shown items; a cooling-down early item must not hide a later
    // never-shown item that is eligible now. Repeats remain a fallback tier
    // only after every never-shown item has been shown at least once.
    final eligibleUnseen = unseen.where(isEligible).toList(growable: false);
    final eligible = eligibleUnseen.isNotEmpty
        ? eligibleUnseen
        : unseen.isNotEmpty
        ? const <ReviewItem>[]
        : inScope
              .where((item) => item.lastShownAt != null && isEligible(item))
              .toList(growable: false);

    final sorted = [...eligible]..sort(_compare);
    return List<ReviewItem>.unmodifiable(sorted);
  }

  ReviewItem? selectNext({
    required List<ReviewItem> items,
    required ReminderScope scope,
    required Duration repeatCooldown,
    required DateTime now,
    Duration globalInterval = Duration.zero,
    DateTime? lastDispatchAt,
    Map<int, Duration> topicIntervals = const <int, Duration>{},
    Map<int, DateTime> topicLastRemindedAt = const <int, DateTime>{},
  }) {
    final eligible = eligibleItems(
      items: items,
      scope: scope,
      repeatCooldown: repeatCooldown,
      now: now,
      globalInterval: globalInterval,
      lastDispatchAt: lastDispatchAt,
      topicIntervals: topicIntervals,
      topicLastRemindedAt: topicLastRemindedAt,
    );
    return eligible.isEmpty ? null : eligible.first;
  }

  static Duration _maxDuration(Duration a, Duration b) => a >= b ? a : b;

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

    final countComparison = a.reminderCount.compareTo(b.reminderCount);
    if (countComparison != 0) {
      return countComparison;
    }

    final shownComparison = a.lastShownAt!.compareTo(b.lastShownAt!);
    if (shownComparison != 0) {
      return shownComparison;
    }
    return a.id.compareTo(b.id);
  }
}
