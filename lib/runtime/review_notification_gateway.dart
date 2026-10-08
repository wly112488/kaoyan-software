import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import '../domain/review_item.dart';

const _channelId = 'study_reminders';
const _channelName = '学习提醒';
const _channelDescription = '考研碎片复习提醒';
const _testNotificationId = 2147483646;
const _reviewChannel = AndroidNotificationChannel(
  _channelId,
  _channelName,
  description: _channelDescription,
  importance: Importance.high,
);

final class NotificationChannelStatus {
  const NotificationChannelStatus({
    required this.appEnabled,
    required this.channelExists,
    required this.importance,
  });

  final bool appEnabled;
  final bool channelExists;
  final Importance? importance;

  bool get bannerLikely =>
      appEnabled &&
      channelExists &&
      importance != null &&
      importance!.value >= Importance.high.value;
}

String encodeReviewItemPayload(int id) => 'review_item:$id';

int? decodeReviewItemPayload(String? payload) {
  if (payload == null || !payload.startsWith('review_item:')) return null;
  final id = int.tryParse(payload.substring('review_item:'.length));
  return id != null && id > 0 ? id : null;
}

int? reviewItemIdFromLaunchDetails(NotificationAppLaunchDetails? details) {
  if (details?.didNotificationLaunchApp != true) return null;
  return decodeReviewItemPayload(details?.notificationResponse?.payload);
}

abstract interface class ReviewNotificationGateway {
  Future<void> initialize({void Function(int itemId)? onTap});
  Future<bool> canPost();
  Future<bool> requestPermission();
  Future<void> submit(ReviewItem item);
  Future<NotificationChannelStatus> channelStatus();
  Future<List<int>> activeReviewItemNotificationIds();
  Future<void> sendTestNotification();
}

abstract interface class TrackedReviewNotificationGateway
    implements ReviewNotificationGateway {
  Future<bool> submitTracked(
    ReviewItem item,
    DateTime dispatchAt,
    String dispatchToken,
  );
  Future<bool?> fencePendingDispatch(String dispatchToken);
  Future<bool> wasSubmitted(int itemId, DateTime dispatchAt);
}

final class AndroidReviewNotificationGateway
    implements TrackedReviewNotificationGateway {
  AndroidReviewNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  Future<NotificationAppLaunchDetails?> getLaunchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

  @override
  Future<void> initialize({void Function(int itemId)? onTap}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_review'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = decodeReviewItemPayload(response.payload);
        if (id != null) onTap?.call(id);
      },
    );
    await _android?.createNotificationChannel(_reviewChannel);
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> canPost() async {
    final status = await channelStatus();
    if (status.appEnabled && !status.channelExists) {
      // Android 6/7 supports notifications but has no channel API.
      return await const MethodChannel('kaoyan_review/reminder_alarm')
          .invokeMethod<bool>('supportsNotificationChannels') == false;
    }
    return status.appEnabled &&
        status.channelExists &&
        status.importance != Importance.none;
  }

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<NotificationChannelStatus> channelStatus() async {
    final enabled = await _android?.areNotificationsEnabled() ?? false;
    final channels = await _android?.getNotificationChannels();
    AndroidNotificationChannel? reminderChannel;
    for (final channel in channels ?? const <AndroidNotificationChannel>[]) {
      if (channel.id == _channelId) {
        reminderChannel = channel;
        break;
      }
    }
    return NotificationChannelStatus(
      appEnabled: enabled,
      channelExists: reminderChannel != null,
      importance: reminderChannel?.importance,
    );
  }

  @override
  Future<List<int>> activeReviewItemNotificationIds() async {
    final active = await _plugin.getActiveNotifications();
    return List<int>.unmodifiable(
      active
          .map((notification) => notification.id)
          .whereType<int>()
          .where((id) => id > 0 && id != _testNotificationId),
    );
  }

  @override
  Future<void> sendTestNotification() async {
    await _plugin.show(
      id: _testNotificationId,
      title: '考研碎片复习 · 测试通知',
      body: '如果系统允许横幅，这条测试消息应显示在屏幕上。',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      ),
    );
  }

  @override
  Future<void> submit(ReviewItem item) => _submit(item, null);

  @override
  Future<bool> submitTracked(
    ReviewItem item,
    DateTime dispatchAt,
    String dispatchToken,
  ) async =>
      await const MethodChannel('kaoyan_review/reminder_alarm')
          .invokeMethod<bool>('submitReservedNotification', {
            'itemId': item.id,
            'content': item.content,
            'dispatchAtMillis': dispatchAt.millisecondsSinceEpoch,
            'dispatchToken': dispatchToken,
          }) ??
      false;

  @override
  Future<bool?> fencePendingDispatch(String dispatchToken) async =>
      await const MethodChannel('kaoyan_review/reminder_alarm')
          .invokeMethod<bool>('fencePendingDispatch', {
            'dispatchToken': dispatchToken,
          });

  @override
  Future<bool> wasSubmitted(int itemId, DateTime dispatchAt) async =>
      await const MethodChannel('kaoyan_review/reminder_alarm')
          .invokeMethod<bool>('wasSubmitted', {
            'itemId': itemId,
            'dispatchAtMillis': dispatchAt.millisecondsSinceEpoch,
          }) ??
      false;

  Future<void> _submit(ReviewItem item, DateTime? dispatchAt) async {
    final notificationId = item.id % 2147483647;
    await _plugin.show(
      id: notificationId,
      title: '考研碎片复习',
      body: item.content,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
          when: dispatchAt?.millisecondsSinceEpoch,
          styleInformation: BigTextStyleInformation(
            item.content,
            contentTitle: '考研碎片复习',
            summaryText: '复习内容',
          ),
        ),
      ),
      payload: encodeReviewItemPayload(item.id),
    );
  }
}
