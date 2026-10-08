import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/app/app_error_details.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  test('formats SQLite message, result code, stage, and stack trace', () {
    final error = _FakeDatabaseException();
    final details = AppErrorDetails.format(
      stage: '读取主题',
      error: error,
      stackTrace: StackTrace.fromString('#0 TopicRepository.listTopics'),
    );

    expect(details, contains('环节：读取主题'));
    expect(details, contains('database is locked (code 5 SQLITE_BUSY)'));
    expect(details, contains('SQLite 错误码：5'));
    expect(details, contains('TopicRepository.listTopics'));
    expect(details, isNot(contains('SECRET_SQL_ARGUMENT')));
  });

  testWidgets('error dialog exposes details and a copy action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppErrorDetails(
                context,
                title: '读取失败',
                details: 'database is locked',
              ),
              child: const Text('显示错误'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示错误'));
    await tester.pumpAndSettle();

    expect(find.text('database is locked'), findsOneWidget);
    expect(find.text('复制错误详情'), findsOneWidget);
  });
}

final class _FakeDatabaseException extends DatabaseException {
  _FakeDatabaseException() : super('database is locked (code 5 SQLITE_BUSY)');

  @override
  int? getResultCode() => 5;

  @override
  Object? get result => null;

  @override
  String toString() =>
      "DatabaseException(database is locked (code 5 SQLITE_BUSY)) "
      "sql 'SELECT * FROM topics' args [SECRET_SQL_ARGUMENT]";
}
