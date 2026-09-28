import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/review_item.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 27, 8);
  final shownAt = DateTime.utc(2026, 9, 27, 9);

  test('keeps passage formatting and reminder history', () {
    final item = ReviewItem(
      id: 7,
      content: '第一行\n第二行',
      topicId: 2,
      enabled: true,
      createdAt: createdAt,
      updatedAt: createdAt,
      lastShownAt: shownAt,
    );

    expect(item.content, '第一行\n第二行');
    expect(item.topicId, 2);
    expect(item.lastShownAt, shownAt);
  });

  test('rejects whitespace-only content', () {
    expect(
      () => ReviewItem(
        id: 7,
        content: ' \n ',
        topicId: 2,
        enabled: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
  });

  test('rejects non-positive identities', () {
    expect(
      () => ReviewItem(
        id: 0,
        content: '有效内容',
        topicId: 2,
        enabled: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => ReviewItem(
        id: 7,
        content: '有效内容',
        topicId: 0,
        enabled: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
  });
}
