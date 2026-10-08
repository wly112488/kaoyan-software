import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/app/app_services.dart';
import 'package:kaoyan_review/app/app_shell.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppServices services;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-review-ui-');
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

  testWidgets('first Topic creation continues into the first ReviewItem form', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: AppShell(services: services)));
    await _waitFor(tester, find.text('还没有复习内容'));

    expect(find.text('还没有复习内容'), findsOneWidget);
    await tester.tap(find.text('创建第一个主题'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('新建主题'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('topic-name-field')),
      '数学',
    );
    await tester.tap(find.text('保存主题'));
    await _waitFor(tester, find.text('新增复习内容', skipOffstage: false));

    expect(find.text('新增复习内容', skipOffstage: false), findsOneWidget);
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
