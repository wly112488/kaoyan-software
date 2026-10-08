abstract interface class ExactReminderAlarmPort {
  Future<bool> canScheduleExactAlarms();
  Future<bool> schedule(DateTime at);
  Future<void> cancel();
}
