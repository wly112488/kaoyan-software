enum ReminderScopeMode { allTopics, selectedTopics }

final class ReminderScope {
  ReminderScope._(this.mode, Set<int> topicIds)
      : topicIds = Set<int>.unmodifiable(topicIds);

  factory ReminderScope.allTopics() {
    return ReminderScope._(ReminderScopeMode.allTopics, const <int>{});
  }

  factory ReminderScope.selectedTopics(Set<int> topicIds) {
    if (topicIds.isEmpty) {
      throw ArgumentError.value(
        topicIds,
        'topicIds',
        'SELECTED_TOPICS must not be empty',
      );
    }
    if (topicIds.any((id) => id <= 0)) {
      throw ArgumentError.value(
        topicIds,
        'topicIds',
        'Topic ids must be positive',
      );
    }
    return ReminderScope._(ReminderScopeMode.selectedTopics, topicIds);
  }

  final ReminderScopeMode mode;
  final Set<int> topicIds;

  bool allows(int topicId) {
    if (topicId <= 0) {
      return false;
    }
    return mode == ReminderScopeMode.allTopics || topicIds.contains(topicId);
  }
}
