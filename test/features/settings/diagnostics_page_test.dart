import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/features/settings/diagnostics_page.dart';
import 'package:kaoyan_review/domain/review_item.dart';
import 'package:kaoyan_review/runtime/review_notification_gateway.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();
  const deviceChannel = MethodChannel('kaoyan_review/settings');
  final platform =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tempDir;
  late AppServices services;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-diagnostics-ui-');
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    services = AppServices(
      store: store,
      notifications: _AvailableNotifications(),
    );
    final topic = await services.topics.createTopic(
      name: '数学',
      now: DateTime.utc(2026, 9, 28),
    );
    await services.reviewItems.createReviewItem(
      content: 'SECRET_STUDY_CONTENT',
      topicId: topic.id,
      enabled: true,
      now: DateTime.utc(2026, 9, 28),
    );
    platform.setMockMethodCallHandler(deviceChannel, (call) async {
      if (call.method == 'getDeviceInfo') {
        return <String, Object?>{
          'deviceModel': 'Test Emulator',
          'androidVersion': '16',
          'appVersion': '1.0.0',
          'appBuild': '1',
        };
      }
      return null;
    });
  });

  tearDown(() async {
    platform.setMockMethodCallHandler(deviceChannel, null);
    await services.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('labels device information failures separately', (tester) async {
    platform.setMockMethodCallHandler(deviceChannel, (call) async {
      throw PlatformException(code: 'device_info_unavailable');
    });

    await tester.pumpWidget(
      MaterialApp(home: DiagnosticsPage(services: services)),
    );
    await _waitForDiagnostics(tester);

    expect(find.textContaining('设备信息（Android 原生通道）读取失败'), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsWidgets);
  });

  testWidgets('labels notification status failures separately', (tester) async {
    (services.notifications as _AvailableNotifications).channelStatusError =
        StateError('notification channel unavailable');

    await tester.pumpWidget(
      MaterialApp(home: DiagnosticsPage(services: services)),
    );
    await _waitForDiagnostics(tester);

    expect(find.textContaining('通知权限与通道（Android 通知服务）读取失败'), findsOneWidget);
    expect(find.textContaining('StateError'), findsWidgets);
  });

  testWidgets('labels scheduled Android alarms distinctly', (tester) async {
    await tester.runAsync(() async {
      await services.runtimeState.recordEvaluation(
        await services.store.database,
        at: DateTime.utc(2026, 10, 8, 8),
        outcome: 'noEligibleItem',
        source: 'scheduled_alarm',
      );
    });

    await tester.pumpWidget(
      MaterialApp(home: DiagnosticsPage(services: services)),
    );
    await _waitForDiagnostics(tester);

    await tester.scrollUntilVisible(
      find.text('最近评估来源'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Android 系统计划闹钟'), findsOneWidget);
  });
}

Future<void> _waitForDiagnostics(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (find.text('Test Emulator').evaluate().isNotEmpty ||
        find.textContaining('读取失败').evaluate().isNotEmpty) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }
}

final class _AvailableNotifications implements ReviewNotificationGateway {
  Object? channelStatusError;

  @override
  Future<bool> canPost() async => true;

  @override
  Future<void> initialize({void Function(int itemId)? onTap}) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<NotificationChannelStatus> channelStatus() async {
    if (channelStatusError case final error?) throw error;
    return const NotificationChannelStatus(
      appEnabled: true,
      channelExists: true,
      importance: Importance.high,
    );
  }

  @override
  Future<List<int>> activeReviewItemNotificationIds() async => const <int>[];

  @override
  Future<void> sendTestNotification() async {}

  @override
  Future<void> submit(ReviewItem item) async {}
}
