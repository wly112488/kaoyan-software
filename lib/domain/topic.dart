String normalizeTopicName(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(raw, 'name', 'Topic name must not be blank');
  }
  return normalized;
}

String topicNameKey(String raw) => normalizeTopicName(raw).toLowerCase();

final class Topic {
  Topic({
    required this.id,
    required String name,
    required this.createdAt,
    required this.updatedAt,
  }) : name = normalizeTopicName(name) {
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'Topic id must be positive');
    }
  }

  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
}
