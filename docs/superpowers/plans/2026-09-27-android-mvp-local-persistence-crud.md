# Android MVP Local Persistence and CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the completed Plan 1 domain model locally with SQLite and provide transactional CRUD for Topics, ReviewItems, ReminderSettings, ReminderScope, and `last_shown_at` while preserving all Spec invariants across process/database reopen.

**Architecture:** Add one SQLite-backed local persistence boundary under `lib/data/local/`. `AppDatabase` owns schema/open/close and the singleton initial ReminderSettings row; focused repositories map database rows to the existing Plan 1 domain classes. Runtime uses `sqflite`; tests inject `sqflite_common_ffi` so foreign-key, unique-index, transaction, restart, and scope-integrity behavior is directly testable without Android scheduling or UI.

**Tech Stack:** Flutter 3.47.5 branch baseline, Dart SDK `^3.13.4`, existing pure-Dart domain layer, `sqflite ^2.4.4`, `path ^1.9.1`, `sqflite_common_ffi ^2.4.3` for tests, `flutter_test`.

**Spec:** `docs/superpowers/specs/ANDROID_MVP_SPEC.md`

**Implementation baseline:** `feat/android-mvp-domain-foundation` after Spec-closure commit `18512f3a208f157cd4e7faca721bec03037ba278`; Plan 1 domain implementation is based on commit `20a4c091da7e316056a5f69843ebc19801407ed2`.

## Global Constraints

- Android first; target device for real-device acceptance is OPPO Reno8.
- Flutter remains the client framework.
- Persistence is local-only; no login, server, cloud, or multi-device sync.
- Every ReviewItem references exactly one existing Topic.
- Topic normalized names are nonblank and unique under `topicNameKey()`.
- ReminderScope is `ALL_TOPICS` or `SELECTED_TOPICS` with a nonempty valid Topic-ID set.
- `reminder_enabled = false` never legalizes an empty `SELECTED_TOPICS` state.
- A fresh store must load legal initial settings: disabled, `ALL_TOPICS`, `ALL_DAY`, 60-minute interval, 24-hour cooldown.
- Topic deletion must never orphan ReviewItems, silently widen scope, or leave selected scope empty.
- Editing ReviewItem content/Topic/enabled state must preserve `last_shown_at`.
- `next_eligible_at` remains derived; do not persist it.
- `last_shown_at` is persisted as reminder history, but Plan 2 does not decide Android notification dispatch success; Plan 3 owns the call site that invokes the persistence update.
- Bounded active-window membership is `[start, end)`; Plan 2 persists the window faithfully but does not yet own wall-clock evaluation.
- Production interval validation remains at least 15 minutes through the existing `ReminderSettings` constructor.
- Exact alarms, WorkManager, Android notifications, permissions, foreground state, Diagnostics UI, APK distribution, and OPPO real-device verification are outside this Plan.
- OCR and AI remain out of scope.

---

## Scope Check and Implementation Roadmap

### Plan 1 — Domain Foundation — complete

Delivered the Flutter Android scaffold and pure domain contracts under `lib/domain/`, including `Topic`, `ReviewItem`, `ReminderScope`, `ActiveWindow`, `ReminderSettings`, deterministic candidate selection, and reminder-evaluation ordering.

### Plan 2 — Local Persistence and CRUD — this document

- **Independent deliverable:** `flutter test` proves schema initialization, legal initial settings, Topic/ReviewItem/settings persistence, referential integrity, selected-scope integrity, restart durability, and transactional Topic deletion behavior.
- **Spec semantics covered:** §§3, 4, 5.2 persistence ownership, and persistence-relevant acceptance/invariants in §§10–16.
- **Dependencies:** actual Plan 1 interfaces; Spec closure commit `18512f3a...`.
- **Implementation prerequisites:** satisfied.

### Plan 3 — Android Reminder Runtime

- **Goal:** Implement active-window evaluation, foreground suppression, notification capability checks, Android best-effort scheduling, notification submission, and serialized selection/dispatch/history update.
- **Independent deliverable:** emulator/integration evidence for Android runtime semantics without claiming OPPO verification.
- **Spec semantics covered:** §§5.3–5.4, 6–10, runtime acceptance 21–30.
- **Dependency:** Plan 2 persistence APIs and actual schema/repository behavior.
- **Prerequisite before detailed planning:** Plan 2 implementation and tests complete; re-read actual persistence interfaces.

### Plan 4 — Product UI, Diagnostics, and APK

- **Goal:** Add Topic/ReviewItem CRUD UI, reminder settings/scope UI, notification deep-link destination, Diagnostics, and distributable APK.
- **Dependency:** Plans 2 and 3.
- **Prerequisite before detailed planning:** actual repository/runtime interfaces stable.

### Plan 5 — OPPO Reno8 Real-Device Closure

- **Goal:** Execute the Spec real-device matrix, record evidence, and fix only verified device-specific defects without weakening Spec invariants.
- **Dependency:** installable Plan 4 APK.

---

## File Structure for Plan 2

**Modify**
- `pubspec.yaml` — add runtime SQLite/path dependencies and FFI test dependency.
- `pubspec.lock` — regenerated by `flutter pub get`.
- `lib/domain/reminder_settings.dart` — add the canonical `ReminderSettings.initial()` factory; existing constructor validation remains authoritative.

**Create**
- `lib/data/local/app_database.dart` — SQLite schema v1, open/close, foreign-key configuration, initial singleton settings row.
- `lib/data/local/topic_repository.dart` — Topic create/list/rename/delete with normalized uniqueness, ReviewItem protection, and selected-scope-safe deletion.
- `lib/data/local/review_item_repository.dart` — ReviewItem create/list/get/update/delete and persisted `last_shown_at` update.
- `lib/data/local/reminder_settings_repository.dart` — load/save singleton ReminderSettings plus selected Topic set atomically.
- `test/data/local/app_database_test.dart` — schema/default/foreign-key/reopen tests.
- `test/data/local/topic_repository_test.dart` — Topic CRUD, uniqueness, deletion boundaries.
- `test/data/local/review_item_repository_test.dart` — ReviewItem CRUD, FK, history-preservation tests.
- `test/data/local/reminder_settings_repository_test.dart` — initial settings and scope persistence tests.
- `test/data/local/persistence_integration_test.dart` — cross-repository restart and transactional invariant proof.

No product UI, notification plugin, WorkManager code, Android manifest permission changes, or Diagnostics surface belongs in these files.

---

### Task 1: SQLite Bootstrap and Canonical Initial Settings

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `lib/domain/reminder_settings.dart`
- Create: `lib/data/local/app_database.dart`
- Create: `test/data/local/app_database_test.dart`

**Interfaces:**
- Consumes: existing `ActiveWindow`, `ReminderScope`, `ReminderSettings` Plan 1 constructors.
- Produces:
  - `ReminderSettings.initial()`
  - `AppDatabase.openProduction()`
  - `AppDatabase.openWith({required DatabaseFactory factory, required String path})`
  - `Future<Database> AppDatabase.database`
  - `Future<void> AppDatabase.close()`

**Acceptance:**
- Runtime project declares SQLite/path dependencies compatible with the branch Dart SDK.
- Fresh schema enables SQLite foreign keys.
- Fresh schema creates Topics, ReviewItems, singleton ReminderSettings, and selected-scope tables with database-level key/unique/check constraints.
- A fresh database contains exactly one legal initial ReminderSettings row: disabled, all Topics, all day, 60 minutes, 24 hours.
- Closing/reopening the same database does not recreate or change existing settings.

- [ ] **Step 1: Add persistence dependencies**

Replace the dependency blocks in `pubspec.yaml` with the following exact entries while preserving the existing package metadata and Flutter section:

```yaml
dependencies:
  flutter:
    sdk: flutter
  path: ^1.9.1
  sqflite: ^2.4.4

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  sqflite_common_ffi: ^2.4.3
```

Run:

```bash
flutter pub get
```

Expected: exit 0; `pubspec.lock` is updated and dependency resolution succeeds under Dart `^3.13.4`.

- [ ] **Step 2: Write failing initial-settings/domain-factory tests**

Append these tests to `test/domain/reminder_settings_test.dart`:

```dart
test('initial settings match the authoritative Spec defaults', () {
  final settings = ReminderSettings.initial();

  expect(settings.enabled, isFalse);
  expect(settings.activeWindow.mode, ActiveWindowMode.allDay);
  expect(settings.reminderInterval, const Duration(minutes: 60));
  expect(settings.repeatCooldown, const Duration(hours: 24));
  expect(settings.scope.mode, ReminderScopeMode.allTopics);
  expect(settings.scope.topicIds, isEmpty);
});
```

Run:

```bash
flutter test test/domain/reminder_settings_test.dart
```

Expected: FAIL because `ReminderSettings.initial()` does not exist yet.

- [ ] **Step 3: Add the canonical initial-settings factory**

Replace `lib/domain/reminder_settings.dart` with:

```dart
import 'active_window.dart';
import 'reminder_scope.dart';

const minimumProductionReminderInterval = Duration(minutes: 15);

final class ReminderSettings {
  ReminderSettings({
    required this.enabled,
    required this.activeWindow,
    required this.reminderInterval,
    required this.repeatCooldown,
    required this.scope,
  }) {
    if (reminderInterval < minimumProductionReminderInterval) {
      throw ArgumentError.value(
        reminderInterval,
        'reminderInterval',
        'Production reminder interval must be at least 15 minutes',
      );
    }
    if (repeatCooldown.isNegative) {
      throw ArgumentError.value(
        repeatCooldown,
        'repeatCooldown',
        'Repeat cooldown must not be negative',
      );
    }
  }

  factory ReminderSettings.initial() {
    return ReminderSettings(
      enabled: false,
      activeWindow: ActiveWindow.allDay(),
      reminderInterval: const Duration(minutes: 60),
      repeatCooldown: const Duration(hours: 24),
      scope: ReminderScope.allTopics(),
    );
  }

  final bool enabled;
  final ActiveWindow activeWindow;
  final Duration reminderInterval;
  final Duration repeatCooldown;
  final ReminderScope scope;
}
```

Run:

```bash
flutter test test/domain/reminder_settings_test.dart
```

Expected: PASS.

- [ ] **Step 4: Write failing database bootstrap tests**

Create `test/data/local/app_database_test.dart`:

```dart
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
```

Run:

```bash
flutter test test/data/local/app_database_test.dart
```

Expected: FAIL because `AppDatabase` does not exist.

- [ ] **Step 5: Implement schema v1 and database lifecycle**

Create `lib/data/local/app_database.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

final class AppDatabase {
  AppDatabase._({required DatabaseFactory factory, required String path})
      : _factory = factory,
        _path = path;

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
    final store = AppDatabase._(factory: factory, path: path);
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
```

Run:

```bash
flutter test test/data/local/app_database_test.dart
```

Expected: PASS.

- [ ] **Step 6: Run Task 1 regression and commit**

Run:

```bash
flutter test test/domain/reminder_settings_test.dart test/data/local/app_database_test.dart
flutter analyze
```

Expected: both commands exit 0 with no test failures/analyzer issues.

Commit:

```bash
git add pubspec.yaml pubspec.lock lib/domain/reminder_settings.dart lib/data/local/app_database.dart test/domain/reminder_settings_test.dart test/data/local/app_database_test.dart
git commit -m "feat: add local database bootstrap"
```

**Per-Task Coverage Review:** initial factory → domain test; DB defaults/reopen → bootstrap test; FK enablement/dangling Topic rejection → direct SQLite test; dependency resolution/analyzer → command evidence. `COVERAGE_COMPLETE`.

---

### Task 2: Topic Repository and Transactional Deletion Rules

**Files:**
- Create: `lib/data/local/topic_repository.dart`
- Create: `test/data/local/topic_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `Topic`, `normalizeTopicName()`, `topicNameKey()`.
- Produces:
  - `Future<List<Topic>> TopicRepository.listTopics()`
  - `Future<Topic> TopicRepository.createTopic({required String name, required DateTime now})`
  - `Future<Topic> TopicRepository.renameTopic({required int id, required String name, required DateTime now})`
  - `Future<void> TopicRepository.deleteTopic(int id)`

**Acceptance:**
- Topic names persist trimmed while uniqueness uses `topicNameKey()`.
- Rename preserves Topic ID and creation timestamp.
- Duplicate normalized name is rejected.
- Topic with ReviewItems cannot be deleted.
- Deleting an unselected empty Topic is allowed.
- Deleting a selected empty Topic from a multi-selection atomically removes it from scope.
- Deleting the last selected Topic is blocked whether reminders are enabled or disabled.

- [ ] **Step 1: Write failing Topic repository tests**

Create `test/data/local/topic_repository_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppDatabase store;
  late TopicRepository topics;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-topic-test-');
    store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    topics = TopicRepository(store);
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('create trims name, list persists it, and rename keeps stable identity', () async {
    final createdAt = DateTime.utc(2026, 9, 27, 1);
    final topic = await topics.createTopic(name: '  医学  ', now: createdAt);
    expect(topic.name, '医学');

    final renamedAt = createdAt.add(const Duration(hours: 1));
    final renamed = await topics.renameTopic(
      id: topic.id,
      name: '临床医学',
      now: renamedAt,
    );

    expect(renamed.id, topic.id);
    expect(renamed.createdAt, createdAt);
    expect(renamed.updatedAt, renamedAt);
    expect((await topics.listTopics()).single.name, '临床医学');
  });

  test('duplicate normalized Topic name is rejected', () async {
    final now = DateTime.utc(2026, 9, 27);
    await topics.createTopic(name: 'Biology', now: now);

    expect(
      () => topics.createTopic(name: ' biology ', now: now),
      throwsStateError,
    );
  });

  test('Topic with ReviewItems cannot be deleted', () async {
    final now = DateTime.utc(2026, 9, 27);
    final topic = await topics.createTopic(name: '医学', now: now);
    final db = await store.database;
    await db.insert('review_items', <String, Object?>{
      'content': 'content',
      'topic_id': topic.id,
      'enabled': 1,
      'created_at_us': now.microsecondsSinceEpoch,
      'updated_at_us': now.microsecondsSinceEpoch,
      'last_shown_at_us': null,
    });

    expect(() => topics.deleteTopic(topic.id), throwsStateError);
  });

  test('deleting one selected empty Topic keeps the remaining selected Topic', () async {
    final now = DateTime.utc(2026, 9, 27);
    final a = await topics.createTopic(name: '医学', now: now);
    final b = await topics.createTopic(name: '生物', now: now);
    final db = await store.database;
    await db.update(
      'reminder_settings',
      <String, Object?>{'scope_mode': 'selected_topics'},
      where: 'id = 1',
    );
    await db.insert('reminder_scope_topics', <String, Object?>{'topic_id': a.id});
    await db.insert('reminder_scope_topics', <String, Object?>{'topic_id': b.id});

    await topics.deleteTopic(b.id);

    final scopeRows = await db.query('reminder_scope_topics');
    expect(scopeRows, <Map<String, Object?>>[
      <String, Object?>{'topic_id': a.id},
    ]);
    expect((await topics.listTopics()).map((topic) => topic.id), <int>[a.id]);
  });

  for (final enabled in <int>[0, 1]) {
    test('last selected Topic deletion is blocked when enabled=$enabled', () async {
      final now = DateTime.utc(2026, 9, 27);
      final topic = await topics.createTopic(name: '医学', now: now);
      final db = await store.database;
      await db.update(
        'reminder_settings',
        <String, Object?>{
          'scope_mode': 'selected_topics',
          'enabled': enabled,
        },
        where: 'id = 1',
      );
      await db.insert(
        'reminder_scope_topics',
        <String, Object?>{'topic_id': topic.id},
      );

      expect(() => topics.deleteTopic(topic.id), throwsStateError);
    });
  }
}
```

Run:

```bash
flutter test test/data/local/topic_repository_test.dart
```

Expected: FAIL because `TopicRepository` does not exist.

- [ ] **Step 2: Implement Topic repository**

Create `lib/data/local/topic_repository.dart`:

```dart
import '../../domain/topic.dart';
import 'app_database.dart';

final class TopicRepository {
  TopicRepository(this._store);

  final AppDatabase _store;

  Future<List<Topic>> listTopics() async {
    final db = await _store.database;
    final rows = await db.query('topics', orderBy: 'id ASC');
    return List<Topic>.unmodifiable(rows.map(_topicFromRow));
  }

  Future<Topic> createTopic({
    required String name,
    required DateTime now,
  }) async {
    final normalized = normalizeTopicName(name);
    final key = topicNameKey(normalized);
    final timestamp = now.toUtc().microsecondsSinceEpoch;
    final db = await _store.database;

    return db.transaction((txn) async {
      final duplicate = await txn.query(
        'topics',
        columns: <String>['id'],
        where: 'name_key = ?',
        whereArgs: <Object?>[key],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Topic name already exists: $normalized');
      }

      final id = await txn.insert('topics', <String, Object?>{
        'name': normalized,
        'name_key': key,
        'created_at_us': timestamp,
        'updated_at_us': timestamp,
      });
      return Topic(
        id: id,
        name: normalized,
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );
    });
  }

  Future<Topic> renameTopic({
    required int id,
    required String name,
    required DateTime now,
  }) async {
    final normalized = normalizeTopicName(name);
    final key = topicNameKey(normalized);
    final db = await _store.database;

    return db.transaction((txn) async {
      final current = await txn.query(
        'topics',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (current.isEmpty) {
        throw StateError('Topic $id does not exist');
      }
      final duplicate = await txn.query(
        'topics',
        columns: <String>['id'],
        where: 'name_key = ? AND id <> ?',
        whereArgs: <Object?>[key, id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Topic name already exists: $normalized');
      }

      final timestamp = now.toUtc().microsecondsSinceEpoch;
      await txn.update(
        'topics',
        <String, Object?>{
          'name': normalized,
          'name_key': key,
          'updated_at_us': timestamp,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      final row = Map<String, Object?>.from(current.single)
        ..['name'] = normalized
        ..['name_key'] = key
        ..['updated_at_us'] = timestamp;
      return _topicFromRow(row);
    });
  }

  Future<void> deleteTopic(int id) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      final topicRows = await txn.query(
        'topics',
        columns: <String>['id'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (topicRows.isEmpty) {
        throw StateError('Topic $id does not exist');
      }

      final itemCount = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM review_items WHERE topic_id = ?',
            <Object?>[id],
          )) ??
          0;
      if (itemCount > 0) {
        throw StateError('Topic $id still owns ReviewItems');
      }

      final settings = await txn.query(
        'reminder_settings',
        columns: <String>['scope_mode'],
        where: 'id = 1',
        limit: 1,
      );
      if (settings.length != 1) {
        throw StateError('ReminderSettings singleton is missing');
      }

      if (settings.single['scope_mode'] == 'selected_topics') {
        final selected = await txn.query(
          'reminder_scope_topics',
          columns: <String>['topic_id'],
          orderBy: 'topic_id ASC',
        );
        final isSelected = selected.any((row) => row['topic_id'] == id);
        if (isSelected && selected.length == 1) {
          throw StateError('Cannot delete the last selected Topic');
        }
        if (isSelected) {
          await txn.delete(
            'reminder_scope_topics',
            where: 'topic_id = ?',
            whereArgs: <Object?>[id],
          );
        }
      }

      final deleted = await txn.delete(
        'topics',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (deleted != 1) {
        throw StateError('Expected to delete exactly one Topic $id');
      }
    });
  }

  Topic _topicFromRow(Map<String, Object?> row) {
    return Topic(
      id: row['id']! as int,
      name: row['name']! as String,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        row['created_at_us']! as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        row['updated_at_us']! as int,
        isUtc: true,
      ),
    );
  }
}
```

Add this import at the top because `Sqflite.firstIntValue` is used:

```dart
import 'package:sqflite/sqflite.dart';
```

The final import block must be:

```dart
import 'package:sqflite/sqflite.dart';

import '../../domain/topic.dart';
import 'app_database.dart';
```

Run:

```bash
flutter test test/data/local/topic_repository_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run Task 2 regression and commit**

Run:

```bash
flutter test test/data/local/app_database_test.dart test/data/local/topic_repository_test.dart
flutter analyze
```

Expected: exit 0.

Commit:

```bash
git add lib/data/local/topic_repository.dart test/data/local/topic_repository_test.dart
git commit -m "feat: persist topics safely"
```

**Per-Task Coverage Review:** normalized uniqueness → direct duplicate test; stable rename → direct test; ReviewItem ownership deletion boundary → direct negative test; multi-selected deletion → direct transaction test; last-selected deletion with both reminder enabled states → direct negative tests. `COVERAGE_COMPLETE`.

---

### Task 3: ReviewItem Repository and Reminder-History Persistence

**Files:**
- Create: `lib/data/local/review_item_repository.dart`
- Create: `test/data/local/review_item_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `ReviewItem`, existing Topic FK.
- Produces:
  - `Future<List<ReviewItem>> ReviewItemRepository.listReviewItems()`
  - `Future<ReviewItem?> ReviewItemRepository.getReviewItem(int id)`
  - `Future<ReviewItem> ReviewItemRepository.createReviewItem(...)`
  - `Future<ReviewItem> ReviewItemRepository.updateReviewItem(...)`
  - `Future<void> ReviewItemRepository.deleteReviewItem(int id)`
  - `Future<ReviewItem> ReviewItemRepository.recordShownAt({required int id, required DateTime shownAt})`

**Acceptance:**
- Create rejects blank content and nonexistent Topic IDs.
- Update can change content, Topic, and enabled state while preserving stable ID, creation time, and `last_shown_at`.
- `recordShownAt` persists only reminder history and does not pretend notification dispatch occurred by itself; Plan 3 owns when it is called.
- Delete removes exactly the requested ReviewItem.
- Row mapping round-trips UTC instants deterministically.

- [ ] **Step 1: Write failing ReviewItem repository tests**

Create `test/data/local/review_item_repository_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/review_item_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late AppDatabase store;
  late TopicRepository topics;
  late ReviewItemRepository items;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kaoyan-item-test-');
    store = await AppDatabase.openWith(
      factory: databaseFactoryFfi,
      path: '${tempDir.path}${Platform.pathSeparator}app.db',
    );
    topics = TopicRepository(store);
    items = ReviewItemRepository(store);
  });

  tearDown(() async {
    await store.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('create/list round-trips a ReviewItem', () async {
    final now = DateTime.utc(2026, 9, 27, 8);
    final topic = await topics.createTopic(name: '医学', now: now);

    final created = await items.createReviewItem(
      content: '心输出量相关知识',
      topicId: topic.id,
      enabled: true,
      now: now,
    );

    final loaded = (await items.listReviewItems()).single;
    expect(loaded.id, created.id);
    expect(loaded.content, '心输出量相关知识');
    expect(loaded.topicId, topic.id);
    expect(loaded.enabled, isTrue);
    expect(loaded.createdAt, now);
    expect(loaded.updatedAt, now);
    expect(loaded.lastShownAt, isNull);
  });

  test('create rejects a missing Topic and blank content', () async {
    final now = DateTime.utc(2026, 9, 27);
    expect(
      () => items.createReviewItem(
        content: 'text',
        topicId: 999,
        enabled: true,
        now: now,
      ),
      throwsStateError,
    );

    final topic = await topics.createTopic(name: '医学', now: now);
    expect(
      () => items.createReviewItem(
        content: '   ',
        topicId: topic.id,
        enabled: true,
        now: now,
      ),
      throwsArgumentError,
    );
  });

  test('editing preserves creation time and lastShownAt', () async {
    final createdAt = DateTime.utc(2026, 9, 27, 8);
    final firstTopic = await topics.createTopic(name: '医学', now: createdAt);
    final secondTopic = await topics.createTopic(name: '生物', now: createdAt);
    final created = await items.createReviewItem(
      content: 'old',
      topicId: firstTopic.id,
      enabled: true,
      now: createdAt,
    );
    final shownAt = createdAt.add(const Duration(hours: 1));
    await items.recordShownAt(id: created.id, shownAt: shownAt);

    final updatedAt = createdAt.add(const Duration(hours: 2));
    final updated = await items.updateReviewItem(
      id: created.id,
      content: 'new',
      topicId: secondTopic.id,
      enabled: false,
      now: updatedAt,
    );

    expect(updated.createdAt, createdAt);
    expect(updated.updatedAt, updatedAt);
    expect(updated.lastShownAt, shownAt);
    expect(updated.topicId, secondTopic.id);
    expect(updated.enabled, isFalse);
  });

  test('delete removes exactly the requested ReviewItem', () async {
    final now = DateTime.utc(2026, 9, 27);
    final topic = await topics.createTopic(name: '医学', now: now);
    final a = await items.createReviewItem(
      content: 'a',
      topicId: topic.id,
      enabled: true,
      now: now,
    );
    final b = await items.createReviewItem(
      content: 'b',
      topicId: topic.id,
      enabled: true,
      now: now,
    );

    await items.deleteReviewItem(a.id);

    expect(await items.getReviewItem(a.id), isNull);
    expect((await items.getReviewItem(b.id))?.content, 'b');
  });
}
```

Run:

```bash
flutter test test/data/local/review_item_repository_test.dart
```

Expected: FAIL because `ReviewItemRepository` does not exist.

- [ ] **Step 2: Implement ReviewItem repository**

Create `lib/data/local/review_item_repository.dart`:

```dart
import '../../domain/review_item.dart';
import 'app_database.dart';

final class ReviewItemRepository {
  ReviewItemRepository(this._store);

  final AppDatabase _store;

  Future<List<ReviewItem>> listReviewItems() async {
    final db = await _store.database;
    final rows = await db.query('review_items', orderBy: 'id ASC');
    return List<ReviewItem>.unmodifiable(rows.map(_itemFromRow));
  }

  Future<ReviewItem?> getReviewItem(int id) async {
    final db = await _store.database;
    final rows = await db.query(
      'review_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _itemFromRow(rows.single);
  }

  Future<ReviewItem> createReviewItem({
    required String content,
    required int topicId,
    required bool enabled,
    required DateTime now,
  }) async {
    if (content.trim().isEmpty) {
      throw ArgumentError.value(content, 'content', 'ReviewItem content must not be blank');
    }
    final db = await _store.database;
    final timestamp = now.toUtc().microsecondsSinceEpoch;

    return db.transaction((txn) async {
      await _requireTopic(txn, topicId);
      final id = await txn.insert('review_items', <String, Object?>{
        'content': content,
        'topic_id': topicId,
        'enabled': enabled ? 1 : 0,
        'created_at_us': timestamp,
        'updated_at_us': timestamp,
        'last_shown_at_us': null,
      });
      return ReviewItem(
        id: id,
        content: content,
        topicId: topicId,
        enabled: enabled,
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );
    });
  }

  Future<ReviewItem> updateReviewItem({
    required int id,
    required String content,
    required int topicId,
    required bool enabled,
    required DateTime now,
  }) async {
    if (content.trim().isEmpty) {
      throw ArgumentError.value(content, 'content', 'ReviewItem content must not be blank');
    }
    final db = await _store.database;

    return db.transaction((txn) async {
      final current = await txn.query(
        'review_items',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (current.isEmpty) {
        throw StateError('ReviewItem $id does not exist');
      }
      await _requireTopic(txn, topicId);
      await txn.update(
        'review_items',
        <String, Object?>{
          'content': content,
          'topic_id': topicId,
          'enabled': enabled ? 1 : 0,
          'updated_at_us': now.toUtc().microsecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      final updated = await txn.query(
        'review_items',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return _itemFromRow(updated.single);
    });
  }

  Future<ReviewItem> recordShownAt({
    required int id,
    required DateTime shownAt,
  }) async {
    final db = await _store.database;
    final updated = await db.update(
      'review_items',
      <String, Object?>{
        'last_shown_at_us': shownAt.toUtc().microsecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (updated != 1) {
      throw StateError('ReviewItem $id does not exist');
    }
    return (await getReviewItem(id))!;
  }

  Future<void> deleteReviewItem(int id) async {
    final db = await _store.database;
    final deleted = await db.delete(
      'review_items',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (deleted != 1) {
      throw StateError('ReviewItem $id does not exist');
    }
  }

  Future<void> _requireTopic(DatabaseExecutor executor, int topicId) async {
    final rows = await executor.query(
      'topics',
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[topicId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Topic $topicId does not exist');
    }
  }

  ReviewItem _itemFromRow(Map<String, Object?> row) {
    final lastShown = row['last_shown_at_us'] as int?;
    return ReviewItem(
      id: row['id']! as int,
      content: row['content']! as String,
      topicId: row['topic_id']! as int,
      enabled: (row['enabled']! as int) == 1,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        row['created_at_us']! as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(
        row['updated_at_us']! as int,
        isUtc: true,
      ),
      lastShownAt: lastShown == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(lastShown, isUtc: true),
    );
  }
}
```

Add this import at the top because `DatabaseExecutor` is used:

```dart
import 'package:sqflite/sqflite.dart';
```

Final import block:

```dart
import 'package:sqflite/sqflite.dart';

import '../../domain/review_item.dart';
import 'app_database.dart';
```

Run:

```bash
flutter test test/data/local/review_item_repository_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run Task 3 regression and commit**

Run:

```bash
flutter test test/data/local/topic_repository_test.dart test/data/local/review_item_repository_test.dart
flutter analyze
```

Expected: exit 0.

Commit:

```bash
git add lib/data/local/review_item_repository.dart test/data/local/review_item_repository_test.dart
git commit -m "feat: persist review items"
```

**Per-Task Coverage Review:** create/list round trip → direct test; blank/missing Topic negative states → direct tests; edit-history preservation → direct test; exact delete → direct test. `COVERAGE_COMPLETE`.

---

### Task 4: ReminderSettings and ReminderScope Persistence

**Files:**
- Create: `lib/data/local/reminder_settings_repository.dart`
- Create: `test/data/local/reminder_settings_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `ReminderSettings`, `ReminderScope`, `ActiveWindow`.
- Produces:
  - `Future<ReminderSettings> ReminderSettingsRepository.loadSettings()`
  - `Future<void> ReminderSettingsRepository.saveSettings(ReminderSettings settings)`

**Acceptance:**
- Fresh load returns the canonical defaults, never null.
- `ALL_TOPICS` persists with zero rows in `reminder_scope_topics`.
- `SELECTED_TOPICS` persists a nonempty set atomically and rejects any missing Topic ID.
- Saving `ALL_TOPICS` after a selected scope removes stale selected rows.
- Bounded window mode/start/end, interval, cooldown, enabled state, and scope survive close/reopen exactly.

- [ ] **Step 1: Write failing settings repository tests**

Create `test/data/local/reminder_settings_repository_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_settings_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: dbPath);
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
    await settings.saveSettings(ReminderSettings(
      enabled: true,
      activeWindow: ActiveWindow.bounded(startMinute: 22 * 60, endMinute: 60),
      reminderInterval: const Duration(minutes: 30),
      repeatCooldown: const Duration(hours: 48),
      scope: ReminderScope.selectedTopics(<int>{a.id, b.id}),
    ));

    await store.close();
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: dbPath);
    settings = ReminderSettingsRepository(store);

    final loaded = await settings.loadSettings();
    expect(loaded.enabled, isTrue);
    expect(loaded.activeWindow.mode, ActiveWindowMode.bounded);
    expect(loaded.activeWindow.startMinute, 22 * 60);
    expect(loaded.activeWindow.endMinute, 60);
    expect(loaded.reminderInterval, const Duration(minutes: 30));
    expect(loaded.repeatCooldown, const Duration(hours: 48));
    expect(loaded.scope.mode, ReminderScopeMode.selectedTopics);
    expect(loaded.scope.topicIds, <int>{a.id, b.id});
  });

  test('selected scope rejects missing Topic ids', () async {
    expect(
      () => settings.saveSettings(ReminderSettings(
        enabled: false,
        activeWindow: ActiveWindow.allDay(),
        reminderInterval: const Duration(minutes: 60),
        repeatCooldown: const Duration(hours: 24),
        scope: ReminderScope.selectedTopics(<int>{999}),
      )),
      throwsStateError,
    );
  });

  test('saving ALL_TOPICS clears persisted selected Topic rows', () async {
    final now = DateTime.utc(2026, 9, 27);
    final topic = await topics.createTopic(name: '医学', now: now);
    await settings.saveSettings(ReminderSettings(
      enabled: false,
      activeWindow: ActiveWindow.allDay(),
      reminderInterval: const Duration(minutes: 60),
      repeatCooldown: const Duration(hours: 24),
      scope: ReminderScope.selectedTopics(<int>{topic.id}),
    ));

    await settings.saveSettings(ReminderSettings.initial());

    final db = await store.database;
    expect(await db.query('reminder_scope_topics'), isEmpty);
    expect((await settings.loadSettings()).scope.mode, ReminderScopeMode.allTopics);
  });
}
```

Run:

```bash
flutter test test/data/local/reminder_settings_repository_test.dart
```

Expected: FAIL because `ReminderSettingsRepository` does not exist.

- [ ] **Step 2: Implement settings repository**

Create `lib/data/local/reminder_settings_repository.dart`:

```dart
import '../../domain/active_window.dart';
import '../../domain/reminder_scope.dart';
import '../../domain/reminder_settings.dart';
import 'app_database.dart';

final class ReminderSettingsRepository {
  ReminderSettingsRepository(this._store);

  final AppDatabase _store;

  Future<ReminderSettings> loadSettings() async {
    final db = await _store.database;
    final rows = await db.query(
      'reminder_settings',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.length != 1) {
      throw StateError('ReminderSettings singleton is missing');
    }

    final row = rows.single;
    final activeWindow = switch (row['active_window_mode']) {
      'all_day' => ActiveWindow.allDay(),
      'bounded' => ActiveWindow.bounded(
          startMinute: row['start_minute']! as int,
          endMinute: row['end_minute']! as int,
        ),
      final Object? value => throw StateError('Invalid active_window_mode: $value'),
    };

    final scopeMode = row['scope_mode'];
    final ReminderScope scope;
    if (scopeMode == 'all_topics') {
      scope = ReminderScope.allTopics();
    } else if (scopeMode == 'selected_topics') {
      final selectedRows = await db.query(
        'reminder_scope_topics',
        columns: <String>['topic_id'],
        orderBy: 'topic_id ASC',
      );
      final ids = selectedRows.map((selected) => selected['topic_id']! as int).toSet();
      if (ids.isEmpty) {
        throw StateError('Persisted SELECTED_TOPICS scope is empty');
      }
      scope = ReminderScope.selectedTopics(ids);
    } else {
      throw StateError('Invalid scope_mode: $scopeMode');
    }

    return ReminderSettings(
      enabled: (row['enabled']! as int) == 1,
      activeWindow: activeWindow,
      reminderInterval: Duration(milliseconds: row['reminder_interval_ms']! as int),
      repeatCooldown: Duration(milliseconds: row['repeat_cooldown_ms']! as int),
      scope: scope,
    );
  }

  Future<void> saveSettings(ReminderSettings settings) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      final selectedIds = settings.scope.topicIds.toList()..sort();
      if (settings.scope.mode == ReminderScopeMode.selectedTopics) {
        for (final id in selectedIds) {
          final exists = await txn.query(
            'topics',
            columns: <String>['id'],
            where: 'id = ?',
            whereArgs: <Object?>[id],
            limit: 1,
          );
          if (exists.isEmpty) {
            throw StateError('Selected Topic $id does not exist');
          }
        }
      }

      final window = settings.activeWindow;
      final updated = await txn.update(
        'reminder_settings',
        <String, Object?>{
          'enabled': settings.enabled ? 1 : 0,
          'active_window_mode': window.mode == ActiveWindowMode.allDay ? 'all_day' : 'bounded',
          'start_minute': window.startMinute,
          'end_minute': window.endMinute,
          'reminder_interval_ms': settings.reminderInterval.inMilliseconds,
          'repeat_cooldown_ms': settings.repeatCooldown.inMilliseconds,
          'scope_mode': settings.scope.mode == ReminderScopeMode.allTopics
              ? 'all_topics'
              : 'selected_topics',
        },
        where: 'id = 1',
      );
      if (updated != 1) {
        throw StateError('ReminderSettings singleton is missing');
      }

      await txn.delete('reminder_scope_topics');
      if (settings.scope.mode == ReminderScopeMode.selectedTopics) {
        for (final id in selectedIds) {
          await txn.insert(
            'reminder_scope_topics',
            <String, Object?>{'topic_id': id},
          );
        }
      }
    });
  }
}
```

Run:

```bash
flutter test test/data/local/reminder_settings_repository_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run Task 4 regression and commit**

Run:

```bash
flutter test test/data/local/app_database_test.dart test/data/local/topic_repository_test.dart test/data/local/review_item_repository_test.dart test/data/local/reminder_settings_repository_test.dart
flutter analyze
```

Expected: exit 0.

Commit:

```bash
git add lib/data/local/reminder_settings_repository.dart test/data/local/reminder_settings_repository_test.dart
git commit -m "feat: persist reminder settings"
```

**Per-Task Coverage Review:** fresh nonnull defaults → direct test; bounded/all fields reopen → direct persistence test; invalid selected FK → direct negative test; ALL_TOPICS stale-row removal → direct test. `COVERAGE_COMPLETE`.

---

### Task 5: Cross-Repository Restart and Integrity Acceptance

**Files:**
- Create: `test/data/local/persistence_integration_test.dart`

**Interfaces:**
- Consumes: all Plan 2 repository APIs exactly as implemented in Tasks 1–4.
- Produces: no new production API; produces acceptance evidence that the repositories compose without violating Spec invariants.

**Acceptance:**
- Topic + ReviewItem + selected scope + reminder history survive database close/reopen.
- Moving/deleting a ReviewItem can make a Topic empty without resetting ReviewItem history.
- Deleting an empty selected Topic from a multi-selection updates selected scope atomically and remains valid after reopen.
- No duplicate source of truth for `next_eligible_at` is introduced.
- Full Plan 1 + Plan 2 test suite and analyzer pass.

- [ ] **Step 1: Write the cross-repository acceptance test**

Create `test/data/local/persistence_integration_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_settings_repository.dart';
import 'package:kaoyan_review/data/local/review_item_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('persistent state remains valid across reopen and selected Topic deletion', () async {
    final tempDir = await Directory.systemTemp.createTemp('kaoyan-integration-');
    final path = '${tempDir.path}${Platform.pathSeparator}app.db';
    final createdAt = DateTime.utc(2026, 9, 27, 8);
    final shownAt = createdAt.add(const Duration(hours: 1));

    var store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    var topics = TopicRepository(store);
    var items = ReviewItemRepository(store);
    var settings = ReminderSettingsRepository(store);

    final medicine = await topics.createTopic(name: '医学', now: createdAt);
    final biology = await topics.createTopic(name: '生物', now: createdAt);
    final item = await items.createReviewItem(
      content: '需要复习的段落',
      topicId: biology.id,
      enabled: true,
      now: createdAt,
    );
    await items.recordShownAt(id: item.id, shownAt: shownAt);
    await settings.saveSettings(ReminderSettings(
      enabled: true,
      activeWindow: ActiveWindow.allDay(),
      reminderInterval: const Duration(minutes: 60),
      repeatCooldown: const Duration(hours: 24),
      scope: ReminderScope.selectedTopics(<int>{medicine.id, biology.id}),
    ));

    await store.close();
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    topics = TopicRepository(store);
    items = ReviewItemRepository(store);
    settings = ReminderSettingsRepository(store);

    final reloadedItem = await items.getReviewItem(item.id);
    expect(reloadedItem?.lastShownAt, shownAt);
    expect((await settings.loadSettings()).scope.topicIds, <int>{medicine.id, biology.id});

    await items.updateReviewItem(
      id: item.id,
      content: reloadedItem!.content,
      topicId: medicine.id,
      enabled: reloadedItem.enabled,
      now: createdAt.add(const Duration(hours: 2)),
    );
    expect((await items.getReviewItem(item.id))?.lastShownAt, shownAt);

    await topics.deleteTopic(biology.id);
    expect((await settings.loadSettings()).scope.topicIds, <int>{medicine.id});

    await store.close();
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    settings = ReminderSettingsRepository(store);
    items = ReviewItemRepository(store);

    expect((await settings.loadSettings()).scope.topicIds, <int>{medicine.id});
    expect((await items.getReviewItem(item.id))?.lastShownAt, shownAt);

    final db = await store.database;
    final columns = await db.rawQuery('PRAGMA table_info(review_items)');
    expect(columns.map((row) => row['name']), isNot(contains('next_eligible_at')));

    await store.close();
    await tempDir.delete(recursive: true);
  });
}
```

Run:

```bash
flutter test test/data/local/persistence_integration_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run the complete Plan 1 + Plan 2 verification set**

Run:

```bash
flutter test
flutter analyze
```

Expected: all tests PASS; analyzer reports no issues.

Also run:

```bash
flutter pub deps --style=compact
```

Expected: dependency graph resolves with `sqflite`, `path`, and test-only `sqflite_common_ffi`; no notification, WorkManager, AI, OCR, networking, or cloud dependency has been introduced.

- [ ] **Step 3: Commit integrated persistence acceptance**

```bash
git add test/data/local/persistence_integration_test.dart
git commit -m "test: verify persistence invariants"
```

**Per-Task Coverage Review:** restart durability → direct file-backed FFI reopen; ReviewItem history survives Topic move → direct assertion; selected-scope-safe Topic deletion → direct assertion before/after reopen; negative ownership for derived `next_eligible_at` → schema introspection; no scope creep/dependency leak → dependency graph verification. `COVERAGE_COMPLETE`.

---

## Plan 2 Self-Review

### 1. Spec coverage

Covered in this detailed Plan:
- stable local source of truth for Topics, ReviewItems, ReminderSettings, ReminderScope, and `last_shown_at`;
- legal first-run ReminderSettings;
- Topic normalized uniqueness and stable identity persistence;
- ReviewItem exactly-one-Topic referential integrity;
- Topic deletion restrictions including the newly closed last-selected rule;
- selected-scope valid Topic references and nonempty persistence;
- ReviewItem edit/history preservation;
- derived-only `next_eligible_at` ownership;
- persistence/reopen behavior.

Explicitly mapped downstream:
- `[start, end)` wall-clock membership evaluation → Plan 3 runtime evaluator;
- serialized candidate selection + Android dispatch + history commit boundary → Plan 3;
- Android scheduling, notifications, permissions, foreground/background/reboot/timezone behavior → Plan 3;
- product CRUD/settings UI and Diagnostics → Plan 4;
- APK and OPPO Reno8 evidence → Plans 4–5.

No current Plan 2 Task requires a new product-semantic or architecture decision.

### 2. Placeholder scan

The plan contains no `TBD`, `TODO`, “implement later”, unspecified validation, or unnamed tests for Plan 2 behavior. Downstream work is named in the roadmap rather than left as a placeholder inside a current Task.

### 3. Type/interface consistency

- Existing Plan 1 names are used verbatim: `Topic`, `ReviewItem`, `ReminderScope`, `ReminderScopeMode`, `ActiveWindow`, `ActiveWindowMode`, `ReminderSettings`.
- IDs remain positive `int` values matching Plan 1 constructors.
- timestamps round-trip as UTC `DateTime` via integer microseconds.
- durations persist in integer milliseconds and reconstruct as `Duration`.
- `ReminderSettings.initial()` is introduced once in Task 1 and reused later.
- `AppDatabase`, Topic/ReviewItem/settings repository signatures remain stable through all later Tasks.

**Self-review result:** Plan 2 is internally consistent and ready for execution.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-27-android-mvp-local-persistence-crud.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per Task, review between Tasks, fast iteration.
2. **Inline Execution** — execute Tasks in the current session using `superpowers:executing-plans`, with checkpoints.

Downstream Plan 3 must not be fully detailed until Plan 2 has been implemented and its actual persistence interfaces/tests are re-read.