import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:kaoyan_review/data/local/reminder_runtime_state_repository.dart';
import 'package:kaoyan_review/data/local/reminder_settings_repository.dart';
import 'package:kaoyan_review/data/local/review_item_repository.dart';
import 'package:kaoyan_review/data/local/topic_repository.dart';
import 'package:kaoyan_review/domain/active_window.dart';
import 'package:kaoyan_review/domain/reminder_scope.dart';
import 'package:kaoyan_review/domain/reminder_settings.dart';
import 'package:kaoyan_review/runtime/reminder_scheduler.dart';
import 'package:kaoyan_review/runtime/reminder_settings_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late AppDatabase store;
  late ReminderSettingsRepository repository;
  late DateTime now;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kaoyan-reminder-scheduler-');
    final path = '${dir.path}${Platform.pathSeparator}app.db';
    store = await AppDatabase.openWith(factory: databaseFactoryFfi, path: path);
    repository = ReminderSettingsRepository(store);
    now = DateTime.utc(2026, 9, 28, 12);
    final topic = await TopicRepository(store)
        .createTopic(name: '内科', now: now);
    await ReviewItemRepository(store).createReviewItem(
      content: '内容',
      topicId: topic.id,
      enabled: true,
      now: now,
    );
  });

  tearDown(() async {
    await store.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ReminderSettings settings({
    bool enabled = true,
    Duration interval = const Duration(hours: 1),
    Duration cooldown = const Duration(hours: 24),
    ReminderScope? scope,
    Map<int, Set<int>> weeklyTopicIds = const <int, Set<int>>{},
  }) => ReminderSettings(
    enabled: enabled,
    activeWindow: ActiveWindow.allDay(),
    reminderInterval: interval,
    repeatCooldown: cooldown,
    scope: scope ?? ReminderScope.allTopics(),
    weeklyTopicIds: weeklyTopicIds,
  );

  test(
    'enabled settings register one one-off task for the next opportunity',
    () async {
      final work = _FakePeriodicWorkPort();
      final scheduler = ReminderScheduler(store: store, work: work);

      expect(await scheduler.reconcile(settings(), now: now), isTrue);

      expect(work.registerCount, 1);
      expect(work.registeredInitialDelay, Duration.zero);
      expect(work.cancelCount, 0);
      expect(
        (await ReminderRuntimeStateRepository(
          store,
        ).loadState()).scheduleStatus,
        ReminderScheduleStatus.scheduled,
      );
    },
  );

  test(
    'minimum delay prevents an overdue opportunity from running immediately',
    () async {
      final work = _FakePeriodicWorkPort();
      final scheduler = ReminderScheduler(store: store, work: work);

      expect(
        await scheduler.reconcile(
          settings(interval: const Duration(minutes: 1)),
          now: now,
          minimumDelay: const Duration(minutes: 1),
        ),
        isTrue,
      );

      expect(work.registeredInitialDelay, const Duration(minutes: 1));
    },
  );

  test(
    'concurrent lifecycle reconciliations do not overlap alarm registration',
    () async {
      final work = _BlockingWorkPort();
      final scheduler = ReminderScheduler(store: store, work: work);

      final pauseReconcile = scheduler.reconcile(settings(), now: now);
      await work.firstRegistrationStarted.future;
      final resumeReconcile = scheduler.reconcile(
        settings(),
        now: now,
        minimumDelay: const Duration(minutes: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(work.registeredDelays, <Duration>[Duration.zero]);

      work.releaseFirstRegistration.complete();
      expect(await pauseReconcile, isTrue);
      expect(await resumeReconcile, isTrue);
      expect(
        work.registeredDelays,
        <Duration>[Duration.zero, const Duration(minutes: 1)],
      );
    },
  );

  test(
    'next opportunity scan covers the maximum cooldown and weekly plan',
    () async {
      final topics = TopicRepository(store);
      final items = ReviewItemRepository(store);
      await items.recordShownAt(id: 1, shownAt: now);
      for (var id = 2; id <= 40; id++) {
        final addedTopic = await topics.createTopic(name: '主题$id', now: now);
        final item = await items.createReviewItem(
          content: '内容$id',
          topicId: addedTopic.id,
          enabled: true,
          now: now,
        );
        await items.recordShownAt(id: item.id, shownAt: now);
      }
      await repository.saveSettings(
        settings(
          interval: const Duration(hours: 24),
          cooldown: const Duration(days: 30),
          weeklyTopicIds: <int, Set<int>>{
            DateTime.sunday: (await topics.listTopics())
                .map((value) => value.id)
                .toSet(),
          },
        ),
      );
      final scheduler = ReminderScheduler(
        store: store,
        work: _FakePeriodicWorkPort(),
      );

      final next = await scheduler.nextOpportunityAt(now: now);

      expect(next, isNotNull);
      expect(next!.weekday, DateTime.sunday);
      expect(next.difference(now).inDays, greaterThan(30));
      expect(next.difference(now).inDays, lessThanOrEqualTo(37));
    },
  );

  test('repeat opportunity follows the current content pool round', () async {
    final localNow = DateTime(2026, 9, 28, 12);
    final topics = TopicRepository(store);
    final items = ReviewItemRepository(store);
    await items.recordShownAt(
      id: 1,
      shownAt: localNow.subtract(const Duration(minutes: 45)),
    );
    for (var index = 2; index <= 3; index++) {
      final extraTopic = await topics.createTopic(name: '轮转$index', now: now);
      final created = await items.createReviewItem(
        content: '轮转内容$index',
        topicId: extraTopic.id,
        enabled: true,
        now: localNow,
      );
      await items.recordShownAt(
        id: created.id,
        shownAt: localNow.subtract(Duration(minutes: 60 - index * 15)),
      );
    }
    await repository.saveSettings(
      settings(
        interval: const Duration(minutes: 15),
        cooldown: const Duration(hours: 24),
      ),
    );
    final scheduler = ReminderScheduler(
      store: store,
      work: _FakePeriodicWorkPort(),
    );

    expect(await scheduler.nextOpportunityAt(now: localNow), localNow);
  });

  test(
    'foreground suppression defers the next reminder by one interval',
    () async {
      final localNow = DateTime(2026, 9, 28, 17, 27, 30);
      final dispatchedAt = localNow.subtract(const Duration(minutes: 3));
      final runtime = ReminderRuntimeStateRepository(store);
      final db = await store.database;
      await db.transaction((txn) async {
        await runtime.recordEvaluation(
          txn,
          at: dispatchedAt,
          outcome: 'notification_submitted',
          dispatchItemId: 1,
          dispatchTopicId: 1,
          dispatchAt: dispatchedAt,
        );
        await runtime.recordEvaluation(
          txn,
          at: localNow,
          outcome: 'foregroundSuppressed',
        );
      });
      await repository.saveSettings(
        settings(
          interval: const Duration(minutes: 1),
          cooldown: const Duration(minutes: 1),
        ),
      );
      final work = _FakePeriodicWorkPort();
      final scheduler = ReminderScheduler(store: store, work: work);

      expect(
        await scheduler.nextOpportunityAt(now: localNow),
        localNow.add(const Duration(minutes: 1)),
      );
      expect(
        await scheduler.reconcile(
          settings(
            interval: const Duration(minutes: 1),
            cooldown: const Duration(minutes: 1),
          ),
          now: localNow,
        ),
        isTrue,
      );
      expect(work.registeredInitialDelay, const Duration(minutes: 1));
    },
  );

  test(
    'cooling-down FIFO head does not hide a later eligible unseen item',
    () async {
      final topics = TopicRepository(store);
      final firstTopic = (await topics.listTopics()).single;
      await topics.setReminderInterval(
        id: firstTopic.id,
        interval: const Duration(hours: 1),
        now: now,
      );
      final db = await store.database;
      await db.transaction(
        (txn) => topics.recordRemindedAtWith(
          txn,
          topicId: firstTopic.id,
          remindedAt: now.subtract(const Duration(minutes: 30)),
        ),
      );
      final laterTopic = await topics.createTopic(name: '外科', now: now);
      await ReviewItemRepository(store).createReviewItem(
        content: '可提醒内容',
        topicId: laterTopic.id,
        enabled: true,
        now: now,
      );
      await repository.saveSettings(settings());
      final scheduler = ReminderScheduler(
        store: store,
        work: _FakePeriodicWorkPort(),
      );

      final next = await scheduler.nextOpportunityAt(now: now);

      expect(next, now);
    },
  );

  test('disabled settings cancel without registering', () async {
    final work = _FakePeriodicWorkPort();
    final scheduler = ReminderScheduler(store: store, work: work);

    expect(
      await scheduler.reconcile(settings(enabled: false), now: now),
      isTrue,
    );

    expect(work.cancelCount, 1);
    expect(work.registerCount, 0);
    expect(
      (await ReminderRuntimeStateRepository(store).loadState()).scheduleStatus,
      ReminderScheduleStatus.disabled,
    );
  });

  test(
    'weekly topics outside the selected scope are never scheduled',
    () async {
      final topics = TopicRepository(store);
      final scopedTopic = (await topics.listTopics()).single;
      final weeklyOnlyTopic = await topics.createTopic(name: '周计划主题', now: now);
      final work = _FakePeriodicWorkPort();
      final scheduler = ReminderScheduler(store: store, work: work);
      await repository.saveSettings(
        settings(
          scope: ReminderScope.selectedTopics(<int>{scopedTopic.id}),
          weeklyTopicIds: <int, Set<int>>{
            DateTime.monday: <int>{weeklyOnlyTopic.id},
          },
        ),
      );

      expect(await scheduler.nextOpportunityAt(now: now), isNull);
      expect(
        await scheduler.reconcile(
          settings(
            scope: ReminderScope.selectedTopics(<int>{scopedTopic.id}),
            weeklyTopicIds: <int, Set<int>>{
              DateTime.monday: <int>{weeklyOnlyTopic.id},
            },
          ),
          now: now,
        ),
        isTrue,
      );
      expect(work.cancelCount, 1);
      expect(work.registerCount, 0);
      expect(
        (await ReminderRuntimeStateRepository(
          store,
        ).loadState()).scheduleStatus,
        ReminderScheduleStatus.notScheduled,
      );
    },
  );

  test('registration failure records failed schedule state', () async {
    final work = _FakePeriodicWorkPort()
      ..registerError = StateError('WorkManager unavailable');
    final scheduler = ReminderScheduler(store: store, work: work);

    expect(await scheduler.reconcile(settings(), now: now), isFalse);

    final state = await ReminderRuntimeStateRepository(store).loadState();
    expect(state.scheduleStatus, ReminderScheduleStatus.failed);
    expect(state.scheduleError, contains('WorkManager unavailable'));
  });

  test(
    'settings remain persisted when schedule reconciliation fails',
    () async {
      final scheduler = ReminderScheduler(
        store: store,
        work: _FakePeriodicWorkPort()
          ..registerError = StateError('WorkManager unavailable'),
      );
      final service = ReminderSettingsService(
        repository: repository,
        scheduler: scheduler,
      );
      final nextSettings = settings(interval: const Duration(minutes: 30));

      expect(await service.save(nextSettings), isFalse);

      final loaded = await repository.loadSettings();
      expect(loaded.enabled, isTrue);
      expect(loaded.reminderInterval, const Duration(minutes: 30));
      expect(loaded.scope.mode, ReminderScopeMode.allTopics);
    },
  );
}

final class _FakePeriodicWorkPort implements ReminderWorkPort {
  int registerCount = 0;
  int cancelCount = 0;
  Duration? registeredInitialDelay;
  Object? registerError;

  @override
  Future<void> register({required Duration initialDelay}) async {
    registerCount++;
    registeredInitialDelay = initialDelay;
    if (registerError case final error?) throw error;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }
}

final class _BlockingWorkPort implements ReminderWorkPort {
  final firstRegistrationStarted = Completer<void>();
  final releaseFirstRegistration = Completer<void>();
  final registeredDelays = <Duration>[];

  @override
  Future<void> register({required Duration initialDelay}) async {
    registeredDelays.add(initialDelay);
    if (registeredDelays.length == 1) {
      firstRegistrationStarted.complete();
      await releaseFirstRegistration.future;
    }
  }

  @override
  Future<void> cancel() async {}
}
