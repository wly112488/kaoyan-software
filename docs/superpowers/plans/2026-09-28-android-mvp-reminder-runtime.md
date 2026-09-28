# Android MVP Reminder Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Android reminder runtime that schedules one best-effort periodic evaluation, evaluates current persisted state, suppresses foreground notifications, submits an Android notification only when permitted, and commits `last_shown_at` only after successful notification submission.

**Architecture:** Keep Android scheduling separate from product truth. One unique WorkManager periodic task wakes a background isolate; every run reopens the local SQLite store and evaluates the current persisted settings/items rather than carrying stale content in work input. `ReminderExecutionService` serializes evaluation through one exclusive SQLite transaction; the selected item’s history update is staged in that transaction, the Android notification submission is the final external action, and the transaction commits only after submission succeeds. A tiny local Android Flutter plugin exposes the current process importance so foreground suppression works from both the UI engine and WorkManager’s background engine without Usage Access or Accessibility permissions.

**Tech Stack:** Flutter 3.47.5, Dart SDK `^3.13.4`, existing `sqflite ^2.4.4`, `workmanager ^0.10.10`, `flutter_local_notifications ^22.3.1`, local Android process-state plugin, `flutter_test`, `integration_test`.

**Spec:** `docs/superpowers/specs/ANDROID_MVP_SPEC.md`

**Implementation baseline:** `main@597e01f12cb23a7ed8074e66e63176577634b308` after Plan 1 and Plan 2 merged through PR #1.

## Global Constraints

- Android first; OPPO Reno8 remains the target for later real-device acceptance.
- Flutter remains the client framework.
- Persisted current settings/items are authoritative; scheduler metadata is not product truth.
- Production reminder interval is at least 15 minutes.
- Work is best-effort/inexact; do not request `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM`.
- Every trigger evaluates current persisted settings and current ReviewItems; no ReviewItem is prebound into scheduled work.
- Bounded active windows are `[start, end)` in the device’s current local wall-clock time.
- Foreground execution emits no fragmented-study system notification and consumes no history.
- Missing notification capability emits no notification and consumes no history.
- Cooldown is never bypassed to force a notification.
- Selection remains deterministic according to the existing `ReminderCandidateSelector`.
- `last_shown_at` becomes durable only after successful Android notification submission.
- Tap/dismiss does not alter cooldown.
- Duplicate/concurrent evaluations cannot independently commit the same unchanged candidate twice.
- Missed/outside-window runs do not trigger WorkManager retry bursts.
- Force Stop continuity remains `UNSUPPORTED_WHILE_FORCE_STOPPED`.
- Emulator evidence remains distinct from OPPO Reno8 evidence.
- Product UI, Diagnostics presentation, notification-detail navigation UI, APK distribution UX, and OPPO real-device closure remain downstream work.

## External Implementation Evidence Fixed for This Plan

- `workmanager 0.10.10` is the selected scheduler adapter. Android periodic work has a 15-minute minimum; `ExistingPeriodicWorkPolicy.update` updates one unique periodic work instead of creating a second cadence.
- `flutter_local_notifications 22.3.1` is the selected notification adapter. It supports Android 13+ permission requests, notification-capability checks, immediate `show()`, notification payloads, and active-notification inspection.
- The notification plugin is used only for immediate notification submission. Its notification-scheduling APIs and exact-alarm modes are not used.
- `flutter_local_notifications` requires core-library desugaring; the project already uses Java 17 and AGP 9.1.0, which is above the plugin’s documented AGP floor.
- WorkManager Android requires no app-specific boot receiver. Android WorkManager owns persistence/rescheduling of its registered work; startup reconciliation is still performed from current product settings.

---

## Scope Check and Implementation Roadmap

### Plan 1 — Domain Foundation — complete

Delivered the Android Flutter scaffold and pure domain contracts.

### Plan 2 — Local Persistence and CRUD — complete

Delivered SQLite schema/repositories, persistence invariants, restart durability, and consistent ReminderSettings reads.

### Plan 3 — Android Reminder Runtime — this document

- **Independent deliverable:** automated tests prove active-window boundaries, runtime short-circuit behavior, successful-submission history semantics, duplicate-evaluation serialization, scheduler reconciliation, and no-retry worker behavior; Android emulator evidence proves process-foreground detection, local-notification submission, and WorkManager registration without claiming OPPO verification.
- **Spec semantics covered:** §§4.2–4.4, 5.3–5.4, 6–10, acceptance 12–14 and 19–30 except the final ReviewItem-detail UI destination for acceptance 29.
- **Dependencies:** merged Plan 1 domain interfaces and Plan 2 persistence APIs.
- **Implementation prerequisites:** satisfied.

### Plan 4 — Product UI, Notification Navigation, Diagnostics, and APK

- **Goal:** Build Topic/ReviewItem/settings UI, user-driven notification permission/settings actions, consume notification-tap item IDs to open the full ReviewItem, render Diagnostics, and produce the distributable APK.
- **Spec semantics covered:** presentation boundary, acceptance 29 final destination, 31, 33, and user-facing degraded-state handling.
- **Dependency:** actual Plan 3 runtime interfaces and runtime-state persistence.
- **Prerequisite before detailed planning:** Plan 3 complete; re-read final runtime interfaces/tests.

### Plan 5 — OPPO Reno8 Real-Device Closure

- **Goal:** Execute the real-device matrix and close device-specific findings without weakening the Spec.
- **Dependency:** installable Plan 4 APK.

---

## File Structure for Plan 3

**Modify**
- `pubspec.yaml` — add WorkManager, notification, local process-state plugin, and integration-test dependencies.
- `pubspec.lock` — regenerate dependency lock.
- `android/app/build.gradle.kts` — enable core-library desugaring required by `flutter_local_notifications`.
- `lib/domain/active_window.dart` — add the authoritative local-wall-clock membership function.
- `lib/domain/reminder_evaluator.dart` — expose the existing short-circuit gate so runtime does not duplicate Plan 1 decision ordering.
- `lib/data/local/app_database.dart` — migrate schema v1 → v2 with singleton runtime diagnostics state.
- `lib/data/local/reminder_settings_repository.dart` — allow an existing `DatabaseExecutor`/transaction to load one settings snapshot without nesting a transaction.
- `lib/data/local/review_item_repository.dart` — allow transaction-scoped list/history operations.
- `lib/main.dart` — initialize WorkManager/notification/runtime reconciliation before launching the shell.

**Create**
- `test/domain/active_window_test.dart` — exact `[start,end)` tests.
- `lib/data/local/reminder_runtime_state_repository.dart` — schedule/evaluation/dispatch diagnostic persistence.
- `test/data/local/reminder_runtime_state_repository_test.dart` — migration/runtime-state tests.
- `packages/android_process_state/pubspec.yaml` — local plugin metadata.
- `packages/android_process_state/lib/android_process_state.dart` — Dart process-foreground API.
- `packages/android_process_state/android/build.gradle` — Android library module.
- `packages/android_process_state/android/src/main/AndroidManifest.xml` — empty plugin manifest.
- `packages/android_process_state/android/src/main/kotlin/com/wly112488/android_process_state/AndroidProcessStatePlugin.kt` — process-importance implementation.
- `lib/runtime/foreground_status.dart` — runtime foreground port + Android adapter.
- `test/runtime/foreground_status_test.dart` — Dart method-channel contract test.
- `android/app/src/main/res/drawable/ic_stat_review.xml` — notification small icon.
- `lib/runtime/review_notification_gateway.dart` — notification initialization, capability, permission, payload, and immediate submission.
- `test/runtime/review_notification_gateway_test.dart` — payload/notification-ID contract tests.
- `lib/runtime/reminder_execution_service.dart` — exclusive current-state evaluation and dispatch/history commit.
- `test/runtime/reminder_execution_service_test.dart` — short-circuit, rollback, success, and duplicate-run tests.
- `lib/runtime/reminder_scheduler.dart` — unique periodic WorkManager schedule/cancel reconciliation.
- `lib/runtime/reminder_settings_service.dart` — persist settings first, then reconcile scheduling without rolling back user intent on scheduler failure.
- `lib/runtime/reminder_worker.dart` — background isolate entry point and no-retry periodic handler.
- `test/runtime/reminder_scheduler_test.dart` — schedule policy tests.
- `lib/runtime/notification_tap_bus.dart` — runtime-only item-ID handoff contract for Plan 4.
- `lib/runtime/reminder_runtime_bootstrap.dart` — foreground startup initialization/reconciliation.
- `integration_test/android_reminder_runtime_test.dart` — Android emulator notification/process-state smoke proof.

No Topic/ReviewItem product screens, settings screens, Diagnostics screen, OCR, AI, cloud, exact alarm, foreground service, Usage Access, Accessibility Service, or OPPO-specific workaround belongs in this Plan.

---

### Task 1: Close Active-Window Runtime Semantics

**Files:**
- Modify: `lib/domain/active_window.dart`
- Create: `test/domain/active_window_test.dart`

**Interfaces:**
- Consumes: existing `ActiveWindowMode`, `startMinute`, `endMinute`.
- Produces: `bool ActiveWindow.containsLocal(DateTime localNow)`.

**Acceptance:**
- `ALL_DAY` always returns true.
- Same-day bounded windows include exact start and exclude exact end.
- Cross-midnight windows include exact start, midnight, and times before end; exact end is excluded.
- Runtime uses minute-of-day from the caller-provided local wall clock and does not persist timezone-derived eligibility.

- [ ] **Step 1: Write failing boundary tests**

Create `test/domain/active_window_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/active_window.dart';

void main() {
  test('all-day contains every local time', () {
    final window = ActiveWindow.allDay();
    expect(window.containsLocal(DateTime(2026, 9, 28, 0, 0)), isTrue);
    expect(window.containsLocal(DateTime(2026, 9, 28, 23, 59, 59)), isTrue);
  });

  test('same-day window is left-closed and right-open', () {
    final window = ActiveWindow.bounded(startMinute: 8 * 60, endMinute: 23 * 60);
    expect(window.containsLocal(DateTime(2026, 9, 28, 7, 59, 59)), isFalse);
    expect(window.containsLocal(DateTime(2026, 9, 28, 8, 0)), isTrue);
    expect(window.containsLocal(DateTime(2026, 9, 28, 22, 59, 59)), isTrue);
    expect(window.containsLocal(DateTime(2026, 9, 28, 23, 0)), isFalse);
  });

  test('cross-midnight window is left-closed and right-open', () {
    final window = ActiveWindow.bounded(startMinute: 22 * 60, endMinute: 60);
    expect(window.containsLocal(DateTime(2026, 9, 28, 21, 59, 59)), isFalse);
    expect(window.containsLocal(DateTime(2026, 9, 28, 22, 0)), isTrue);
    expect(window.containsLocal(DateTime(2026, 9, 29, 0, 0)), isTrue);
    expect(window.containsLocal(DateTime(2026, 9, 29, 0, 59, 59)), isTrue);
    expect(window.containsLocal(DateTime(2026, 9, 29, 1, 0)), isFalse);
  });
}
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/domain/active_window_test.dart`

Expected: FAIL because `ActiveWindow.containsLocal` does not exist.

- [ ] **Step 3: Implement exact membership**

Add this method to `ActiveWindow` in `lib/domain/active_window.dart`:

```dart
  bool containsLocal(DateTime localNow) {
    if (mode == ActiveWindowMode.allDay) {
      return true;
    }

    final minute = localNow.hour * 60 + localNow.minute;
    final start = startMinute!;
    final end = endMinute!;

    if (start < end) {
      return minute >= start && minute < end;
    }
    return minute >= start || minute < end;
  }
```

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/domain/active_window_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/active_window.dart test/domain/active_window_test.dart
git commit -m "feat: evaluate reminder active windows"
```

**Per-Task Coverage Review:** all-day, same-day start/end, cross-midnight start/midnight/end are direct tests. `COVERAGE_COMPLETE`.

---

### Task 2: Add Transaction-Scoped Runtime Persistence and Schema v2

**Files:**
- Modify: `lib/data/local/app_database.dart`
- Modify: `lib/data/local/reminder_settings_repository.dart`
- Modify: `lib/data/local/review_item_repository.dart`
- Create: `lib/data/local/reminder_runtime_state_repository.dart`
- Create: `test/data/local/reminder_runtime_state_repository_test.dart`

**Interfaces:**
- Produces:
  - `Future<ReminderSettings> ReminderSettingsRepository.loadSettingsFrom(DatabaseExecutor executor)`
  - `Future<List<ReviewItem>> ReviewItemRepository.listReviewItemsFrom(DatabaseExecutor executor)`
  - `Future<void> ReviewItemRepository.recordShownAtWith(DatabaseExecutor executor, {required int id, required DateTime shownAt})`
  - `ReminderRuntimeStateRepository.recordEvaluation(...)`
  - `ReminderRuntimeStateRepository.recordSchedule(...)`
  - `ReminderRuntimeStateRepository.loadState()`

**Acceptance:**
- Existing v1 databases migrate to v2 without changing Topics, ReviewItems, settings, scope, or history.
- Fresh v2 databases create exactly one runtime-state row.
- Runtime diagnostics retain last evaluation, last successful dispatch IDs/time, and latest schedule attempt/status/error.
- Existing public Plan 2 repository APIs continue to work.
- Outer runtime transactions can read settings/items and update history without nested transactions.

- [ ] **Step 1: Write failing migration/runtime-state tests**

Create `test/data/local/reminder_runtime_state_repository_test.dart` with tests that:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_runtime_state_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kaoyan-runtime-state-');
    path = '${dir.path}${Platform.pathSeparator}app.db';
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('fresh database has one runtime state row', () async {
    final store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    final repo = ReminderRuntimeStateRepository(store);
    final state = await repo.loadState();

    expect(state.scheduleStatus, ReminderScheduleStatus.notScheduled);
    expect(state.lastEvaluationAt, isNull);
    expect(state.lastDispatchAt, isNull);
    await store.close();
  });

  test('runtime state persists evaluation, dispatch, and schedule evidence', () async {
    final store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    final repo = ReminderRuntimeStateRepository(store);
    final now = DateTime.utc(2026, 9, 28, 3);

    final db = await store.database;
    await repo.recordEvaluation(
      db,
      at: now,
      outcome: 'notification_submitted',
      dispatchItemId: 7,
      dispatchTopicId: 3,
      dispatchAt: now,
    );
    await repo.recordSchedule(
      db,
      at: now,
      status: ReminderScheduleStatus.scheduled,
      error: null,
    );

    final loaded = await repo.loadState();
    expect(loaded.lastEvaluationOutcome, 'notification_submitted');
    expect(loaded.lastDispatchItemId, 7);
    expect(loaded.lastDispatchTopicId, 3);
    expect(loaded.scheduleStatus, ReminderScheduleStatus.scheduled);
    await store.close();
  });
}
```

Run: `flutter test test/data/local/reminder_runtime_state_repository_test.dart`

Expected: FAIL because schema v2/runtime repository does not exist.

- [ ] **Step 2: Upgrade `AppDatabase` to schema v2**

In `lib/data/local/app_database.dart`:

```dart
  static const schemaVersion = 2;
```

Add `onUpgrade` to `OpenDatabaseOptions`:

```dart
        onUpgrade: _upgradeSchema,
```

After the existing v1 table creation, create the runtime table through one shared helper:

```dart
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
        schedule_error TEXT
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
  }
```

At the end of `_createSchema`, before returning, call:

```dart
    await _createRuntimeStateTable(db);
```

Do not wrap `_upgradeSchema` in another transaction; sqflite already runs version callbacks transactionally.

- [ ] **Step 3: Add executor-aware repository methods**

Refactor `ReminderSettingsRepository.loadSettings()` so its current body becomes `loadSettingsFrom` and the public method preserves the Plan 2 consistent-snapshot behavior:

```dart
  Future<ReminderSettings> loadSettings() async {
    final db = await _store.database;
    return db.transaction((txn) => loadSettingsFrom(txn));
  }

  Future<ReminderSettings> loadSettingsFrom(DatabaseExecutor executor) async {
    final rows = await executor.query(
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
      final selectedRows = await executor.query(
        'reminder_scope_topics',
        columns: <String>['topic_id'],
        orderBy: 'topic_id ASC',
      );
      final ids = selectedRows.map((row) => row['topic_id']! as int).toSet();
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
```

Add to `ReviewItemRepository`:

```dart
  Future<List<ReviewItem>> listReviewItemsFrom(DatabaseExecutor executor) async {
    final rows = await executor.query('review_items', orderBy: 'id ASC');
    return List<ReviewItem>.unmodifiable(rows.map(_itemFromRow));
  }

  Future<void> recordShownAtWith(
    DatabaseExecutor executor, {
    required int id,
    required DateTime shownAt,
  }) async {
    final updated = await executor.update(
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
  }
```

Change `listReviewItems()` to call `listReviewItemsFrom(db)`, and change `recordShownAt()` to call `recordShownAtWith(db, ...)` before reloading the item.

- [ ] **Step 4: Implement runtime-state repository**

Create `lib/data/local/reminder_runtime_state_repository.dart`:

```dart
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

enum ReminderScheduleStatus { notScheduled, scheduled, disabled, failed }

final class ReminderRuntimeState {
  const ReminderRuntimeState({
    required this.lastEvaluationAt,
    required this.lastEvaluationOutcome,
    required this.lastDispatchAt,
    required this.lastDispatchItemId,
    required this.lastDispatchTopicId,
    required this.lastScheduleAttemptAt,
    required this.scheduleStatus,
    required this.scheduleError,
  });

  final DateTime? lastEvaluationAt;
  final String? lastEvaluationOutcome;
  final DateTime? lastDispatchAt;
  final int? lastDispatchItemId;
  final int? lastDispatchTopicId;
  final DateTime? lastScheduleAttemptAt;
  final ReminderScheduleStatus scheduleStatus;
  final String? scheduleError;
}

final class ReminderRuntimeStateRepository {
  ReminderRuntimeStateRepository(this._store);

  final AppDatabase _store;

  Future<ReminderRuntimeState> loadState() async {
    final db = await _store.database;
    final rows = await db.query('reminder_runtime_state', where: 'id = 1', limit: 1);
    if (rows.length != 1) throw StateError('Reminder runtime singleton is missing');
    return _fromRow(rows.single);
  }

  Future<void> recordEvaluation(
    DatabaseExecutor executor, {
    required DateTime at,
    required String outcome,
    int? dispatchItemId,
    int? dispatchTopicId,
    DateTime? dispatchAt,
  }) async {
    final updated = await executor.update(
      'reminder_runtime_state',
      <String, Object?>{
        'last_evaluation_at_us': at.toUtc().microsecondsSinceEpoch,
        'last_evaluation_outcome': outcome,
        if (dispatchAt != null) 'last_dispatch_at_us': dispatchAt.toUtc().microsecondsSinceEpoch,
        if (dispatchItemId != null) 'last_dispatch_item_id': dispatchItemId,
        if (dispatchTopicId != null) 'last_dispatch_topic_id': dispatchTopicId,
      },
      where: 'id = 1',
    );
    if (updated != 1) throw StateError('Reminder runtime singleton is missing');
  }

  Future<void> recordSchedule(
    DatabaseExecutor executor, {
    required DateTime at,
    required ReminderScheduleStatus status,
    required String? error,
  }) async {
    final updated = await executor.update(
      'reminder_runtime_state',
      <String, Object?>{
        'last_schedule_attempt_at_us': at.toUtc().microsecondsSinceEpoch,
        'schedule_status': _statusValue(status),
        'schedule_error': error,
      },
      where: 'id = 1',
    );
    if (updated != 1) throw StateError('Reminder runtime singleton is missing');
  }

  ReminderRuntimeState _fromRow(Map<String, Object?> row) {
    DateTime? time(String key) {
      final value = row[key] as int?;
      return value == null ? null : DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
    }

    return ReminderRuntimeState(
      lastEvaluationAt: time('last_evaluation_at_us'),
      lastEvaluationOutcome: row['last_evaluation_outcome'] as String?,
      lastDispatchAt: time('last_dispatch_at_us'),
      lastDispatchItemId: row['last_dispatch_item_id'] as int?,
      lastDispatchTopicId: row['last_dispatch_topic_id'] as int?,
      lastScheduleAttemptAt: time('last_schedule_attempt_at_us'),
      scheduleStatus: switch (row['schedule_status']) {
        'not_scheduled' => ReminderScheduleStatus.notScheduled,
        'scheduled' => ReminderScheduleStatus.scheduled,
        'disabled' => ReminderScheduleStatus.disabled,
        'failed' => ReminderScheduleStatus.failed,
        final Object? value => throw StateError('Invalid schedule_status: $value'),
      },
      scheduleError: row['schedule_error'] as String?,
    );
  }

  String _statusValue(ReminderScheduleStatus status) => switch (status) {
        ReminderScheduleStatus.notScheduled => 'not_scheduled',
        ReminderScheduleStatus.scheduled => 'scheduled',
        ReminderScheduleStatus.disabled => 'disabled',
        ReminderScheduleStatus.failed => 'failed',
      };
}
```

- [ ] **Step 5: Verify migration and all Plan 2 tests remain green**

Run:

```bash
flutter test test/data/local/reminder_runtime_state_repository_test.dart
flutter test test/data/local
```

Expected: PASS; existing persistence tests remain green.

- [ ] **Step 6: Commit**

```bash
git add lib/data/local test/data/local
git commit -m "feat: add reminder runtime persistence state"
```

**Per-Task Coverage Review:** fresh v2 row, persisted runtime evidence, v1→v2 migration, executor-based repository behavior, and Plan 2 regression are all directly verified. `COVERAGE_COMPLETE`.

---

### Task 3: Add Background-Isolate-Safe Foreground Detection

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `packages/android_process_state/pubspec.yaml`
- Create: `packages/android_process_state/lib/android_process_state.dart`
- Create: `packages/android_process_state/android/build.gradle`
- Create: `packages/android_process_state/android/src/main/AndroidManifest.xml`
- Create: `packages/android_process_state/android/src/main/kotlin/com/wly112488/android_process_state/AndroidProcessStatePlugin.kt`
- Create: `lib/runtime/foreground_status.dart`
- Create: `test/runtime/foreground_status_test.dart`

**Interfaces:**
- Produces `abstract interface class ForegroundStatus { Future<bool> isForeground(); }`.
- Produces `AndroidForegroundStatus` backed by process importance.

**Acceptance:**
- No Usage Access, Accessibility, overlay, or foreground-service permission is introduced.
- A Flutter engine running in the app process can query whether that process currently has a foreground/visible Activity.
- The adapter is available to WorkManager’s background engine through normal Flutter plugin registration.

- [ ] **Step 1: Add local plugin dependency**

Add to root `pubspec.yaml` under `dependencies`:

```yaml
  android_process_state:
    path: packages/android_process_state
```

Create `packages/android_process_state/pubspec.yaml`:

```yaml
name: android_process_state
description: Android process foreground-state bridge for kaoyan_review.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.13.4

flutter:
  plugin:
    platforms:
      android:
        package: com.wly112488.android_process_state
        pluginClass: AndroidProcessStatePlugin

dependencies:
  flutter:
    sdk: flutter
```

- [ ] **Step 2: Implement Dart and Android plugin sides**

Create `packages/android_process_state/lib/android_process_state.dart`:

```dart
import 'package:flutter/services.dart';

final class AndroidProcessState {
  const AndroidProcessState();

  static const MethodChannel _channel = MethodChannel(
    'kaoyan_review/android_process_state',
  );

  Future<bool> isForeground() async {
    return await _channel.invokeMethod<bool>('isForeground') ?? false;
  }
}
```

Create `packages/android_process_state/android/build.gradle`:

```groovy
plugins {
    id 'com.android.library'
    id 'org.jetbrains.kotlin.android'
}

android {
    namespace 'com.wly112488.android_process_state'
    compileSdk 36

    defaultConfig {
        minSdk 21
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
```

Create `packages/android_process_state/android/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android" />
```

Create `packages/android_process_state/android/src/main/kotlin/com/wly112488/android_process_state/AndroidProcessStatePlugin.kt`:

```kotlin
package com.wly112488.android_process_state

import android.app.ActivityManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidProcessStatePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "kaoyan_review/android_process_state")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isForeground" -> {
                val info = ActivityManager.RunningAppProcessInfo()
                ActivityManager.getMyMemoryState(info)
                val foreground =
                    info.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                    info.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
                result.success(foreground)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
```

- [ ] **Step 3: Add app runtime adapter and test contract**

Create `lib/runtime/foreground_status.dart`:

```dart
import 'package:android_process_state/android_process_state.dart';

abstract interface class ForegroundStatus {
  Future<bool> isForeground();
}

final class AndroidForegroundStatus implements ForegroundStatus {
  AndroidForegroundStatus({AndroidProcessState? processState})
      : _processState = processState ?? const AndroidProcessState();

  final AndroidProcessState _processState;

  @override
  Future<bool> isForeground() => _processState.isForeground();
}
```

Create `test/runtime/foreground_status_test.dart` to install a mock handler on channel `kaoyan_review/android_process_state`, return `true` for `isForeground`, call `AndroidForegroundStatus().isForeground()`, assert true, then clear the handler.

- [ ] **Step 4: Resolve dependencies and verify**

Run:

```bash
flutter pub get
flutter test test/runtime/foreground_status_test.dart
flutter analyze
```

Expected: PASS / no issues.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock packages/android_process_state lib/runtime/foreground_status.dart test/runtime/foreground_status_test.dart
git commit -m "feat: detect Android foreground process state"
```

**Per-Task Coverage Review:** no elevated permission is declared; method-channel contract is directly tested; Android compile is verified later by the Plan-wide APK build and emulator integration test. `COVERAGE_COMPLETE`.

---

### Task 4: Add Android Notification Capability and Immediate Submission

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `android/app/build.gradle.kts`
- Create: `android/app/src/main/res/drawable/ic_stat_review.xml`
- Create: `lib/runtime/review_notification_gateway.dart`
- Create: `test/runtime/review_notification_gateway_test.dart`

**Interfaces:**
- Produces `ReviewNotificationGateway.initialize({void Function(int itemId)? onTap})`.
- Produces `Future<bool> canPost()`.
- Produces `Future<bool> requestPermission()` for Plan 4’s user-driven permission action.
- Produces `Future<void> submit(ReviewItem item)`.
- Produces payload helpers `encodeReviewItemPayload` / `decodeReviewItemPayload`.

**Acceptance:**
- Android 13+ permission is requested only when caller explicitly invokes `requestPermission()`; startup/worker evaluation never opens a permission prompt.
- Capability check returns false when Android reports notifications disabled.
- Immediate notification submission contains app title, ReviewItem text, stable payload, and a private lock-screen visibility setting.
- No notification scheduling API and no exact-alarm permission is used.

- [ ] **Step 1: Add plugin dependency and Android desugaring**

Add to `pubspec.yaml`:

```yaml
  flutter_local_notifications: ^22.3.1
```

In `android/app/build.gradle.kts`, set:

```kotlin
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
```

and add at file level:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Do not add exact-alarm permissions or scheduled-notification receivers.

Create `android/app/src/main/res/drawable/ic_stat_review.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M4,4h6c1.1,0 2,0.9 2,2v14c0,-1.1 -0.9,-2 -2,-2H4zM20,4h-6c-1.1,0 -2,0.9 -2,2v14c0,-1.1 0.9,-2 2,-2h6z" />
</vector>
```

- [ ] **Step 2: Write payload contract tests**

Create `test/runtime/review_notification_gateway_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/runtime/review_notification_gateway.dart';

void main() {
  test('review item payload round-trips positive id', () {
    expect(decodeReviewItemPayload(encodeReviewItemPayload(42)), 42);
  });

  test('non-review payload is rejected', () {
    expect(decodeReviewItemPayload('other:42'), isNull);
    expect(decodeReviewItemPayload('review_item:not-an-int'), isNull);
    expect(decodeReviewItemPayload(null), isNull);
  });
}
```

Run: `flutter test test/runtime/review_notification_gateway_test.dart`

Expected: FAIL because helpers do not exist.

- [ ] **Step 3: Implement gateway**

Create `lib/runtime/review_notification_gateway.dart`:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/review_item.dart';

const _channelId = 'study_reminders';
const _channelName = '学习提醒';
const _channelDescription = '考研碎片复习提醒';

String encodeReviewItemPayload(int id) => 'review_item:$id';

int? decodeReviewItemPayload(String? payload) {
  if (payload == null || !payload.startsWith('review_item:')) return null;
  final id = int.tryParse(payload.substring('review_item:'.length));
  return id != null && id > 0 ? id : null;
}

abstract interface class ReviewNotificationGateway {
  Future<void> initialize({void Function(int itemId)? onTap});
  Future<bool> canPost();
  Future<bool> requestPermission();
  Future<void> submit(ReviewItem item);
}

final class AndroidReviewNotificationGateway implements ReviewNotificationGateway {
  AndroidReviewNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize({void Function(int itemId)? onTap}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_review'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = decodeReviewItemPayload(response.payload);
        if (id != null) onTap?.call(id);
      },
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> canPost() async => await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<void> submit(ReviewItem item) async {
    final notificationId = item.id % 2147483647;
    await _plugin.show(
      id: notificationId,
      title: '考研碎片复习',
      body: item.content,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      ),
      payload: encodeReviewItemPayload(item.id),
    );
  }
}
```

- [ ] **Step 4: Verify plugin compile and payload tests**

Run:

```bash
flutter pub get
flutter test test/runtime/review_notification_gateway_test.dart
flutter analyze
```

Expected: PASS / no issues.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/build.gradle.kts android/app/src/main/res/drawable/ic_stat_review.xml lib/runtime/review_notification_gateway.dart test/runtime/review_notification_gateway_test.dart
git commit -m "feat: add Android review notification gateway"
```

**Per-Task Coverage Review:** payload positive/negative behavior is direct; dependency/Gradle integration is analyzer/build-verified; permission prompting remains caller-driven by interface and no startup request exists. `COVERAGE_COMPLETE`.

---

### Task 5: Serialize Current-State Evaluation, Notification Submission, and History Commit

**Files:**
- Modify: `lib/domain/reminder_evaluator.dart`
- Create: `lib/runtime/reminder_execution_service.dart`
- Create: `test/runtime/reminder_execution_service_test.dart`

**Interfaces:**
- Produces `ReminderEvaluator.blockingOutcome(...)` so Plan 1 ordering remains one source of truth.
- Produces `ReminderExecutionService.runOnce()`.
- Consumes transaction-aware Plan 2 repositories, `ForegroundStatus`, `ReviewNotificationGateway`, and `ReminderRuntimeStateRepository`.

**Acceptance:**
- Decision ordering is disabled → active window → foreground → notification capability → eligibility.
- Store reads happen against current state inside one exclusive transaction.
- Foreground and notification capability are rechecked immediately before submission.
- A failed notification submission rolls back staged `last_shown_at`.
- Successful submission commits one dispatch timestamp and runtime evidence.
- Two concurrent `runOnce()` calls cannot independently submit the same unchanged candidate.

- [ ] **Step 1: Extract the existing short-circuit gate**

Add to `ReminderEvaluator`:

```dart
  ReminderEvaluationOutcome? blockingOutcome({
    required ReminderSettings settings,
    required bool withinActiveWindow,
    required bool isForeground,
    required bool notificationAvailable,
  }) {
    if (!settings.enabled) return ReminderEvaluationOutcome.reminderDisabled;
    if (!withinActiveWindow) return ReminderEvaluationOutcome.outsideActiveWindow;
    if (isForeground) return ReminderEvaluationOutcome.foregroundSuppressed;
    if (!notificationAvailable) return ReminderEvaluationOutcome.notificationUnavailable;
    return null;
  }
```

Refactor `evaluate()` to call `blockingOutcome` first and return `withoutCandidate(blocked)` when non-null, then retain the existing selector logic unchanged.

Run: `flutter test test/domain/reminder_evaluator_test.dart`

Expected: PASS; Plan 1 ordering remains unchanged.

- [ ] **Step 2: Write service tests with fakes and a real FFI database**

Create tests covering these exact cases:

1. disabled settings → gateway capability is never queried;
2. outside window → foreground/capability are not queried;
3. foreground → capability is not queried and history unchanged;
4. notification unavailable → history unchanged;
5. no eligible item → no submit/history update;
6. `submit()` throws → transaction rollback leaves `last_shown_at == null`;
7. successful submit → `last_shown_at` becomes dispatch instant and runtime state records item/topic IDs;
8. two concurrent `runOnce()` calls with the first fake `submit()` held on a `Completer` produce exactly one submit; after first commit, the second returns `noEligibleItem` under a 24-hour cooldown.

Use temp SQLite through `sqflite_common_ffi`; create one Topic and one enabled ReviewItem through Plan 2 repositories. Fakes implement `ForegroundStatus` and `ReviewNotificationGateway` and count method calls.

Run: `flutter test test/runtime/reminder_execution_service_test.dart`

Expected: FAIL because service does not exist.

- [ ] **Step 3: Implement execution service**

Create `lib/runtime/reminder_execution_service.dart` with:

```dart
import 'package:sqflite/sqflite.dart';

import '../data/local/app_database.dart';
import '../data/local/reminder_runtime_state_repository.dart';
import '../data/local/reminder_settings_repository.dart';
import '../data/local/review_item_repository.dart';
import '../domain/reminder_candidate_selector.dart';
import '../domain/reminder_evaluator.dart';
import 'foreground_status.dart';
import 'review_notification_gateway.dart';

enum ReminderRunOutcome {
  reminderDisabled,
  outsideActiveWindow,
  foregroundSuppressed,
  notificationUnavailable,
  noEligibleItem,
  notificationSubmitted,
  notificationSubmissionFailed,
  storeFailure,
}

abstract interface class ReminderClock {
  DateTime nowUtc();
  DateTime nowLocal();
}

final class SystemReminderClock implements ReminderClock {
  const SystemReminderClock();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
  @override
  DateTime nowLocal() => DateTime.now();
}

final class ReminderExecutionService {
  ReminderExecutionService({
    required AppDatabase store,
    required ForegroundStatus foregroundStatus,
    required ReviewNotificationGateway notifications,
    ReminderClock clock = const SystemReminderClock(),
    ReminderEvaluator? evaluator,
    ReminderCandidateSelector? selector,
  })  : _store = store,
        _foregroundStatus = foregroundStatus,
        _notifications = notifications,
        _clock = clock,
        _evaluator = evaluator ?? ReminderEvaluator(),
        _selector = selector ?? ReminderCandidateSelector(),
        _settings = ReminderSettingsRepository(store),
        _items = ReviewItemRepository(store),
        _runtime = ReminderRuntimeStateRepository(store);

  final AppDatabase _store;
  final ForegroundStatus _foregroundStatus;
  final ReviewNotificationGateway _notifications;
  final ReminderClock _clock;
  final ReminderEvaluator _evaluator;
  final ReminderCandidateSelector _selector;
  final ReminderSettingsRepository _settings;
  final ReviewItemRepository _items;
  final ReminderRuntimeStateRepository _runtime;

  Future<ReminderRunOutcome> runOnce() async {
    final db = await _store.database;
    try {
      return await db.transaction<ReminderRunOutcome>((txn) async {
        final settings = await _settings.loadSettingsFrom(txn);
        final nowUtc = _clock.nowUtc();
        final nowLocal = _clock.nowLocal();
        final within = settings.activeWindow.containsLocal(nowLocal);

        if (!settings.enabled) {
          return _finish(txn, nowUtc, ReminderRunOutcome.reminderDisabled);
        }
        if (!within) {
          return _finish(txn, nowUtc, ReminderRunOutcome.outsideActiveWindow);
        }

        final foreground = await _foregroundStatus.isForeground();
        if (foreground) {
          return _finish(txn, nowUtc, ReminderRunOutcome.foregroundSuppressed);
        }

        final notificationAvailable = await _notifications.canPost();
        final blocked = _evaluator.blockingOutcome(
          settings: settings,
          withinActiveWindow: true,
          isForeground: false,
          notificationAvailable: notificationAvailable,
        );
        if (blocked == ReminderEvaluationOutcome.notificationUnavailable) {
          return _finish(txn, nowUtc, ReminderRunOutcome.notificationUnavailable);
        }

        final items = await _items.listReviewItemsFrom(txn);
        final candidate = _selector.selectNext(
          items: items,
          scope: settings.scope,
          repeatCooldown: settings.repeatCooldown,
          now: nowUtc,
        );
        if (candidate == null) {
          return _finish(txn, nowUtc, ReminderRunOutcome.noEligibleItem);
        }

        if (await _foregroundStatus.isForeground()) {
          return _finish(txn, nowUtc, ReminderRunOutcome.foregroundSuppressed);
        }
        if (!await _notifications.canPost()) {
          return _finish(txn, nowUtc, ReminderRunOutcome.notificationUnavailable);
        }

        final dispatchAt = _clock.nowUtc();
        await _items.recordShownAtWith(
          txn,
          id: candidate.id,
          shownAt: dispatchAt,
        );
        await _runtime.recordEvaluation(
          txn,
          at: dispatchAt,
          outcome: 'notification_submitted',
          dispatchItemId: candidate.id,
          dispatchTopicId: candidate.topicId,
          dispatchAt: dispatchAt,
        );

        try {
          await _notifications.submit(candidate);
        } catch (error) {
          throw _NotificationSubmissionFailure(error);
        }

        return ReminderRunOutcome.notificationSubmitted;
      }, exclusive: true);
    } on _NotificationSubmissionFailure {
      final at = _clock.nowUtc();
      await _runtime.recordEvaluation(
        db,
        at: at,
        outcome: 'notification_submission_failed',
      );
      return ReminderRunOutcome.notificationSubmissionFailed;
    } catch (_) {
      try {
        await _runtime.recordEvaluation(
          db,
          at: _clock.nowUtc(),
          outcome: 'store_failure',
        );
      } catch (_) {
        // The store itself is unavailable; there is nowhere durable to record it.
      }
      return ReminderRunOutcome.storeFailure;
    }
  }

  Future<ReminderRunOutcome> _finish(
    DatabaseExecutor executor,
    DateTime at,
    ReminderRunOutcome outcome,
  ) async {
    await _runtime.recordEvaluation(
      executor,
      at: at,
      outcome: outcome.name,
    );
    return outcome;
  }
}

final class _NotificationSubmissionFailure implements Exception {
  const _NotificationSubmissionFailure(this.cause);
  final Object cause;
}
```

The `last_shown_at` update is intentionally staged before `submit()` but remains uncommitted; if `submit()` throws, the exclusive SQLite transaction rolls it back. The transaction commits only after `submit()` returns successfully.

- [ ] **Step 4: Run service and full domain tests**

Run:

```bash
flutter test test/runtime/reminder_execution_service_test.dart
flutter test test/domain
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/domain/reminder_evaluator.dart lib/runtime/reminder_execution_service.dart test/runtime/reminder_execution_service_test.dart
git commit -m "feat: serialize reminder evaluation and dispatch"
```

**Per-Task Coverage Review:** every gate, failed-submit rollback, successful history commit, current-state selection, and duplicate concurrent execution has direct evidence. `COVERAGE_COMPLETE`.

---

### Task 6: Reconcile One Unique WorkManager Cadence and Background Worker

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/runtime/reminder_scheduler.dart`
- Create: `lib/runtime/reminder_settings_service.dart`
- Create: `lib/runtime/reminder_worker.dart`
- Create: `test/runtime/reminder_scheduler_test.dart`

**Interfaces:**
- Produces `ReminderScheduler.reconcile(ReminderSettings settings)`.
- Produces `ReminderSettingsService.save(ReminderSettings settings)`.
- Produces top-level `reminderCallbackDispatcher()`.

**Acceptance:**
- Disabled settings cancel the one unique periodic reminder work.
- Enabled settings register/update exactly one unique work with `frequency == reminderInterval`, `initialDelay == reminderInterval`, and `ExistingPeriodicWorkPolicy.update`.
- Saving settings persists product truth before scheduling; scheduler failure does not roll back user intent.
- Scheduler status is persisted as scheduled/disabled/failed.
- Background worker opens current local state on each execution and does not accept preselected content through WorkManager input.
- Handled worker failures return success to WorkManager so reminder semantics do not create immediate retry/catch-up bursts.

- [ ] **Step 1: Add WorkManager dependency**

Add to root `pubspec.yaml`:

```yaml
  workmanager: ^0.10.10
```

Run: `flutter pub get`

Expected: exit 0.

- [ ] **Step 2: Implement scheduler behind a testable port**

Create `lib/runtime/reminder_scheduler.dart`:

```dart
import 'package:workmanager/workmanager.dart';

import '../data/local/app_database.dart';
import '../data/local/reminder_runtime_state_repository.dart';
import '../domain/reminder_settings.dart';

const reminderUniqueWorkName = 'kaoyan_review.periodic_reminder';
const reminderWorkerTaskName = 'periodic_reminder_evaluation';

abstract interface class PeriodicWorkPort {
  Future<void> register({
    required Duration frequency,
    required Duration initialDelay,
  });
  Future<void> cancel();
}

final class WorkmanagerPeriodicWorkPort implements PeriodicWorkPort {
  @override
  Future<void> register({
    required Duration frequency,
    required Duration initialDelay,
  }) {
    return Workmanager().registerPeriodicTask(
      reminderUniqueWorkName,
      reminderWorkerTaskName,
      frequency: frequency,
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  @override
  Future<void> cancel() => Workmanager().cancelByUniqueName(reminderUniqueWorkName);
}

final class ReminderScheduler {
  ReminderScheduler({
    required AppDatabase store,
    PeriodicWorkPort? work,
  })  : _store = store,
        _work = work ?? WorkmanagerPeriodicWorkPort(),
        _runtime = ReminderRuntimeStateRepository(store);

  final AppDatabase _store;
  final PeriodicWorkPort _work;
  final ReminderRuntimeStateRepository _runtime;

  Future<bool> reconcile(ReminderSettings settings) async {
    final now = DateTime.now().toUtc();
    final db = await _store.database;
    try {
      if (!settings.enabled) {
        await _work.cancel();
        await _runtime.recordSchedule(
          db,
          at: now,
          status: ReminderScheduleStatus.disabled,
          error: null,
        );
        return true;
      }

      await _work.register(
        frequency: settings.reminderInterval,
        initialDelay: settings.reminderInterval,
      );
      await _runtime.recordSchedule(
        db,
        at: now,
        status: ReminderScheduleStatus.scheduled,
        error: null,
      );
      return true;
    } catch (error) {
      await _runtime.recordSchedule(
        db,
        at: now,
        status: ReminderScheduleStatus.failed,
        error: error.toString(),
      );
      return false;
    }
  }
}
```

- [ ] **Step 3: Implement settings persistence + schedule reconciliation**

Create `lib/runtime/reminder_settings_service.dart`:

```dart
import '../data/local/reminder_settings_repository.dart';
import '../domain/reminder_settings.dart';
import 'reminder_scheduler.dart';

final class ReminderSettingsService {
  ReminderSettingsService({
    required ReminderSettingsRepository repository,
    required ReminderScheduler scheduler,
  })  : _repository = repository,
        _scheduler = scheduler;

  final ReminderSettingsRepository _repository;
  final ReminderScheduler _scheduler;

  Future<bool> save(ReminderSettings settings) async {
    await _repository.saveSettings(settings);
    return _scheduler.reconcile(settings);
  }
}
```

- [ ] **Step 4: Implement no-retry background worker**

Create `lib/runtime/reminder_worker.dart`:

```dart
import 'dart:ui';

import 'package:workmanager/workmanager.dart';

import '../data/local/app_database.dart';
import 'foreground_status.dart';
import 'reminder_execution_service.dart';
import 'reminder_scheduler.dart';
import 'review_notification_gateway.dart';

@pragma('vm:entry-point')
void reminderCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != reminderWorkerTaskName) {
      return true;
    }

    DartPluginRegistrant.ensureInitialized();
    AppDatabase? store;
    try {
      store = await AppDatabase.openProduction();
      final notifications = AndroidReviewNotificationGateway();
      await notifications.initialize();
      final service = ReminderExecutionService(
        store: store,
        foregroundStatus: AndroidForegroundStatus(),
        notifications: notifications,
      );
      await service.runOnce();
    } catch (_) {
      // A periodic reminder run is one opportunity only. Returning true prevents
      // WorkManager retry/backoff from creating a catch-up burst.
    } finally {
      await store?.close();
    }
    return true;
  });
}
```

No ReviewItem ID, Topic ID, scope, cooldown, or active-window value is put in WorkManager input data.

- [ ] **Step 5: Write scheduler/settings tests**

Create `test/runtime/reminder_scheduler_test.dart` with a fake `PeriodicWorkPort` that records registrations/cancellations and can throw. Directly verify:

```dart
expect(fake.registeredFrequency, const Duration(hours: 1));
expect(fake.registeredInitialDelay, const Duration(hours: 1));
expect(fake.cancelCount, 0);
```

for enabled settings; verify one cancellation and no registration for disabled settings; verify a thrown registration records `ReminderScheduleStatus.failed`; verify `ReminderSettingsService.save()` leaves the new settings persisted even when `reconcile()` returns false.

Run: `flutter test test/runtime/reminder_scheduler_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/runtime/reminder_scheduler.dart lib/runtime/reminder_settings_service.dart lib/runtime/reminder_worker.dart test/runtime/reminder_scheduler_test.dart
git commit -m "feat: schedule periodic reminder evaluation"
```

**Per-Task Coverage Review:** enabled/disabled/failed schedule states, exact unique cadence parameters, persist-before-schedule ordering, and no-retry worker contract are directly verified. `COVERAGE_COMPLETE`.

---

### Task 7: Wire Startup Reconciliation, Notification Tap Handoff, and Emulator Proof

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `lib/main.dart`
- Create: `lib/runtime/notification_tap_bus.dart`
- Create: `lib/runtime/reminder_runtime_bootstrap.dart`
- Create: `integration_test/android_reminder_runtime_test.dart`

**Interfaces:**
- Produces `NotificationTapBus.instance`, which preserves the latest tapped ReviewItem ID for Plan 4 and exposes a broadcast stream.
- Produces `ReminderRuntimeBootstrap.initialize()`.

**Acceptance:**
- Foreground startup initializes WorkManager exactly once, initializes notifications, and reconciles the unique schedule from current persisted settings.
- Tapped notification payloads are converted into ReviewItem IDs without implementing the final detail screen yet.
- Android emulator proves process-foreground detection and immediate notification submission after permission is granted.
- Debug APK builds without exact-alarm/Usage Access/Accessibility permissions.
- Full unit/integration test and analyzer suite are green.

- [ ] **Step 1: Add integration-test SDK dependency**

Add under `dev_dependencies`:

```yaml
  integration_test:
    sdk: flutter
```

Run: `flutter pub get`.

- [ ] **Step 2: Implement tap bus**

Create `lib/runtime/notification_tap_bus.dart`:

```dart
import 'dart:async';

final class NotificationTapBus {
  NotificationTapBus._();

  static final NotificationTapBus instance = NotificationTapBus._();

  final StreamController<int> _controller = StreamController<int>.broadcast();
  int? _pendingItemId;

  Stream<int> get stream => _controller.stream;

  int? takePendingItemId() {
    final value = _pendingItemId;
    _pendingItemId = null;
    return value;
  }

  void record(int itemId) {
    _pendingItemId = itemId;
    _controller.add(itemId);
  }
}
```

Plan 4 must consume this bus to satisfy the final “open full ReviewItem” UI acceptance; Plan 3 only owns payload→ID handoff.

- [ ] **Step 3: Implement runtime bootstrap**

Create `lib/runtime/reminder_runtime_bootstrap.dart`:

```dart
import 'package:workmanager/workmanager.dart';

import '../data/local/app_database.dart';
import '../data/local/reminder_settings_repository.dart';
import 'notification_tap_bus.dart';
import 'reminder_scheduler.dart';
import 'reminder_worker.dart';
import 'review_notification_gateway.dart';

final class ReminderRuntimeBootstrap {
  static Future<void> initialize() async {
    await Workmanager().initialize(reminderCallbackDispatcher);

    final notifications = AndroidReviewNotificationGateway();
    await notifications.initialize(
      onTap: NotificationTapBus.instance.record,
    );

    final store = await AppDatabase.openProduction();
    try {
      final settings = await ReminderSettingsRepository(store).loadSettings();
      await ReminderScheduler(store: store).reconcile(settings);
    } finally {
      await store.close();
    }
  }
}
```

- [ ] **Step 4: Wire async startup**

Replace `main()` in `lib/main.dart` with:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderRuntimeBootstrap.initialize();
  runApp(const KaoyanReviewApp());
}
```

and add:

```dart
import 'runtime/reminder_runtime_bootstrap.dart';
```

Keep the existing app shell otherwise unchanged.

- [ ] **Step 5: Add Android emulator integration smoke test**

Create `integration_test/android_reminder_runtime_test.dart`:

```dart
import 'package:android_process_state/android_process_state.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/review_item.dart';
import 'package:kaoyan_review/runtime/review_notification_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android runtime foreground and notification adapters work', (tester) async {
    expect(await const AndroidProcessState().isForeground(), isTrue);

    final gateway = AndroidReviewNotificationGateway();
    await gateway.initialize();
    expect(await gateway.canPost(), isTrue);

    final item = ReviewItem(
      id: 9001,
      content: 'Android reminder integration smoke',
      topicId: 1,
      enabled: true,
      createdAt: DateTime.utc(2026, 9, 28),
      updatedAt: DateTime.utc(2026, 9, 28),
    );
    await gateway.submit(item);

    final active = await FlutterLocalNotificationsPlugin().getActiveNotifications();
    expect(active.any((notification) => notification.id == 9001), isTrue);
  });
}
```

- [ ] **Step 6: Run complete automated verification**

Run:

```bash
flutter test
flutter analyze
flutter build apk --debug
```

Expected:
- all unit tests PASS;
- analyzer reports no issues;
- debug APK build exits 0.

- [ ] **Step 7: Run Android emulator verification**

With a booted Android 13+ emulator and the debug app installed, grant notification permission explicitly for test setup:

```powershell
adb shell pm grant com.wly112488.kaoyan_review android.permission.POST_NOTIFICATIONS
flutter test integration_test/android_reminder_runtime_test.dart -d emulator-5554
```

Expected: integration test PASS.

Then launch the app once so startup reconciliation registers WorkManager and inspect Android JobScheduler:

```powershell
adb shell dumpsys jobscheduler com.wly112488.kaoyan_review
```

Expected: output contains an AndroidX WorkManager `SystemJobService` job for `com.wly112488.kaoyan_review`. Timing remains best-effort; this check proves registration, not exact execution time.

- [ ] **Step 8: Verify prohibited permissions are absent**

Run from the project root after building:

```powershell
Select-String -Path android/app/src/main/AndroidManifest.xml -Pattern "SCHEDULE_EXACT_ALARM|USE_EXACT_ALARM|PACKAGE_USAGE_STATS|BIND_ACCESSIBILITY_SERVICE|SYSTEM_ALERT_WINDOW"
```

Expected: no matches.

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart lib/runtime/notification_tap_bus.dart lib/runtime/reminder_runtime_bootstrap.dart integration_test/android_reminder_runtime_test.dart
git commit -m "feat: bootstrap Android reminder runtime"
```

**Per-Task Coverage Review:** startup reconciliation, tap-ID handoff, foreground process adapter, immediate notification submission, Android build, WorkManager registration, and prohibited-permission absence all have explicit verification. Full ReviewItem navigation remains explicitly assigned to Plan 4. `COVERAGE_COMPLETE`.

---

## Plan 3 Final Verification

After all Tasks are individually green, run exactly:

```bash
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
```

On the Android 13+ emulator, additionally run:

```powershell
adb shell pm grant com.wly112488.kaoyan_review android.permission.POST_NOTIFICATIONS
flutter test integration_test/android_reminder_runtime_test.dart -d emulator-5554
adb shell dumpsys jobscheduler com.wly112488.kaoyan_review
```

Record emulator evidence only as `VERIFIED_EMULATOR`. Do not change any OPPO Reno8 matrix entry from `NOT_VERIFIED_ON_DEVICE` in this Plan.

## Self-Review

### 1. Spec coverage

- Active-window exact boundaries → Task 1.
- Current-state persistence/runtime evidence → Task 2.
- Foreground suppression source → Tasks 3 and 5.
- Notification capability and successful submission semantics → Tasks 4 and 5.
- Deterministic current-state eligibility/cooldown → existing Plan 1 selector consumed by Task 5.
- Duplicate/concurrent evaluation exclusion → Task 5 exclusive-transaction concurrency test.
- Settings cadence replacement / disabled cancellation / scheduler failure degradation → Task 6.
- Background process death/startup and current-state reopen → Task 6 worker + Task 7 startup reconciliation.
- Reboot persistence is delegated to Android WorkManager and remains device-sensitive; registration is emulator-verified here, OPPO reboot proof remains Plan 5.
- Time/timezone changes require no fixed timezone schedule because each worker evaluates `DateTime.now()` local wall-clock at execution time → Tasks 1 and 5.
- Force Stop remains unsupported and no code claims otherwise.
- Notification tap payload→ReviewItem ID → Task 7; final UI navigation to full ReviewItem → named downstream Plan 4.
- Diagnostics data persistence → Task 2; Diagnostics presentation/copy/device metadata → downstream Plan 4.
- APK remote distribution → downstream Plan 4.
- OPPO behavior → downstream Plan 5.

### 2. Placeholder scan

No `TBD`, `TODO`, “similar to”, unspecified error handling, or unnamed implementation step is part of this Plan.

### 3. Type/interface consistency

- `DatabaseExecutor` is shared by `Database` and `Transaction` and is used by the transaction-aware repository methods.
- `ReminderExecutionService` consumes the exact Plan 2 `AppDatabase`, `ReminderSettingsRepository`, and `ReviewItemRepository` objects.
- `ReminderScheduler` owns only WorkManager cadence state; `ReminderSettingsService` persists product truth first.
- `ReviewNotificationGateway` is the only notification side-effect port used by the execution service.
- `ForegroundStatus` is the only runtime foreground check used by the execution service.
- Plan 4 can consume `NotificationTapBus` and `ReminderRuntimeStateRepository` without redefining runtime semantics.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-28-android-mvp-reminder-runtime.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

When Plan 3 is complete, write the detailed Plan 4 from the authoritative Spec and the actual runtime interfaces/tests produced here; do not pre-freeze Plan 4 implementation mechanics now.
