import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_error_details.dart';
import '../../app/app_services.dart';
import '../../domain/reminder_settings.dart';
import '../../domain/topic.dart';
import 'topic_form_dialog.dart';

class TopicManagementPage extends StatefulWidget {
  const TopicManagementPage({required this.services, super.key});

  final AppServices services;

  @override
  TopicManagementPageState createState() => TopicManagementPageState();
}

class TopicManagementPageState extends State<TopicManagementPage> {
  bool _loading = true;
  List<Topic> _topics = const <Topic>[];
  Map<int, int> _itemCounts = const <int, int>{};
  Duration _globalInterval = const Duration(minutes: 60);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final topics = await widget.services.topics.listTopics();
      final items = await widget.services.reviewItems.listReviewItems();
      final settings = await widget.services.reminderSettings.loadSettings();
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _globalInterval = settings.reminderInterval;
        _itemCounts = <int, int>{
          for (final topic in topics)
            topic.id: items.where((item) => item.topicId == topic.id).length,
        };
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Topic list reload failed: $error\n$stackTrace');
      if (mounted) setState(() => _loading = false);
      if (mounted) {
        showAppErrorSnackBar(
          context,
          message: '读取主题失败，请重试',
          details: AppErrorDetails.format(
            stage: '主题列表读取',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
  }

  Future<void> refresh() => _reload();

  Future<void> _createTopic() async {
    final topic = await showTopicFormDialog(
      context,
      repository: widget.services.topics,
    );
    if (topic != null) await _reload();
  }

  Future<void> _renameTopic(Topic topic) async {
    final updated = await showTopicFormDialog(
      context,
      repository: widget.services.topics,
      topic: topic,
    );
    if (updated != null) await _reload();
  }

  Future<void> _deleteTopic(Topic topic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除主题？'),
        content: Text('确定删除“${topic.name}”吗？此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.services.topics.deleteTopic(topic.id);
      await _reload();
    } on StateError catch (error) {
      final message = error.message.contains('still owns ReviewItems')
          ? '该主题下还有复习内容，请先移动或删除这些内容。'
          : error.message.contains('last selected Topic')
          ? '它是提醒范围内最后一个主题，请先调整提醒范围。'
          : error.message.contains('last Topic for weekday')
          ? '它是某个星期计划里的最后一个主题，请先调整每周计划。'
          : '无法删除这个主题';
      _showMessage(message);
    } catch (_) {
      _showMessage('删除失败，请重试');
    }
  }

  Future<void> _setReminderInterval(Topic topic) async {
    final controller = TextEditingController(
      text: '${(topic.reminderInterval ?? _globalInterval).inMinutes}',
    );
    String? error;
    final result = await showDialog<(bool, Duration?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${topic.name} 的提醒间隔'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: '分钟',
              helperText:
                  '至少 ${_globalInterval.inMinutes} 分钟，最多 ${maximumRepeatCooldown.inMinutes} 分钟',
              errorText: error,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, (true, null)),
              child: const Text('继承全局'),
            ),
            FilledButton(
              onPressed: () {
                final minutes = int.tryParse(controller.text);
                if (minutes == null ||
                    minutes < _globalInterval.inMinutes ||
                    minutes > maximumRepeatCooldown.inMinutes) {
                  setDialogState(() => error = '请输入有效分钟数');
                  return;
                }
                Navigator.pop(dialogContext, (
                  true,
                  Duration(minutes: minutes),
                ));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !result.$1) return;
    try {
      await widget.services.topics.setReminderInterval(
        id: topic.id,
        interval: result.$2,
        now: DateTime.now(),
      );
      await widget.services.rescheduleReminders();
      await _reload();
    } catch (_) {
      _showMessage('保存主题提醒间隔失败');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('主题管理')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'topic-management-add',
        onPressed: _createTopic,
        icon: const Icon(Icons.add),
        label: const Text('新建主题'),
      ),
      body: _topics.isEmpty
          ? const Center(child: Text('还没有主题'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              itemCount: _topics.length,
              itemBuilder: (context, index) {
                final topic = _topics[index];
                return Card(
                  child: ListTile(
                    title: Text(topic.name),
                    subtitle: Text(
                      '${_itemCounts[topic.id] ?? 0} 条复习内容 · 提醒间隔 '
                      '${(topic.reminderInterval ?? _globalInterval).inMinutes} 分钟'
                      '${topic.reminderInterval == null ? '（默认）' : ''}',
                    ),
                    trailing: Wrap(
                      children: <Widget>[
                        IconButton(
                          tooltip: '提醒间隔',
                          onPressed: () => _setReminderInterval(topic),
                          icon: const Icon(Icons.schedule_outlined),
                        ),
                        IconButton(
                          tooltip: '重命名',
                          onPressed: () => _renameTopic(topic),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: '删除',
                          onPressed: () => _deleteTopic(topic),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
