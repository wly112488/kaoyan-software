import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final class AndroidReminderAlarmPermission {
  static AndroidFlutterLocalNotificationsPlugin? get _androidNotifications =>
      FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  static Future<bool> canSchedule() async {
    try {
      return await _androidNotifications?.canScheduleExactNotifications() ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    await _androidNotifications?.requestExactAlarmsPermission();
  }
}
