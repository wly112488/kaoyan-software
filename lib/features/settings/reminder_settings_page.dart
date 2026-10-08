import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_error_details.dart';
import '../../app/app_services.dart';
import '../../domain/active_window.dart';
import '../../domain/reminder_scope.dart';
import '../../domain/reminder_settings.dart';
import '../../domain/topic.dart';
import '../../runtime/exact_alarm_permission.dart';
import '../../runtime/reminder_scheduler.dart';
import '../../runtime/reminder_settings_service.dart';
import '../../runtime/review_notification_gateway.dart';
import 'diagnostics_page.dart';

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({required this.services, super.key});

  final AppServices services;

  @override
  ReminderSettingsPageState createState() => ReminderSettingsPageState();
}

class ReminderSettingsPageState extends State<ReminderSettingsPage> {
  static const _settingsChannel = MethodChannel('kaoyan_review/settings');
  ReminderSettings _settings = ReminderSettings.initial();
  List<Topic> _topics = const <Topic>[];
  bool _loading = true;
  bool _saving = false;
  bool? _permissionGranted;
  bool? _exactAlarmAllowed;
  NotificationChannelStatus? _channelStatus;
  String? _channelStatusError;
  String? _status;
  final TextEditingController _intervalController = TextEditingController(
    text: '60',
  );
  final TextEditingController _cooldownController = TextEditingController(
    text: '${ReminderSettings.initial().repeatCooldown.inMinutes}',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var stage = '提醒设置';
    try {
      final settings = await widget.services.reminderSettings.loadSettings();
      stage = '主题列表';
      final topics = await widget.services.topics.listTopics();
      var exactAlarmAllowed = false;
      try {
        exactAlarmAllowed = await AndroidReminderAlarmPermission.canSchedule();
      } catch (error, stackTrace) {
        debugPrint('Exact alarm permission read failed: $error\n$stackTrace');
      }
      var canPost = false;
      NotificationChannelStatus? channelStatus;
      String? channelStatusError;
      try {
        channelStatus = await widget.services.notifications.channelStatus();
        canPost = channelStatus.appEnabled;
      } catch (error, stackTrace) {
        channelStatusError = '通知通道状态读取失败（${error.runtimeType}）';
        debugPrint(
          'Reminder settings notification status failed: $error\n$stackTrace',
        );
        canPost = false;
      }
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _topics = topics;
        _permissionGranted = canPost;
        _exactAlarmAllowed = exactAlarmAllowed;
        _channelStatus = channelStatus;
        _channelStatusError = channelStatusError;
        _loading = false;
      });
      _intervalController.text = '${settings.reminderInterval.inMinutes}';
      _cooldownController.text = '${settings.repeatCooldown.inMinutes}';
    } catch (error, stackTrace) {
      debugPrint(
        'Reminder settings load failed at $stage: $error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '$stage读取失败（${error.runtimeType}）';
      });
      showAppErrorSnackBar(
        context,
        message: '$stage读取失败',
        details: AppErrorDetails.format(
          stage: stage,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<void> refreshTopics() async {
    try {
      final topics = await widget.services.topics.listTopics();
      if (!mounted) return;
      setState(() => _topics = topics);
    } catch (error, stackTrace) {
      debugPrint('Reminder settings Topic refresh failed: $error\n$stackTrace');
      if (mounted) {
        showAppErrorSnackBar(
          context,
          message: '主题列表刷新失败',
          details: AppErrorDetails.format(
            stage: '提醒设置中的主题列表读取',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
  }

  Future<void> refreshPermissionStatus() async {
    try {
      final exactAlarmAllowed =
          await AndroidReminderAlarmPermission.canSchedule();
      final canPost = await widget.services.notifications.canPost();
      if (!mounted) return;
      setState(() {
        _exactAlarmAllowed = exactAlarmAllowed;
        _permissionGranted = canPost;
      });
      if (exactAlarmAllowed && _settings.enabled) {
        await widget.services.rescheduleReminders(
          policy: ReminderWorkPolicy.keep,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Reminder permission refresh failed: $error\n$stackTrace');
    }
  }

  Future<void> _toggleEnabled(bool enabled) async {
    var granted = _permissionGranted ?? false;
    String? permissionError;
    if (enabled) {
      try {
        granted = await widget.services.notifications.requestPermission();
        granted = granted || await widget.services.notifications.canPost();
      } catch (error, stackTrace) {
        debugPrint(
          'Reminder notification permission request failed: $error\n$stackTrace',
        );
        permissionError = '通知权限请求失败（${error.runtimeType}）';
        granted = false;
      }
    }
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
      _settings = _copySettings(enabled: enabled);
      _status = enabled && permissionError != null
          ? permissionError
          : enabled && !granted
          ? '通知权限未开启，提醒意图已保留'
          : null;
    });
  }

  ReminderSettings _copySettings({
    bool? enabled,
    ActiveWindow? activeWindow,
    Duration? interval,
    Duration? cooldown,
    ReminderScope? scope,
    Map<int, Set<int>>? weeklyTopicIds,
  }) {
    return ReminderSettings(
      enabled: enabled ?? _settings.enabled,
      activeWindow: activeWindow ?? _settings.activeWindow,
      reminderInterval: interval ?? _settings.reminderInterval,
      repeatCooldown: cooldown ?? _settings.repeatCooldown,
      scope: scope ?? _settings.scope,
      weeklyTopicIds: weeklyTopicIds ?? _settings.weeklyTopicIds,
    );
  }

  Future<int?> _pickMinute(int initialMinute) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinute ~/ 60,
        minute: initialMinute % 60,
      ),
      helpText: '选择提醒时段',
    );
    return selected == null ? null : selected.hour * 60 + selected.minute;
  }

  Future<void> _pickWindow({required bool start}) async {
    final current = _settings.activeWindow;
    final minute = await _pickMinute(
      start ? current.startMinute ?? 9 * 60 : current.endMinute ?? 22 * 60,
    );
    if (minute == null || !mounted) return;
    final startMinute = start ? minute : current.startMinute ?? 9 * 60;
    final endMinute = start ? current.endMinute ?? 22 * 60 : minute;
    if (startMinute >= endMinute) {
      _message('开始时间必须早于结束时间；不支持跨午夜时段');
      return;
    }
    setState(() {
      _settings = _copySettings(
        activeWindow: ActiveWindow.bounded(
          startMinute: startMinute,
          endMinute: endMinute,
        ),
      );
    });
  }

  void _setScopeMode(ReminderScopeMode mode) {
    if (mode == ReminderScopeMode.allTopics) {
      setState(
        () => _settings = _copySettings(scope: ReminderScope.allTopics()),
      );
      return;
    }
    if (_topics.isEmpty) {
      _message('请先创建主题，再选择提醒范围');
      return;
    }
    final selected = _settings.scope.mode == ReminderScopeMode.selectedTopics
        ? _settings.scope.topicIds.intersection(
            _topics.map((topic) => topic.id).toSet(),
          )
        : _topics.map((topic) => topic.id).toSet();
    setState(() {
      _settings = _copySettings(
        scope: ReminderScope.selectedTopics(
          selected.isEmpty ? <int>{_topics.first.id} : selected,
        ),
      );
    });
  }

  void _toggleTopic(int id, bool selected) {
    final ids = <int>{..._settings.scope.topicIds};
    if (selected) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    if (ids.isEmpty) {
      _message('指定主题范围至少保留一个主题');
      return;
    }
    setState(
      () => _settings = _copySettings(scope: ReminderScope.selectedTopics(ids)),
    );
  }

  Future<void> _save() async {
    final interval = int.tryParse(_intervalController.text);
    final cooldown = int.tryParse(_cooldownController.text);
    final minimumInterval = minimumProductionReminderInterval.inMinutes;
    final maximumInterval = maximumProductionReminderInterval.inMinutes;
    final maximumCooldown = maximumRepeatCooldown.inMinutes;
    if (interval == null ||
        interval < minimumInterval ||
        interval > maximumInterval) {
      setState(() => _status = '全局间隔请输入 $minimumInterval–$maximumInterval 分钟');
      return;
    }
    if (cooldown == null || cooldown < interval || cooldown > maximumCooldown) {
      setState(() => _status = '重复冷却上限必须不小于全局间隔，且不超过 30 天');
      return;
    }
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      final scheduled = await widget.services.settingsService.save(_settings);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = !scheduled
            ? '设置已保存，但系统调度失败。请稍后重试。'
            : _settings.enabled && _permissionGranted != true
            ? '设置已保存；通知权限关闭时不会显示提醒。'
            : _settings.enabled && _exactAlarmAllowed != true
            ? '设置已保存；精确闹钟未授权，后台提醒可能延迟。'
            : '提醒设置已保存';
      });
    } catch (error, stackTrace) {
      debugPrint('Reminder settings save failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = switch (error) {
          ReminderSettingsWriteException() =>
            '提醒设置写入失败（${error.cause.runtimeType}）',
          ReminderSchedulingException() =>
            '提醒设置已写入，但调度状态更新失败（${error.cause.runtimeType}）',
          _ => '提醒设置保存流程失败（${error.runtimeType}）',
        };
      });
    }
  }

  Future<void> _openSystemSettings() async {
    try {
      await _settingsChannel.invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException {
      _message('请在系统设置中为考研复习开启通知权限');
    } catch (error, stackTrace) {
      debugPrint('Open notification settings failed: $error\n$stackTrace');
      _message('打开系统通知设置失败（${error.runtimeType}）');
    }
  }

  Future<void> _openExactAlarmSettings() async {
    try {
      await AndroidReminderAlarmPermission.openSettings();
    } on MissingPluginException {
      _message('请在系统设置中允许考研复习使用精确闹钟');
    } catch (error, stackTrace) {
      debugPrint('Open exact alarm settings failed: $error\n$stackTrace');
      _message('打开精确闹钟设置失败（${error.runtimeType}）');
    }
  }

  Future<void> _sendTestNotification() async {
    try {
      await widget.services.notifications.sendTestNotification();
      if (mounted) {
        _message('测试通知已发送；请检查屏幕横幅和通知栏。');
      }
    } catch (error, stackTrace) {
      debugPrint('Send test notification failed: $error\n$stackTrace');
      if (mounted) {
        _message('测试通知发送失败（${error.runtimeType}），请检查通知权限');
      }
    }
  }

  String _channelStatusLabel(NotificationChannelStatus? status) {
    if (status == null) return _channelStatusError ?? '无法读取通知通道状态';
    if (!status.appEnabled) return '应用通知权限未开启';
    if (!status.channelExists) return '提醒通道尚未创建';
    final importance = status.importance;
    if (importance == null) return '无法读取提醒通道重要性';
    if (!status.bannerLikely) {
      return '提醒通道重要性为 ${importance.name}，系统可能不显示横幅';
    }
    return '提醒通道重要性为 ${importance.name}；横幅仍由系统设置决定';
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  void _changeGlobalInterval(String rawValue) {
    final minutes = int.tryParse(rawValue);
    if (minutes == null ||
        minutes < minimumProductionReminderInterval.inMinutes ||
        minutes > maximumProductionReminderInterval.inMinutes) {
      return;
    }
    final interval = Duration(minutes: minutes);
    final cooldown = _settings.repeatCooldown < interval
        ? interval
        : _settings.repeatCooldown;
    setState(() {
      _settings = _copySettings(interval: interval, cooldown: cooldown);
      _cooldownController.text = '${cooldown.inMinutes}';
    });
  }

  void _changeRepeatCooldown(String rawValue) {
    final minutes = int.tryParse(rawValue);
    if (minutes == null ||
        minutes < _settings.reminderInterval.inMinutes ||
        minutes > maximumRepeatCooldown.inMinutes) {
      return;
    }
    setState(() {
      _settings = _copySettings(cooldown: Duration(minutes: minutes));
    });
  }

  void _toggleWeeklyPlan(bool enabled) {
    if (!enabled) {
      setState(() => _settings = _copySettings(weeklyTopicIds: {}));
      return;
    }
    if (_topics.isEmpty) {
      _message('请先创建主题，再设置每周主题计划');
      return;
    }
    final initialIds = _settings.scope.mode == ReminderScopeMode.selectedTopics
        ? _settings.scope.topicIds
        : _topics.map((topic) => topic.id).toSet();
    final plan = <int, Set<int>>{
      for (var day = DateTime.monday; day <= DateTime.sunday; day++)
        day: <int>{...initialIds},
    };
    setState(() => _settings = _copySettings(weeklyTopicIds: plan));
  }

  void _toggleWeekdayTopic(int weekday, int topicId, bool selected) {
    final plan = <int, Set<int>>{
      for (final entry in _settings.weeklyTopicIds.entries)
        entry.key: <int>{...entry.value},
    };
    final ids = plan.putIfAbsent(weekday, () => <int>{});
    if (selected) {
      ids.add(topicId);
    } else {
      ids.remove(topicId);
      if (ids.isEmpty) plan.remove(weekday);
    }
    setState(() => _settings = _copySettings(weeklyTopicIds: plan));
  }

  static const _weekdayNames = <int, String>{
    DateTime.monday: '周一',
    DateTime.tuesday: '周二',
    DateTime.wednesday: '周三',
    DateTime.thursday: '周四',
    DateTime.friday: '周五',
    DateTime.saturday: '周六',
    DateTime.sunday: '周日',
  };

  @override
  void dispose() {
    _intervalController.dispose();
    _cooldownController.dispose();
    super.dispose();
  }

  String _clockLabel(int? minute, int fallback) {
    final value = minute ?? fallback;
    return '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final bounded = _settings.activeWindow.mode == ActiveWindowMode.bounded;
    final selected = _settings.scope.mode == ReminderScopeMode.selectedTopics;
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: <Widget>[
          SwitchListTile(
            key: const ValueKey('reminder-enabled-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('开启复习提醒'),
            subtitle: const Text('由系统在后台定期检查符合条件的内容'),
            value: _settings.enabled,
            onChanged: _saving ? null : _toggleEnabled,
          ),
          if (_settings.enabled && _permissionGranted != true)
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: const Text('通知权限未开启'),
                subtitle: const Text('提醒设置会保留，但系统不会显示通知。'),
                trailing: TextButton(
                  onPressed: _openSystemSettings,
                  child: const Text('系统设置'),
                ),
              ),
            ),
          if (_settings.enabled && _exactAlarmAllowed != true)
            Card(
              child: ListTile(
                leading: const Icon(Icons.alarm_off_outlined),
                title: const Text('精确提醒尚未授权'),
                subtitle: const Text('华为后台可能延迟普通任务；允许精确闹钟以按设定时间触发。'),
                trailing: TextButton(
                  onPressed: _openExactAlarmSettings,
                  child: const Text('允许设置'),
                ),
              ),
            ),
          if (_settings.enabled)
            Card(
              child: ListTile(
                leading: Icon(
                  _channelStatus?.bannerLikely == true
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: const Text('横幅通知状态'),
                subtitle: Text(_channelStatusLabel(_channelStatus)),
                trailing: TextButton(
                  onPressed: _openSystemSettings,
                  child: const Text('检查设置'),
                ),
              ),
            ),
          if (_settings.enabled)
            OutlinedButton.icon(
              onPressed: _saving ? null : _sendTestNotification,
              icon: const Icon(Icons.notification_important_outlined),
              label: const Text('发送测试通知'),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _status!,
                key: const ValueKey('reminder-settings-status'),
              ),
            ),
          const Divider(height: 28),
          Text('提醒时段', style: Theme.of(context).textTheme.titleMedium),
          SegmentedButton<bool>(
            segments: const <ButtonSegment<bool>>[
              ButtonSegment(value: false, label: Text('全天')),
              ButtonSegment(value: true, label: Text('指定时段')),
            ],
            selected: <bool>{bounded},
            onSelectionChanged: (value) {
              final useBounded = value.single;
              setState(() {
                _settings = _copySettings(
                  activeWindow: useBounded
                      ? ActiveWindow.bounded(
                          startMinute:
                              _settings.activeWindow.startMinute ?? 9 * 60,
                          endMinute:
                              _settings.activeWindow.endMinute ?? 22 * 60,
                        )
                      : ActiveWindow.allDay(),
                );
              });
            },
          ),
          if (bounded)
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickWindow(start: true),
                    child: Text(
                      '开始 ${_clockLabel(_settings.activeWindow.startMinute, 9 * 60)}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickWindow(start: false),
                    child: Text(
                      '结束 ${_clockLabel(_settings.activeWindow.endMinute, 22 * 60)}',
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('reminder-interval-minutes'),
            controller: _intervalController,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: '全局最短提醒间隔（分钟）',
              helperText:
                  '${minimumProductionReminderInterval.inMinutes}–${maximumProductionReminderInterval.inMinutes} 分钟；也是未单独设置主题的默认间隔',
            ),
            onChanged: _changeGlobalInterval,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('reminder-repeat-cooldown-minutes'),
            controller: _cooldownController,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: '同一内容重复冷却上限（分钟）',
              helperText:
                  '实际等待时间会按当前可提醒内容数量和全局间隔缩短；上限至少 ${_settings.reminderInterval.inMinutes} 分钟，最多 ${maximumRepeatCooldown.inMinutes} 分钟（30 天）',
            ),
            onChanged: _changeRepeatCooldown,
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('按星期筛选主题'),
            subtitle: const Text('未配置的星期不会发送提醒；每日可选多个主题'),
            value: _settings.hasWeeklyTopicPlan,
            onChanged: _toggleWeeklyPlan,
          ),
          if (_settings.hasWeeklyTopicPlan)
            ..._weekdayNames.entries.map((day) {
              final selectedIds =
                  _settings.weeklyTopicIds[day.key] ?? const <int>{};
              return ExpansionTile(
                title: Text(day.value),
                subtitle: Text(
                  selectedIds.isEmpty
                      ? '当天不提醒'
                      : '已选 ${selectedIds.length} 个主题',
                ),
                children: _topics
                    .map(
                      (topic) => CheckboxListTile(
                        title: Text(topic.name),
                        value: selectedIds.contains(topic.id),
                        onChanged: (value) => _toggleWeekdayTopic(
                          day.key,
                          topic.id,
                          value ?? false,
                        ),
                      ),
                    )
                    .toList(),
              );
            }),
          const Divider(height: 32),
          Text('主题范围', style: Theme.of(context).textTheme.titleMedium),
          SegmentedButton<ReminderScopeMode>(
            segments: const <ButtonSegment<ReminderScopeMode>>[
              ButtonSegment(
                value: ReminderScopeMode.allTopics,
                label: Text('全部主题'),
              ),
              ButtonSegment(
                value: ReminderScopeMode.selectedTopics,
                label: Text('指定主题'),
              ),
            ],
            selected: <ReminderScopeMode>{
              selected
                  ? ReminderScopeMode.selectedTopics
                  : ReminderScopeMode.allTopics,
            },
            onSelectionChanged: (value) => _setScopeMode(value.single),
          ),
          if (selected)
            if (_topics.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('还没有主题，请先到主题页面创建。'),
              )
            else
              ..._topics.map(
                (topic) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(topic.name),
                  value: _settings.scope.topicIds.contains(topic.id),
                  onChanged: (value) => _toggleTopic(topic.id, value ?? false),
                ),
              ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.health_and_safety_outlined),
            title: const Text('诊断信息'),
            subtitle: const Text('查看设备、提醒运行和调度状态'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DiagnosticsPage(services: widget.services),
              ),
            ),
          ),
        ],
      ),
      bottomSheet: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存提醒设置'),
          ),
        ),
      ),
    );
  }
}
