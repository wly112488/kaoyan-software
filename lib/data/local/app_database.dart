import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

final class AppDatabase {
  AppDatabase._(this._factory, this._path);

  static const schemaVersion = 1;
  static const databaseFileName = 'kaoyan_review.db';

  final DatabaseFactory _factory;
  final String _path;
  Database? _database;

  static Future<AppDatabase> openProduction() async {
    final root = await getDatabasesPath();
    return openWith(factory: databaseFactory, path: p.join(root, databaseFileName));
  }

  static Future<AppDatabase> openWith({
    required DatabaseFactory factory,
    required String path,
  }) async {
    final store = AppDatabase._(factory, path);
    await store.database;
    return store;
  }

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    final opened = await _factory.openDatabase(
      _path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
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
        updated_at_us INTEGER NOT NULL
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
        reminder_interval_ms INTEGER NOT NULL CHECK (reminder_interval_ms >= 900000),
        repeat_cooldown_ms INTEGER NOT NULL CHECK (repeat_cooldown_ms >= 0),
        scope_mode TEXT NOT NULL
          CHECK (scope_mode IN ('all_topics', 'selected_topics')),
        CHECK (
          (active_window_mode = 'all_day' AND start_minute IS NULL AND end_minute IS NULL)
          OR
          (active_window_mode = 'bounded'
            AND start_minute BETWEEN 0 AND 1439
            AND end_minute BETWEEN 0 AND 1439
            AND start_minute <> end_minute)
        )
      )
    ''');

    batch.execute('''
      CREATE TABLE reminder_scope_topics (
        topic_id INTEGER PRIMARY KEY,
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
  }
}
