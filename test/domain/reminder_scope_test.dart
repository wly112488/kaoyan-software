import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';

void main() {
  test('ALL_TOPICS allows every positive Topic id', () {
    final scope = ReminderScope.allTopics();

    expect(scope.mode, ReminderScopeMode.allTopics);
    expect(scope.allows(1), isTrue);
    expect(scope.allows(99), isTrue);
  });

  test('SELECTED_TOPICS uses union membership', () {
    final scope = ReminderScope.selectedTopics({2, 5});

    expect(scope.mode, ReminderScopeMode.selectedTopics);
    expect(scope.allows(2), isTrue);
    expect(scope.allows(5), isTrue);
    expect(scope.allows(3), isFalse);
  });

  test('SELECTED_TOPICS rejects empty and invalid ids', () {
    expect(() => ReminderScope.selectedTopics({}), throwsArgumentError);
    expect(() => ReminderScope.selectedTopics({1, 0}), throwsArgumentError);
  });
}
