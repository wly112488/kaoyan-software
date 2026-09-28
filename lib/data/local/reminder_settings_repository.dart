import '../../domain/active_window.dart';
import '../../domain/reminder_scope.dart';
import '../../domain/reminder_settings.dart';
import 'app_database.dart';

final class ReminderSettingsRepository {
  ReminderSettingsRepository(this._store);

  final AppDatabase _store;

  Future<ReminderSettings> loadSettings() async {
    final db = await _store.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'reminder_settings',
        where: 'id = 1',
        limit: 1,
      );
      if (rows.length != 1) {
        throw StateError('ReminderSettings singleton is missing');
      }

      final row = rows.single;
      final activeWindow = switch (row['active_window_mode']) {
        'all_day' => ActiveWindow.allDay(),
        'bounded' => ActiveWindow.bounded(
          startMinute: row['start_minute']! as int,
          endMinute: row['end_minute']! as int,
        ),
        final Object? value => throw StateError(
          'Invalid active_window_mode: $value',
        ),
      };

      final scopeMode = row['scope_mode'];
      final ReminderScope scope;
      if (scopeMode == 'all_topics') {
        scope = ReminderScope.allTopics();
      } else if (scopeMode == 'selected_topics') {
        final selectedRows = await txn.query(
          'reminder_scope_topics',
          columns: <String>['topic_id'],
          orderBy: 'topic_id ASC',
        );
        final ids = selectedRows
            .map((selected) => selected['topic_id']! as int)
            .toSet();
        if (ids.isEmpty) {
          throw StateError('Persisted SELECTED_TOPICS scope is empty');
        }
        scope = ReminderScope.selectedTopics(ids);
      } else {
        throw StateError('Invalid scope_mode: $scopeMode');
      }

      return ReminderSettings(
        enabled: (row['enabled']! as int) == 1,
        activeWindow: activeWindow,
        reminderInterval: Duration(
          milliseconds: row['reminder_interval_ms']! as int,
        ),
        repeatCooldown: Duration(
          milliseconds: row['repeat_cooldown_ms']! as int,
        ),
        scope: scope,
      );
    });
  }

  Future<void> saveSettings(ReminderSettings settings) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      final selectedIds = settings.scope.topicIds.toList()..sort();
      if (settings.scope.mode == ReminderScopeMode.selectedTopics) {
        for (final id in selectedIds) {
          final exists = await txn.query(
            'topics',
            columns: <String>['id'],
            where: 'id = ?',
            whereArgs: <Object?>[id],
            limit: 1,
          );
          if (exists.isEmpty) {
            throw StateError('Selected Topic $id does not exist');
          }
        }
      }

      final window = settings.activeWindow;
      final updated = await txn.update(
        'reminder_settings',
        <String, Object?>{
          'enabled': settings.enabled ? 1 : 0,
          'active_window_mode': window.mode == ActiveWindowMode.allDay ? 'all_day' : 'bounded',
          'start_minute': window.startMinute,
          'end_minute': window.endMinute,
          'reminder_interval_ms': settings.reminderInterval.inMilliseconds,
          'repeat_cooldown_ms': settings.repeatCooldown.inMilliseconds,
          'scope_mode': settings.scope.mode == ReminderScopeMode.allTopics
              ? 'all_topics'
              : 'selected_topics',
        },
        where: 'id = 1',
      );
      if (updated != 1) {
        throw StateError('ReminderSettings singleton is missing');
      }

      await txn.delete('reminder_scope_topics');
      if (settings.scope.mode == ReminderScopeMode.selectedTopics) {
        for (final id in selectedIds) {
          await txn.insert(
            'reminder_scope_topics',
            <String, Object?>{'topic_id': id},
          );
        }
      }
    });
  }
}
