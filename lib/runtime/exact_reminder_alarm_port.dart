abstract interface class ExactReminderAlarmPort {
  Future<bool> canScheduleExactAlarms();
  Future<bool> schedule(DateTime at, {bool keepExisting = false});
  Future<void> cancel();
}
