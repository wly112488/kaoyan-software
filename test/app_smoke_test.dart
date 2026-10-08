import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/app/kaoyan_review_app.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppServices services;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-app-test-');
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    services = AppServices(store: store);
  });

  tearDown(() async {
    await services.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('builds the Android MVP shell', (tester) async {
    await tester.pumpWidget(
      KaoyanReviewApp(loadServices: () async => services),
    );
    await _waitFor(tester, find.text('还没有复习内容'));

    expect(find.text('还没有复习内容'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.text('主题'));
    await tester.pump();
    await _waitFor(tester, find.text('主题管理'));
    expect(find.text('主题管理'), findsWidgets);

    await tester.tap(find.text('设置'));
    await tester.pump();
    await _waitFor(tester, find.text('提醒设置'));
    expect(find.text('提醒设置'), findsWidgets);
  });

  testWidgets('shows database startup failure and retries successfully', (
    tester,
  ) async {
    var shouldFail = true;
    var attempts = 0;
    await tester.pumpWidget(
      KaoyanReviewApp(
        loadServices: () async {
          attempts++;
          if (shouldFail) throw StateError('database unavailable');
          return services;
        },
      ),
    );
    await tester.pump();

    expect(find.text('启动初始化失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(attempts, 1);

    shouldFail = false;
    await tester.tap(find.text('重试'));
    await _waitFor(tester, find.text('还没有复习内容'));

    expect(attempts, 2);
    expect(find.text('还没有复习内容'), findsOneWidget);
  });

  test(
    'opens local services without waiting for reminder runtime startup',
    () async {
      final runtimeInitialization = Completer<void>();
      final localStore = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: '${tempDir.path}${Platform.pathSeparator}optional-runtime.db',
      );

      final opening = AppServices.openProduction(
        initializeRuntime: () => runtimeInitialization.future,
        openStore: () async => localStore,
      );
      final openedEarly = await Future.any<bool>(<Future<bool>>[
        opening.then((_) => true),
        Future<void>.delayed(const Duration(milliseconds: 50))
            .then((_) => false),
      ]);
      final opened = await opening;
      addTearDown(opened.close);

      expect(openedEarly, isTrue);
      final topic = await opened.topics.createTopic(
        name: '历史',
        now: DateTime.utc(2026, 9, 30),
      );
      for (var index = 0; index < 2; index++) {
        await opened.reviewItems.createReviewItem(
          content: '内容 ${index + 1}',
          topicId: topic.id,
          enabled: true,
          now: DateTime.utc(2026, 9, 30, 0, index),
        );
      }
      final runtime = opened.initializeReminderRuntime();
      await Future<void>.delayed(Duration.zero);
      expect(runtimeInitialization.isCompleted, isFalse);
      expect((await opened.reviewItems.listReviewItems()).length, 2);
      expect((await opened.topics.listTopics()).single.name, '历史');
      runtimeInitialization.complete();
      await runtime;
    },
  );

  testWidgets('shows the underlying error on the startup failure screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      KaoyanReviewApp(
        loadServices: () async => throw StateError('database is locked'),
      ),
    );
    await tester.pump();

    expect(find.text('启动初始化失败'), findsOneWidget);
    expect(find.textContaining('database is locked'), findsOneWidget);
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(finder, findsWidgets);
}
