import '../data/local/app_database.dart';
import '../data/local/reminder_runtime_state_repository.dart';
import '../data/local/reminder_settings_repository.dart';
import '../data/local/review_item_repository.dart';
import '../data/local/topic_repository.dart';
import '../runtime/reminder_scheduler.dart';
import '../runtime/reminder_runtime_bootstrap.dart';
import '../runtime/reminder_settings_service.dart';
import '../runtime/foreground_status.dart';
import '../runtime/reminder_execution_service.dart';
import '../runtime/review_notification_gateway.dart';

typedef ReminderRuntimeInitializer = Future<void> Function();
typedef ProductionStoreOpener = Future<AppDatabase> Function();

final class AppServices {
  AppServices({
    required this.store,
    this.runtimeInitializationError,
    this.runtimeInitializer,
    ReviewNotificationGateway? notifications,
    PeriodicWorkPort? periodicWork,
    ForegroundStatus? foregroundStatus,
    ReminderClock clock = const SystemReminderClock(),
  }) : topics = TopicRepository(store),
       reviewItems = ReviewItemRepository(store),
       reminderSettings = ReminderSettingsRepository(store),
       runtimeState = ReminderRuntimeStateRepository(store),
       notifications = notifications ?? AndroidReviewNotificationGateway(),
       scheduler = ReminderScheduler(store: store, work: periodicWork) {
    executionService = ReminderExecutionService(
      store: store,
      foregroundStatus: foregroundStatus ?? AndroidForegroundStatus(),
      notifications: this.notifications,
      clock: clock,
    );
    settingsService = ReminderSettingsService(
      repository: reminderSettings,
      scheduler: scheduler,
    );
  }

  static Future<AppServices> openProduction({
    ReminderRuntimeInitializer? initializeRuntime,
    ProductionStoreOpener? openStore,
  }) async {
    final store = await (openStore ?? (() => AppDatabase.openProduction()))();
    try {
      return AppServices(
        store: store,
        runtimeInitializer:
            initializeRuntime ?? ReminderRuntimeBootstrap.initialize,
      );
    } catch (_) {
      await store.close();
      rethrow;
    }
  }

  final AppDatabase store;
  final ReminderRuntimeInitializer? runtimeInitializer;
  Object? runtimeInitializationError;
  Future<void>? _runtimeInitialization;

  Future<void> initializeReminderRuntime() {
    final existing = _runtimeInitialization;
    if (existing != null) return existing;
    final initializer = runtimeInitializer;
    if (initializer == null) return Future<void>.value();

    final attempt = Future<void>.sync(initializer).then<void>(
      (_) {},
      onError: (Object error, StackTrace _) {
        // Reminder delivery is optional for opening locally stored study content.
        runtimeInitializationError = error;
      },
    );
    _runtimeInitialization = attempt;
    return attempt;
  }

  final TopicRepository topics;
  final ReviewItemRepository reviewItems;
  final ReminderSettingsRepository reminderSettings;
  final ReminderRuntimeStateRepository runtimeState;
  final ReviewNotificationGateway notifications;
  final ReminderScheduler scheduler;
  late final ReminderSettingsService settingsService;
  late final ReminderExecutionService executionService;

  Future<void> close() => store.close();

  Future<bool> rescheduleReminders({
    Duration minimumDelay = Duration.zero,
  }) async {
    final settings = await reminderSettings.loadSettings();
    final foregroundSafeDelay = settings.enabled &&
            settings.reminderInterval > minimumDelay
        ? settings.reminderInterval
        : minimumDelay;
    return scheduler.reconcile(settings, minimumDelay: foregroundSafeDelay);
  }
}
