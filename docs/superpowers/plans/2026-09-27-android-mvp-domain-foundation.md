# Android MVP Domain Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap the Android-only Flutter project and implement the pure domain contracts that define ReviewItem, Topic, ReminderScope, ReminderSettings, deterministic eligibility, and reminder-evaluation ordering without yet adding persistence, Android background scheduling, notifications, or product UI.

**Architecture:** Keep Plan 1 deliberately side-effect free. Domain objects and reminder evaluation live under `lib/domain/` and are testable with normal `flutter test`; Android/runtime concerns consume these interfaces in downstream plans. This plan does not choose persistence packages, notification plugins, WorkManager bindings, or OEM-specific runtime mechanics.

**Tech Stack:** Flutter (Android platform only for this project stage), Dart, `flutter_test`; no third-party runtime dependency is required by this plan.

**Spec:** `docs/superpowers/specs/ANDROID_MVP_SPEC.md`

## Global Constraints

- Android first; target device for real-device acceptance is OPPO Reno8.
- Client framework constraint: Flutter.
- The MVP is local-only; no login, account, server, cloud sync, or multi-device sync.
- Production OCR is out of scope.
- AI API integration, AI summarization, AI classification, AI question generation, chapter recognition, and semantic knowledge-point typing are out of scope.
- Every ReviewItem belongs to exactly one Topic.
- ReminderScope is `ALL_TOPICS` or `SELECTED_TOPICS` with a non-empty Topic set.
- Multi-Topic scope uses union semantics.
- Topic switching must not reset ReviewItem reminder history.
- `next_eligible_at` is derived from `last_shown_at + current repeat_cooldown`; it is not an independent source of truth.
- Production reminder interval is 15 minutes or greater.
- Exact-alarm capability is not an MVP prerequisite.
- Cooldown must not be bypassed merely to produce a notification.
- Selection is deterministic: never-shown first, then oldest `created_at`; otherwise oldest `last_shown_at`; ties by stable ReviewItem identity.
- Emulator evidence cannot be promoted to OPPO Reno8 real-device verification.

---

## Scope Check and Implementation Roadmap

The authoritative Spec contains multiple independently deliverable responsibilities, so it must not be implemented as one undifferentiated plan.

### Plan 1 — Domain Foundation (this document)

- **Goal:** Create the Flutter project and pure domain/evaluation contracts.
- **Independent deliverable:** `flutter test` proves all core Topic, ReviewItem, ReminderScope, settings-validation, eligibility, deterministic selection, and evaluation-order behavior without Android services or a database.
- **Spec semantics covered:** core parts of §§4, 5, 7, and the decision ordering in §6.3; supporting invariants from §19.
- **Dependencies:** authoritative Spec only.
- **Implementation prerequisites:** satisfied.

### Plan 2 — Local Persistence and CRUD

- **Goal:** Persist Topic, ReviewItem, ReminderSettings, ReminderScope, `last_shown_at`, and diagnostic state in one local source of truth; implement Topic/ReviewItem/settings CRUD and transactional invariants.
- **Independent deliverable:** persistence survives app/process restart in automated database tests, and CRUD cannot create orphaned ReviewItems or invalid scope state.
- **Spec semantics covered:** §§4, 5, 12, Topic deletion behavior, and persistence-related Acceptance Criteria.
- **Dependency:** completed Plan 1 interfaces.
- **Prerequisites before detailed planning:** re-read the implemented Plan 1 interfaces and correct the Spec wording conflict between §4.2 (“deletion is blocked until the user changes the reminder scope or disables reminders”) and §4.3/§19 (a `SELECTED_TOPICS` scope must never be empty). The implementation plan must not invent an empty selected-scope state. Also clarify how absence of any first-run saved ReminderSettings is represented before the user configures reminders.

### Plan 3 — Android Reminder Runtime and Notification Dispatch

- **Goal:** Connect current persisted state to best-effort Android background evaluation, foreground suppression, notification permission/capability checks, notification submission, atomic successful-dispatch history commit, reboot/update recovery, and diagnostic runtime outcomes.
- **Independent deliverable:** emulator/integration evidence proves the runtime pipeline without claiming OPPO-specific verification.
- **Spec semantics covered:** §§6.3–6.5, 8–11, notification portions of §16.
- **Dependencies:** completed Plans 1–2.
- **Prerequisites before detailed planning:** re-read actual persistence interfaces from Plan 2; clarify the exact active-window boundary convention (for example, whether end time is exclusive) in the Spec before encoding it; use current Android/Flutter plugin evidence when selecting runtime packages.

### Plan 4 — MVP UI, Diagnostics, and APK

- **Goal:** Implement the minimal user-facing flows for Topic/ReviewItem CRUD, reminder settings/scope, notification navigation, Diagnostics copy/reporting, and remote-install APK packaging.
- **Independent deliverable:** a non-developer can configure the app and install an APK without Android Studio/adb.
- **Spec semantics covered:** §§3, 6.1, 13–16, UI-visible degraded states.
- **Dependencies:** completed Plans 1–3.
- **Prerequisites before detailed planning:** re-read actual domain/persistence/runtime APIs; if first-run UI needs prefilled interval/cooldown values, those product defaults must be added to the Spec instead of being invented in the UI plan.

### Plan 5 — OPPO Reno8 Real-Device Verification and Closure

- **Goal:** Execute the Spec §17 matrix on the remote OPPO Reno8, collect Diagnostics evidence, fix implementation defects without weakening Spec semantics, and classify each scenario accurately.
- **Independent deliverable:** documented `VERIFIED_ON_OPPO_RENO8`, `NOT_VERIFIED_ON_DEVICE`, or `UNSUPPORTED_WHILE_FORCE_STOPPED` evidence per scenario.
- **Dependencies:** installable output from Plan 4.
- **Prerequisites before detailed planning:** actual target-device Android/ColorOS version and an installable test APK.

OCR remains outside this MVP roadmap because the authoritative Spec explicitly defers production OCR.

---

## Current Repository Evidence

The repository currently contains only the authoritative Spec under `docs/superpowers/specs/`; there is no Flutter source tree, `pubspec.yaml`, Android project, or test harness. Plan 1 therefore creates the initial Flutter project rather than adapting an existing application structure.

## File Structure for Plan 1

Plan 1 creates or replaces these files:

- `pubspec.yaml` — Flutter package manifest generated by Flutter; no third-party runtime packages are required in Plan 1.
- `analysis_options.yaml` — Flutter analyzer configuration generated by Flutter.
- `android/` — Android-only Flutter platform scaffold generated by Flutter; no custom Android runtime code in this plan.
- `lib/main.dart` — minimal compile/smoke-test shell only; product UI belongs to Plan 4.
- `lib/domain/topic.dart` — Topic identity/name normalization contract.
- `lib/domain/review_item.dart` — ReviewItem immutable domain state and validation.
- `lib/domain/reminder_scope.dart` — `ALL_TOPICS` / non-empty `SELECTED_TOPICS` model and union membership semantics.
- `lib/domain/active_window.dart` — representation/validation of `ALL_DAY` vs bounded daily windows; no wall-clock boundary evaluation yet.
- `lib/domain/reminder_settings.dart` — reminder enabled/interval/cooldown/window/scope contract and production interval validation.
- `lib/domain/reminder_candidate_selector.dart` — enabled/scope/cooldown filtering and deterministic ordering.
- `lib/domain/reminder_evaluator.dart` — pure decision-order coordinator with no notification/database side effects.
- `test/app_smoke_test.dart` — verifies bootstrap shell builds.
- `test/domain/topic_test.dart` — Topic normalization/validation.
- `test/domain/review_item_test.dart` — ReviewItem validation and history preservation through explicit reconstruction.
- `test/domain/reminder_scope_test.dart` — all/single/multi-topic scope invariants.
- `test/domain/reminder_settings_test.dart` — interval/cooldown/window model validation.
- `test/domain/reminder_candidate_selector_test.dart` — eligibility boundary and deterministic-order coverage.
- `test/domain/reminder_evaluator_test.dart` — evaluation short-circuit order and candidate result coverage.

---

### Task 1: Bootstrap the Android-only Flutter project

**Files:**
- Create via Flutter scaffold: `pubspec.yaml`
- Create via Flutter scaffold: `analysis_options.yaml`
- Create via Flutter scaffold: `android/**`
- Replace: `lib/main.dart`
- Delete generated default test: `test/widget_test.dart`
- Create: `test/app_smoke_test.dart`

**Interfaces:**
- **Consumes:** none.
- **Produces:** Flutter package name `kaoyan_review`; root widget `KaoyanReviewApp` with `const KaoyanReviewApp({super.key})`.

**Acceptance:**
- The repository is a valid Flutter project with Android as its only generated platform.
- `flutter analyze` exits successfully.
- `flutter test test/app_smoke_test.dart` proves the root app builds and displays the MVP shell title.
- No persistence, notification, OCR, AI, iOS, or iPadOS dependency is introduced.

- [ ] **Step 1: Generate the Flutter Android scaffold**

Run from repository root:

```bash
flutter create --platforms=android --org com.wly112488 --project-name kaoyan_review .
```

Expected: Flutter creates `pubspec.yaml`, `analysis_options.yaml`, `android/`, `lib/`, and `test/` while preserving `docs/`.

- [ ] **Step 2: Write the failing bootstrap smoke test**

Replace the generated `test/widget_test.dart` with `test/app_smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/main.dart';

void main() {
  testWidgets('builds the Android MVP shell', (tester) async {
    await tester.pumpWidget(const KaoyanReviewApp());

    expect(find.text('考研碎片复习'), findsOneWidget);
  });
}
```

Delete `test/widget_test.dart` if it still exists.

- [ ] **Step 3: Run the smoke test to verify RED**

Run:

```bash
flutter test test/app_smoke_test.dart
```

Expected: FAIL because `KaoyanReviewApp` is not defined by the generated counter-app `lib/main.dart`.

- [ ] **Step 4: Replace the generated counter app with the minimal shell**

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const KaoyanReviewApp());
}

class KaoyanReviewApp extends StatelessWidget {
  const KaoyanReviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '考研碎片复习',
      home: Scaffold(
        appBar: AppBar(title: const Text('考研碎片复习')),
        body: const SizedBox.shrink(),
      ),
    );
  }
}
```

- [ ] **Step 5: Verify GREEN and analyzer cleanliness**

Run:

```bash
flutter test test/app_smoke_test.dart
flutter analyze
```

Expected: both commands exit 0; smoke test reports PASS and analyzer reports no issues.

- [ ] **Step 6: Commit the bootstrap**

```bash
git add pubspec.yaml analysis_options.yaml android lib/main.dart test/app_smoke_test.dart
git add -u test/widget_test.dart
git commit -m "chore: bootstrap Android Flutter app"
```

**Per-Task Coverage Review:** smoke test directly proves the generated Flutter shell is usable; `flutter analyze` proves the scaffold and root widget compile; platform-generation command directly excludes iOS/iPadOS scaffolds. No runtime dependencies beyond Flutter are added.

**Coverage Gate:** `COVERAGE_COMPLETE`

---

### Task 2: Define Topic and ReviewItem domain contracts

**Files:**
- Create: `lib/domain/topic.dart`
- Create: `lib/domain/review_item.dart`
- Create: `test/domain/topic_test.dart`
- Create: `test/domain/review_item_test.dart`

**Interfaces:**
- **Consumes:** Dart `DateTime` and integer stable identities.
- **Produces:**
  - `String normalizeTopicName(String raw)`
  - `String topicNameKey(String raw)`
  - `final class Topic`
  - `final class ReviewItem`

`Topic` signature:

```dart
Topic({
  required int id,
  required String name,
  required DateTime createdAt,
  required DateTime updatedAt,
})
```

`ReviewItem` signature:

```dart
ReviewItem({
  required int id,
  required String content,
  required int topicId,
  required bool enabled,
  required DateTime createdAt,
  required DateTime updatedAt,
  DateTime? lastShownAt,
})
```

**Acceptance:**
- Topic identity must be positive and Topic names trim to a non-empty stored value.
- `topicNameKey` supplies the case-insensitive normalized key required by downstream persistence uniqueness checks.
- ReviewItem identity and Topic identity must be positive.
- ReviewItem content must contain at least one non-whitespace character, while the original content formatting is retained.
- `lastShownAt` is nullable and is not implicitly reset by construction of an edited item.

- [ ] **Step 1: Write failing Topic tests**

Create `test/domain/topic_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/topic.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 27, 8);

  test('trims Topic display name and builds lowercase uniqueness key', () {
    final topic = Topic(
      id: 1,
      name: '  Biology  ',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    expect(topic.name, 'Biology');
    expect(topicNameKey('  BIOLOGY  '), 'biology');
  });

  test('rejects blank Topic name', () {
    expect(
      () => Topic(
        id: 1,
        name: '   ',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
  });

  test('rejects non-positive Topic identity', () {
    expect(
      () => Topic(
        id: 0,
        name: '医学',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run Topic tests to verify RED**

```bash
flutter test test/domain/topic_test.dart
```

Expected: FAIL because `lib/domain/topic.dart` does not exist.

- [ ] **Step 3: Implement Topic**

Create `lib/domain/topic.dart`:

```dart
String normalizeTopicName(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(raw, 'name', 'Topic name must not be blank');
  }
  return normalized;
}

String topicNameKey(String raw) => normalizeTopicName(raw).toLowerCase();

final class Topic {
  Topic({
    required this.id,
    required String name,
    required this.createdAt,
    required this.updatedAt,
  }) : name = normalizeTopicName(name) {
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'Topic id must be positive');
    }
  }

  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

- [ ] **Step 4: Verify Topic GREEN**

```bash
flutter test test/domain/topic_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write failing ReviewItem tests**

Create `test/domain/review_item_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/review_item.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 27, 8);
  final shownAt = DateTime.utc(2026, 9, 27, 9);

  test('keeps passage formatting and reminder history', () {
    final item = ReviewItem(
      id: 7,
      content: '第一行\n第二行',
      topicId: 2,
      enabled: true,
      createdAt: createdAt,
      updatedAt: createdAt,
      lastShownAt: shownAt,
    );

    expect(item.content, '第一行\n第二行');
    expect(item.topicId, 2);
    expect(item.lastShownAt, shownAt);
  });

  test('rejects whitespace-only content', () {
    expect(
      () => ReviewItem(
        id: 7,
        content: ' \n ',
        topicId: 2,
        enabled: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
  });

  test('rejects non-positive identities', () {
    expect(
      () => ReviewItem(
        id: 0,
        content: '有效内容',
        topicId: 2,
        enabled: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => ReviewItem(
        id: 7,
        content: '有效内容',
        topicId: 0,
        enabled: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 6: Run ReviewItem tests to verify RED**

```bash
flutter test test/domain/review_item_test.dart
```

Expected: FAIL because `lib/domain/review_item.dart` does not exist.

- [ ] **Step 7: Implement ReviewItem**

Create `lib/domain/review_item.dart`:

```dart
final class ReviewItem {
  ReviewItem({
    required this.id,
    required this.content,
    required this.topicId,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.lastShownAt,
  }) {
    if (id <= 0) {
      throw ArgumentError.value(id, 'id', 'ReviewItem id must be positive');
    }
    if (topicId <= 0) {
      throw ArgumentError.value(
        topicId,
        'topicId',
        'ReviewItem topicId must be positive',
      );
    }
    if (content.trim().isEmpty) {
      throw ArgumentError.value(
        content,
        'content',
        'ReviewItem content must not be blank',
      );
    }
  }

  final int id;
  final String content;
  final int topicId;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastShownAt;
}
```

- [ ] **Step 8: Verify Task 2 tests and commit**

```bash
flutter test test/domain/topic_test.dart test/domain/review_item_test.dart
flutter analyze
git add lib/domain/topic.dart lib/domain/review_item.dart test/domain/topic_test.dart test/domain/review_item_test.dart
git commit -m "feat: define study content domain models"
```

Expected: tests PASS; analyzer exits 0; commit succeeds.

**Per-Task Coverage Review:** Topic tests directly prove blank/identity rejection and normalization; ReviewItem tests directly prove content/identity constraints and that `lastShownAt` remains explicit state. Case-insensitive uniqueness itself is assigned to Plan 2 because uniqueness requires authoritative persisted state.

**Coverage Gate:** `COVERAGE_COMPLETE`

---

### Task 3: Define ReminderScope and ReminderSettings value contracts

**Files:**
- Create: `lib/domain/reminder_scope.dart`
- Create: `lib/domain/active_window.dart`
- Create: `lib/domain/reminder_settings.dart`
- Create: `test/domain/reminder_scope_test.dart`
- Create: `test/domain/reminder_settings_test.dart`

**Interfaces:**
- **Consumes:** positive Topic IDs from Task 2.
- **Produces:**
  - `enum ReminderScopeMode { allTopics, selectedTopics }`
  - `ReminderScope.allTopics()`
  - `ReminderScope.selectedTopics(Set<int> topicIds)`
  - `bool ReminderScope.allows(int topicId)`
  - `enum ActiveWindowMode { allDay, bounded }`
  - `ActiveWindow.allDay()`
  - `ActiveWindow.bounded({required int startMinute, required int endMinute})`
  - `ReminderSettings({required bool enabled, required ActiveWindow activeWindow, required Duration reminderInterval, required Duration repeatCooldown, required ReminderScope scope})`

**Acceptance:**
- `SELECTED_TOPICS` can never contain an empty set or non-positive Topic ID.
- Multi-topic membership behaves as a union.
- Bounded active-window values are valid minute-of-day values 0–1439 and cannot use identical start/end; same-day and cross-midnight representations are both accepted.
- Production reminder interval rejects any value below 15 minutes.
- Repeat cooldown rejects negative duration and accepts zero or positive duration because the authoritative Spec defines no stricter minimum.

- [ ] **Step 1: Write failing ReminderScope tests**

Create `test/domain/reminder_scope_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';

void main() {
  test('ALL_TOPICS allows every positive Topic id', () {
    final scope = ReminderScope.allTopics();

    expect(scope.mode, ReminderScopeMode.allTopics);
    expect(scope.allows(1), isTrue);
    expect(scope.allows(99), isTrue);
  });

  test('SELECTED_TOPICS uses union membership', () {
    final scope = ReminderScope.selectedTopics({2, 5});

    expect(scope.mode, ReminderScopeMode.selectedTopics);
    expect(scope.allows(2), isTrue);
    expect(scope.allows(5), isTrue);
    expect(scope.allows(3), isFalse);
  });

  test('SELECTED_TOPICS rejects empty and invalid ids', () {
    expect(() => ReminderScope.selectedTopics({}), throwsArgumentError);
    expect(() => ReminderScope.selectedTopics({1, 0}), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run ReminderScope tests to verify RED**

```bash
flutter test test/domain/reminder_scope_test.dart
```

Expected: FAIL because the ReminderScope implementation does not exist.

- [ ] **Step 3: Implement ReminderScope**

Create `lib/domain/reminder_scope.dart`:

```dart
enum ReminderScopeMode { allTopics, selectedTopics }

final class ReminderScope {
  ReminderScope._(this.mode, Set<int> topicIds)
      : topicIds = Set<int>.unmodifiable(topicIds);

  factory ReminderScope.allTopics() {
    return ReminderScope._(ReminderScopeMode.allTopics, const <int>{});
  }

  factory ReminderScope.selectedTopics(Set<int> topicIds) {
    if (topicIds.isEmpty) {
      throw ArgumentError.value(
        topicIds,
        'topicIds',
        'SELECTED_TOPICS must not be empty',
      );
    }
    if (topicIds.any((id) => id <= 0)) {
      throw ArgumentError.value(
        topicIds,
        'topicIds',
        'Topic ids must be positive',
      );
    }
    return ReminderScope._(ReminderScopeMode.selectedTopics, topicIds);
  }

  final ReminderScopeMode mode;
  final Set<int> topicIds;

  bool allows(int topicId) {
    if (topicId <= 0) {
      return false;
    }
    return mode == ReminderScopeMode.allTopics || topicIds.contains(topicId);
  }
}
```

- [ ] **Step 4: Verify ReminderScope GREEN**

```bash
flutter test test/domain/reminder_scope_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write failing settings/window tests**

Create `test/domain/reminder_settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';

void main() {
  final allTopics = ReminderScope.allTopics();

  test('accepts all-day, same-day, and cross-midnight window representations', () {
    expect(ActiveWindow.allDay().mode, ActiveWindowMode.allDay);
    expect(
      ActiveWindow.bounded(startMinute: 8 * 60, endMinute: 23 * 60).mode,
      ActiveWindowMode.bounded,
    );
    expect(
      ActiveWindow.bounded(startMinute: 22 * 60, endMinute: 60).mode,
      ActiveWindowMode.bounded,
    );
  });

  test('rejects invalid bounded window values', () {
    expect(
      () => ActiveWindow.bounded(startMinute: -1, endMinute: 60),
      throwsArgumentError,
    );
    expect(
      () => ActiveWindow.bounded(startMinute: 60, endMinute: 1440),
      throwsArgumentError,
    );
    expect(
      () => ActiveWindow.bounded(startMinute: 60, endMinute: 60),
      throwsArgumentError,
    );
  });

  test('enforces 15-minute production reminder minimum', () {
    expect(
      () => ReminderSettings(
        enabled: true,
        activeWindow: ActiveWindow.allDay(),
        reminderInterval: const Duration(minutes: 14),
        repeatCooldown: Duration.zero,
        scope: allTopics,
      ),
      throwsArgumentError,
    );

    final settings = ReminderSettings(
      enabled: true,
      activeWindow: ActiveWindow.allDay(),
      reminderInterval: const Duration(minutes: 15),
      repeatCooldown: const Duration(hours: 24),
      scope: allTopics,
    );
    expect(settings.reminderInterval, const Duration(minutes: 15));
  });

  test('rejects negative cooldown', () {
    expect(
      () => ReminderSettings(
        enabled: true,
        activeWindow: ActiveWindow.allDay(),
        reminderInterval: const Duration(minutes: 15),
        repeatCooldown: const Duration(seconds: -1),
        scope: allTopics,
      ),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 6: Run settings tests to verify RED**

```bash
flutter test test/domain/reminder_settings_test.dart
```

Expected: FAIL because `active_window.dart` and `reminder_settings.dart` do not exist.

- [ ] **Step 7: Implement ActiveWindow representation**

Create `lib/domain/active_window.dart`:

```dart
enum ActiveWindowMode { allDay, bounded }

final class ActiveWindow {
  ActiveWindow._({
    required this.mode,
    this.startMinute,
    this.endMinute,
  });

  factory ActiveWindow.allDay() {
    return ActiveWindow._(mode: ActiveWindowMode.allDay);
  }

  factory ActiveWindow.bounded({
    required int startMinute,
    required int endMinute,
  }) {
    if (startMinute < 0 || startMinute > 1439) {
      throw ArgumentError.value(
        startMinute,
        'startMinute',
        'startMinute must be between 0 and 1439',
      );
    }
    if (endMinute < 0 || endMinute > 1439) {
      throw ArgumentError.value(
        endMinute,
        'endMinute',
        'endMinute must be between 0 and 1439',
      );
    }
    if (startMinute == endMinute) {
      throw ArgumentError('Bounded active-window start and end must differ');
    }
    return ActiveWindow._(
      mode: ActiveWindowMode.bounded,
      startMinute: startMinute,
      endMinute: endMinute,
    );
  }

  final ActiveWindowMode mode;
  final int? startMinute;
  final int? endMinute;
}
```

This Plan intentionally represents but does not evaluate bounded-window wall-clock inclusion. The exact inclusive/exclusive end-boundary is a recorded Plan 3 prerequisite because the current Spec does not state it.

- [ ] **Step 8: Implement ReminderSettings**

Create `lib/domain/reminder_settings.dart`:

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

  final bool enabled;
  final ActiveWindow activeWindow;
  final Duration reminderInterval;
  final Duration repeatCooldown;
  final ReminderScope scope;
}
```

- [ ] **Step 9: Verify Task 3 and commit**

```bash
flutter test test/domain/reminder_scope_test.dart test/domain/reminder_settings_test.dart
flutter analyze
git add lib/domain/reminder_scope.dart lib/domain/active_window.dart lib/domain/reminder_settings.dart test/domain/reminder_scope_test.dart test/domain/reminder_settings_test.dart
git commit -m "feat: define reminder configuration contracts"
```

Expected: tests PASS; analyzer exits 0; commit succeeds.

**Per-Task Coverage Review:** tests directly prove selected-scope non-emptiness, union membership, production interval boundary, cooldown negativity rejection, and active-window representation constraints. Wall-clock inclusion at exact end boundary is deliberately not implemented because the Spec must close that observable semantic before Plan 3.

**Coverage Gate:** `COVERAGE_COMPLETE`

---

### Task 4: Implement deterministic eligible-item selection

**Files:**
- Create: `lib/domain/reminder_candidate_selector.dart`
- Create: `test/domain/reminder_candidate_selector_test.dart`

**Interfaces:**
- **Consumes:** `ReviewItem`, `ReminderScope`, current `DateTime now`, current `Duration repeatCooldown`.
- **Produces:**
  - `List<ReviewItem> ReminderCandidateSelector.eligibleItems(...)`
  - `ReviewItem? ReminderCandidateSelector.selectNext(...)`

Exact signatures:

```dart
List<ReviewItem> eligibleItems({
  required List<ReviewItem> items,
  required ReminderScope scope,
  required Duration repeatCooldown,
  required DateTime now,
})

ReviewItem? selectNext({
  required List<ReviewItem> items,
  required ReminderScope scope,
  required Duration repeatCooldown,
  required DateTime now,
})
```

**Acceptance:**
- Disabled items are excluded.
- Items outside the current scope are excluded.
- Never-shown items are cooldown-eligible.
- `now < lastShownAt + cooldown` excludes an item.
- `now == lastShownAt + cooldown` includes an item.
- Multi-topic selection acts as union through ReminderScope membership.
- Ordering exactly matches Spec §7 and is deterministic on identical input.
- An empty pool returns `null` from `selectNext`.

- [ ] **Step 1: Write the failing selector tests**

Create `test/domain/reminder_candidate_selector_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/reminder_candidate_selector.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/review_item.dart';

ReviewItem item({
  required int id,
  required int topicId,
  required DateTime createdAt,
  DateTime? lastShownAt,
  bool enabled = true,
}) {
  return ReviewItem(
    id: id,
    content: 'item-$id',
    topicId: topicId,
    enabled: enabled,
    createdAt: createdAt,
    updatedAt: createdAt,
    lastShownAt: lastShownAt,
  );
}

void main() {
  final selector = ReminderCandidateSelector();
  final now = DateTime.utc(2026, 9, 27, 12);
  final cooldown = const Duration(hours: 24);

  test('filters disabled, out-of-scope, and cooling-down items', () {
    final selected = selector.eligibleItems(
      items: [
        item(id: 1, topicId: 1, createdAt: now.subtract(const Duration(days: 4))),
        item(id: 2, topicId: 2, createdAt: now.subtract(const Duration(days: 3))),
        item(
          id: 3,
          topicId: 1,
          createdAt: now.subtract(const Duration(days: 2)),
          lastShownAt: now.subtract(const Duration(hours: 23)),
        ),
        item(
          id: 4,
          topicId: 1,
          createdAt: now.subtract(const Duration(days: 1)),
          enabled: false,
        ),
      ],
      scope: ReminderScope.selectedTopics({1}),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(selected.map((e) => e.id), [1]);
  });

  test('includes an item exactly at the cooldown boundary', () {
    final candidate = selector.selectNext(
      items: [
        item(
          id: 8,
          topicId: 1,
          createdAt: now.subtract(const Duration(days: 2)),
          lastShownAt: now.subtract(cooldown),
        ),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate?.id, 8);
  });

  test('orders never-shown first by createdAt then stable id', () {
    final candidate = selector.selectNext(
      items: [
        item(id: 9, topicId: 1, createdAt: DateTime.utc(2026, 9, 20)),
        item(id: 2, topicId: 1, createdAt: DateTime.utc(2026, 9, 20)),
        item(
          id: 1,
          topicId: 1,
          createdAt: DateTime.utc(2026, 9, 1),
          lastShownAt: DateTime.utc(2026, 9, 1),
        ),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate?.id, 2);
  });

  test('orders previously shown items by oldest lastShownAt then stable id', () {
    final oldShownAt = DateTime.utc(2026, 9, 1);
    final candidate = selector.selectNext(
      items: [
        item(
          id: 9,
          topicId: 1,
          createdAt: DateTime.utc(2026, 8, 1),
          lastShownAt: oldShownAt,
        ),
        item(
          id: 2,
          topicId: 1,
          createdAt: DateTime.utc(2026, 8, 2),
          lastShownAt: oldShownAt,
        ),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate?.id, 2);
  });

  test('returns null when no item is eligible', () {
    final candidate = selector.selectNext(
      items: [
        item(
          id: 1,
          topicId: 1,
          createdAt: now.subtract(const Duration(days: 2)),
          lastShownAt: now.subtract(const Duration(minutes: 5)),
        ),
      ],
      scope: ReminderScope.allTopics(),
      repeatCooldown: cooldown,
      now: now,
    );

    expect(candidate, isNull);
  });
}
```

- [ ] **Step 2: Run selector tests to verify RED**

```bash
flutter test test/domain/reminder_candidate_selector_test.dart
```

Expected: FAIL because `ReminderCandidateSelector` does not exist.

- [ ] **Step 3: Implement selector**

Create `lib/domain/reminder_candidate_selector.dart`:

```dart
import 'reminder_scope.dart';
import 'review_item.dart';

final class ReminderCandidateSelector {
  List<ReviewItem> eligibleItems({
    required List<ReviewItem> items,
    required ReminderScope scope,
    required Duration repeatCooldown,
    required DateTime now,
  }) {
    if (repeatCooldown.isNegative) {
      throw ArgumentError.value(
        repeatCooldown,
        'repeatCooldown',
        'Repeat cooldown must not be negative',
      );
    }

    final eligible = items.where((item) {
      if (!item.enabled) {
        return false;
      }
      if (!scope.allows(item.topicId)) {
        return false;
      }
      final lastShownAt = item.lastShownAt;
      if (lastShownAt == null) {
        return true;
      }
      final nextEligibleAt = lastShownAt.add(repeatCooldown);
      return !now.isBefore(nextEligibleAt);
    }).toList(growable: false);

    final sorted = [...eligible]..sort(_compare);
    return List<ReviewItem>.unmodifiable(sorted);
  }

  ReviewItem? selectNext({
    required List<ReviewItem> items,
    required ReminderScope scope,
    required Duration repeatCooldown,
    required DateTime now,
  }) {
    final eligible = eligibleItems(
      items: items,
      scope: scope,
      repeatCooldown: repeatCooldown,
      now: now,
    );
    return eligible.isEmpty ? null : eligible.first;
  }

  int _compare(ReviewItem a, ReviewItem b) {
    final aNeverShown = a.lastShownAt == null;
    final bNeverShown = b.lastShownAt == null;

    if (aNeverShown != bNeverShown) {
      return aNeverShown ? -1 : 1;
    }

    if (aNeverShown) {
      final createdComparison = a.createdAt.compareTo(b.createdAt);
      if (createdComparison != 0) {
        return createdComparison;
      }
      return a.id.compareTo(b.id);
    }

    final shownComparison = a.lastShownAt!.compareTo(b.lastShownAt!);
    if (shownComparison != 0) {
      return shownComparison;
    }
    return a.id.compareTo(b.id);
  }
}
```

- [ ] **Step 4: Verify selector GREEN and commit**

```bash
flutter test test/domain/reminder_candidate_selector_test.dart
flutter analyze
git add lib/domain/reminder_candidate_selector.dart test/domain/reminder_candidate_selector_test.dart
git commit -m "feat: add deterministic reminder eligibility"
```

Expected: tests PASS; analyzer exits 0; commit succeeds.

**Per-Task Coverage Review:** tests directly prove the three filters, exact cooldown boundary, empty-pool behavior, never-shown priority, creation-time ordering, last-shown ordering, stable-ID tie breaking, and scope union behavior through the selected-scope test. State commit/concurrency is not claimed here and remains assigned to Android runtime/persistence coordination in downstream plans.

**Coverage Gate:** `COVERAGE_COMPLETE`

---

### Task 5: Implement the pure reminder-evaluation decision order

**Files:**
- Create: `lib/domain/reminder_evaluator.dart`
- Create: `test/domain/reminder_evaluator_test.dart`

**Interfaces:**
- **Consumes:** `ReminderSettings`, `List<ReviewItem>`, `DateTime now`, and runtime facts supplied as booleans: `withinActiveWindow`, `isForeground`, `notificationAvailable`.
- **Produces:**
  - `enum ReminderEvaluationOutcome`
  - `final class ReminderEvaluationResult`
  - `final class ReminderEvaluator`
  - `ReminderEvaluationResult ReminderEvaluator.evaluate(...)`

Outcome order is exactly:

```text
reminderDisabled
→ outsideActiveWindow
→ foregroundSuppressed
→ notificationUnavailable
→ noEligibleItem
→ candidateSelected
```

**Acceptance:**
- Evaluation short-circuits in the Spec §6.3 order before item filtering/selection.
- Candidate selection uses only the Task 4 selector and current settings.
- A non-candidate outcome never fabricates or consumes a ReviewItem.
- `candidateSelected` carries exactly the selected ReviewItem; no `lastShownAt` mutation occurs in this pure Plan 1 layer.
- Successful Android notification submission and atomic history commit remain downstream responsibilities.

- [ ] **Step 1: Write the failing evaluator tests**

Create `test/domain/reminder_evaluator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_evaluator.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/domain/review_item.dart';

ReminderSettings settings({bool enabled = true}) {
  return ReminderSettings(
    enabled: enabled,
    activeWindow: ActiveWindow.allDay(),
    reminderInterval: const Duration(minutes: 15),
    repeatCooldown: const Duration(hours: 24),
    scope: ReminderScope.allTopics(),
  );
}

ReviewItem eligibleItem(DateTime now) {
  return ReviewItem(
    id: 1,
    content: '有效复习内容',
    topicId: 1,
    enabled: true,
    createdAt: now.subtract(const Duration(days: 1)),
    updatedAt: now.subtract(const Duration(days: 1)),
  );
}

void main() {
  final evaluator = ReminderEvaluator();
  final now = DateTime.utc(2026, 9, 27, 12);

  test('disabled reminders short-circuit first', () {
    final result = evaluator.evaluate(
      settings: settings(enabled: false),
      items: [eligibleItem(now)],
      now: now,
      withinActiveWindow: false,
      isForeground: true,
      notificationAvailable: false,
    );

    expect(result.outcome, ReminderEvaluationOutcome.reminderDisabled);
    expect(result.candidate, isNull);
  });

  test('outside active window precedes foreground and notification checks', () {
    final result = evaluator.evaluate(
      settings: settings(),
      items: [eligibleItem(now)],
      now: now,
      withinActiveWindow: false,
      isForeground: true,
      notificationAvailable: false,
    );

    expect(result.outcome, ReminderEvaluationOutcome.outsideActiveWindow);
  });

  test('foreground suppression precedes notification capability', () {
    final result = evaluator.evaluate(
      settings: settings(),
      items: [eligibleItem(now)],
      now: now,
      withinActiveWindow: true,
      isForeground: true,
      notificationAvailable: false,
    );

    expect(result.outcome, ReminderEvaluationOutcome.foregroundSuppressed);
  });

  test('notification unavailable precedes candidate selection', () {
    final result = evaluator.evaluate(
      settings: settings(),
      items: [eligibleItem(now)],
      now: now,
      withinActiveWindow: true,
      isForeground: false,
      notificationAvailable: false,
    );

    expect(result.outcome, ReminderEvaluationOutcome.notificationUnavailable);
  });

  test('reports noEligibleItem without a candidate', () {
    final result = evaluator.evaluate(
      settings: settings(),
      items: const [],
      now: now,
      withinActiveWindow: true,
      isForeground: false,
      notificationAvailable: true,
    );

    expect(result.outcome, ReminderEvaluationOutcome.noEligibleItem);
    expect(result.candidate, isNull);
  });

  test('returns deterministic candidate without mutating lastShownAt', () {
    final item = eligibleItem(now);
    final result = evaluator.evaluate(
      settings: settings(),
      items: [item],
      now: now,
      withinActiveWindow: true,
      isForeground: false,
      notificationAvailable: true,
    );

    expect(result.outcome, ReminderEvaluationOutcome.candidateSelected);
    expect(result.candidate?.id, item.id);
    expect(item.lastShownAt, isNull);
  });
}
```

- [ ] **Step 2: Run evaluator tests to verify RED**

```bash
flutter test test/domain/reminder_evaluator_test.dart
```

Expected: FAIL because `ReminderEvaluator` does not exist.

- [ ] **Step 3: Implement ReminderEvaluator**

Create `lib/domain/reminder_evaluator.dart`:

```dart
import 'reminder_candidate_selector.dart';
import 'reminder_settings.dart';
import 'review_item.dart';

enum ReminderEvaluationOutcome {
  reminderDisabled,
  outsideActiveWindow,
  foregroundSuppressed,
  notificationUnavailable,
  noEligibleItem,
  candidateSelected,
}

final class ReminderEvaluationResult {
  const ReminderEvaluationResult._({
    required this.outcome,
    this.candidate,
  });

  const ReminderEvaluationResult.withoutCandidate(
    ReminderEvaluationOutcome outcome,
  ) : this._(outcome: outcome);

  const ReminderEvaluationResult.withCandidate(ReviewItem candidate)
      : this._(
          outcome: ReminderEvaluationOutcome.candidateSelected,
          candidate: candidate,
        );

  final ReminderEvaluationOutcome outcome;
  final ReviewItem? candidate;
}

final class ReminderEvaluator {
  ReminderEvaluator({ReminderCandidateSelector? selector})
      : _selector = selector ?? ReminderCandidateSelector();

  final ReminderCandidateSelector _selector;

  ReminderEvaluationResult evaluate({
    required ReminderSettings settings,
    required List<ReviewItem> items,
    required DateTime now,
    required bool withinActiveWindow,
    required bool isForeground,
    required bool notificationAvailable,
  }) {
    if (!settings.enabled) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.reminderDisabled,
      );
    }
    if (!withinActiveWindow) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.outsideActiveWindow,
      );
    }
    if (isForeground) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.foregroundSuppressed,
      );
    }
    if (!notificationAvailable) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.notificationUnavailable,
      );
    }

    final candidate = _selector.selectNext(
      items: items,
      scope: settings.scope,
      repeatCooldown: settings.repeatCooldown,
      now: now,
    );
    if (candidate == null) {
      return const ReminderEvaluationResult.withoutCandidate(
        ReminderEvaluationOutcome.noEligibleItem,
      );
    }

    return ReminderEvaluationResult.withCandidate(candidate);
  }
}
```

- [ ] **Step 4: Run the complete Plan 1 test suite and analyzer**

```bash
flutter test
flutter analyze
```

Expected: all tests PASS; analyzer exits 0.

- [ ] **Step 5: Commit the evaluator**

```bash
git add lib/domain/reminder_evaluator.dart test/domain/reminder_evaluator_test.dart
git commit -m "feat: add reminder evaluation decision flow"
```

**Per-Task Coverage Review:** each precondition has a direct test proving short-circuit precedence, no-eligible behavior is direct, and candidate-selection test proves this pure layer does not commit `lastShownAt`. Android notification success, transactional exclusivity, and history commit are explicitly not claimed by this task and remain assigned to downstream runtime/persistence plans.

**Coverage Gate:** `COVERAGE_COMPLETE`

---

## Plan 1 Acceptance Run

After all Tasks are complete, run from repository root:

```bash
flutter test
flutter analyze
git status --short
```

Expected:

- `flutter test`: all Plan 1 tests PASS.
- `flutter analyze`: exits 0 with no analyzer errors.
- `git status --short`: empty after the final commit.

Then inspect `git log --oneline -5` and confirm the Plan produced separate reviewable commits for bootstrap, content models, reminder contracts, eligibility, and evaluation flow.

---

## Self-Review

### 1. Spec coverage

Current detailed Plan:

- §4 ReviewItem core state → Tasks 2 and 4.
- §4 Topic identity/name normalization → Task 2; persisted uniqueness/deletion → Plan 2.
- §4.3 ReminderScope union/non-empty contract → Task 3; persistence/deletion interaction → Plan 2.
- §5 interval/cooldown/window representation → Task 3; scheduler cadence and persisted configuration → Plans 2–3.
- §6.3 pure decision order → Task 5; side effects/dispatch → Plan 3.
- §7 enabled/scope/cooldown filters and deterministic selection → Task 4; atomic successful-dispatch commit → Plan 3 using Plan 2 storage.
- §§8–11 Android lifecycle, permissions, notification submission → Plan 3.
- §12 local source of truth → Plan 2.
- §§13–16 user flows, UI, Diagnostics, remote install → Plan 4, with domain behavior already locked by Plan 1.
- §17 OPPO real-device verification → Plan 5.
- OCR/iOS/cloud/AI remain outside this MVP roadmap per Spec.

No current-Plan requirement is left without a Task. Downstream requirements are mapped to named roadmap plans with prerequisites.

### 2. Placeholder scan

The detailed Tasks contain exact file paths, interfaces, test code, implementation code, commands, expected outcomes, and commit commands. The roadmap intentionally does not pre-commit downstream file/class signatures because `writing-plans` requires those plans to be regenerated from the actual interfaces produced by preceding plans.

### 3. Type consistency

- `Topic.id`, `ReviewItem.id`, and `ReviewItem.topicId` are `int` throughout.
- `lastShownAt`, `createdAt`, `updatedAt`, and `now` are `DateTime` throughout.
- cooldown and interval are `Duration` throughout.
- `ReminderScope` is the single scope type consumed by `ReminderSettings` and `ReminderCandidateSelector`.
- `ReminderEvaluator` consumes the exact Task 3/4 types and does not introduce a second selector or settings representation.

### Spec issues discovered during planning

Plan 1 can proceed without choosing these unresolved semantics, but downstream detailed planning must stop until they are corrected in the authoritative Spec:

1. **Last selected Topic deletion conflict:** §4.2 permits deletion after merely disabling reminders, while §4.3 and §19 prohibit an empty `SELECTED_TOPICS` state. Plan 2 must not detail or implement that transition until the Spec is reconciled.
2. **First-run ReminderSettings absence/default:** the Spec does not state whether no saved settings row exists before first configuration or defines normative initial values. Plan 2/4 must not invent user-visible defaults.
3. **Bounded active-window exact boundary:** same-day/cross-midnight shapes are defined, but exact start/end inclusivity is not. Plan 3 must not encode a boundary convention until the Spec closes it.

These issues do not affect the pure contracts detailed in Plan 1 because Plan 1 does not persist settings/delete Topics/evaluate wall-clock window membership.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-27-android-mvp-domain-foundation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — use `superpowers:subagent-driven-development`, dispatch a fresh subagent per task, and review between tasks.

**2. Inline Execution** — use `superpowers:executing-plans` and execute this plan task-by-task in the current session with checkpoints.

Only Plan 1 is eligible for execution now. After Plan 1 is implemented, re-read the authoritative Spec, actual source tree, interfaces, tests, and acceptance evidence before detailing Plan 2.
