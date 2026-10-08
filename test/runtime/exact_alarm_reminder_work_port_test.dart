import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/runtime/exact_reminder_alarm_port.dart';
import 'package:kaoyan_review/runtime/reminder_scheduler.dart';

void main() {
  final now = DateTime(2026, 10, 7, 11, 0);

  test(
    'uses an exact alarm at the computed due time when permission is granted',
    () async {
      final alarm = _FakeAlarmPort(canSchedule: true);
      final fallback = _FakeWorkPort();
      final port = ExactAlarmReminderWorkPort(
        alarm: alarm,
        fallback: fallback,
        now: () => now,
      );

      await port.register(initialDelay: const Duration(minutes: 2));

      expect(alarm.scheduledAt, now.add(const Duration(minutes: 2)));
      expect(fallback.registerCount, 0);
      expect(fallback.cancelCount, 1);
    },
  );

  test(
    'uses WorkManager only when exact alarm permission is unavailable',
    () async {
      final alarm = _FakeAlarmPort(canSchedule: false);
      final fallback = _FakeWorkPort();
      final port = ExactAlarmReminderWorkPort(
        alarm: alarm,
        fallback: fallback,
        now: () => now,
      );

      await port.register(initialDelay: const Duration(minutes: 2));

      expect(alarm.scheduledAt, isNull);
      expect(fallback.registeredInitialDelay, const Duration(minutes: 2));
    },
  );

  test('cancel removes both the exact alarm and fallback work', () async {
    final alarm = _FakeAlarmPort(canSchedule: true);
    final fallback = _FakeWorkPort();
    final port = ExactAlarmReminderWorkPort(
      alarm: alarm,
      fallback: fallback,
      now: () => now,
    );

    await port.cancel();

    expect(alarm.cancelCount, 1);
    expect(fallback.cancelCount, 1);
  });
}

final class _FakeAlarmPort implements ExactReminderAlarmPort {
  _FakeAlarmPort({required this.canSchedule});

  final bool canSchedule;
  DateTime? scheduledAt;
  int cancelCount = 0;

  @override
  Future<bool> canScheduleExactAlarms() async => canSchedule;

  @override
  Future<bool> schedule(DateTime at) async {
    scheduledAt = at;
    return true;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }
}

final class _FakeWorkPort implements ReminderWorkPort {
  Duration? registeredInitialDelay;
  int registerCount = 0;
  int cancelCount = 0;

  @override
  Future<void> register({required Duration initialDelay}) async {
    registerCount++;
    registeredInitialDelay = initialDelay;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }
}
