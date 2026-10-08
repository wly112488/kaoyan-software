import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaoyan_review/data/local/app_database.dart';
import 'package:workmanager/workmanager.dart';

const _alarmChannel = MethodChannel('kaoyan_review/reminder_alarm');
const _requireScheduled = bool.fromEnvironment('REQUIRE_HEADLESS_EXACT_ALARM');

@pragma('vm:entry-point')
void headlessAlarmProbeDispatcher() {
  Workmanager().executeTask((task, _) async {
    final store = await AppDatabase.openProduction(singleInstance: false);
    try {
      String outcome;
      try {
        final scheduled = await _alarmChannel.invokeMethod<bool>(
          'schedule',
          <String, Object?>{
            'atEpochMillis': DateTime.now()
                .add(const Duration(minutes: 10))
                .millisecondsSinceEpoch,
          },
        );
        await _alarmChannel.invokeMethod<void>('cancel');
        outcome = _requireScheduled
            ? (scheduled == true
                  ? 'headlessAlarmScheduled'
                  : 'headlessAlarmUnavailable')
            : 'headlessBridgeAvailable';
      } catch (error) {
        outcome = error.runtimeType.toString();
      }
      await (await store.database).update(
        'reminder_runtime_state',
        <String, Object?>{'last_worker_outcome': outcome},
        where: 'id = 1',
      );
      return true;
    } finally {
      await store.close();
    }
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('independent Worker engine has native alarm scheduling channel', (
    tester,
  ) async {
    final store = await AppDatabase.openProduction();
    try {
      final db = await store.database;
      await db.update('reminder_runtime_state', <String, Object?>{
        'last_worker_outcome': null,
      }, where: 'id = 1');
      await Workmanager().initialize(headlessAlarmProbeDispatcher);
      await Workmanager().registerOneOffTask(
        'headless_alarm_bridge_probe',
        'headless_alarm_bridge_probe',
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      String? outcome;
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (outcome == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final rows = await db.query(
          'reminder_runtime_state',
          columns: <String>['last_worker_outcome'],
          where: 'id = 1',
        );
        outcome = rows.single['last_worker_outcome'] as String?;
      }
      expect(
        outcome,
        _requireScheduled
            ? 'headlessAlarmScheduled'
            : 'headlessBridgeAvailable',
      );
    } finally {
      await store.close();
    }
  });
}
