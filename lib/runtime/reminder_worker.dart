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
    // Both background schedulers run in an isolate. sqflite requires that
    // isolate to own a non-singleton connection and leave it open for the
    // isolate lifetime instead of closing the foreground app's connection.
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
    stage = '读取提醒设置';
    final settings = await ReminderSettingsRepository(store).loadSettings();
    stage = '安排下一次提醒';
    await ReminderScheduler(store: store).reconcile(
      settings,
      minimumDelay: retryDelayAfterReminderRun(outcome, settings),
    );
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
    // Returning success avoids WorkManager's exponential retry burst. The
    // failure is now visible in diagnostics whenever the database is usable.
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
