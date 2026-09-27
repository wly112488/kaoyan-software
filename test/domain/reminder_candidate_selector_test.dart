import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/reminder_candidate_selector.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/review_item.dart';

ReviewItem item({
  required int id,
  required int topicId,
  required DateTime createdAt,
  DateTime? lastShownAt,
  bool enabled = true,
}) {
  return ReviewItem(
    id: id,
    content: 'item-$id',
    topicId: topicId,
    enabled: enabled,
    createdAt: createdAt,
    updatedAt: createdAt,
    lastShownAt: lastShownAt,
  );
}

void main() {
  final selector = ReminderCandidateSelector();
  final now = DateTime.utc(2026, 9, 27, 12);
  final cooldown = const Duration(hours: 24);

  test('filters disabled, out-of-scope, and cooling-down items', () {
    final selected = selector.eligibleItems(
      items: [
        item(id: 1, topicId: 1, createdAt: now.subtract(const Duration(days: 4))),
        item(id: 2, topicId: 2, createdAt: now.subtract(const Duration(days: 3))),
        item(
          id: 3,
          topicId: 1,
          createdAt: now.subtract(const Duration(days: 2)),
          lastShownAt: now.subtract(const Duration(hours: 23)),
        ),
        item(
          id: 4,
          topicId: 1,
          createdAt: now.subtract(const Duration(days: 1)),
          enabled: false,
        ),
      ],
      scope: ReminderScope.selectedTopics({1}),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(selected.map((e) => e.id), [1]);
  });

  test('includes an item exactly at the cooldown boundary', () {
    final candidate = selector.selectNext(
      items: [
        item(
          id: 8,
          topicId: 1,
          createdAt: now.subtract(const Duration(days: 2)),
          lastShownAt: now.subtract(cooldown),
        ),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate?.id, 8);
  });

  test('orders never-shown first by createdAt then stable id', () {
    final candidate = selector.selectNext(
      items: [
        item(id: 9, topicId: 1, createdAt: DateTime.utc(2026, 9, 20)),
        item(id: 2, topicId: 1, createdAt: DateTime.utc(2026, 9, 20)),
        item(
          id: 1,
          topicId: 1,
          createdAt: DateTime.utc(2026, 9, 1),
          lastShownAt: DateTime.utc(2026, 9, 1),
        ),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate?.id, 2);
  });

  test('orders never-shown items by oldest createdAt', () {
    final candidate = selector.selectNext(
      items: [
        item(id: 1, topicId: 1, createdAt: DateTime.utc(2026, 9, 20)),
        item(id: 9, topicId: 1, createdAt: DateTime.utc(2026, 9, 10)),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate?.id, 9);
  });

  test('orders previously shown items by oldest lastShownAt then stable id', () {
    final oldShownAt = DateTime.utc(2026, 9, 1);
    final candidate = selector.selectNext(
      items: [
        item(
          id: 9,
          topicId: 1,
          createdAt: DateTime.utc(2026, 8, 1),
          lastShownAt: oldShownAt,
        ),
        item(
          id: 2,
          topicId: 1,
          createdAt: DateTime.utc(2026, 8, 2),
          lastShownAt: oldShownAt,
        ),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate?.id, 2);
  });

  test('orders previously shown items by oldest lastShownAt', () {
    final candidate = selector.selectNext(
      items: [
        item(
          id: 9,
          topicId: 1,
          createdAt: DateTime.utc(2026, 8, 2),
          lastShownAt: DateTime.utc(2026, 9, 1),
        ),
        item(
          id: 1,
          topicId: 1,
          createdAt: DateTime.utc(2026, 8, 1),
          lastShownAt: DateTime.utc(2026, 9, 10),
        ),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate?.id, 9);
  });

  test('returns null when no item is eligible', () {
    final candidate = selector.selectNext(
      items: [
        item(
          id: 1,
          topicId: 1,
          createdAt: now.subtract(const Duration(days: 2)),
          lastShownAt: now.subtract(const Duration(minutes: 5)),
        ),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate, isNull);
  });
}
