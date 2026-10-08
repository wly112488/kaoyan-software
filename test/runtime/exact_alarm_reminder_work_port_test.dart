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

  test('alarm bridge failure still registers fallback work', () async {
    final alarm = _FakeAlarmPort(canSchedule: true)
      ..scheduleError = StateError('background alarm bridge unavailable');
    final fallback = _FakeWorkPort();
    await ExactAlarmReminderWorkPort(
      alarm: alarm,
      fallback: fallback,
      now: () => now,
    ).register(initialDelay: const Duration(minutes: 1));
    expect(fallback.registeredInitialDelay, const Duration(minutes: 1));
  });

  test(
    'lifecycle reconciliation asks native scheduler to keep its deadline',
    () async {
      final alarm = _FakeAlarmPort(canSchedule: true);
      await ExactAlarmReminderWorkPort(
        alarm: alarm,
        fallback: _FakeWorkPort(),
        now: () => now,
      ).register(
        initialDelay: const Duration(seconds: 20),
        policy: ReminderWorkPolicy.keep,
      );
      expect(alarm.keepExisting, isTrue);
    },
  );

  test('Worker transition to native alarm does not cancel itself', () async {
    final fallback = _FakeWorkPort();
    await ExactAlarmReminderWorkPort(
      alarm: _FakeAlarmPort(canSchedule: true),
      fallback: fallback,
      now: () => now,
    ).register(
      initialDelay: const Duration(minutes: 1),
      policy: ReminderWorkPolicy.append,
    );
    expect(fallback.cancelCount, 0);
  });
}

final class _FakeAlarmPort implements ExactReminderAlarmPort {
  _FakeAlarmPort({required this.canSchedule});

  final bool canSchedule;
  DateTime? scheduledAt;
  int cancelCount = 0;
  Object? scheduleError;
  bool? keepExisting;

  @override
  Future<bool> canScheduleExactAlarms() async => canSchedule;

  @override
  Future<bool> schedule(DateTime at, {bool keepExisting = false}) async {
    if (scheduleError case final error?) throw error;
    scheduledAt = at;
    this.keepExisting = keepExisting;
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
  Future<void> register({
    required Duration initialDelay,
    ReminderWorkPolicy policy = ReminderWorkPolicy.replace,
  }) async {
    registerCount++;
    registeredInitialDelay = initialDelay;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }
}
