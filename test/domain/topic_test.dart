import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/topic.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 27, 8);

  test('trims Topic display name and builds lowercase uniqueness key', () {
    final topic = Topic(
      id: 1,
      name: '  Biology  ',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    expect(topic.name, 'Biology');
    expect(topicNameKey('  BIOLOGY  '), 'biology');
  });

  test('rejects blank Topic name', () {
    expect(
      () =>
          Topic(id: 1, name: '   ', createdAt: createdAt, updatedAt: createdAt),
      throwsArgumentError,
    );
  });

  test('rejects non-positive Topic identity', () {
    expect(
      () =>
          Topic(id: 0, name: '医学', createdAt: createdAt, updatedAt: createdAt),
      throwsArgumentError,
    );
  });
}
