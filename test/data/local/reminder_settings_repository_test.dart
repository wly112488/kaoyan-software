import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_settings_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late String dbPath;
  late AppDatabase store;
  late TopicRepository topics;
  late ReminderSettingsRepository settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-settings-test-');
    dbPath = '${tempDir.path}${Platform.pathSeparator}app.db';
    store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
    topics = TopicRepository(store);
    settings = ReminderSettingsRepository(store);
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fresh load returns canonical initial settings', () async {
    final loaded = await settings.loadSettings();
    expect(loaded.enabled, isFalse);
    expect(loaded.activeWindow.mode, ActiveWindowMode.allDay);
    expect(loaded.reminderInterval, const Duration(minutes: 60));
    expect(loaded.repeatCooldown, const Duration(hours: 24));
    expect(loaded.scope.mode, ReminderScopeMode.allTopics);
  });

  test('selected scope and bounded window survive reopen', () async {
    final now = DateTime.utc(2026, 9, 27);
    final a = await topics.createTopic(name: '医学', now: now);
    final b = await topics.createTopic(name: '生物', now: now);
    await settings.saveSettings(
      ReminderSettings(
        enabled: true,
        activeWindow: ActiveWindow.bounded(
          startMinute: 9 * 60,
          endMinute: 22 * 60,
        ),
        reminderInterval: const Duration(minutes: 30),
        repeatCooldown: const Duration(hours: 48),
        scope: ReminderScope.selectedTopics(<int>{a.id, b.id}),
        weeklyTopicIds: <int, Set<int>>{
          DateTime.monday: <int>{a.id, b.id},
          DateTime.friday: <int>{b.id},
        },
      ),
    );

    await store.close();
    store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
    settings = ReminderSettingsRepository(store);

    final loaded = await settings.loadSettings();
    expect(loaded.enabled, isTrue);
    expect(loaded.activeWindow.mode, ActiveWindowMode.bounded);
    expect(loaded.activeWindow.startMinute, 9 * 60);
    expect(loaded.activeWindow.endMinute, 22 * 60);
    expect(loaded.reminderInterval, const Duration(minutes: 30));
    expect(loaded.repeatCooldown, const Duration(hours: 48));
    expect(loaded.scope.mode, ReminderScopeMode.selectedTopics);
    expect(loaded.scope.topicIds, <int>{a.id, b.id});
    expect(loaded.weeklyTopicIds, <int, Set<int>>{
      DateTime.monday: <int>{a.id, b.id},
      DateTime.friday: <int>{b.id},
    });
  });

  test('selected scope rejects missing Topic ids', () async {
    expect(
      () => settings.saveSettings(
        ReminderSettings(
          enabled: false,
          activeWindow: ActiveWindow.allDay(),
          reminderInterval: const Duration(minutes: 60),
          repeatCooldown: const Duration(hours: 24),
          scope: ReminderScope.selectedTopics(<int>{999}),
        ),
      ),
      throwsStateError,
    );
  });

  test('saving ALL_TOPICS clears persisted selected Topic rows', () async {
    final now = DateTime.utc(2026, 9, 27);
    final topic = await topics.createTopic(name: '医学', now: now);
    await settings.saveSettings(
      ReminderSettings(
        enabled: false,
        activeWindow: ActiveWindow.allDay(),
        reminderInterval: const Duration(minutes: 60),
        repeatCooldown: const Duration(hours: 24),
        scope: ReminderScope.selectedTopics(<int>{topic.id}),
      ),
    );

    await settings.saveSettings(ReminderSettings.initial());

    final db = await store.database;
    expect(await db.query('reminder_scope_topics'), isEmpty);
    expect(
      (await settings.loadSettings()).scope.mode,
      ReminderScopeMode.allTopics,
    );
  });

  test(
    'loadSettings reads settings and topic IDs in one SQLite snapshot query',
    () async {
      final testDir = await Directory.systemTemp.createTemp(
        'kaoyan-read-snapshot-',
      );
      final recorder = _ReadBoundaryRecorder();
      final factory = _RecordingDatabaseFactory(databaseFactoryFfi, recorder);
      final testStore = await AppDatabase.openWith(
        factory: factory,
        path: '${testDir.path}${Platform.pathSeparator}app.db',
      );
      addTearDown(() async {
        await testStore.close();
        await testDir.delete(recursive: true);
      });

      final db = factory.openedDatabase!;
      final now = DateTime.utc(2026, 9, 28);
      final topicId = await db.insert('topics', <String, Object?>{
        'name': 'Biology',
        'name_key': 'biology',
        'created_at_us': now.microsecondsSinceEpoch,
        'updated_at_us': now.microsecondsSinceEpoch,
      });
      await db.update('reminder_settings', <String, Object?>{
        'enabled': 1,
        'scope_mode': 'selected_topics',
      }, where: 'id = 1');
      await db.insert('reminder_scope_topics', <String, Object?>{
        'topic_id': topicId,
      });

      recorder.reset();
      final loaded = await ReminderSettingsRepository(testStore).loadSettings();

      expect(loaded.scope.mode, ReminderScopeMode.selectedTopics);
      expect(loaded.scope.topicIds, <int>{topicId});
      expect(recorder.transactionCount, 0);
      expect(recorder.rawQueryCount, 1);
      expect(recorder.rawQueryText, contains('selected_topic_ids'));
      expect(recorder.rawQueryText, contains('weekday_topic_ids'));
      expect(recorder.databaseQueryCount, 0);
    },
  );

  test('settings snapshot reads do not contend with a worker write', () async {
    final testDir = await Directory.systemTemp.createTemp(
      'kaoyan-worker-read-Write-',
    );
    final path = '${testDir.path}${Platform.pathSeparator}app.db';
    final foreground = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: path,
    );
    final worker = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: path,
      singleInstance: false,
    );
    addTearDown(() async {
      await foreground.close();
      await worker.close();
      await testDir.delete(recursive: true);
    });

    final workerDb = await worker.database;
    final workerWrite = workerDb.transaction((txn) async {
      await txn.update('reminder_runtime_state', <String, Object?>{
        'last_evaluation_outcome': 'notification_pending',
      }, where: 'id = 1');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    final loaded = await ReminderSettingsRepository(foreground).loadSettings();
    expect(loaded.scope.mode, ReminderScopeMode.allTopics);
    await workerWrite;
  });
}

final class _ReadBoundaryRecorder {
  int transactionCount = 0;
  int transactionQueryCount = 0;
  int databaseQueryCount = 0;
  int rawQueryCount = 0;
  String? rawQueryText;

  void reset() {
    transactionCount = 0;
    transactionQueryCount = 0;
    databaseQueryCount = 0;
    rawQueryCount = 0;
    rawQueryText = null;
  }
}

final class _RecordingDatabaseFactory implements DatabaseFactory {
  _RecordingDatabaseFactory(this._delegate, this._recorder);

  final DatabaseFactory _delegate;
  final _ReadBoundaryRecorder _recorder;
  Database? openedDatabase;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    final database = await _delegate.openDatabase(path, options: options);
    openedDatabase = database;
    return _RecordingDatabase(database, _recorder);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingDatabase implements Database {
  _RecordingDatabase(this._delegate, this._recorder);

  final Database _delegate;
  final _ReadBoundaryRecorder _recorder;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) {
    return _delegate.transaction<T>((txn) {
      _recorder.transactionCount++;
      return action(_RecordingTransaction(txn, _recorder));
    }, exclusive: exclusive);
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    _recorder.databaseQueryCount++;
    return _delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    _recorder.rawQueryCount++;
    _recorder.rawQueryText = sql;
    return _delegate.rawQuery(sql, arguments);
  }

  @override
  Future<void> close() => _delegate.close();

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingTransaction implements Transaction {
  _RecordingTransaction(this._delegate, this._recorder);

  final Transaction _delegate;
  final _ReadBoundaryRecorder _recorder;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    _recorder.transactionQueryCount++;
    return _delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
