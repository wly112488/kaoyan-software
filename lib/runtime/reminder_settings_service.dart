import '../data/local/reminder_settings_repository.dart';
import '../domain/reminder_settings.dart';
import 'reminder_scheduler.dart';

final class ReminderSettingsService {
  ReminderSettingsService({
    required ReminderSettingsRepository repository,
    required ReminderScheduler scheduler,
  })
    // Preserve the established public named constructor parameters.
    // ignore: prefer_initializing_formals
    : _repository = repository,
       // ignore: prefer_initializing_formals
       _scheduler = scheduler;

  final ReminderSettingsRepository _repository;
  final ReminderScheduler _scheduler;

  Future<bool> save(ReminderSettings settings) async {
    try {
      await _repository.saveSettings(settings);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ReminderSettingsWriteException(error),
        stackTrace,
      );
    }
    try {
      // Saving settings happens in the foreground. Start the first opportunity
      // after one configured interval so leaving the screen cannot race an
      // already-due alarm into an immediate notification.
      return await _scheduler.reconcile(
        settings,
        minimumDelay: settings.enabled
            ? settings.reminderInterval
            : Duration.zero,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(ReminderSchedulingException(error), stackTrace);
    }
  }
}

final class ReminderSettingsWriteException implements Exception {
  const ReminderSettingsWriteException(this.cause);

  final Object cause;

  @override
  String toString() => 'reminder settings write failed: $cause';
}

final class ReminderSchedulingException implements Exception {
  const ReminderSchedulingException(this.cause);

  final Object cause;

  @override
  String toString() => 'reminder scheduling failed: $cause';
}
