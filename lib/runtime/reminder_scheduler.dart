import 'dart:async';

import 'package:workmanager/workmanager.dart';

import 'android_reminder_alarm_port.dart';
import 'exact_reminder_alarm_port.dart';
import '../data/local/app_database.dart';
import '../data/local/reminder_runtime_state_repository.dart';
import '../data/local/reminder_settings_repository.dart';
import '../data/local/review_item_repository.dart';
import '../data/local/topic_repository.dart';
import '../domain/active_window.dart';
import '../domain/reminder_settings.dart';
import '../domain/repeat_cooldown_policy.dart';
import '../domain/review_item.dart';
import '../domain/topic.dart';

const reminderUniqueWorkName = 'kaoyan_review.next_reminder';
const reminderWorkerTaskName = 'reminder_evaluation';
const legacyReminderUniqueWorkName = 'kaoyan_review.periodic_reminder';

enum ReminderWorkPolicy { replace, keep, append }

abstract interface class ReminderWorkPort {
  Future<void> register({
    required Duration initialDelay,
    ReminderWorkPolicy policy = ReminderWorkPolicy.replace,
  });
  Future<void> cancel();
}

typedef PeriodicWorkPort = ReminderWorkPort;

final class WorkmanagerOneOffWorkPort implements ReminderWorkPort {
  @override
  Future<void> register({
    required Duration initialDelay,
    ReminderWorkPolicy policy = ReminderWorkPolicy.replace,
  }) async {
    // Remove periodic work created by earlier app versions. Its task name is
    // no longer handled by the current dispatcher, but it would otherwise
    // keep waking the app indefinitely after an upgrade.
    await Workmanager().cancelByUniqueName(legacyReminderUniqueWorkName);
    await Workmanager().registerOneOffTask(
      reminderUniqueWorkName,
      reminderWorkerTaskName,
      // The Android bridge serializes in whole seconds (inSeconds truncates).
      // Round up so a due boundary cannot become an immediate retry loop.
      initialDelay: Duration(
        seconds:
            (initialDelay.inMicroseconds +
                Duration.microsecondsPerSecond -
                1) ~/
            Duration.microsecondsPerSecond,
      ),
      existingWorkPolicy: switch (policy) {
        ReminderWorkPolicy.keep => ExistingWorkPolicy.keep,
        ReminderWorkPolicy.replace => ExistingWorkPolicy.replace,
        // The installed Android plugin maps update to APPEND_OR_REPLACE.
        // A running Worker must append its successor, not cancel itself.
        ReminderWorkPolicy.append => ExistingWorkPolicy.update,
      },
    );
  }

  @override
  Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(legacyReminderUniqueWorkName);
    await Workmanager().cancelByUniqueName(reminderUniqueWorkName);
  }
}

final class ExactAlarmReminderWorkPort implements ReminderWorkPort {
  ExactAlarmReminderWorkPort({
    required this.alarm,
    required this.fallback,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ExactReminderAlarmPort alarm;
  final ReminderWorkPort fallback;
  final DateTime Function() _now;

  @override
  Future<void> register({
    required Duration initialDelay,
    ReminderWorkPolicy policy = ReminderWorkPolicy.replace,
  }) async {
    var scheduled = false;
    try {
      if (await alarm.canScheduleExactAlarms()) {
        scheduled = await alarm.schedule(
          _now().add(initialDelay),
          keepExisting: policy == ReminderWorkPolicy.keep,
        );
      }
    } catch (_) {
      // A platform/permission failure must not break the fallback chain.
    }
    if (scheduled) {
      if (policy != ReminderWorkPolicy.append) await fallback.cancel();
      return;
    }
    await alarm.cancel();
    await fallback.register(initialDelay: initialDelay, policy: policy);
  }

  @override
  Future<void> cancel() async {
    await alarm.cancel();
    await fallback.cancel();
  }
}

final class ReminderScheduler {
  static Future<void> _reconcileTail = Future<void>.value();

  ReminderScheduler({required AppDatabase store, ReminderWorkPort? work})
    : _store = store,
      _work =
          work ??
          ExactAlarmReminderWorkPort(
            alarm: AndroidReminderAlarmPort(),
            fallback: WorkmanagerOneOffWorkPort(),
          ),
      _settings = ReminderSettingsRepository(store),
      _items = ReviewItemRepository(store),
      _topics = TopicRepository(store),
      _runtime = ReminderRuntimeStateRepository(store);

  final AppDatabase _store;
  final ReminderWorkPort _work;
  final ReminderSettingsRepository _settings;
  final ReviewItemRepository _items;
  final TopicRepository _topics;
  final ReminderRuntimeStateRepository _runtime;

  Future<DateTime?> nextOpportunityAt({DateTime? now}) async {
    final settings = await _settings.loadSettings();
    if (!settings.enabled) return null;
    final items = await _items.listReviewItems();
    final topics = await _topics.listTopics();
    final runtime = await _runtime.loadState();
    return _calculateNextOpportunity(
      settings: settings,
      items: items,
      topics: topics,
      lastDispatchAt: runtime.lastDispatchAt,
      lastEvaluationAt: runtime.lastEvaluationAt,
      lastEvaluationOutcome: runtime.lastEvaluationOutcome,
      now: now ?? DateTime.now(),
    );
  }

  Future<bool> reconcile(
    ReminderSettings settings, {
    DateTime? now,
    Duration minimumDelay = Duration.zero,
    ReminderWorkPolicy policy = ReminderWorkPolicy.replace,
  }) {
    final previous = _reconcileTail;
    final done = Completer<void>();
    _reconcileTail = done.future;
    return _reconcileQueued(
      previous: previous,
      done: done,
      settings: settings,
      now: now,
      minimumDelay: minimumDelay,
      policy: policy,
    );
  }

  Future<bool> _reconcileQueued({
    required Future<void> previous,
    required Completer<void> done,
    required ReminderSettings settings,
    required DateTime? now,
    required Duration minimumDelay,
    required ReminderWorkPolicy policy,
  }) async {
    await previous;
    try {
      return await _reconcileNow(
        settings,
        now: now,
        minimumDelay: minimumDelay,
        policy: policy,
      );
    } finally {
      done.complete();
    }
  }

  Future<bool> _reconcileNow(
    ReminderSettings settings, {
    DateTime? now,
    required Duration minimumDelay,
    required ReminderWorkPolicy policy,
  }) async {
    final localNow = now ?? DateTime.now();
    final utcNow = localNow.toUtc();
    final db = await _store.database;
    try {
      if (!settings.enabled) {
        await _work.cancel();
        await _runtime.recordSchedule(
          db,
          at: utcNow,
          status: ReminderScheduleStatus.disabled,
          error: null,
        );
        return true;
      }

      final items = await _items.listReviewItems();
      final topics = await _topics.listTopics();
      final runtime = await _runtime.loadState();
      final due = _calculateNextOpportunity(
        settings: settings,
        items: items,
        topics: topics,
        lastDispatchAt: runtime.lastDispatchAt,
        lastEvaluationAt: runtime.lastEvaluationAt,
        lastEvaluationOutcome: runtime.lastEvaluationOutcome,
        now: localNow,
      );
      if (due == null) {
        await _work.cancel();
      } else {
        final minDue = localNow.add(minimumDelay);
        final scheduledAt = due.isAfter(minDue) ? due : minDue;
        final delay = scheduledAt.difference(localNow);
        await _work.register(
          initialDelay: delay.isNegative ? Duration.zero : delay,
          policy: policy,
        );
      }
      await _runtime.recordSchedule(
        db,
        at: utcNow,
        status: due == null
            ? ReminderScheduleStatus.notScheduled
            : ReminderScheduleStatus.scheduled,
        error: null,
      );
      return true;
    } catch (error) {
      await _runtime.recordSchedule(
        db,
        at: utcNow,
        status: ReminderScheduleStatus.failed,
        error: error.toString(),
      );
      return false;
    }
  }

  DateTime? _calculateNextOpportunity({
    required ReminderSettings settings,
    required List<ReviewItem> items,
    required List<Topic> topics,
    required DateTime? lastDispatchAt,
    required DateTime? lastEvaluationAt,
    required String? lastEvaluationOutcome,
    required DateTime now,
  }) {
    final active = items.where((item) {
      return item.enabled && settings.scope.allows(item.topicId);
    }).toList();
    if (active.isEmpty) return null;

    final topicById = <int, Topic>{for (final topic in topics) topic.id: topic};
    var globalDue = lastDispatchAt == null
        ? now
        : _maxDate(
            now,
            lastDispatchAt.toLocal().add(settings.reminderInterval),
          );
    if ((lastEvaluationOutcome == 'notificationUnavailable' ||
            lastEvaluationOutcome == 'foregroundSuppressed') &&
        lastEvaluationAt != null) {
      globalDue = _maxDate(
        globalDue,
        lastEvaluationAt.toLocal().add(settings.reminderInterval),
      );
    }
    DateTime? earliest;

    // Cooldowns may be as long as 30 days. Include a full extra week so a
    // weekly topic plan can reach its next eligible weekday after that wait.
    for (var dayOffset = 0; dayOffset <= 37; dayOffset++) {
      final date = DateTime(now.year, now.month, now.day + dayOffset);
      final weekdayTopics = settings.weeklyTopicIds[date.weekday];
      if (settings.hasWeeklyTopicPlan && weekdayTopics == null) continue;
      final daily = active.where((item) {
        if (weekdayTopics == null) return true;
        if (!weekdayTopics.contains(item.topicId)) return false;
        return settings.scope.allows(item.topicId);
      }).toList();
      if (daily.isEmpty) continue;
      final effectiveCooldown = effectiveRepeatCooldown(
        maximumCooldown: settings.repeatCooldown,
        globalInterval: settings.reminderInterval,
        activeContentCount: daily.length,
      );

      final unseen = daily.where((item) => item.lastShownAt == null).toList()
        ..sort(_compareFifo);
      final candidates = unseen.isNotEmpty
          ? unseen
          : daily.where((item) => item.lastShownAt != null).toList();
      if (unseen.isEmpty) candidates.sort(_compareLru);

      DateTime? dueFor(ReviewItem item) {
        final topic = topicById[item.topicId];
        final topicInterval = _maxDuration(
          settings.reminderInterval,
          topic?.reminderInterval ?? settings.reminderInterval,
        );
        var due = globalDue;
        final topicLast = topic?.lastRemindedAt;
        if (topicLast != null) {
          due = _maxDate(due, topicLast.toLocal().add(topicInterval));
        }
        final lastShown = item.lastShownAt;
        if (lastShown != null) {
          due = _maxDate(
            due,
            lastShown.toLocal().add(
              _maxDuration(effectiveCooldown, topicInterval),
            ),
          );
        }
        final dayStart = DateTime(date.year, date.month, date.day);
        final nextDay = dayStart.add(const Duration(days: 1));
        if (due.isBefore(dayStart)) due = dayStart;
        if (!due.isBefore(nextDay)) return null;
        return _fitActiveWindow(due, date, settings.activeWindow);
      }

      final dayDues = candidates
          .map(dueFor)
          .whereType<DateTime>()
          .toList(growable: false);
      if (dayDues.isEmpty) continue;
      final dayDue = dayDues.reduce(_minDate);
      if (earliest == null || dayDue.isBefore(earliest)) earliest = dayDue;
    }
    return earliest;
  }

  static DateTime? _fitActiveWindow(
    DateTime due,
    DateTime date,
    ActiveWindow window,
  ) {
    if (window.mode == ActiveWindowMode.allDay) return due;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      window.startMinute! ~/ 60,
      window.startMinute! % 60,
    );
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      window.endMinute! ~/ 60,
      window.endMinute! % 60,
    );
    final adjusted = due.isBefore(start) ? start : due;
    return adjusted.isBefore(end) ? adjusted : null;
  }

  static int _compareFifo(ReviewItem a, ReviewItem b) {
    final created = a.createdAt.compareTo(b.createdAt);
    return created != 0 ? created : a.id.compareTo(b.id);
  }

  static int _compareLru(ReviewItem a, ReviewItem b) {
    final count = a.reminderCount.compareTo(b.reminderCount);
    if (count != 0) return count;
    final shown = a.lastShownAt!.compareTo(b.lastShownAt!);
    return shown != 0 ? shown : a.id.compareTo(b.id);
  }

  static DateTime _maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  static DateTime _minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static Duration _maxDuration(Duration a, Duration b) => a >= b ? a : b;
}
