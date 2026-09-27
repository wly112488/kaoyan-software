# Android 考研碎片复习 App MVP Spec

**Status:** Draft for explicit approval  
**Date:** 2026-09-27  
**Platform:** Android first; target device for real-device acceptance is OPPO Reno8  
**Client framework constraint:** Flutter  
**Authoritative scope:** This document defines the MVP product semantics, architecture boundaries, state/failure semantics, invariants, and acceptance behavior. Exact files, packages, classes, functions, commands, commits, and detailed implementation steps belong to the later implementation plan.

---

## 1. Purpose

The MVP serves postgraduate-exam users who already possess study notes and want to reuse fragmented phone time for passive interruption-based review.

The product stores short study passages as `ReviewItem`s. While the app is not in the foreground, the system periodically attempts to surface one eligible passage through an Android system notification. Users control which coarse-grained topics participate in reminders, how often reminder opportunities occur, which daily time window is allowed, and how long the same item must cool down before it can appear again.

The MVP is not a knowledge-understanding system. It does not split notes into semantic knowledge cards, infer chapters, infer knowledge-point types, summarize with AI, or generate questions.

The product does **not** attempt to detect whether the user is actively scrolling another app or otherwise “using the phone.” Android platform scheduling and notification state are the trigger boundary. The only app-usage condition owned by this product is whether this app itself is currently foregrounded.

---

## 2. Scope

### 2.1 In scope

The MVP owns:

- manual text input and pasted text;
- persistent local `ReviewItem` storage;
- user-managed coarse-grained `Topic`s;
- exactly one Topic per ReviewItem;
- reminder scope over all Topics, one Topic, or multiple Topics;
- a daily allowed reminder window;
- a reminder interval;
- one global repeat cooldown applied to all ReviewItems;
- deterministic eligible-item selection;
- Android system-notification delivery on a best-effort background schedule;
- suppression of reminder notifications while the app is in the foreground;
- persistent reminder state across ordinary app exits/process reclamation and device restarts where the Android/OEM platform permits;
- a remote-test Diagnostics surface;
- APK distribution for remote installation;
- automated, emulator, and OPPO Reno8 real-device verification boundaries.

### 2.2 Explicit non-goals

The MVP does not implement:

- iOS or iPadOS;
- login, account, server, cloud sync, or multi-device sync;
- production OCR;
- AI API integration;
- AI summarization, classification, question generation, or note rewriting;
- chapter recognition;
- semantic knowledge-point types such as person, year, meaning, cause, effect, or significance;
- knowledge graphs;
- multi-level topic trees or subtopics;
- complex tags;
- spaced-repetition algorithms such as SM-2/Ebbinghaus scoring;
- mastery ratings or memory scores;
- social/community/ranking functions;
- commercial/billing functions;
- exact-to-the-minute or exact-to-the-second notification guarantees;
- detection of whether the user is currently using another application.

OCR remains a later capability whose future flow is constrained to: image → OCR text → user edits text → chooses Topic → saves ReviewItem. Its later addition must not require changing the ReviewItem or Topic semantics defined here.

---

## 3. Inputs and Outputs

### 3.1 User inputs

The user can provide:

- ReviewItem text content;
- Topic name;
- ReviewItem Topic assignment;
- reminder enabled/disabled state;
- active reminder window;
- reminder interval;
- repeat cooldown;
- reminder scope: all Topics or an explicit non-empty Topic set.

### 3.2 System outputs

The system produces:

- persisted ReviewItems and Topics;
- the current effective reminder configuration;
- reminder-opportunity evaluations;
- an Android system notification containing a ReviewItem preview when an eligible item can be dispatched;
- navigation to the full ReviewItem when the user taps the notification;
- persisted reminder history required to enforce cooldown;
- Diagnostics state and a copyable diagnostic report.

---

## 4. Core Domain Semantics

## 4.1 ReviewItem

A `ReviewItem` is one user-authored or pasted passage that may be surfaced by reminders.

A ReviewItem owns at least the following semantic state:

- stable identity;
- text content;
- exactly one Topic association;
- enabled/disabled state;
- creation and last-update timestamps;
- `last_shown_at`, whose normative meaning is defined in §9.

A ReviewItem with `enabled = false` remains stored and editable but is excluded from reminder eligibility.

`next_eligible_at` is **derived state**, not an independent source of truth:

```text
if last_shown_at is null:
    next_eligible_at = immediately eligible, subject to other filters
else:
    next_eligible_at = last_shown_at + current repeat_cooldown
```

Therefore, changing the global repeat cooldown changes eligibility immediately for all ReviewItems. No stale per-item cooldown value may override the current setting.

A ReviewItem is cooldown-eligible at the exact boundary when:

```text
now >= next_eligible_at
```

## 4.2 Topic

A `Topic` is a user-managed coarse category such as 医学、生物、历史、政治、英语、数学、专业课.

Topic names are user-defined and are not hard-coded as a fixed taxonomy.

Topic identity is stable and independent of its display name. Renaming a Topic preserves all ReviewItem associations and reminder-scope references to that Topic identity.

After trimming leading/trailing whitespace, Topic names must be non-empty and unique under case-insensitive comparison.

Every ReviewItem must reference exactly one existing Topic. The MVP does not allow an unassigned ReviewItem.

### Topic deletion

Topic deletion is fail-safe and must not silently lose study content:

- a Topic referenced by one or more ReviewItems cannot be deleted;
- the user must first move or delete those ReviewItems;
- an empty Topic may be deleted;
- if an empty Topic is part of an explicit multi-Topic reminder scope, deleting it removes that Topic from the scope when at least one selected Topic remains;
- if deleting an empty Topic would leave an explicit reminder scope with zero selected Topics, deletion is blocked until the user changes the reminder scope or disables reminders;
- deleting an empty Topic while reminder scope is `ALL_TOPICS` does not alter the scope mode.

## 4.3 ReminderScope

Reminder scope has exactly two valid modes:

1. `ALL_TOPICS` — every existing Topic may contribute eligible ReviewItems.
2. `SELECTED_TOPICS` — only ReviewItems whose Topic identity is in a persisted, non-empty selected Topic set may contribute.

Single-Topic selection is `SELECTED_TOPICS` with one Topic. Multi-Topic selection is `SELECTED_TOPICS` with more than one Topic.

Multi-Topic selection uses union semantics:

```text
Topic A + Topic B = items in Topic A ∪ items in Topic B
```

It never means that an item must belong to multiple Topics.

Changing ReminderScope affects only future candidate filtering. It does not change or clear:

- `last_shown_at`;
- derived `next_eligible_at`;
- enabled state;
- ReviewItem history.

---

## 5. Reminder Settings Semantics

Reminder settings contain the following product-level state:

- `reminder_enabled`;
- active reminder window;
- `reminder_interval`;
- `repeat_cooldown`;
- ReminderScope.

### 5.1 Reminder interval

The production MVP supports reminder intervals of **15 minutes or greater**. The UI may offer presets and/or a custom value, but any production value below 15 minutes is invalid.

The interval is a target cadence between reminder opportunities, not a guarantee that Android will execute at an exact wall-clock time.

When reminders transition from disabled to enabled, the first normal reminder opportunity is due no earlier than one configured reminder interval later. Enabling reminders does not immediately interrupt the user.

Changing the interval replaces the prior cadence for future opportunities. Old scheduling state must not continue producing reminders under the previous interval.

Debug/test builds may expose 1/2/5-minute test controls for verification, but those controls are not valid production settings and must not alter the production minimum interval contract.

### 5.2 Active reminder window

The user may configure either:

- `ALL_DAY`; or
- one bounded daily window with a start time and end time.

For a bounded window:

- start < end means a same-day window, e.g. 08:00–23:00;
- start > end means a window crossing midnight, e.g. 22:00–01:00;
- start = end is invalid; users who want 24-hour availability use `ALL_DAY`.

No reminder notification may be dispatched outside the active window.

If a reminder opportunity is delayed by Android/OEM scheduling and executes outside the allowed window, that opportunity is skipped. The system does not “catch up” by emitting missed reminders in a burst.

### 5.3 Repeat cooldown

`repeat_cooldown` is a single current setting applied to all ReviewItems.

Changing cooldown is effective immediately and recalculates eligibility from each item’s existing `last_shown_at` under the new cooldown. It does not clear history.

---

## 6. Architecture and Responsibility Boundaries

The MVP has five logical responsibility boundaries.

### 6.1 Presentation boundary

Owns:

- ReviewItem list and detail/edit flows;
- Topic management;
- reminder settings and reminder scope controls;
- permission/degraded-state messaging;
- Diagnostics UI.

It does not own reminder selection or Android background scheduling semantics.

### 6.2 Local domain/data boundary

Owns authoritative persisted state for:

- ReviewItems;
- Topics;
- reminder settings;
- ReminderScope;
- reminder dispatch/history state needed by eligibility;
- diagnostic scheduling outcomes needed for remote verification.

Storage is local-only for the MVP. No server is a source of truth.

### 6.3 Reminder evaluation boundary

Owns the deterministic sequence:

```text
current persisted settings
→ reminder-enabled check
→ active-window check
→ foreground check
→ notification-capability check
→ ReviewItem enabled filter
→ ReminderScope / Topic filter
→ cooldown filter
→ deterministic selection
→ notification dispatch attempt
→ reminder-state commit on successful dispatch request
```

A scheduling trigger requests an **evaluation**, not a preselected content-specific notification. Item selection occurs against current persisted state at evaluation time. This prevents stale scheduled notifications from surfacing deleted, disabled, moved, or out-of-scope content.

### 6.4 Android scheduling/notification boundary

Owns interaction with Android background execution and system notifications.

MVP scheduling is explicitly **best-effort/inexact**. Exact-alarm capability is not required by the product and the MVP must not depend on exact-alarm permission for its normal behavior.

The Android boundary must preserve persisted product intent across ordinary process death and restore/reschedule reminder evaluation after device restart where platform conditions permit.

### 6.5 Diagnostics boundary

Owns read-only exposure of runtime facts needed by a remote non-developer tester. Diagnostics must not become an alternate control path that bypasses normal reminder invariants.

---

## 7. Eligible Selection Contract

At each reminder evaluation, the candidate pool is computed from current persisted state in this exact order:

```text
All ReviewItems
→ keep enabled ReviewItems
→ keep ReviewItems permitted by current ReminderScope
→ keep ReviewItems with last_shown_at = null OR now >= last_shown_at + repeat_cooldown
→ Eligible Pool
```

If the Eligible Pool is empty, the evaluation ends without sending a reminder and without changing any ReviewItem’s `last_shown_at`.

The MVP selection rule is deterministic:

1. ReviewItems never successfully dispatched before (`last_shown_at = null`) come first;
2. among never-shown items, earlier `created_at` comes first;
3. otherwise the item with the oldest `last_shown_at` comes first;
4. ties are broken by stable ReviewItem identity.

This rule avoids short-term repetition without introducing random or adaptive recommendation behavior.

Selection and the successful-dispatch state update form one logical exclusivity boundary: two concurrent/duplicate reminder evaluations must not both select and commit the same ReviewItem based on the same pre-update state. The implementation must serialize or otherwise make this transition atomic enough to preserve that invariant.

---

## 8. Application and Device State Semantics

## 8.1 App foreground

When the app is in the foreground, scheduled reminder evaluations may occur, but they must not display the fragmented-study system notification.

Foreground suppression:

- does not update `last_shown_at`;
- does not consume or reserve a ReviewItem;
- does not trigger catch-up reminders when the app later backgrounds;
- leaves the next normal reminder opportunity on the configured cadence.

## 8.2 App background / locked screen

When the app is not in the foreground and the device/platform permits background execution, the system may evaluate and dispatch a reminder subject to all other rules.

Locked-screen presentation follows Android notification and user privacy/settings behavior. The app does not guarantee that full study text will be visible on a lock screen.

## 8.3 Process reclaimed

Ordinary Android process reclamation must not erase persisted ReviewItems, Topics, settings, scope, or `last_shown_at`. Reminder intent remains enabled and should resume through the platform scheduling mechanism without requiring the process to remain resident.

## 8.4 Recent-task swipe-away

Swiping the app away from Recents is not specified as equivalent to Android Force Stop. The product expects persisted reminder intent to remain, but actual OPPO Reno8/ColorOS behavior is `NOT_VERIFIED_ON_DEVICE` until real-device evidence exists.

## 8.5 Force Stop

A user-initiated system Force Stop places the app outside the MVP’s guarantee boundary. The app must not claim that reminders continue after Force Stop.

Reminder behavior after Force Stop is `UNSUPPORTED_WHILE_FORCE_STOPPED` until the user explicitly launches/interacts with the app again and Android removes the stopped state.

No diagnostic or UI wording may represent Force Stop continuity as guaranteed.

## 8.6 Device reboot

If reminders were enabled before reboot, the persisted intent remains enabled. After Android boot/unlock and subject to platform/OEM rules, the app must restore or allow restoration of the reminder schedule from the persisted current settings rather than from stale pre-reboot in-memory state.

Reboot behavior on OPPO Reno8 remains `NOT_VERIFIED_ON_DEVICE` until real-device testing.

## 8.7 App update

An app update must preserve local domain state. After update, reminder scheduling must reflect the latest persisted current configuration. Pre-update scheduling artifacts must not create a second independent reminder cadence.

## 8.8 System time / timezone change

All wall-clock active-window evaluation uses the device’s current local time zone at evaluation time.

Cooldown is elapsed-duration semantics from `last_shown_at`; changing the displayed timezone must not intentionally reset cooldown history.

After system time/timezone changes, future reminder evaluation must use the current system clock/configuration. The implementation must avoid maintaining a permanently stale schedule based solely on the old timezone.

---

## 9. Notification Semantics

A reminder notification contains:

- application identity/title;
- a preview of the selected ReviewItem text, truncated by normal Android notification presentation if necessary;
- a tap action that opens the app to the full selected ReviewItem.

The MVP does not add memory-rating actions, quizzes, or mastery buttons.

### 9.1 Normative meaning of `last_shown_at`

`last_shown_at` means the time at which the app **successfully submitted the selected ReviewItem as a notification to Android’s notification service under an enabled app/channel notification state**.

It does not mean:

- time the notification was merely scheduled;
- time the user tapped it;
- time the user dismissed it;
- guaranteed time a banner became visually visible to the user.

Android/OEM/DND/lock-screen policies can affect visual presentation after dispatch. The app cannot reliably prove human visibility and must not encode that stronger meaning into `last_shown_at`.

If notification permission is denied, app notifications are disabled, or the dispatch fails before successful submission, the ReviewItem’s `last_shown_at` is not updated.

If Android accepts the notification but later presents it silently or suppresses alerting because of system policy such as Do Not Disturb, the dispatch still counts for cooldown because the app cannot reliably observe a stronger user-visibility guarantee.

Notification tap/dismiss events do not change cooldown in the MVP.

---

## 10. Permission and Platform Constraints

### 10.1 Notification permission

On Android versions requiring runtime notification permission, reminders are operational only after the required permission is granted and the relevant app/channel notification state permits posting.

If notifications are not permitted:

- reminders enter `DEGRADED_NOTIFICATION_PERMISSION`;
- no ReviewItem is marked shown merely because a background evaluation occurred;
- the app surfaces a user-actionable explanation and route to the appropriate permission/settings surface where feasible;
- persisted reminder settings remain intact so normal behavior can resume after permission is restored.

### 10.2 Exact alarms

The MVP does not require exact wall-clock delivery and does not depend on `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM` as a normal product prerequisite.

Android may defer best-effort periodic work because of Doze, App Standby, battery policy, background restrictions, OEM policy, or device conditions. Such delay is allowed by this Spec and is not itself a product-contract failure.

### 10.3 OPPO / ColorOS

OPPO/ColorOS exposes battery/background/auto-launch controls that can affect background execution. The product may diagnose and explain likely restrictions, but it must not claim that it can bypass OEM controls.

Any OPPO-specific settings guidance must be based on detected/known ColorOS behavior and must be treated as assistance, not as an unconditional guarantee.

Until tested on the actual OPPO Reno8 target device, the following remain `NOT_VERIFIED_ON_DEVICE`:

- long-running periodic reminder stability;
- reminder continuity after recent-task swipe-away;
- reboot recovery;
- behavior under OPPO battery/background restrictions;
- lock-screen notification behavior;
- recovery after the remote user changes relevant ColorOS settings.

---

## 11. Failure and Degraded-State Semantics

| Condition | Required behavior |
|---|---|
| Reminder disabled | No reminder notification; persisted content/settings remain intact. |
| No Topic exists | No ReviewItem can be newly saved until a Topic is created; reminders cannot produce content. |
| Current scope is `ALL_TOPICS` but no Topic/items exist | Evaluation ends with no notification. |
| Current selected Topics contain no ReviewItems | Evaluation ends with no notification. |
| Matching ReviewItems exist but all are in cooldown | Evaluation ends with no notification; cooldown is not bypassed. |
| Notification permission/app notification disabled | Enter degraded permission state; do not update `last_shown_at`. |
| App foreground | Suppress fragmented-study notification; do not update `last_shown_at`. |
| Outside active window | Skip that opportunity; do not catch up with a burst later. |
| Local storage read fails | Do not dispatch an unverified/stale item; record a diagnostic failure outcome. |
| Scheduling request fails | Persist user intent; expose diagnostic degraded state; do not silently claim reminder is active. |
| OEM/background policy delays execution | Accept delay as platform degradation; preserve current configuration and report observable status. |
| Force Stop | No continuity guarantee until user relaunches/interacts with the app. |
| Topic deletion would orphan ReviewItems | Block deletion. |
| Topic deletion would make `SELECTED_TOPICS` empty | Block deletion until scope changes or reminders are disabled. |
| ReviewItem deleted/disabled/moved after a future reminder trigger was scheduled | Because item selection occurs at evaluation time, deleted/disabled/out-of-scope content must not be selected. |
| Reminder settings changed | Future evaluation must use only current persisted settings; stale settings must not remain an independent active cadence. |

No failure path may silently widen ReminderScope, ignore cooldown, or substitute another Topic merely to ensure that a notification is emitted.

---

## 12. Persistence and Source of Truth

The MVP uses one local persistent store as the authoritative source for product state.

Authoritative state includes:

- Topics;
- ReviewItems;
- current ReminderSettings;
- current ReminderScope;
- `last_shown_at`;
- minimal diagnostic scheduling/dispatch outcomes needed for support and verification.

Derived values such as `next_eligible_at` and Eligible Pool membership are computed from authoritative state and the current clock/settings.

Android scheduler metadata is not an independent product source of truth. If scheduler metadata and persisted product configuration disagree, the persisted current product configuration governs what an evaluation is allowed to do.

The implementation plan may choose the concrete Flutter persistence package/schema, but it may not change these ownership rules.

---

## 13. User Flows

### 13.1 First-use content flow

```text
Open app
→ create at least one Topic
→ add/paste one passage
→ select exactly one Topic
→ save ReviewItem
```

### 13.2 Reminder setup flow

```text
Open Reminder Settings
→ choose enabled
→ choose active window
→ choose interval (>= 15 min production)
→ choose repeat cooldown
→ choose ALL_TOPICS or non-empty SELECTED_TOPICS
→ save
→ system establishes future best-effort reminder evaluation
```

### 13.3 Multi-topic flow

```text
Select 医学 + 生物
→ current scope is union of items from both Topics
→ apply enabled filter
→ apply cooldown filter
→ deterministic oldest/never-shown selection
```

### 13.4 Notification flow

```text
Background reminder opportunity
→ evaluate current state
→ if eligible item exists and notifications are permitted
→ submit system notification
→ commit last_shown_at on successful notification submission
→ user may tap notification
→ open full ReviewItem
```

### 13.5 Topic-switch flow

```text
Current scope: 医学 + 生物
→ switch to 历史
→ no ReviewItem history is reset
→ later switch back to 医学
→ previous 医学 cooldown state still applies
```

---

## 14. Diagnostics and Remote Verification

The actual OPPO Reno8 is held remotely by a non-developer tester. The app therefore requires a Diagnostics surface sufficient for remote black-box verification without Android Studio, adb, command line, or system-log access.

Diagnostics must expose at least:

- device model;
- Android version;
- app version/build identity;
- notification permission/app notification capability state;
- reminder enabled state;
- active reminder window;
- reminder interval;
- repeat cooldown;
- current ReminderScope mode and selected Topic names/IDs;
- total ReviewItem count;
- currently scope-matching ReviewItem count;
- current Eligible Pool count;
- most recent reminder-evaluation time;
- most recent evaluation outcome category;
- most recent successful notification-dispatch time;
- most recently dispatched ReviewItem identity and Topic identity;
- next expected reminder opportunity as a **best-effort estimate**, clearly not an exact guarantee;
- observable scheduler/degraded status;
- observable notification/background restrictions the app can detect;
- verification status for OPPO-specific behaviors.

Diagnostics provides one action to copy a compact text report for remote sharing.

The copied report should use identifiers and state rather than copying full study-note content unless the user explicitly chooses to include content. This minimizes accidental disclosure of personal notes.

Diagnostics may provide a debug-only “test reminder/evaluate now” capability, but it must use the same eligibility and cooldown rules unless explicitly labeled as a separate diagnostic probe. Production reminder semantics must not be weakened for testing.

---

## 15. Verification Status Model

Behavior evidence is classified as:

- `VERIFIED_AUTOMATED` — directly proven by automated tests of product/domain behavior;
- `VERIFIED_EMULATOR` — observed on a supported Android emulator environment;
- `VERIFIED_ON_OPPO_RENO8` — observed on the real target device under a documented test condition;
- `NOT_VERIFIED_ON_DEVICE` — implementation may exist, but real OPPO Reno8 evidence does not yet exist;
- `UNSUPPORTED_WHILE_FORCE_STOPPED` — Android stopped-state boundary where continuity is not promised.

Emulator success may not be promoted to `VERIFIED_ON_OPPO_RENO8`.

Real-device verification must record the ColorOS/Android version because OEM behavior may differ by system version.

---

## 16. Acceptance Criteria

The MVP is behaviorally acceptable only when the following are satisfied.

### 16.1 ReviewItem and Topic

1. Given an existing Topic, when the user saves a non-empty passage assigned to that Topic, then the ReviewItem persists after app restart.
2. Given an existing ReviewItem, when the user edits its text or Topic, then the current value persists and prior `last_shown_at` is not reset merely because content/Topic changed.
3. Given a Topic with ReviewItems, when the user attempts to delete the Topic, then deletion is blocked and no ReviewItem becomes orphaned.
4. Given an empty Topic, when it is renamed, then its identity and any ReminderScope reference remain stable.
5. Given duplicate Topic-name input after normalization, when the user attempts to save it, then the system rejects the duplicate.

### 16.2 ReminderScope

6. Given `ALL_TOPICS`, when eligibility is evaluated, then any enabled Topic may contribute candidates.
7. Given one selected Topic, when eligibility is evaluated, then only that Topic may contribute candidates.
8. Given multiple selected Topics, when eligibility is evaluated, then candidates are the union of those Topics.
9. Given an item recently shown under Topic A, when the user changes to Topic B and later returns to Topic A, then the prior Topic A cooldown still applies.
10. Given an explicit selected scope, when deletion of its last selected Topic is attempted, then deletion is blocked rather than silently widening the scope.

### 16.3 Cooldown and selection

11. Given `last_shown_at = null`, when all other filters pass, then the ReviewItem is eligible.
12. Given `now < last_shown_at + repeat_cooldown`, when eligibility is evaluated, then the ReviewItem is excluded.
13. Given `now = last_shown_at + repeat_cooldown`, when eligibility is evaluated, then the ReviewItem is eligible.
14. Given multiple eligible items, when selection runs repeatedly over identical state, then it returns the same deterministic item according to §7.
15. Given no eligible item, when a reminder evaluation occurs, then no notification is submitted and no `last_shown_at` changes.
16. Given two duplicate/concurrent reminder evaluations, when both observe overlapping candidates, then the system does not commit the same unchanged candidate twice as two independent reminder dispatches.

### 16.4 Scheduling and foreground behavior

17. Given reminders enabled with a production interval under 15 minutes, when settings are saved, then the value is rejected as invalid.
18. Given reminders enabled and the app foregrounded, when an evaluation occurs, then no fragmented-study system notification is emitted and no item history is consumed.
19. Given an evaluation outside the active window, when the scheduler runs late, then no reminder is emitted and missed opportunities are not replayed in a burst.
20. Given reminder settings are changed, when future evaluations run, then old settings do not continue as an independent active cadence.
21. Given the device reboots, when the platform permits post-boot restoration and the app had reminders enabled, then reminder intent is reconstructed from persisted current settings; OPPO Reno8 proof remains `NOT_VERIFIED_ON_DEVICE` until tested.
22. Given the user Force Stops the app, then the product does not claim reminder continuity until the user relaunches/interacts with the app.

### 16.5 Notification semantics

23. Given notification permission is denied/notifications disabled, when an evaluation finds an eligible item, then no `last_shown_at` is committed and the app exposes a degraded permission state.
24. Given notification submission succeeds, when the state commit completes, then `last_shown_at` equals the dispatch time used for cooldown semantics; user tap is not required.
25. Given a successfully submitted notification, when the user taps it, then the app opens the corresponding full ReviewItem.
26. Given the user dismisses or ignores a successfully submitted notification, then cooldown is unchanged from the successful-dispatch state.

### 16.6 Diagnostics and remote use

27. Given a remote tester with no development tools, when Diagnostics is opened, then all required fields in §14 are visible and a copyable diagnostic report can be produced.
28. Given emulator-only evidence, when verification status is displayed/reported, then OPPO-specific behavior remains `NOT_VERIFIED_ON_DEVICE`.
29. Given an OPPO Reno8 test build, when the project is built for remote distribution, then an installable APK can be produced without requiring the remote tester to use Android Studio or adb.

---

## 17. Required OPPO Reno8 Real-Device Verification Matrix

Before OPPO-specific reminder reliability can be considered verified, the remote tester must execute and record at least:

| Scenario | Initial status |
|---|---|
| App background, screen on | `NOT_VERIFIED_ON_DEVICE` |
| Lock screen | `NOT_VERIFIED_ON_DEVICE` |
| Recent-task swipe-away | `NOT_VERIFIED_ON_DEVICE` |
| Ordinary process reclamation / later background execution | `NOT_VERIFIED_ON_DEVICE` |
| Device reboot | `NOT_VERIFIED_ON_DEVICE` |
| Notification permission denied then restored | `NOT_VERIFIED_ON_DEVICE` |
| Battery/background restriction enabled | `NOT_VERIFIED_ON_DEVICE` |
| Battery/background restriction relaxed where user-accessible | `NOT_VERIFIED_ON_DEVICE` |
| Long-running repeated reminders across several hours | `NOT_VERIFIED_ON_DEVICE` |
| App foreground during an otherwise due opportunity | `NOT_VERIFIED_ON_DEVICE` |
| Topic scope change between reminder opportunities | `NOT_VERIFIED_ON_DEVICE` |

Force Stop is not a scenario to “make pass”; it validates the documented `UNSUPPORTED_WHILE_FORCE_STOPPED` boundary.

---

## 18. Shared Dependencies and Platform Evidence

### 18.1 Project constraints

- Flutter is the client framework constraint for the project so later iOS/iPadOS expansion does not require replacing the whole product layer.
- MVP persistence is local-only.
- Android system notification is the only production reminder presentation surface.
- Exact alarm permission is not an MVP prerequisite.

### 18.2 Platform evidence dispositions

The following evidence affects this design:

1. **Android WorkManager periodic-work minimum interval: 15 minutes** — **Adopted** as the production minimum reminder interval and as evidence that periodic background timing is not a sub-minute exact scheduler.  
   Source: https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work

2. **Android 13+ runtime notification permission (`POST_NOTIFICATIONS`)** — **Adopted** into permission/degraded-state semantics.  
   Source: https://developer.android.com/about/versions/13/behavior-changes-all

3. **Android exact-alarm access is restricted and Android 14 denies `SCHEDULE_EXACT_ALARM` by default for many new installs targeting modern SDKs** — **Adopted** as evidence for excluding exact-alarm dependency from this non-exact study reminder MVP.  
   Sources:  
   https://developer.android.com/develop/background-work/services/alarms  
   https://developer.android.com/about/versions/14/behavior-changes-all

4. **Android background work is subject to platform standby/battery timing constraints** — **Adopted** into the best-effort scheduling contract rather than treated as a bug in the product contract.  
   Sources:  
   https://developer.android.com/topic/performance/appstandby  
   https://developer.android.com/reference/kotlin/androidx/work/package-summary

5. **Android stopped-state / Force Stop blocks ordinary background continuity until user action; Android 15 further cancels pending intents when the app enters the stopped state** — **Adopted** into `UNSUPPORTED_WHILE_FORCE_STOPPED`.  
   Source: https://developer.android.com/about/versions/15/behavior-changes-all

6. **Android reboot requires scheduler restoration semantics; Android background APIs support reboot/time-change rescheduling mechanisms** — **Adopted** into reboot/time-change recovery requirements without prescribing the later implementation-plan mechanism.  
   Sources:  
   https://developer.android.com/develop/background-work/services/alarms  
   https://developer.android.com/reference/androidx/work/package-summary

7. **OPPO exposes background activity/battery and auto-launch controls that can affect timely background behavior** — **Adopted** into OEM degraded-state handling and mandatory Reno8 verification, but **not** treated as proof of a specific Reno8 result before testing.  
   Sources:  
   https://support.oppo.com/en/answer/?aid=2171043  
   https://support.oppo.com/co/answer/?aid=neu119

### 18.3 Deferred evidence/decisions

- OCR library/provider selection — **Deferred** to the later OCR capability; not needed for MVP implementation planning.
- iOS/iPadOS notification behavior — **Deferred**; outside current platform scope.
- Cloud synchronization architecture — **Deferred**; outside current product scope.
- AI provider/model selection — **Not Applicable** to the MVP because AI is not in scope.

---

## 19. Invariants

The implementation must preserve all of the following:

1. Every ReviewItem belongs to exactly one existing Topic.
2. ReminderScope is either `ALL_TOPICS` or `SELECTED_TOPICS` with a non-empty valid Topic set.
3. Multi-Topic scope means union.
4. Topic switching never resets ReviewItem reminder history.
5. Cooldown cannot be bypassed merely to produce a notification.
6. `last_shown_at` is updated only after a successful notification submission under an enabled notification state.
7. User tap/dismiss is not the cooldown source of truth.
8. `next_eligible_at` is derived from the current cooldown and `last_shown_at`, not a conflicting independent authority.
9. Item selection occurs at reminder-evaluation time from current persisted state.
10. Stale scheduled work cannot authorize a notification that current persisted settings would forbid.
11. Foreground app state suppresses fragmented-study notification and does not consume an item.
12. Outside-window/missed opportunities do not create catch-up bursts.
13. No platform/OEM best-effort behavior may be presented as an exact guarantee.
14. Emulator evidence cannot be promoted to OPPO Reno8 real-device verification.
15. Force Stop continuity is outside the supported guarantee boundary.
16. Deleting a Topic cannot orphan ReviewItems or silently widen ReminderScope.

---

## 20. Spec Readiness

This Spec closes the MVP’s product behavior, architecture boundaries, Topic/ReviewItem/ReminderScope contracts, reminder selection semantics, notification-state semantics, Android lifecycle boundary, failure/degraded behavior, remote verification semantics, and acceptance criteria.

The remaining work is implementation mechanics: concrete Flutter packages, local database schema/package, Android plugin/native integration details, exact file/class/function boundaries, test framework placement, build commands, task sequence, and commits. Those belong to `writing-plans`.

The Spec is therefore **implementation-ready pending explicit user approval**. If implementation planning discovers a missing semantic or architectural decision, planning must stop and return that issue to this Spec rather than silently deciding it in the plan.
