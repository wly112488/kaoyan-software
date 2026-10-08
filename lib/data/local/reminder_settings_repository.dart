import 'package:sqflite/sqflite.dart';

import '../../domain/active_window.dart';
import '../../domain/reminder_scope.dart';
import '../../domain/reminder_settings.dart';
import 'app_database.dart';

final class ReminderSettingsRepository {
  ReminderSettingsRepository(this._store);

  final AppDatabase _store;

  Future<ReminderSettings> loadSettings() async {
    final db = await _store.database;
    // This is one SQLite statement, so settings and both topic selections are
    // read from one statement snapshot. Avoid opening sqflite's default
    // BEGIN IMMEDIATE transaction for a UI read: that reserves SQLite's writer
    // lock and can contend with the WorkManager reminder transaction.
    final rows = await db.rawQuery('''
      SELECT settings.*,
        (SELECT group_concat(topic_id, ',')
         FROM (SELECT topic_id FROM reminder_scope_topics ORDER BY topic_id))
          AS selected_topic_ids,
        (SELECT group_concat(weekday || ':' || topic_id, ',')
         FROM (SELECT weekday, topic_id FROM reminder_weekday_topics
               ORDER BY weekday, topic_id)) AS weekday_topic_ids
      FROM reminder_settings AS settings
      WHERE settings.id = 1
    ''');
    if (rows.length != 1) {
      throw StateError('ReminderSettings singleton is missing');
    }

    final row = rows.single;
    final selectedIds = _parseIds(row['selected_topic_ids'] as String?);
    final weeklyTopicIds = <int, Set<int>>{};
    final encodedWeekdays = row['weekday_topic_ids'] as String?;
    if (encodedWeekdays != null && encodedWeekdays.isNotEmpty) {
      for (final assignment in encodedWeekdays.split(',')) {
        final parts = assignment.split(':');
        final weekday = int.parse(parts[0]);
        final topicId = int.parse(parts[1]);
        (weeklyTopicIds[weekday] ??= <int>{}).add(topicId);
      }
    }
    return _settingsFromParts(
      row,
      selectedIds: selectedIds,
      weeklyTopicIds: weeklyTopicIds,
    );
  }

  Future<ReminderSettings> loadSettingsFrom(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'reminder_settings',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.length != 1) {
      throw StateError('ReminderSettings singleton is missing');
    }

    final row = rows.single;
    final selectedIds = <int>{};
    final scopeMode = row['scope_mode'];
    if (scopeMode == 'selected_topics') {
      final selectedRows = await executor.query(
        'reminder_scope_topics',
        columns: <String>['topic_id'],
        orderBy: 'topic_id ASC',
      );
      selectedIds.addAll(
        selectedRows.map((selected) => selected['topic_id']! as int),
      );
    }

    final weekdayRows = await executor.query(
      'reminder_weekday_topics',
      columns: <String>['weekday', 'topic_id'],
      orderBy: 'weekday ASC, topic_id ASC',
    );
    final weeklyTopicIds = <int, Set<int>>{};
    for (final selected in weekdayRows) {
      final weekday = selected['weekday']! as int;
      (weeklyTopicIds[weekday] ??= <int>{}).add(selected['topic_id']! as int);
    }
    return _settingsFromParts(
      row,
      selectedIds: selectedIds,
      weeklyTopicIds: weeklyTopicIds,
    );
  }

  ReminderSettings _settingsFromParts(
    Map<String, Object?> row, {
    required Set<int> selectedIds,
    required Map<int, Set<int>> weeklyTopicIds,
  }) {
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

    final ReminderScope scope;
    final scopeMode = row['scope_mode'];
    if (scopeMode == 'all_topics') {
      scope = ReminderScope.allTopics();
    } else if (scopeMode == 'selected_topics') {
      if (selectedIds.isEmpty) {
        throw StateError('Persisted SELECTED_TOPICS scope is empty');
      }
      scope = ReminderScope.selectedTopics(selectedIds);
    } else {
      throw StateError('Invalid scope_mode: $scopeMode');
    }

    return ReminderSettings(
      enabled: (row['enabled']! as int) == 1,
      activeWindow: activeWindow,
      reminderInterval: Duration(
        milliseconds: row['reminder_interval_ms']! as int,
      ),
      repeatCooldown: Duration(milliseconds: row['repeat_cooldown_ms']! as int),
      scope: scope,
      weeklyTopicIds: weeklyTopicIds,
    );
  }

  Set<int> _parseIds(String? value) => value == null || value.isEmpty
      ? <int>{}
      : value.split(',').map(int.parse).toSet();

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

      for (final entry in settings.weeklyTopicIds.entries) {
        for (final id in entry.value) {
          final exists = await txn.query(
            'topics',
            columns: <String>['id'],
            where: 'id = ?',
            whereArgs: <Object?>[id],
            limit: 1,
          );
          if (exists.isEmpty) {
            throw StateError('Weekly plan Topic $id does not exist');
          }
        }
      }

      final window = settings.activeWindow;
      final updated = await txn.update('reminder_settings', <String, Object?>{
        'enabled': settings.enabled ? 1 : 0,
        'active_window_mode': window.mode == ActiveWindowMode.allDay
            ? 'all_day'
            : 'bounded',
        'start_minute': window.startMinute,
        'end_minute': window.endMinute,
        'reminder_interval_ms': settings.reminderInterval.inMilliseconds,
        'repeat_cooldown_ms': settings.repeatCooldown.inMilliseconds,
        'scope_mode': settings.scope.mode == ReminderScopeMode.allTopics
            ? 'all_topics'
            : 'selected_topics',
      }, where: 'id = 1');
      if (updated != 1) {
        throw StateError('ReminderSettings singleton is missing');
      }

      await txn.delete('reminder_scope_topics');
      if (settings.scope.mode == ReminderScopeMode.selectedTopics) {
        for (final id in selectedIds) {
          await txn.insert('reminder_scope_topics', <String, Object?>{
            'topic_id': id,
          });
        }
      }

      await txn.delete('reminder_weekday_topics');
      for (final entry in settings.weeklyTopicIds.entries) {
        for (final id in entry.value) {
          await txn.insert('reminder_weekday_topics', <String, Object?>{
            'weekday': entry.key,
            'topic_id': id,
          });
        }
      }
    });
  }
}
