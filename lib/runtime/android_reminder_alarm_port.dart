import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'exact_reminder_alarm_port.dart';
import 'exact_alarm_permission.dart';

const _reminderAlarmChannel = MethodChannel('kaoyan_review/reminder_alarm');

final class AndroidReminderAlarmPort implements ExactReminderAlarmPort {
  @override
  Future<bool> canScheduleExactAlarms() async {
    try {
      final allowed = await AndroidReminderAlarmPermission.canSchedule();
      developer.log('Exact alarm permission: $allowed', name: 'reminder_alarm');
      return allowed;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> schedule(DateTime at, {bool keepExisting = false}) async {
    try {
      final scheduled =
          await _reminderAlarmChannel.invokeMethod<bool>(
            'schedule',
            <String, Object?>{
              'atEpochMillis': at.millisecondsSinceEpoch,
              'keepExisting': keepExisting,
            },
          ) ??
          false;
      developer.log(
        'Native exact alarm schedule result: $scheduled',
        name: 'reminder_alarm',
      );
      return scheduled;
    } on MissingPluginException {
      developer.log(
        'Native exact alarm channel is missing',
        name: 'reminder_alarm',
      );
      return false;
    } on PlatformException catch (error) {
      developer.log(
        'Native exact alarm scheduling failed',
        name: 'reminder_alarm',
        error: error,
      );
      return false;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _reminderAlarmChannel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Still cancel fallback work on unsupported platforms.
    } on PlatformException {
      // An unavailable native alarm service must not prevent fallback work.
    }
  }
}
