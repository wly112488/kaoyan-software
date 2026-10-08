import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/app/app_shell.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/features/review/review_item_detail_page.dart';
import 'package:kaoyan_review/runtime/notification_tap_bus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final tapBus = NotificationTapBus.instance;

  late Directory tempDir;
  late AppServices services;

  setUp(() async {
    tapBus.takePendingItemId();
    tempDir = await Directory.systemTemp.createTemp('kaoyan-tap-ui-');
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    services = AppServices(store: store);
  });

  tearDown(() async {
    tapBus.takePendingItemId();
    await services.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('cold-start pending notification ID rereads and opens the item', (
    tester,
  ) async {
    final itemId = await tester.runAsync(() => createItem(services));
    final persistedItemId = itemId!;
    tapBus.record(persistedItemId);
    await tester.pumpWidget(MaterialApp(home: AppShell(services: services)));
    await _flushDatabaseWork(tester, times: 4);

    expect(
      find.byType(ReviewItemDetailPage, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets(
    'warm notification tap for a deleted item shows unavailable fallback',
    (tester) async {
      final itemId = await tester.runAsync(() => createItem(services));
      final persistedItemId = itemId!;
      await tester.pumpWidget(MaterialApp(home: AppShell(services: services)));
      await _flushDatabaseWork(tester, times: 2);
      expect(find.text('tap target content'), findsOneWidget);

      await tester.runAsync(
        () => services.reviewItems.deleteReviewItem(persistedItemId),
      );

      tapBus.record(persistedItemId);
      await _flushDatabaseWork(tester, times: 3);

      expect(find.text('内容已不可用'), findsOneWidget);
      expect(
        find.text('tap target content', skipOffstage: false),
        findsNothing,
      );
    },
  );

  testWidgets(
    'duplicate notification tap does not push duplicate detail routes',
    (tester) async {
      final itemId = await tester.runAsync(() => createItem(services));
      final persistedItemId = itemId!;
      await tester.pumpWidget(MaterialApp(home: AppShell(services: services)));
      await _flushDatabaseWork(tester, times: 2);

      tapBus.record(persistedItemId);
      tapBus.record(persistedItemId);
      await _flushDatabaseWork(tester, times: 3);

      expect(
        find.byType(ReviewItemDetailPage, skipOffstage: false),
        findsOneWidget,
      );
    },
  );
}

Future<int> createItem(AppServices services) async {
  final topic = await services.topics.createTopic(
    name: 'Topic',
    now: DateTime.utc(2026, 9, 28),
  );
  final item = await services.reviewItems.createReviewItem(
    content: 'tap target content',
    topicId: topic.id,
    enabled: true,
    now: DateTime.utc(2026, 9, 28),
  );
  return item.id;
}

Future<void> _flushDatabaseWork(
  WidgetTester tester, {
  required int times,
}) async {
  for (var index = 0; index < times; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }
}
