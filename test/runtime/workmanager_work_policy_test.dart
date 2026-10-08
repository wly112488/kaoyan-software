import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/runtime/reminder_scheduler.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WorkmanagerPlatform previous;
  late _RecordingPlatform platform;
  setUp(() {
    Workmanager();
    previous = WorkmanagerPlatform.instance;
    platform = _RecordingPlatform();
    WorkmanagerPlatform.instance = platform;
  });
  tearDown(() => WorkmanagerPlatform.instance = previous);

  test(
    'lifecycle recovery keeps pending fallback instead of delaying it',
    () async {
      await WorkmanagerOneOffWorkPort().register(
        initialDelay: const Duration(seconds: 20),
        policy: ReminderWorkPolicy.keep,
      );
      expect(platform.policy, ExistingWorkPolicy.keep);
      expect(platform.cancelledNames, <String>[legacyReminderUniqueWorkName]);
    },
  );

  test(
    'Worker appends its successor without cancelling the current task',
    () async {
      await WorkmanagerOneOffWorkPort().register(
        initialDelay: const Duration(minutes: 1),
        policy: ReminderWorkPolicy.append,
      );
      expect(platform.policy, ExistingWorkPolicy.update);
      expect(platform.cancelledNames, isNot(contains(reminderUniqueWorkName)));
    },
  );

  test('business settings changes replace obsolete fallback tasks', () async {
    await WorkmanagerOneOffWorkPort().register(
      initialDelay: const Duration(minutes: 2),
    );
    expect(platform.policy, ExistingWorkPolicy.replace);
  });

  test(
    'fallback delay rounds up instead of waking before eligibility',
    () async {
      await WorkmanagerOneOffWorkPort().register(
        initialDelay: const Duration(seconds: 59, milliseconds: 900),
        policy: ReminderWorkPolicy.append,
      );
      expect(platform.delay, const Duration(seconds: 60));
      await WorkmanagerOneOffWorkPort().register(
        initialDelay: const Duration(microseconds: 1),
      );
      expect(platform.delay, const Duration(seconds: 1));
      await WorkmanagerOneOffWorkPort().register(initialDelay: Duration.zero);
      expect(platform.delay, Duration.zero);
    },
  );
}

final class _RecordingPlatform extends WorkmanagerPlatform {
  ExistingWorkPolicy? policy;
  Duration? delay;
  final cancelledNames = <String>[];

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    policy = existingWorkPolicy;
    delay = initialDelay;
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async =>
      cancelledNames.add(uniqueName);
}
