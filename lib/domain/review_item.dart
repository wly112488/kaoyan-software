final class ReviewItem {
  ReviewItem({
    required this.id,
    required this.content,
    required this.topicId,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.lastShownAt,
  }) {
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'ReviewItem id must be positive');
    }
    if (topicId <= 0) {
      throw ArgumentError.value(
        topicId,
        'topicId',
        'ReviewItem topicId must be positive',
      );
    }
    if (content.trim().isEmpty) {
      throw ArgumentError.value(
        content,
        'content',
        'ReviewItem content must not be blank',
      );
    }
  }

  final int id;
  final String content;
  final int topicId;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastShownAt;
}
