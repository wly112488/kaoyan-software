import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

enum ReminderScheduleStatus { notScheduled, scheduled, disabled, failed }

final class ReminderRuntimeState {
  const ReminderRuntimeState({
    required this.lastEvaluationAt,
    required this.lastEvaluationOutcome,
    required this.lastEvaluationSource,
    required this.lastDispatchAt,
    required this.lastDispatchItemId,
    required this.lastDispatchTopicId,
    required this.lastScheduleAttemptAt,
    required this.scheduleStatus,
    required this.scheduleError,
    required this.lastWorkerErrorAt,
    required this.lastWorkerErrorDetails,
    required this.lastWorkerStartedAt,
    required this.lastWorkerCompletedAt,
    required this.lastWorkerOutcome,
  });

  final DateTime? lastEvaluationAt;
  final String? lastEvaluationOutcome;
  final String? lastEvaluationSource;
  final DateTime? lastDispatchAt;
  final int? lastDispatchItemId;
  final int? lastDispatchTopicId;
  final DateTime? lastScheduleAttemptAt;
  final ReminderScheduleStatus scheduleStatus;
  final String? scheduleError;
  final DateTime? lastWorkerErrorAt;
  final String? lastWorkerErrorDetails;
  final DateTime? lastWorkerStartedAt;
  final DateTime? lastWorkerCompletedAt;
  final String? lastWorkerOutcome;
}

final class ReminderRuntimeStateRepository {
  ReminderRuntimeStateRepository(this._store);

  final AppDatabase _store;

  Future<ReminderRuntimeState> loadState() async {
    final db = await _store.database;
    return loadStateFrom(db);
  }

  Future<ReminderRuntimeState> loadStateFrom(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'reminder_runtime_state',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.length != 1) {
      throw StateError('Reminder runtime singleton is missing');
    }
    return _fromRow(rows.single);
  }

  Future<void> recordEvaluation(
    DatabaseExecutor executor, {
    required DateTime at,
    required String outcome,
    String? source,
    int? dispatchItemId,
    int? dispatchTopicId,
    DateTime? dispatchAt,
  }) async {
    final values = <String, Object?>{
      'last_evaluation_at_us': at.toUtc().microsecondsSinceEpoch,
      'last_evaluation_outcome': outcome,
      'last_evaluation_source': ?source,
    };
    if (dispatchAt != null) {
      values['last_dispatch_at_us'] = dispatchAt.toUtc().microsecondsSinceEpoch;
    }
    if (dispatchItemId != null) {
      values['last_dispatch_item_id'] = dispatchItemId;
    }
    if (dispatchTopicId != null) {
      values['last_dispatch_topic_id'] = dispatchTopicId;
    }

    final updated = await executor.update(
      'reminder_runtime_state',
      values,
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

  Future<void> recordWorkerFailure(
    DatabaseExecutor executor, {
    required DateTime at,
    required String details,
  }) async {
    final updated = await executor.update(
      'reminder_runtime_state',
      <String, Object?>{
        'last_evaluation_at_us': at.toUtc().microsecondsSinceEpoch,
        'last_evaluation_outcome': 'workerFailure',
        'last_evaluation_source': 'workmanager',
        'last_worker_error_at_us': at.toUtc().microsecondsSinceEpoch,
        'last_worker_error_details': details,
      },
      where: 'id = 1',
    );
    if (updated != 1) throw StateError('Reminder runtime singleton is missing');
  }

  Future<void> recordWorkerStarted(
    DatabaseExecutor executor, {
    required DateTime at,
  }) async {
    final updated = await executor.update(
      'reminder_runtime_state',
      <String, Object?>{
        'last_worker_started_at_us': at.toUtc().microsecondsSinceEpoch,
        'last_worker_completed_at_us': null,
        'last_worker_outcome': 'running',
      },
      where: 'id = 1',
    );
    if (updated != 1) throw StateError('Reminder runtime singleton is missing');
  }

  Future<void> recordWorkerCompleted(
    DatabaseExecutor executor, {
    required DateTime at,
    required String outcome,
  }) async {
    final updated = await executor.update(
      'reminder_runtime_state',
      <String, Object?>{
        'last_worker_completed_at_us': at.toUtc().microsecondsSinceEpoch,
        'last_worker_outcome': outcome,
      },
      where: 'id = 1',
    );
    if (updated != 1) throw StateError('Reminder runtime singleton is missing');
  }

  Future<void> clearWorkerFailure(DatabaseExecutor executor) async {
    final updated = await executor.update(
      'reminder_runtime_state',
      <String, Object?>{
        'last_worker_error_at_us': null,
        'last_worker_error_details': null,
      },
      where: 'id = 1',
    );
    if (updated != 1) throw StateError('Reminder runtime singleton is missing');
  }

  ReminderRuntimeState _fromRow(Map<String, Object?> row) {
    DateTime? time(String key) {
      final value = row[key] as int?;
      return value == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
    }

    return ReminderRuntimeState(
      lastEvaluationAt: time('last_evaluation_at_us'),
      lastEvaluationOutcome: row['last_evaluation_outcome'] as String?,
      lastEvaluationSource: row['last_evaluation_source'] as String?,
      lastDispatchAt: time('last_dispatch_at_us'),
      lastDispatchItemId: row['last_dispatch_item_id'] as int?,
      lastDispatchTopicId: row['last_dispatch_topic_id'] as int?,
      lastScheduleAttemptAt: time('last_schedule_attempt_at_us'),
      scheduleStatus: switch (row['schedule_status']) {
        'not_scheduled' => ReminderScheduleStatus.notScheduled,
        'scheduled' => ReminderScheduleStatus.scheduled,
        'disabled' => ReminderScheduleStatus.disabled,
        'failed' => ReminderScheduleStatus.failed,
        final Object? value => throw StateError(
          'Invalid schedule_status: $value',
        ),
      },
      scheduleError: row['schedule_error'] as String?,
      lastWorkerErrorAt: time('last_worker_error_at_us'),
      lastWorkerErrorDetails: row['last_worker_error_details'] as String?,
      lastWorkerStartedAt: time('last_worker_started_at_us'),
      lastWorkerCompletedAt: time('last_worker_completed_at_us'),
      lastWorkerOutcome: row['last_worker_outcome'] as String?,
    );
  }

  String _statusValue(ReminderScheduleStatus status) => switch (status) {
    ReminderScheduleStatus.notScheduled => 'not_scheduled',
    ReminderScheduleStatus.scheduled => 'scheduled',
    ReminderScheduleStatus.disabled => 'disabled',
    ReminderScheduleStatus.failed => 'failed',
  };
}
