# Android 考研碎片复习 App MVP Spec

**Status:** Approved for implementation planning  
**Date:** 2026-09-27  
**Platform:** Android first; target device for real-device acceptance is OPPO Reno8  
**Client framework constraint:** Flutter

This document is authoritative for MVP product behavior, architecture boundaries, state/failure semantics, invariants, and acceptance. Exact packages, files, classes, functions, commands, commits, and detailed tests belong to `writing-plans`.

---

## 1. Purpose

The MVP serves postgraduate-exam users who already have study notes and want to reuse fragmented phone time for interruption-based review.

The product stores short study passages as `ReviewItem`s. While the app is not in the foreground, the system periodically attempts to surface one eligible passage through an Android system notification. Users control which coarse-grained Topics participate, the target reminder cadence, the daily allowed reminder window, and the minimum cooldown before the same item may appear again.

The MVP is not a knowledge-understanding system. It does not split notes into semantic knowledge cards, infer chapters or knowledge-point types, summarize with AI, generate questions, or detect whether the user is actively using another app.

---

## 2. Scope

### 2.1 In scope

- manual text input and pasted text;
- persistent local `ReviewItem` storage;
- user-managed coarse-grained `Topic`s;
- exactly one Topic per ReviewItem;
- reminder scope over all Topics, one Topic, or multiple Topics;
- one daily active reminder window or all-day mode;
- reminder interval;
- one global repeat cooldown;
- deterministic eligible-item selection;
- Android system-notification delivery on a best-effort background schedule;
- foreground suppression;
- persistence across ordinary process death/restart where Android/OEM permits;
- remote-test Diagnostics;
- APK distribution;
- automated, emulator, and OPPO Reno8 verification boundaries.

### 2.2 Non-goals

The MVP does not implement iOS/iPadOS, login, accounts, servers, cloud/multi-device sync, production OCR, AI APIs, AI summarization/classification/question generation, chapter recognition, semantic knowledge-point types, knowledge graphs, topic trees/subtopics, complex tags, spaced-repetition scoring, mastery ratings, social/community/ranking, commercial/billing functions, exact wall-clock notification guarantees, or detection of whether the user is using another application.

OCR is a later capability constrained to: image → OCR text → user edits text → chooses Topic → saves ReviewItem. Adding OCR later must not require changing ReviewItem or Topic semantics.

---

## 3. Core Domain Semantics

### 3.1 ReviewItem

A `ReviewItem` is one user-authored or pasted passage that may be surfaced by reminders.

It has stable identity, nonblank text content, exactly one Topic, enabled/disabled state, creation/update timestamps, and nullable `last_shown_at`.

A disabled ReviewItem remains stored and editable but is excluded from reminders.

`next_eligible_at` is derived, never an independent source of truth:

```text
last_shown_at == null
    => eligible subject to other filters
otherwise
    next_eligible_at = last_shown_at + current repeat_cooldown
```

The cooldown boundary is inclusive: an item is eligible when `now >= next_eligible_at`.

Changing the global cooldown immediately changes derived eligibility without clearing history.

### 3.2 Topic

A Topic is a user-managed coarse category such as 医学、生物、历史、政治、英语、数学、专业课. Topic names are user-defined, not hard-coded.

Topic identity is stable and independent from its display name. After trimming leading/trailing whitespace, Topic names must be nonblank and unique under the application’s case-insensitive normalized-name rule.

Every ReviewItem references exactly one existing Topic; unassigned ReviewItems are invalid.

Renaming a Topic preserves its identity, ReviewItem associations, and ReminderScope references.

#### Topic deletion

- A Topic referenced by one or more ReviewItems cannot be deleted; those ReviewItems must first be moved or deleted.
- An empty Topic may be deleted.
- Under `ALL_TOPICS`, deleting an empty Topic does not change scope mode.
- Under `SELECTED_TOPICS`, deleting a selected empty Topic is permitted only if at least one other selected Topic remains; the deleted Topic is removed from the selected set atomically with deletion.
- If deletion would leave `SELECTED_TOPICS` empty, deletion is blocked. The user must first switch to `ALL_TOPICS` or select another Topic.
- `reminder_enabled = false` does **not** relax this invariant. An empty `SELECTED_TOPICS` state is never persistable.

### 3.3 ReminderScope

ReminderScope has exactly two valid modes:

1. `ALL_TOPICS` — all existing Topics may contribute eligible items.
2. `SELECTED_TOPICS` — only Topics in a persisted, nonempty selected Topic-ID set may contribute.

One selected Topic is single-topic mode; multiple selected Topics use union semantics:

```text
Topic A + Topic B = items in Topic A ∪ items in Topic B
```

Changing scope affects only future candidate filtering. It never resets `last_shown_at`, cooldown, enabled state, or history.

---

## 4. Reminder Settings Semantics

Reminder settings contain:

- `reminder_enabled`;
- active reminder window;
- `reminder_interval`;
- `repeat_cooldown`;
- ReminderScope.

### 4.1 Initial settings

A fresh installation does not use a nullable or `UNCONFIGURED` ReminderSettings state. The local source of truth is initialized with this legal configuration:

```text
reminder_enabled = false
scope = ALL_TOPICS
active_window = ALL_DAY
reminder_interval = 60 minutes
repeat_cooldown = 24 hours
```

The defaults are persisted as normal current settings. First launch therefore never requires downstream code to branch on `settings == null`.

### 4.2 Reminder interval

Production reminder interval must be at least 15 minutes. The interval is a target cadence between reminder opportunities, not an exact delivery guarantee.

When reminders transition from disabled to enabled, the first normal opportunity is due no earlier than one configured interval later. Enabling reminders does not immediately interrupt the user.

Changing the interval replaces the old cadence for future opportunities; stale scheduling state may not continue as a second independent cadence.

Debug/test builds may expose 1/2/5-minute controls, but those are not valid production settings and must not weaken production validation.

### 4.3 Active reminder window

The user chooses either `ALL_DAY` or one bounded daily window represented by local wall-clock start/end minutes.

Bounded-window membership is **left-closed, right-open**: `[start, end)`.

For a same-day window where `start < end`:

```text
start <= now < end
```

Example: `08:00–23:00` includes `08:00:00` and excludes `23:00:00`.

For a cross-midnight window where `start > end`:

```text
now >= start OR now < end
```

Example: `22:00–01:00` includes 22:00 through midnight and excludes exactly 01:00.

For bounded mode, `start == end` is invalid. Twenty-four-hour availability is represented only by `ALL_DAY`.

If Android/OEM delays an opportunity until outside the allowed window, that opportunity is skipped; missed opportunities are not replayed in a burst.

### 4.4 Repeat cooldown

`repeat_cooldown` is one current setting applied to every ReviewItem. It must not be negative. Changing it is effective immediately against existing `last_shown_at` values and never clears history.

---

## 5. Architecture and Responsibility Boundaries

### 5.1 Presentation

Owns ReviewItem list/detail/edit flows, Topic management, reminder settings/scope controls, permission/degraded-state messaging, and Diagnostics UI. It does not own selection or Android scheduling semantics.

### 5.2 Local persistence

One local persistent store is authoritative for Topics, ReviewItems, current ReminderSettings, current ReminderScope, `last_shown_at`, and minimal scheduling/dispatch diagnostics.

Derived values such as `next_eligible_at` and Eligible Pool membership are not separately authoritative.

Persistence must preserve referential integrity: no ReviewItem may reference a missing Topic, and no persisted selected Topic ID may reference a missing Topic.

Android scheduler metadata is not a product source of truth. If scheduler metadata conflicts with persisted current settings, persisted current settings govern whether an evaluation is allowed to dispatch.

### 5.3 Reminder evaluation

Each reminder trigger requests an evaluation against current persisted state:

```text
current settings
→ enabled check
→ active-window check
→ foreground check
→ notification-capability check
→ ReviewItem enabled filter
→ ReminderScope filter
→ cooldown filter
→ deterministic selection
→ notification dispatch attempt
→ last_shown_at commit after successful submission
```

Content is selected at evaluation time, not prebound when future work is scheduled. Deleted, disabled, moved, or now-out-of-scope items must therefore not be surfaced by stale triggers.

### 5.4 Android runtime

Android scheduling/notification is best-effort/inexact. Exact-alarm permission is not an MVP prerequisite. Runtime must preserve persisted product intent across ordinary process death and restore/reschedule after reboot where platform/OEM permits.

### 5.5 Diagnostics

Diagnostics exposes runtime facts needed by a remote non-developer tester. It is read-only with respect to production invariants and must not become an alternate bypass path.

---

## 6. Eligible Selection Contract

At evaluation time:

```text
All ReviewItems
→ keep enabled items
→ keep items allowed by current ReminderScope
→ keep items where last_shown_at == null OR now >= last_shown_at + repeat_cooldown
→ Eligible Pool
```

If the Eligible Pool is empty, no notification is submitted and no ReviewItem history changes.

Selection is deterministic:

1. never-shown items first;
2. among never-shown items, earlier `created_at` first;
3. otherwise oldest `last_shown_at` first;
4. ties by stable ReviewItem identity.

Duplicate/concurrent evaluations must not both commit the same unchanged candidate as two independent dispatches. Selection plus successful-dispatch history update is one logical exclusivity boundary.

---

## 7. Application and Device States

### 7.1 Foreground

While the app is foregrounded, fragmented-study system notifications are suppressed. Suppression does not update `last_shown_at`, reserve an item, or create a catch-up notification later.

### 7.2 Background / lock screen

When not foregrounded and platform policy permits execution, evaluation may dispatch subject to all other rules. Lock-screen presentation follows Android/user privacy settings; full study text visibility is not guaranteed.

### 7.3 Process reclaimed

Ordinary process reclamation must not erase persisted Topics, ReviewItems, settings, scope, or history. The product must not require the Flutter process to remain resident.

### 7.4 Recent-task swipe-away

Swipe-away is not defined as Android Force Stop. Persisted intent remains, but actual OPPO Reno8/ColorOS continuity is `NOT_VERIFIED_ON_DEVICE` until tested.

### 7.5 Force Stop

After system Force Stop, reminder continuity is outside the MVP guarantee boundary and is `UNSUPPORTED_WHILE_FORCE_STOPPED` until the user relaunches/interacts with the app.

### 7.6 Reboot

If reminders were enabled, current persisted settings remain authoritative after reboot. Runtime must restore/allow restoration from those settings when Android/OEM permits. OPPO Reno8 reboot behavior remains `NOT_VERIFIED_ON_DEVICE` until tested.

### 7.7 App update

App update must preserve local product state and must not leave an old scheduling cadence independently active.

### 7.8 System time / timezone

Active-window membership uses current device local wall-clock time at evaluation. Cooldown uses elapsed instant semantics from `last_shown_at`; timezone display changes do not reset history. Future evaluation must not remain permanently bound to an obsolete timezone schedule.

---

## 8. Notification Semantics

A reminder notification contains application identity/title, a ReviewItem preview subject to normal Android truncation, and a tap action opening the full ReviewItem.

The MVP has no quizzes, memory-rating actions, or mastery buttons.

### 8.1 Meaning of `last_shown_at`

`last_shown_at` is the time at which the app successfully submits the selected ReviewItem to Android’s notification service while app/channel notification state permits posting.

It is not schedule time, user-tap time, dismissal time, or proof that a banner became visibly noticeable to the human.

If permission is denied, app notifications are disabled, or submission fails before acceptance, `last_shown_at` is not updated. If Android accepts the notification but later presents it silently or suppresses alerting under DND/system policy, cooldown still starts because the app cannot reliably prove stronger human visibility.

Tap/dismiss events do not modify cooldown.

---

## 9. Permission and Platform Constraints

On Android versions requiring runtime notification permission, reminder operation requires the permission and enabled app/channel notification state. Missing capability produces `DEGRADED_NOTIFICATION_PERMISSION`; settings remain persisted and no item is marked shown merely because evaluation occurred.

The MVP does not depend on `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM`. Doze, App Standby, battery policy, background restrictions, OEM policy, and device conditions may delay best-effort work.

OPPO/ColorOS battery/background/auto-launch controls may affect execution. The app may diagnose and explain likely restrictions but cannot claim to bypass them.

Until tested on the actual OPPO Reno8, long-running reminder stability, swipe-away continuity, reboot recovery, battery/background-restriction behavior, lock-screen behavior, and recovery after ColorOS setting changes remain `NOT_VERIFIED_ON_DEVICE`.

---

## 10. Failure / Degraded Behavior

- Reminder disabled: no reminder dispatch; content/settings remain intact.
- No Topic: no ReviewItem may be created until a Topic exists; evaluation produces no content.
- Scope has no matching items: evaluation produces no notification.
- All matching items are in cooldown: skip; never bypass cooldown.
- Notification capability missing: degraded state; do not update `last_shown_at`.
- App foreground: suppress; do not update history.
- Outside active window: skip; no catch-up burst.
- Local-store read failure: do not dispatch stale/unverified content; record diagnostic failure.
- Scheduling request failure: preserve user intent and expose diagnostic degradation; do not claim healthy reminder state.
- OEM delay: preserve settings and report observable status; delay is allowed by the best-effort contract.
- Force Stop: no continuity guarantee until relaunch/interact.
- Topic deletion that would orphan ReviewItems: block.
- Topic deletion that would leave `SELECTED_TOPICS` empty: block regardless of reminder enabled/disabled.
- Settings change: future evaluation uses only current persisted settings.

No failure path may silently widen ReminderScope, bypass cooldown, or substitute content merely to force a notification.

---

## 11. Diagnostics and Remote Verification

Diagnostics must expose at least device model, Android version, app version/build, notification capability, reminder enabled state, active window, interval, cooldown, current scope and selected Topics, total/matching/eligible item counts, latest evaluation time/outcome, latest successful notification time and item/topic ID, next expected opportunity as a best-effort estimate, observable scheduler/degraded status, and OPPO-specific verification status.

It provides one copy action. The report should use IDs/state instead of full study content unless the user explicitly chooses otherwise.

Verification states are:

- `VERIFIED_AUTOMATED`;
- `VERIFIED_EMULATOR`;
- `VERIFIED_ON_OPPO_RENO8`;
- `NOT_VERIFIED_ON_DEVICE`;
- `UNSUPPORTED_WHILE_FORCE_STOPPED`.

Emulator success cannot be promoted to OPPO Reno8 verification.

---

## 12. Acceptance Criteria

### 12.1 Topic / ReviewItem

1. Saving a valid ReviewItem under an existing Topic persists it across app restart.
2. Editing ReviewItem text, Topic, or enabled state preserves prior `last_shown_at` unless a successful notification dispatch later changes it.
3. Deleting a Topic with ReviewItems is blocked.
4. Renaming a Topic preserves stable identity and scope/item relationships.
5. Duplicate normalized Topic names are rejected.

### 12.2 ReminderScope

6. `ALL_TOPICS` allows every existing Topic to contribute.
7. One selected Topic allows only that Topic.
8. Multiple selected Topics use union semantics.
9. Switching scope away and back never resets cooldown history.
10. `SELECTED_TOPICS` is never persisted empty. Deleting its last selected Topic is blocked even when reminders are disabled.

### 12.3 Initial settings and active-window closure

11. On first local-store initialization, loading ReminderSettings returns exactly: disabled, `ALL_TOPICS`, `ALL_DAY`, 60-minute interval, 24-hour cooldown; callers do not receive null/unconfigured settings.
12. For same-day `[start, end)`, exactly `start` is inside and exactly `end` is outside.
13. For cross-midnight `[start, end)`, times at/after start or before end are inside; exactly end is outside.
14. Bounded `start == end` is invalid; all-day behavior uses `ALL_DAY` only.

### 12.4 Cooldown / selection

15. Never-shown items are eligible subject to other filters.
16. `now < last_shown_at + cooldown` excludes the item.
17. `now == last_shown_at + cooldown` includes the item.
18. Identical state produces the same deterministic selection.
19. Empty Eligible Pool produces no dispatch and no history update.
20. Duplicate/concurrent evaluations cannot independently commit the same unchanged candidate twice.

### 12.5 Runtime / notification

21. Production interval under 15 minutes is rejected.
22. Foreground evaluation emits no fragmented-study system notification and consumes no history.
23. A late evaluation outside the active window emits nothing and is not replayed as a burst.
24. Changing settings prevents obsolete settings from remaining an independent active cadence.
25. Reboot reconstruction uses current persisted settings when platform policy permits; OPPO proof remains pending until tested.
26. Force Stop continuity is not promised.
27. Missing notification capability does not commit `last_shown_at`.
28. Successful Android notification submission commits dispatch time as `last_shown_at`; user tap is not required.
29. Tapping an accepted notification opens the corresponding full ReviewItem.
30. Dismiss/ignore does not alter the already-started cooldown.

### 12.6 Remote verification

31. A non-developer remote tester can obtain required Diagnostics and copy a diagnostic report without Android Studio/adb.
32. Emulator-only evidence remains `NOT_VERIFIED_ON_DEVICE` for OPPO-specific behavior.
33. An installable Android APK can be produced for remote installation.

---

## 13. OPPO Reno8 Real-Device Matrix

Initial status is `NOT_VERIFIED_ON_DEVICE` for app-background screen-on, lock screen, recent-task swipe-away, ordinary process reclamation/later execution, reboot, notification permission revoke/restore, battery/background restriction enabled, restriction relaxed, several-hours repeated reminders, foreground suppression, and scope changes between opportunities.

Force Stop is not a pass target; it validates `UNSUPPORTED_WHILE_FORCE_STOPPED`.

---

## 14. Platform Evidence Disposition

- Android WorkManager periodic work minimum interval of 15 minutes: **Adopted** for production minimum interval.
- Android 13+ runtime notification permission: **Adopted** for degraded permission semantics.
- Restricted exact-alarm access: **Adopted** as evidence for excluding exact-alarm dependency.
- Android standby/battery timing constraints: **Adopted** into best-effort scheduling semantics.
- Android stopped-state/Force Stop behavior: **Adopted** into `UNSUPPORTED_WHILE_FORCE_STOPPED`.
- Reboot/time-change scheduler restoration mechanisms: **Adopted** as runtime requirements without prescribing implementation mechanics here.
- OPPO background/battery/auto-launch controls: **Adopted** as mandatory real-device verification evidence, not as proof of a Reno8 result.
- OCR library/provider, iOS/iPadOS behavior, cloud architecture: **Deferred** outside current MVP implementation unit.
- AI provider/model: **Not Applicable**.

---

## 15. Invariants

1. Every ReviewItem belongs to exactly one existing Topic.
2. ReminderScope is `ALL_TOPICS` or nonempty `SELECTED_TOPICS`.
3. Reminder disabled state never legalizes an empty `SELECTED_TOPICS`.
4. Multi-Topic scope means union.
5. Topic switching never resets reminder history.
6. Cooldown is never bypassed to force a notification.
7. `last_shown_at` updates only after successful notification submission under an enabled notification state.
8. Tap/dismiss is not cooldown source of truth.
9. `next_eligible_at` is derived from current cooldown plus `last_shown_at`.
10. Selection uses current persisted state at evaluation time.
11. Stale scheduled work cannot authorize behavior forbidden by current settings.
12. Foreground suppression does not consume an item.
13. Missed/outside-window opportunities do not create catch-up bursts.
14. Bounded active windows are always `[start, end)`; `start == end` is invalid.
15. A fresh store always has the defined legal initial ReminderSettings; settings are never semantically null/unconfigured.
16. Emulator evidence cannot become OPPO Reno8 proof.
17. Force Stop continuity is unsupported.
18. Topic deletion cannot orphan ReviewItems or silently widen/empty selected scope.

---

## 16. Planning Boundary

Behavior, architecture, contracts, states, invariants, defaults, active-window boundaries, and acceptance semantics are decided here. Implementation planning may choose concrete Flutter packages, local database schema, repository classes/functions, Android plugins/native integrations, test placement, commands, and commit sequence, but may not change the semantics above.

If planning exposes another missing semantic/architectural decision, planning must return to this Spec instead of deciding it silently.