import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/app/app_shell.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/features/review/review_list_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppServices services;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-review-crud-');
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    services = AppServices(store: store);
    await services.topics.createTopic(
      name: '数学',
      now: DateTime.utc(2026, 9, 28),
    );
  });

  tearDown(() async {
    await services.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets(
    'review list creates, searches, toggles, edits and deletes items',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: AppShell(services: services)));
      await _flushDatabaseWork(tester, times: 3);

      await tester.tap(find.byKey(const ValueKey('review-add-button')));
      await tester.pump();
      await _flushDatabaseWork(tester, times: 2);

      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('正文不能为空'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('review-content-field')),
        'New formula content',
      );
      await tester.tap(find.text('保存'));
      await _waitFor(tester, find.byKey(const ValueKey('review-search-field')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('review-content-field')), findsNothing);
      expect(find.text('New formula content'), findsOneWidget);

      final savedItems = await tester.runAsync(
        () => services.reviewItems.listReviewItems(),
      );
      final itemId = savedItems!.single.id;
      await tester.runAsync(
        () => services.reviewItems.recordShownAt(
          id: itemId,
          shownAt: DateTime.utc(2026, 9, 28, 12),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('review-search-field')),
        'missing',
      );
      await tester.pump();
      expect(find.text('没有符合条件的内容'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('review-search-field')),
        'formula',
      );
      await tester.pump();
      expect(find.text('New formula content'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('item-enabled-$itemId')));
      await _waitForSwitchValue(tester, itemId: itemId, value: false);
      var updated = await tester.runAsync(
        () => services.reviewItems.getReviewItem(itemId),
      );
      expect(updated!.enabled, isFalse);
      expect(updated.lastShownAt, DateTime.utc(2026, 9, 28, 12));

      await tester.enterText(
        find.byKey(const ValueKey('review-search-field')),
        '',
      );
      await tester.pump();
      await tester.tap(find.text('New formula content'));
      await tester.pump();
      await _flushDatabaseWork(tester, times: 4);
      await tester.tap(find.text('编辑'));
      await tester.pump();
      await _flushDatabaseWork(tester, times: 4);
      await tester.enterText(
        find.byKey(const ValueKey('review-content-field')),
        'Updated formula content',
      );
      await tester.tap(find.text('保存'));
      await _flushDatabaseWork(tester, times: 3);
      await _waitFor(tester, find.text('复习内容详情'));

      updated = await tester.runAsync(
        () => services.reviewItems.getReviewItem(itemId),
      );
      expect(updated!.content, 'Updated formula content');
      expect(updated.lastShownAt, DateTime.utc(2026, 9, 28, 12));

      await _waitFor(tester, find.byIcon(Icons.delete_outline));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await _flushDatabaseWork(tester, times: 2);
      expect(
        await tester.runAsync(() => services.reviewItems.getReviewItem(itemId)),
        isNull,
      );
    },
  );

  testWidgets('refresh keeps the loaded review list interactive', (
    tester,
  ) async {
    final topic = await tester.runAsync(services.topics.listTopics);
    await tester.runAsync(
      () => services.reviewItems.createReviewItem(
        content: '已有复习内容',
        topicId: topic!.single.id,
        enabled: true,
        now: DateTime.utc(2026, 9, 28),
      ),
    );

    final pageKey = GlobalKey<ReviewListPageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewListPage(key: pageKey, services: services),
      ),
    );
    await _waitFor(tester, find.text('已有复习内容'));

    unawaited(pageKey.currentState!.refresh());
    await tester.pump();

    expect(find.byKey(const ValueKey('review-search-field')), findsOneWidget);
    expect(find.text('已有复习内容'), findsOneWidget);

    await _flushDatabaseWork(tester, times: 3);
    await tester.pump();
  });

  testWidgets('topic reload failures are attributed without hiding old items', (
    tester,
  ) async {
    final topic = await tester.runAsync(services.topics.listTopics);
    await tester.runAsync(
      () => services.reviewItems.createReviewItem(
        content: '现有复习内容',
        topicId: topic!.single.id,
        enabled: true,
        now: DateTime.utc(2026, 9, 28),
      ),
    );
    final pageKey = GlobalKey<ReviewListPageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewListPage(key: pageKey, services: services),
      ),
    );
    await _flushDatabaseWork(tester, times: 3);
    expect(find.text('现有复习内容'), findsOneWidget);

    final db = await tester.runAsync(() => services.store.database);
    await tester.runAsync(
      () => db!.execute('ALTER TABLE topics RENAME TO topics_unavailable'),
    );
    await tester.runAsync(() => pageKey.currentState!.refresh());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('现有复习内容'), findsOneWidget);
    expect(find.text('主题数据读取失败'), findsOneWidget);
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 20 && finder.evaluate().isEmpty; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }
  expect(finder, findsOneWidget);
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

Future<void> _waitForSwitchValue(
  WidgetTester tester, {
  required int itemId,
  required bool value,
}) async {
  final finder = find.byKey(ValueKey('item-enabled-$itemId'));
  for (var index = 0; index < 20; index++) {
    if (finder.evaluate().isNotEmpty &&
        tester.widget<Switch>(finder).value == value) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
  }
  expect(finder, findsOneWidget);
  expect(tester.widget<Switch>(finder).value, value);
}
