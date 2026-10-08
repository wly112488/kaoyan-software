import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/active_window.dart';

void main() {
  test('all-day contains every local time', () {
    final window = ActiveWindow.allDay();
    expect(window.containsLocal(DateTime(2026, 9, 28, 0, 0)), isTrue);
    expect(window.containsLocal(DateTime(2026, 9, 28, 23, 59, 59)), isTrue);
  });

  test('same-day window is left-closed and right-open', () {
    final window = ActiveWindow.bounded(
      startMinute: 8 * 60,
      endMinute: 23 * 60,
    );
    expect(window.containsLocal(DateTime(2026, 9, 28, 7, 59, 59)), isFalse);
    expect(window.containsLocal(DateTime(2026, 9, 28, 8, 0)), isTrue);
    expect(window.containsLocal(DateTime(2026, 9, 28, 22, 59, 59)), isTrue);
    expect(window.containsLocal(DateTime(2026, 9, 28, 23, 0)), isFalse);
  });

  test('rejects a start time after the end time', () {
    expect(
      () => ActiveWindow.bounded(startMinute: 22 * 60 + 10, endMinute: 22 * 60),
      throwsArgumentError,
    );
  });
}
