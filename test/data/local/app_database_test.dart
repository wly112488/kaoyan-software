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

  test(
    'fresh database enables foreign keys and persists initial settings',
    () async {
      final first = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: dbPath,
      );
      final db = await first.database;

      final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
      expect(foreignKeys.single['foreign_keys'], 1);
      final busyTimeout = await db.rawQuery('PRAGMA busy_timeout');
      expect(busyTimeout.single['timeout'], 5000);

      final settingsRows = await db.query('reminder_settings');
      expect(settingsRows, hasLength(1));
      expect(settingsRows.single, containsPair('id', 1));
      expect(settingsRows.single, containsPair('enabled', 0));
      expect(
        settingsRows.single,
        containsPair('active_window_mode', 'all_day'),
      );
      expect(settingsRows.single['start_minute'], isNull);
      expect(settingsRows.single['end_minute'], isNull);
      expect(
        settingsRows.single,
        containsPair('reminder_interval_ms', 3600000),
      );
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
    },
  );

  test(
    'an isolated worker connection cannot close the foreground database',
    () async {
      final foreground = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: dbPath,
      );
      final foregroundDb = await foreground.database;
      final worker = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: dbPath,
        singleInstance: false,
      );
      final workerDb = await worker.database;

      expect(identical(workerDb, foregroundDb), isFalse);
      await worker.close();
      expect(foregroundDb.isOpen, isTrue);

      await foreground.close();
    },
  );

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
  test('bounded window rejects null endpoints', () async {
    final store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
    addTearDown(store.close);
    final db = await store.database;

    await expectLater(
      db.update('reminder_settings', <String, Object?>{
        'active_window_mode': 'bounded',
        'start_minute': null,
        'end_minute': 60,
      }, where: 'id = 1'),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'migrates the settings constraint to allow one-minute intervals',
    () async {
      final legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE reminder_settings (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
              active_window_mode TEXT NOT NULL,
              start_minute INTEGER,
              end_minute INTEGER,
              reminder_interval_ms INTEGER NOT NULL
                CHECK (reminder_interval_ms >= 900000),
              repeat_cooldown_ms INTEGER NOT NULL
                CHECK (repeat_cooldown_ms >= reminder_interval_ms),
              scope_mode TEXT NOT NULL
            )
          ''');
            await db.insert('reminder_settings', <String, Object?>{
              'id': 1,
              'enabled': 1,
              'active_window_mode': 'all_day',
              'start_minute': null,
              'end_minute': null,
              'reminder_interval_ms': 900000,
              'repeat_cooldown_ms': 86400000,
              'scope_mode': 'all_topics',
            });
          },
        ),
      );
      await legacy.close();

      final upgraded = await AppDatabase.openWith(
        factory: databaseFactoryFfi,
        path: dbPath,
      );
      addTearDown(upgraded.close);
      final db = await upgraded.database;
      final rows = await db.query('reminder_settings');

      expect(rows, hasLength(1));
      expect(rows.single['enabled'], 1);
      expect(rows.single['reminder_interval_ms'], 900000);
      await db.update('reminder_settings', <String, Object?>{
        'reminder_interval_ms': 60000,
        'repeat_cooldown_ms': 60000,
      }, where: 'id = 1');
      expect(
        (await db.query('reminder_settings')).single['reminder_interval_ms'],
        60000,
      );
    },
  );
}
