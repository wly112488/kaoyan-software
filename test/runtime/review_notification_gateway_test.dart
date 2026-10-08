import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/review_item.dart';
import 'package:kaoyan_review/runtime/review_notification_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android before notification channels can still post', () async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const notifications = MethodChannel('dexterous.com/flutter/local_notifications');
    const native = MethodChannel('kaoyan_review/reminder_alarm');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(notifications, (call) async {
      if (call.method == 'areNotificationsEnabled') return true;
      if (call.method == 'getNotificationChannels') return <Map<String, Object?>>[];
      return null;
    });
    messenger.setMockMethodCallHandler(native, (call) async => false);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(notifications, null);
      messenger.setMockMethodCallHandler(native, null);
    });
    expect(await AndroidReviewNotificationGateway().canPost(), isTrue);
  });

  for (final importance in <Importance>[
    Importance.none,
    Importance.low,
    Importance.high,
  ]) {
    test('canPost respects review channel importance $importance', () async {
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'areNotificationsEnabled') return true;
        if (call.method == 'getNotificationChannels') {
          return <Map<String, Object?>>[
            {
              'id': 'study_reminders',
              'name': '学习提醒',
              'importance': importance.value,
              'playSound': true,
              'enableVibration': true,
              'showBadge': true,
              'enableLights': false,
              'bypassDnd': false,
              'ledColor': 0,
              'audioAttributesUsage': 5,
            },
          ];
        }
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(channel, null);
      });
      expect(
        await AndroidReviewNotificationGateway().canPost(),
        importance != Importance.none,
      );
    });
  }

  test('review item payload round-trips positive id', () {
    expect(decodeReviewItemPayload(encodeReviewItemPayload(42)), 42);
  });

  test('non-review payload is rejected', () {
    expect(decodeReviewItemPayload('other:42'), isNull);
    expect(decodeReviewItemPayload('review_item:not-an-int'), isNull);
    expect(decodeReviewItemPayload(null), isNull);
  });

  test('notification launch details produce only a valid cold-start ID', () {
    expect(reviewItemIdFromLaunchDetails(null), isNull);
    expect(
      reviewItemIdFromLaunchDetails(const NotificationAppLaunchDetails(false)),
      isNull,
    );
    expect(
      reviewItemIdFromLaunchDetails(
        const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: 'review_item:29',
          ),
        ),
      ),
      29,
    );
  });

  test('tracked notification dispatch is fenced by its durable token', () async {
    const channel = MethodChannel('kaoyan_review/reminder_alarm');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    const content = 'expanded review body';
    final dispatchAt = DateTime.utc(2026, 10, 8, 12);
    expect(await AndroidReviewNotificationGateway().submitTracked(
      ReviewItem(
        id: 7,
        content: content,
        topicId: 3,
        enabled: true,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      dispatchAt,
      'dispatch-token',
    ), isTrue);

    final call = calls.single;
    expect(call.method, 'submitReservedNotification');
    final args = call.arguments as Map<Object?, Object?>;
    expect(args['itemId'], 7);
    expect(args['content'], content);
    expect(args['dispatchAtMillis'], dispatchAt.millisecondsSinceEpoch);
    expect(args['dispatchToken'], 'dispatch-token');
  });

  test('pending recovery fences the old dispatcher in the native gate', () async {
    const channel = MethodChannel('kaoyan_review/reminder_alarm');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'fencePendingDispatch');
      expect(call.arguments, {'dispatchToken': 'old-token'});
      return false;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(
      await AndroidReviewNotificationGateway().fencePendingDispatch(
        'old-token',
      ),
      isFalse,
    );
  });

  test('active notification query excludes the test notification ID', () async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getActiveNotifications') {
        return <Map<String, Object?>>[
          <String, Object?>{'id': 17},
          <String, Object?>{'id': 2147483646},
          <String, Object?>{'id': null},
        ];
      }
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });

    expect(
      await AndroidReviewNotificationGateway()
          .activeReviewItemNotificationIds(),
      <int>[17],
    );
  });
}
