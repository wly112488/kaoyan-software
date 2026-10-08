import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

final class AppDatabase {
  AppDatabase._(this._factory, this._path);

  static const schemaVersion = 9;
  static const databaseFileName = 'kaoyan_review.db';

  final DatabaseFactory _factory;
  final String _path;
  Database? _database;

  static Future<AppDatabase> openProduction({
    bool singleInstance = true,
  }) async {
    final root = await getDatabasesPath();
    return openWith(
      factory: databaseFactory,
      path: p.join(root, databaseFileName),
      singleInstance: singleInstance,
    );
  }

  static Future<AppDatabase> openWith({
    required DatabaseFactory factory,
    required String path,
    bool singleInstance = true,
  }) async {
    final store = AppDatabase._(factory, path);
    await store._open(singleInstance: singleInstance);
    return store;
  }

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    return _open();
  }

  Future<Database> _open({bool singleInstance = true}) async {
    final opened = await _factory.openDatabase(
      _path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: singleInstance,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA busy_timeout = 5000');
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    final existing = _database;
    _database = null;
    if (existing != null && existing.isOpen) {
      await existing.close();
    }
  }

  static Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE topics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        name_key TEXT NOT NULL UNIQUE,
        created_at_us INTEGER NOT NULL,
        updated_at_us INTEGER NOT NULL,
        reminder_interval_ms INTEGER,
        last_reminded_at_us INTEGER
      )
    ''');

    batch.execute('''
      CREATE TABLE review_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        topic_id INTEGER NOT NULL,
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
        created_at_us INTEGER NOT NULL,
        updated_at_us INTEGER NOT NULL,
        last_shown_at_us INTEGER,
        reminder_count INTEGER NOT NULL DEFAULT 0 CHECK (reminder_count >= 0),
        FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE RESTRICT
      )
    ''');

    batch.execute('''
      CREATE INDEX review_items_topic_id_idx
      ON review_items(topic_id)
    ''');

    batch.execute('''
      CREATE TABLE reminder_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
        active_window_mode TEXT NOT NULL
          CHECK (active_window_mode IN ('all_day', 'bounded')),
        start_minute INTEGER,
        end_minute INTEGER,
        reminder_interval_ms INTEGER NOT NULL CHECK (reminder_interval_ms >= 60000),
        repeat_cooldown_ms INTEGER NOT NULL
          CHECK (repeat_cooldown_ms >= reminder_interval_ms),
        scope_mode TEXT NOT NULL
          CHECK (scope_mode IN ('all_topics', 'selected_topics')),
        CHECK (
          (active_window_mode = 'all_day' AND start_minute IS NULL AND end_minute IS NULL)
          OR
          (active_window_mode = 'bounded'
            AND start_minute IS NOT NULL
            AND end_minute IS NOT NULL
            AND start_minute BETWEEN 0 AND 1439
            AND end_minute BETWEEN 0 AND 1439
            AND start_minute < end_minute)
        )
      )
    ''');

    batch.execute('''
      CREATE TABLE reminder_scope_topics (
        topic_id INTEGER PRIMARY KEY,
        FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE RESTRICT
      )
    ''');

    batch.execute('''
      CREATE TABLE reminder_weekday_topics (
        weekday INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7),
        topic_id INTEGER NOT NULL,
        PRIMARY KEY (weekday, topic_id),
        FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE RESTRICT
      )
    ''');

    batch.insert('reminder_settings', <String, Object?>{
      'id': 1,
      'enabled': 0,
      'active_window_mode': 'all_day',
      'start_minute': null,
      'end_minute': null,
      'reminder_interval_ms': const Duration(minutes: 60).inMilliseconds,
      'repeat_cooldown_ms': const Duration(hours: 24).inMilliseconds,
      'scope_mode': 'all_topics',
    });

    await batch.commit(noResult: true);
    await _createRuntimeStateTable(db);
  }

  static Future<void> _createRuntimeStateTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE reminder_runtime_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_evaluation_at_us INTEGER,
        last_evaluation_outcome TEXT,
        last_dispatch_at_us INTEGER,
        last_dispatch_item_id INTEGER,
        last_dispatch_topic_id INTEGER,
        last_schedule_attempt_at_us INTEGER,
        schedule_status TEXT NOT NULL
          CHECK (schedule_status IN ('not_scheduled', 'scheduled', 'disabled', 'failed')),
        schedule_error TEXT,
        last_worker_error_at_us INTEGER,
        last_worker_error_details TEXT,
        last_evaluation_source TEXT,
        last_worker_started_at_us INTEGER,
        last_worker_completed_at_us INTEGER,
        last_worker_outcome TEXT,
        pending_dispatch_json TEXT
      )
    ''');
    await db.insert('reminder_runtime_state', <String, Object?>{
      'id': 1,
      'schedule_status': 'not_scheduled',
    });
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createRuntimeStateTable(db);
    }
    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE topics ADD COLUMN reminder_interval_ms INTEGER',
      );
      await db.execute(
        'ALTER TABLE topics ADD COLUMN last_reminded_at_us INTEGER',
      );
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE reminder_weekday_topics (
          weekday INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7),
          topic_id INTEGER NOT NULL,
          PRIMARY KEY (weekday, topic_id),
          FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE RESTRICT
        )
      ''');
      await db.execute('''
        UPDATE reminder_settings
        SET active_window_mode = 'all_day', start_minute = NULL, end_minute = NULL
        WHERE active_window_mode = 'bounded' AND start_minute >= end_minute
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        ALTER TABLE review_items
        ADD COLUMN reminder_count INTEGER NOT NULL DEFAULT 0 CHECK (reminder_count >= 0)
      ''');
      await db.execute('''
        UPDATE reminder_settings
        SET repeat_cooldown_ms = reminder_interval_ms
        WHERE repeat_cooldown_ms < reminder_interval_ms
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE reminder_settings_v6 (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
          active_window_mode TEXT NOT NULL
            CHECK (active_window_mode IN ('all_day', 'bounded')),
          start_minute INTEGER,
          end_minute INTEGER,
          reminder_interval_ms INTEGER NOT NULL
            CHECK (reminder_interval_ms >= 60000),
          repeat_cooldown_ms INTEGER NOT NULL
            CHECK (repeat_cooldown_ms >= reminder_interval_ms),
          scope_mode TEXT NOT NULL
            CHECK (scope_mode IN ('all_topics', 'selected_topics')),
          CHECK (
            (active_window_mode = 'all_day' AND start_minute IS NULL AND end_minute IS NULL)
            OR
            (active_window_mode = 'bounded'
              AND start_minute IS NOT NULL
              AND end_minute IS NOT NULL
              AND start_minute BETWEEN 0 AND 1439
              AND end_minute BETWEEN 0 AND 1439
              AND start_minute < end_minute)
          )
        )
      ''');
      await db.execute('''
        INSERT INTO reminder_settings_v6 (
          id, enabled, active_window_mode, start_minute, end_minute,
          reminder_interval_ms, repeat_cooldown_ms, scope_mode
        )
        SELECT
          id, enabled, active_window_mode, start_minute, end_minute,
          reminder_interval_ms, repeat_cooldown_ms, scope_mode
        FROM reminder_settings
      ''');
      await db.execute('DROP TABLE reminder_settings');
      await db.execute(
        'ALTER TABLE reminder_settings_v6 RENAME TO reminder_settings',
      );
    }
    if (oldVersion >= 2 && oldVersion < 7) {
      final runtimeTable = await db.rawQuery('''
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name = 'reminder_runtime_state'
      ''');
      if (runtimeTable.isEmpty) {
        await _createRuntimeStateTable(db);
      } else {
        await _addColumnIfMissing(db, 'last_worker_error_at_us', 'INTEGER');
        await _addColumnIfMissing(db, 'last_worker_error_details', 'TEXT');
      }
    }
    if (oldVersion >= 2 && oldVersion < 8) {
      await _addColumnIfMissing(db, 'last_evaluation_source', 'TEXT');
      await _addColumnIfMissing(db, 'last_worker_started_at_us', 'INTEGER');
      await _addColumnIfMissing(db, 'last_worker_completed_at_us', 'INTEGER');
      await _addColumnIfMissing(db, 'last_worker_outcome', 'TEXT');
    }
    if (oldVersion < 9) {
      await _addColumnIfMissing(db, 'pending_dispatch_json', 'TEXT');
    }
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String columnName,
    String columnType,
  ) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(reminder_runtime_state)',
    );
    if (columns.any((column) => column['name'] == columnName)) return;
    await db.execute(
      'ALTER TABLE reminder_runtime_state ADD COLUMN $columnName $columnType',
    );
  }
}
