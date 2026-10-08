import 'package:sqflite/sqflite.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../data/local/app_database.dart';
import '../data/local/reminder_runtime_state_repository.dart';
import '../data/local/reminder_settings_repository.dart';
import '../data/local/review_item_repository.dart';
import '../data/local/topic_repository.dart';
import '../domain/reminder_candidate_selector.dart';
import '../domain/reminder_evaluator.dart';
import '../domain/reminder_scope.dart';
import '../domain/review_item.dart';
import 'foreground_status.dart';
import 'review_notification_gateway.dart';
import 'pending_reminder_dispatch.dart';

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
  }) : _store = store,
       // Preserve the established public named constructor parameters.
       // ignore: prefer_initializing_formals
       _foregroundStatus = foregroundStatus,
       // ignore: prefer_initializing_formals
       _notifications = notifications,
       // ignore: prefer_initializing_formals
       _clock = clock,
       _evaluator = evaluator ?? ReminderEvaluator(),
       _selector = selector ?? ReminderCandidateSelector(),
       _settings = ReminderSettingsRepository(store),
       _items = ReviewItemRepository(store),
       _topics = TopicRepository(store),
       _runtime = ReminderRuntimeStateRepository(store);

  final AppDatabase _store;
  final ForegroundStatus _foregroundStatus;
  final ReviewNotificationGateway _notifications;
  final ReminderClock _clock;
  final ReminderEvaluator _evaluator;
  final ReminderCandidateSelector _selector;
  final ReminderSettingsRepository _settings;
  final ReviewItemRepository _items;
  final TopicRepository _topics;
  final ReminderRuntimeStateRepository _runtime;

  Future<ReminderRunOutcome> runOnce({String source = 'unspecified'}) async {
    final db = await _store.database;
    try {
      final interrupted = await readPendingDispatch(db);
      if (interrupted != null) {
        if (pendingDispatchIsLive(interrupted, _clock.nowUtc())) {
          return ReminderRunOutcome.noEligibleItem;
        }
        final pending = jsonDecode(interrupted) as Map<String, dynamic>;
        final gateway = _notifications;
        if (gateway is! TrackedReviewNotificationGateway) {
          return ReminderRunOutcome.noEligibleItem;
        }
        final submittedByPlatform = await gateway.fencePendingDispatch(
          pending['dispatch_token'] as String,
        );
        if (submittedByPlatform == null) {
          return ReminderRunOutcome.noEligibleItem;
        }
        final submitted =
            submittedByPlatform || pendingDispatchWasAccepted(interrupted);
        await markPendingDispatchFenced(
          db,
          pending['dispatch_token'] as String,
          submitted: submitted,
        );
        final fenced = await readPendingDispatch(db);
        if (fenced == null) return ReminderRunOutcome.noEligibleItem;
        await recoverPendingDispatch(
          db,
          fenced,
          submitted: submitted,
          now: _clock.nowUtc(),
        );
      }
      final initialSettings = await _settings.loadSettings();
      final initialNowUtc = _clock.nowUtc();
      final initialNowLocal = _clock.nowLocal();
      if (!initialSettings.enabled) {
        return await _finish(
          db,
          initialNowUtc,
          ReminderRunOutcome.reminderDisabled,
          source: source,
        );
      }
      if (!initialSettings.activeWindow.containsLocal(initialNowLocal)) {
        return await _finish(
          db,
          initialNowUtc,
          ReminderRunOutcome.outsideActiveWindow,
          source: source,
        );
      }
      if (await _foregroundStatus.isForeground()) {
        return await _finish(
          db,
          initialNowUtc,
          ReminderRunOutcome.foregroundSuppressed,
          source: source,
        );
      }
      final notificationAvailable = await _notifications.canPost();
      final blocked = _evaluator.blockingOutcome(
        settings: initialSettings,
        withinActiveWindow: true,
        isForeground: false,
        notificationAvailable: notificationAvailable,
      );
      if (blocked == ReminderEvaluationOutcome.notificationUnavailable) {
        return await _finish(
          db,
          initialNowUtc,
          ReminderRunOutcome.notificationUnavailable,
          source: source,
        );
      }

      _DispatchReservation? reservation;
      final outcome = await db.transaction<ReminderRunOutcome?>((txn) async {
        if (await readPendingDispatch(txn) != null) {
          return ReminderRunOutcome.noEligibleItem;
        }
        final settings = await _settings.loadSettingsFrom(txn);
        final nowUtc = _clock.nowUtc();
        final nowLocal = _clock.nowLocal();
        if (!settings.enabled) {
          return _finish(
            txn,
            nowUtc,
            ReminderRunOutcome.reminderDisabled,
            source: source,
          );
        }
        if (!settings.activeWindow.containsLocal(nowLocal)) {
          return _finish(
            txn,
            nowUtc,
            ReminderRunOutcome.outsideActiveWindow,
            source: source,
          );
        }
        final currentItems = await _items.listReviewItemsFrom(txn);
        final currentTopics = await _topics.listTopicsFrom(txn);
        final runtime = await _runtime.loadStateFrom(txn);
        final topicScope = settings.weeklyTopicIds[nowLocal.weekday];
        ReminderScope? effectiveScope = settings.scope;
        if (settings.hasWeeklyTopicPlan) {
          if (topicScope == null) {
            effectiveScope = null;
          } else if (settings.scope.mode == ReminderScopeMode.allTopics) {
            effectiveScope = ReminderScope.selectedTopics(topicScope);
          } else {
            final intersection = topicScope.intersection(
              settings.scope.topicIds,
            );
            effectiveScope = intersection.isEmpty
                ? null
                : ReminderScope.selectedTopics(intersection);
          }
        }
        if (effectiveScope == null) {
          return _finish(
            txn,
            nowUtc,
            ReminderRunOutcome.noEligibleItem,
            source: source,
          );
        }
        final topicIntervals = <int, Duration>{
          for (final topic in currentTopics)
            if (topic.reminderInterval != null)
              topic.id: topic.reminderInterval!,
        };
        final topicLastRemindedAt = <int, DateTime>{
          for (final topic in currentTopics)
            if (topic.lastRemindedAt != null) topic.id: topic.lastRemindedAt!,
        };
        final candidate = _selector.selectNext(
          items: currentItems,
          scope: effectiveScope,
          repeatCooldown: settings.repeatCooldown,
          now: nowUtc,
          globalInterval: settings.reminderInterval,
          lastDispatchAt: runtime.lastDispatchAt,
          topicIntervals: topicIntervals,
          topicLastRemindedAt: topicLastRemindedAt,
        );
        if (candidate == null) {
          return _finish(
            txn,
            nowUtc,
            ReminderRunOutcome.noEligibleItem,
            source: source,
          );
        }

        final dispatchAt = _clock.nowUtc();
        final dispatchToken =
            '$pid:${dispatchAt.microsecondsSinceEpoch}:${Random.secure().nextInt(1 << 32)}';
        reservation = _DispatchReservation(
          candidate: candidate,
          dispatchAt: dispatchAt,
          token: dispatchToken,
          previousRuntime: runtime,
          previousTopicLastRemindedAt: topicLastRemindedAt[candidate.topicId],
        );
        await txn.update('reminder_runtime_state', {
          'pending_dispatch_json': jsonEncode({
            'item_id': candidate.id,
            'topic_id': candidate.topicId,
            'dispatch_at_us': dispatchAt.microsecondsSinceEpoch,
            'dispatch_token': dispatchToken,
            'notification_accepted': false,
            'dispatch_fenced': false,
            'owner_pid': pid,
            'previous_item_at_us':
                candidate.lastShownAt?.microsecondsSinceEpoch,
            'previous_count': candidate.reminderCount,
            'previous_topic_at_us':
                topicLastRemindedAt[candidate.topicId]?.microsecondsSinceEpoch,
            'previous_dispatch_at_us':
                runtime.lastDispatchAt?.microsecondsSinceEpoch,
            'previous_dispatch_item_id': runtime.lastDispatchItemId,
            'previous_dispatch_topic_id': runtime.lastDispatchTopicId,
          }),
        }, where: 'id = 1');
        await _items.recordShownAtWith(
          txn,
          id: candidate.id,
          shownAt: dispatchAt,
        );
        await _topics.recordRemindedAtWith(
          txn,
          topicId: candidate.topicId,
          remindedAt: dispatchAt,
        );
        await _runtime.recordEvaluation(
          txn,
          at: dispatchAt,
          outcome: 'notification_pending',
          source: source,
          dispatchItemId: candidate.id,
          dispatchTopicId: candidate.topicId,
          dispatchAt: dispatchAt,
        );
        return null;
      }, exclusive: true);

      if (outcome != null) return outcome;
      final pending = reservation!;
      if (await _foregroundStatus.isForeground()) {
        await _rollbackDispatch(
          db,
          pending,
          evaluationOutcome: ReminderRunOutcome.foregroundSuppressed.name,
          source: source,
        );
        return ReminderRunOutcome.foregroundSuppressed;
      }
      if (!await _notifications.canPost()) {
        await _rollbackDispatch(
          db,
          pending,
          evaluationOutcome: ReminderRunOutcome.notificationUnavailable.name,
          source: source,
        );
        return ReminderRunOutcome.notificationUnavailable;
      }

      try {
        // Platform-channel work must not run while holding SQLite's exclusive
        // transaction; Android may delay notification delivery independently.
        final gateway = _notifications;
        if (gateway is TrackedReviewNotificationGateway) {
          final accepted = await gateway.submitTracked(
            pending.candidate,
            pending.dispatchAt,
            pending.token,
          );
          if (!accepted) {
            await _rollbackDispatch(
              db,
              pending,
              evaluationOutcome: 'notification_dispatch_superseded',
              source: source,
            );
            return ReminderRunOutcome.notificationSubmissionFailed;
          }
          await markPendingDispatchAccepted(db, pending.token);
        } else {
          await gateway.submit(pending.candidate);
          await markPendingDispatchAccepted(db, pending.token);
        }
      } catch (_) {
        await _rollbackDispatch(
          db,
          pending,
          evaluationOutcome: 'notification_submission_failed',
          source: source,
        );
        return ReminderRunOutcome.notificationSubmissionFailed;
      }

      await db.transaction((txn) async {
        final encoded = await readPendingDispatch(txn);
        if (encoded == null ||
            (jsonDecode(encoded) as Map<String, dynamic>)['dispatch_token'] !=
                pending.token) {
          return;
        }
        await _runtime.recordEvaluation(
          txn,
          at: _clock.nowUtc(),
          outcome: 'notification_submitted',
          source: source,
        );
        await txn.update(
          'reminder_runtime_state',
          {'pending_dispatch_json': null},
          where: 'id = 1 AND pending_dispatch_json = ?',
          whereArgs: [encoded],
        );
      });
      return ReminderRunOutcome.notificationSubmitted;
    } catch (_) {
      try {
        await _runtime.recordEvaluation(
          db,
          at: _clock.nowUtc(),
          outcome: 'store_failure',
          source: source,
        );
      } catch (_) {
        // The store itself is unavailable; there is nowhere durable to record it.
      }
      return ReminderRunOutcome.storeFailure;
    }
  }

  Future<void> _rollbackDispatch(
    Database db,
    _DispatchReservation pending, {
    required String evaluationOutcome,
    required String source,
  }) async {
    await db.transaction((txn) async {
      final encoded = await readPendingDispatch(txn);
      if (encoded == null ||
          (jsonDecode(encoded) as Map<String, dynamic>)['dispatch_token'] !=
              pending.token) {
        return;
      }
      final runtime = await _runtime.loadStateFrom(txn);
      if (runtime.lastDispatchAt != pending.dispatchAt ||
          runtime.lastDispatchItemId != pending.candidate.id) {
        return;
      }

      await txn.update(
        'review_items',
        <String, Object?>{
          'last_shown_at_us':
              pending.candidate.lastShownAt?.microsecondsSinceEpoch,
          'reminder_count': pending.candidate.reminderCount,
        },
        where: 'id = ? AND last_shown_at_us = ?',
        whereArgs: <Object?>[
          pending.candidate.id,
          pending.dispatchAt.microsecondsSinceEpoch,
        ],
      );
      await txn.update(
        'topics',
        <String, Object?>{
          'last_reminded_at_us':
              pending.previousTopicLastRemindedAt?.microsecondsSinceEpoch,
        },
        where: 'id = ? AND last_reminded_at_us = ?',
        whereArgs: <Object?>[
          pending.candidate.topicId,
          pending.dispatchAt.microsecondsSinceEpoch,
        ],
      );
      await txn.update('reminder_runtime_state', <String, Object?>{
        'pending_dispatch_json': null,
        'last_evaluation_at_us': _clock.nowUtc().microsecondsSinceEpoch,
        'last_evaluation_outcome': evaluationOutcome,
        'last_evaluation_source': source,
        'last_dispatch_at_us':
            pending.previousRuntime.lastDispatchAt?.microsecondsSinceEpoch,
        'last_dispatch_item_id': pending.previousRuntime.lastDispatchItemId,
        'last_dispatch_topic_id': pending.previousRuntime.lastDispatchTopicId,
      }, where: 'id = 1');
    }, exclusive: true);
  }

  Future<ReminderRunOutcome> _finish(
    DatabaseExecutor executor,
    DateTime at,
    ReminderRunOutcome outcome, {
    required String source,
  }) async {
    await _runtime.recordEvaluation(
      executor,
      at: at,
      outcome: outcome.name,
      source: source,
    );
    return outcome;
  }
}

final class _DispatchReservation {
  const _DispatchReservation({
    required this.candidate,
    required this.dispatchAt,
    required this.token,
    required this.previousRuntime,
    required this.previousTopicLastRemindedAt,
  });

  final ReviewItem candidate;
  final DateTime dispatchAt;
  final String token;
  final ReminderRuntimeState previousRuntime;
  final DateTime? previousTopicLastRemindedAt;
}
