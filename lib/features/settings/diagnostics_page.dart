import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_error_details.dart';
import '../../app/app_services.dart';
import '../../data/local/reminder_runtime_state_repository.dart';
import '../../domain/reminder_candidate_selector.dart';
import '../../domain/reminder_scope.dart';
import '../../domain/reminder_settings.dart';
import '../../domain/review_item.dart';
import '../../domain/topic.dart';
import '../../runtime/review_notification_gateway.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({required this.services, super.key});

  final AppServices services;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  static const _channel = MethodChannel('kaoyan_review/settings');
  bool _loading = true;
  String? _error;
  String? _errorDetails;
  Map<String, Object?> _device = const <String, Object?>{};
  ReminderSettings? _settings;
  List<Topic> _topics = const <Topic>[];
  List<ReviewItem> _items = const <ReviewItem>[];
  ReminderRuntimeState? _runtime;
  bool _notificationAvailable = false;
  NotificationChannelStatus? _channelStatus;
  List<int> _activeReviewNotificationIds = const <int>[];
  DateTime? _nextOpportunity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorDetails = null;
    });
    try {
      final device = await _readDiagnostic(
        '设备信息（Android 原生通道）',
        () => _channel.invokeMapMethod<String, Object?>('getDeviceInfo'),
      );
      final settings = await _readDiagnostic(
        '提醒设置（本地数据库）',
        widget.services.reminderSettings.loadSettings,
      );
      final topics = await _readDiagnostic(
        '主题数据（本地数据库）',
        widget.services.topics.listTopics,
      );
      final items = await _readDiagnostic(
        '复习内容（本地数据库）',
        widget.services.reviewItems.listReviewItems,
      );
      final runtime = await _readDiagnostic(
        '提醒运行状态（本地数据库）',
        widget.services.runtimeState.loadState,
      );
      final channelStatus = await _readDiagnostic(
        '通知权限与通道（Android 通知服务）',
        widget.services.notifications.channelStatus,
      );
      final activeReviewNotificationIds = await _readDiagnostic(
        '系统活动复习通知（Android 通知管理器）',
        widget.services.notifications.activeReviewItemNotificationIds,
      );
      final notificationAvailable = channelStatus.appEnabled;
      final nextOpportunity = await _readDiagnostic(
        '下一次提醒时间（调度与提醒数据）',
        widget.services.scheduler.nextOpportunityAt,
      );
      if (!mounted) return;
      setState(() {
        _device = device ?? const <String, Object?>{};
        _settings = settings;
        _topics = topics;
        _items = items;
        _runtime = runtime;
        _notificationAvailable = notificationAvailable;
        _channelStatus = channelStatus;
        _activeReviewNotificationIds = activeReviewNotificationIds;
        _nextOpportunity = nextOpportunity;
        _loading = false;
      });
    } catch (error, stackTrace) {
      final failure = error is _DiagnosticsLoadException
          ? '${error.stage}: ${error.cause}'
          : error;
      debugPrint('Diagnostics load failed: $failure\n$stackTrace');
      if (!mounted) return;
      final stage = error is _DiagnosticsLoadException ? error.stage : '诊断信息处理';
      final cause = error is _DiagnosticsLoadException ? error.cause : error;
      setState(() {
        _loading = false;
        _error = error is _DiagnosticsLoadException
            ? '${error.stage}读取失败（${error.cause.runtimeType}）'
            : '诊断信息处理失败（${error.runtimeType}）';
        _errorDetails = AppErrorDetails.format(
          stage: stage,
          error: cause,
          stackTrace: stackTrace,
        );
      });
    }
  }

  Future<T> _readDiagnostic<T>(String stage, Future<T> Function() read) async {
    try {
      return await read();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _DiagnosticsLoadException(stage, error),
        stackTrace,
      );
    }
  }

  List<ReviewItem> _matchingItems(ReminderSettings settings) => _items
      .where((item) => item.enabled && settings.scope.allows(item.topicId))
      .toList(growable: false);

  List<ReviewItem> _eligibleItems(ReminderSettings settings, DateTime now) {
    var scope = settings.scope;
    if (settings.hasWeeklyTopicPlan) {
      final weekdayTopics = settings.weeklyTopicIds[DateTime.now().weekday];
      if (weekdayTopics == null) return const <ReviewItem>[];
      if (settings.scope.mode == ReminderScopeMode.allTopics) {
        scope = ReminderScope.selectedTopics(weekdayTopics);
      } else {
        final intersection = weekdayTopics.intersection(
          settings.scope.topicIds,
        );
        if (intersection.isEmpty) return const <ReviewItem>[];
        scope = ReminderScope.selectedTopics(intersection);
      }
    }
    final topicMap = <int, Topic>{for (final topic in _topics) topic.id: topic};
    return ReminderCandidateSelector().eligibleItems(
      items: _items,
      scope: scope,
      repeatCooldown: settings.repeatCooldown,
      now: now,
      globalInterval: settings.reminderInterval,
      lastDispatchAt: _runtime?.lastDispatchAt,
      topicIntervals: <int, Duration>{
        for (final topic in topicMap.values)
          if (topic.reminderInterval != null) topic.id: topic.reminderInterval!,
      },
      topicLastRemindedAt: <int, DateTime>{
        for (final topic in topicMap.values)
          if (topic.lastRemindedAt != null) topic.id: topic.lastRemindedAt!,
      },
    );
  }

  String _channelStatusLabel() {
    final status = _channelStatus;
    if (status == null) return '无法读取';
    if (!status.appEnabled) return '应用通知权限未开启';
    if (!status.channelExists) return '提醒通道尚未创建';
    if (status.importance == null) return '无法读取提醒通道重要性';
    if (!status.bannerLikely) {
      return '通道重要性 ${status.importance!.name}，可能不显示横幅';
    }
    return '通道重要性 ${status.importance!.name}；横幅由系统设置决定';
  }

  String _formatDate(DateTime? value) =>
      value == null ? '暂无' : value.toLocal().toString().substring(0, 16);

  String _windowLabel(ReminderSettings settings) {
    final window = settings.activeWindow;
    if (window.startMinute == null) return '全天';
    String time(int minute) =>
        '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
    return '${time(window.startMinute!)} – ${time(window.endMinute!)}';
  }

  String _scopeLabel(ReminderSettings settings) {
    if (settings.scope.mode == ReminderScopeMode.allTopics) return '全部主题';
    final names = _topics
        .where((topic) => settings.scope.topicIds.contains(topic.id))
        .map((topic) => '${topic.name} (#${topic.id})')
        .join('、');
    return names.isEmpty
        ? '指定主题编号：${settings.scope.topicIds.join('、')}'
        : names;
  }

  String _evaluationLabel(String? outcome) => switch (outcome) {
    'reminderDisabled' => '提醒已关闭',
    'outsideActiveWindow' => '当前不在提醒时段',
    'foregroundSuppressed' => '应用正在前台，未发送提醒',
    'notificationUnavailable' => '通知权限不可用',
    'noEligibleItem' => '暂无符合条件的内容',
    'candidateSelected' => '已选出待提醒内容',
    'notification_pending' => '提醒正在提交到系统',
    'notification_submitted' => '已发送提醒',
    'notification_submission_failed' => '提醒发送失败',
    'store_failure' => '本地数据读取失败',
    'workerFailure' => '后台提醒任务异常，详情见“后台任务错误”',
    null => '暂无',
    _ => '状态未知',
  };

  String _evaluationSourceLabel(String? source) => switch (source) {
    'workmanager' => 'WorkManager 后台任务',
    'scheduled_alarm' => 'Android 系统计划闹钟',
    'native_alarm' => '旧版系统闹钟（无法区分触发来源）',
    'foreground_timer' => '应用前台计时器',
    'unspecified' => '来源未标记',
    null => '暂无',
    _ => source,
  };

  String _workerOutcomeLabel(String? outcome) => switch (outcome) {
    'running' => '运行中（尚无完成记录）',
    'reminderDisabled' => '提醒已关闭',
    'outsideActiveWindow' => '不在提醒时段',
    'foregroundSuppressed' => '应用在前台，跳过发送',
    'notificationUnavailable' => '通知权限不可用',
    'noEligibleItem' => '暂无符合条件的内容',
    'notificationSubmitted' => '已提交通知',
    'notificationSubmissionFailed' => '通知提交失败',
    'storeFailure' => '本地数据读取失败',
    'workerFailure' => '后台任务异常',
    null => '暂无记录',
    _ => outcome,
  };

  String _scheduleLabel(ReminderScheduleStatus status) => switch (status) {
    ReminderScheduleStatus.notScheduled => '尚未安排',
    ReminderScheduleStatus.scheduled => '已安排',
    ReminderScheduleStatus.disabled => '已关闭',
    ReminderScheduleStatus.failed => '安排失败，请检查系统后台运行设置',
  };

  String _report({required int matchingCount, required int eligibleCount}) {
    final settings = _settings!;
    final runtime = _runtime!;
    return <String>[
      '考研复习诊断报告',
      '设备：${_device['deviceModel'] ?? '未知'}',
      'Android：${_device['androidVersion'] ?? '未知'}',
      '应用：${_device['appVersion'] ?? '未知'}（构建号 ${_device['appBuild'] ?? '未知'}）',
      '通知权限：${_notificationAvailable ? '可用' : '未开启/不可用'}',
      '提醒：${settings.enabled ? '开启' : '关闭'}',
      '时段：${_windowLabel(settings)}',
      '间隔：${settings.reminderInterval.inMinutes} 分钟',
      '重复冷却上限：${settings.repeatCooldown.inMinutes} 分钟',
      '主题范围：${_scopeLabel(settings)}',
      '主题数量：${_topics.length}',
      '复习内容总数：${_items.length}',
      '复习内容编号：${_items.map((item) => item.id).join('、')}',
      '匹配内容数：$matchingCount',
      '当前可提醒数：$eligibleCount',
      '最近评估：${_formatDate(runtime.lastEvaluationAt)}（${_evaluationLabel(runtime.lastEvaluationOutcome)}）',
      '最近评估来源：${_evaluationSourceLabel(runtime.lastEvaluationSource)}',
      '最近通知：${_formatDate(runtime.lastDispatchAt)}，内容编号 ${runtime.lastDispatchItemId ?? '暂无'}，主题编号 ${runtime.lastDispatchTopicId ?? '暂无'}',
      '调度：${_scheduleLabel(runtime.scheduleStatus)}',
      '调度错误类型：${runtime.scheduleError ?? '暂无'}',
      '最近后台任务启动：${_formatDate(runtime.lastWorkerStartedAt)}',
      '最近后台任务完成：${_formatDate(runtime.lastWorkerCompletedAt)}',
      '最近后台任务结果：${_workerOutcomeLabel(runtime.lastWorkerOutcome)}',
      '系统当前活动复习通知编号：${_activeReviewNotificationIds.isEmpty ? '暂无' : _activeReviewNotificationIds.join('、')}',
      '横幅实际展示回执：Android 不向应用提供横幅是否显示的回执',
      '最近后台任务异常时间：${_formatDate(runtime.lastWorkerErrorAt)}',
      '后台任务错误详情：\n${runtime.lastWorkerErrorDetails ?? '暂无'}',
      '下一次机会（粗略估计）：${_formatDate(_nextOpportunity)}',
      '横幅通道：${_channelStatusLabel()}',
      '累计提醒次数：${_items.fold<int>(0, (sum, item) => sum + item.reminderCount)}',
      'OPPO Reno8 真机验证：NOT_VERIFIED_ON_DEVICE',
      '系统强行停止后的提醒：无法保证',
    ].join('\n');
  }

  Future<void> _copyReport(int matchingCount, int eligibleCount) async {
    await Clipboard.setData(
      ClipboardData(
        text: _report(
          matchingCount: matchingCount,
          eligibleCount: eligibleCount,
        ),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('诊断报告已复制')));
    }
  }

  Widget _row(String label, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(value),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('诊断信息')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_error!, textAlign: TextAlign.center),
                if (_errorDetails != null) ...<Widget>[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 360,
                    child: SingleChildScrollView(
                      child: SelectableText(_errorDetails!),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(text: _errorDetails!),
                      );
                      if (!messenger.mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('错误详情已复制')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('复制错误详情'),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    }
    final settings = _settings!;
    final now = DateTime.now().toUtc();
    final matching = _matchingItems(settings);
    final eligible = _eligibleItems(settings, now);
    final runtime = _runtime!;
    final report = _report(
      matchingCount: matching.length,
      eligibleCount: eligible.length,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断信息'),
        actions: <Widget>[
          IconButton(
            onPressed: _load,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          _row('设备型号', '${_device['deviceModel'] ?? '未知'}'),
          _row('Android 版本', '${_device['androidVersion'] ?? '未知'}'),
          _row(
            '应用版本/构建号',
            '${_device['appVersion'] ?? '未知'}（${_device['appBuild'] ?? '未知'}）',
          ),
          _row('通知权限', _notificationAvailable ? '可用' : '未开启或不可用'),
          _row('横幅通知通道', _channelStatusLabel()),
          _row('提醒状态', settings.enabled ? '已开启' : '已关闭'),
          _row('提醒时段', _windowLabel(settings)),
          _row('提醒间隔', '${settings.reminderInterval.inMinutes} 分钟'),
          _row('重复冷却上限', '${settings.repeatCooldown.inMinutes} 分钟'),
          _row('主题范围', _scopeLabel(settings)),
          _row('主题 / 内容数量', '${_topics.length} / ${_items.length}'),
          _row('匹配 / 可提醒数量', '${matching.length} / ${eligible.length}'),
          _row(
            '最近评估',
            '${_formatDate(runtime.lastEvaluationAt)} · ${_evaluationLabel(runtime.lastEvaluationOutcome)}',
          ),
          _row('最近评估来源', _evaluationSourceLabel(runtime.lastEvaluationSource)),
          _row(
            '最近通知',
            '${_formatDate(runtime.lastDispatchAt)} · 内容编号 ${runtime.lastDispatchItemId ?? '暂无'} · 主题编号 ${runtime.lastDispatchTopicId ?? '暂无'}',
          ),
          _row('调度状态', _scheduleLabel(runtime.scheduleStatus)),
          _row('调度错误类型', runtime.scheduleError ?? '暂无'),
          _row('最近后台任务启动', _formatDate(runtime.lastWorkerStartedAt)),
          _row('最近后台任务完成', _formatDate(runtime.lastWorkerCompletedAt)),
          _row('最近后台任务结果', _workerOutcomeLabel(runtime.lastWorkerOutcome)),
          _row(
            '系统当前活动复习通知编号',
            _activeReviewNotificationIds.isEmpty
                ? '暂无'
                : _activeReviewNotificationIds.join('、'),
          ),
          _row('横幅实际展示回执', 'Android 不向应用提供横幅是否显示的回执'),
          _row(
            '最近后台任务异常',
            '${_formatDate(runtime.lastWorkerErrorAt)}\n${runtime.lastWorkerErrorDetails ?? '暂无'}',
          ),
          _row('下一次机会（粗略估计）', _formatDate(_nextOpportunity)),
          _row(
            '累计提醒次数',
            '${_items.fold<int>(0, (sum, item) => sum + item.reminderCount)}',
          ),
          _row('OPPO Reno8 真机验证', '尚未验证（NOT_VERIFIED_ON_DEVICE）'),
          _row('系统强行停止后的提醒', '无法保证'),
          const SizedBox(height: 8),
          SelectableText('报告预览\n$report'),
        ],
      ),
      bottomSheet: SafeArea(
        child: Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            onPressed: () => _copyReport(matching.length, eligible.length),
            icon: const Icon(Icons.copy),
            label: const Text('复制诊断报告'),
          ),
        ),
      ),
    );
  }
}

final class _DiagnosticsLoadException implements Exception {
  const _DiagnosticsLoadException(this.stage, this.cause);

  final String stage;
  final Object cause;
}
