import 'dart:async';
import 'dart:ui';
import 'dart:developer' as developer;

import 'package:workmanager/workmanager.dart';

import '../data/local/app_database.dart';
import '../data/local/reminder_runtime_state_repository.dart';
import '../data/local/reminder_settings_repository.dart';
import 'foreground_status.dart';
import 'reminder_execution_service.dart';
import 'reminder_retry_policy.dart';
import 'reminder_scheduler.dart';
import 'review_notification_gateway.dart';

@pragma('vm:entry-point')
void reminderCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != reminderWorkerTaskName) {
      return true;
    }

    return _runReminderEvaluation(source: 'workmanager');
  });
}

@pragma('vm:entry-point')
void reminderAlarmCallback() {
  DartPluginRegistrant.ensureInitialized();
  unawaited(_runReminderEvaluation(source: 'alarm_manager'));
}

Future<bool> _runReminderEvaluation({required String source}) async {
  AppDatabase? store;
  var workerStarted = false;
  var stage = '初始化后台提醒任务';
  try {
    DartPluginRegistrant.ensureInitialized();
    // The background Engine owns its connection; closing it must not close
    // the UI Engine's sqflite single-instance connection.
    stage = '打开本地数据库';
    store = await AppDatabase.openProduction(singleInstance: false);
    stage = '记录后台任务启动状态';
    final runtime = ReminderRuntimeStateRepository(store);
    var db = await store.database;
    await runtime.recordWorkerStarted(db, at: DateTime.now().toUtc());
    workerStarted = true;
    stage = '初始化通知服务';
    final notifications = AndroidReviewNotificationGateway();
    await notifications.initialize();
    stage = '执行提醒评估';
    final service = ReminderExecutionService(
      store: store,
      foregroundStatus: AndroidForegroundStatus(),
      notifications: notifications,
    );
    final outcome = await service.runOnce(source: source);
    if (outcome == ReminderRunOutcome.storeFailure) {
      throw StateError('Reminder evaluation could not read or update the store');
    }
    stage = '读取提醒设置';
    final settings = await ReminderSettingsRepository(store).loadSettings();
    stage = '安排下一次提醒';
    final scheduled = await ReminderScheduler(store: store).reconcile(
      settings,
      minimumDelay: retryDelayAfterReminderRun(outcome, settings),
      policy: ReminderWorkPolicy.append,
    );
    if (!scheduled) {
      throw StateError('The next reminder could not be scheduled');
    }
    await ReminderRuntimeStateRepository(store)
        .clearWorkerFailure(await store.database);
    await runtime.recordWorkerCompleted(
      await store.database,
      at: DateTime.now().toUtc(),
      outcome: outcome.name,
    );
  } catch (error, stackTrace) {
    developer.log(
      'Reminder worker failed',
      name: 'kaoyan_review.reminder_worker',
      error: error,
      stackTrace: stackTrace,
    );
    final failedAt = DateTime.now().toUtc();
    if (store != null) {
      try {
        final db = await store.database;
        final runtime = ReminderRuntimeStateRepository(store);
        await runtime.recordWorkerFailure(
          db,
          at: failedAt,
          details: <String>[
            '失败环节：$stage',
            '异常类型：${error.runtimeType}',
            '错误信息：$error',
            '调用栈：$stackTrace',
          ].join('\n'),
        );
        if (workerStarted) {
          await runtime.recordWorkerCompleted(
            db,
            at: failedAt,
            outcome: 'workerFailure',
          );
        }
        await runtime.recordSchedule(
          db,
          at: failedAt,
          status: ReminderScheduleStatus.failed,
          error: error.runtimeType.toString(),
        );
      } catch (recordError, recordStackTrace) {
        developer.log(
          'Could not persist reminder worker failure',
          name: 'kaoyan_review.reminder_worker',
          error: recordError,
          stackTrace: recordStackTrace,
        );
      }
    }
    // A one-off task without a successor must be retried independently of UI.
    return false;
  } finally {
    try {
      await store?.close();
    } catch (error, stackTrace) {
      developer.log(
        'Could not close reminder worker database connection',
        name: 'kaoyan_review.reminder_worker',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  return true;
}
