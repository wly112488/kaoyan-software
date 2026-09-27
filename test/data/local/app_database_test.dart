import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-db-test-');
    dbPath = '${tempDir.path}${Platform.pathSeparator}app.db';
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fresh database enables foreign keys and persists initial settings', () async {
    final first = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
    final db = await first.database;

    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
    expect(foreignKeys.single['foreign_keys'], 1);

    final settingsRows = await db.query('reminder_settings');
    expect(settingsRows, hasLength(1));
    expect(settingsRows.single, containsPair('id', 1));
    expect(settingsRows.single, containsPair('enabled', 0));
    expect(settingsRows.single, containsPair('active_window_mode', 'all_day'));
    expect(settingsRows.single['start_minute'], isNull);
    expect(settingsRows.single['end_minute'], isNull);
    expect(settingsRows.single, containsPair('reminder_interval_ms', 3600000));
    expect(settingsRows.single, containsPair('repeat_cooldown_ms', 86400000));
    expect(settingsRows.single, containsPair('scope_mode', 'all_topics'));

    await first.close();

    final reopened = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
    final reopenedDb = await reopened.database;
    final reopenedRows = await reopenedDb.query('reminder_settings');
    expect(reopenedRows, hasLength(1));
    expect(reopenedRows.single, settingsRows.single);
    await reopened.close();
  });

  test('schema rejects dangling ReviewItem topic ids', () async {
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
    final db = await store.database;

    expect(
      () => db.insert('review_items', <String, Object?>{
        'content': 'text',
        'topic_id': 999,
        'enabled': 1,
        'created_at_us': 1,
        'updated_at_us': 1,
        'last_shown_at_us': null,
      }),
      throwsA(isA<DatabaseException>()),
    );

    await store.close();
  });
}
