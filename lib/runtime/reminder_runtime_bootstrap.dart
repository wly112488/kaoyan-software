import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

import '../data/local/app_database.dart';
import '../data/local/reminder_settings_repository.dart';
import 'notification_tap_bus.dart';
import 'reminder_scheduler.dart';
import 'reminder_worker.dart';
import 'review_notification_gateway.dart';

const _nativeNotificationTapChannel = MethodChannel(
  'kaoyan_review/notification_tap',
);

final class ReminderRuntimeBootstrap {
  static Future<void>? _initialization;

  static Future<void> initialize() {
    final existing = _initialization;
    if (existing != null) return existing;

    late final Future<void> attempt;
    attempt = _initialize().catchError((Object error, StackTrace stackTrace) {
      if (identical(_initialization, attempt)) _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _initialization = attempt;
    return attempt;
  }

  static Future<void> _initialize() async {
    await Workmanager().initialize(reminderCallbackDispatcher);

    final notifications = AndroidReviewNotificationGateway();
    await notifications.initialize(onTap: NotificationTapBus.instance.record);
    _nativeNotificationTapChannel.setMethodCallHandler((call) async {
      if (call.method == 'onTap' && call.arguments is int) {
        NotificationTapBus.instance.record(call.arguments as int);
      }
    });
    final launch = await notifications.getLaunchDetails();
    final itemId = reviewItemIdFromLaunchDetails(launch);
    if (itemId != null) NotificationTapBus.instance.record(itemId);
    final nativeItemId = await _nativeNotificationTapChannel.invokeMethod<int>(
      'getPendingItemId',
    );
    if (nativeItemId != null) NotificationTapBus.instance.record(nativeItemId);

    // This bootstrap runs after the UI database is already open. Give it an
    // independent connection so closing the bootstrap store cannot invalidate
    // sqflite's foreground single-instance connection.
    final store = await AppDatabase.openProduction(singleInstance: false);
    try {
      final settings = await ReminderSettingsRepository(store).loadSettings();
      await ReminderScheduler(store: store).reconcile(
        settings,
        minimumDelay: settings.enabled
            ? settings.reminderInterval
            : Duration.zero,
      );
    } finally {
      await store.close();
    }
  }
}
