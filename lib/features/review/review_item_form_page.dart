import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../domain/review_item.dart';
import '../../domain/topic.dart';

class ReviewItemFormPage extends StatefulWidget {
  const ReviewItemFormPage({
    required this.services,
    this.item,
    this.initialTopicId,
    super.key,
  });

  final AppServices services;
  final ReviewItem? item;
  final int? initialTopicId;

  @override
  State<ReviewItemFormPage> createState() => _ReviewItemFormPageState();
}

class _ReviewItemFormPageState extends State<ReviewItemFormPage> {
  late final TextEditingController _contentController;
  List<Topic> _topics = const <Topic>[];
  int? _selectedTopicId;
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(
      text: widget.item?.content ?? '',
    );
    _enabled = widget.item?.enabled ?? true;
    _loadTopics();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    try {
      final topics = await widget.services.topics.listTopics();
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _selectedTopicId =
            widget.item?.topicId ??
            widget.initialTopicId ??
            (topics.isEmpty ? null : topics.first.id);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '读取主题失败，请返回重试';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_contentController.text.trim().isEmpty) {
      setState(() => _error = '正文不能为空');
      return;
    }
    final topicId = _selectedTopicId;
    if (topicId == null) {
      setState(() => _error = '请先创建一个主题');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final item = widget.item;
      if (item == null) {
        await widget.services.reviewItems.createReviewItem(
          content: _contentController.text,
          topicId: topicId,
          enabled: _enabled,
          now: DateTime.now(),
        );
      } else {
        await widget.services.reviewItems.updateReviewItem(
          id: item.id,
          content: _contentController.text,
          topicId: topicId,
          enabled: _enabled,
          now: DateTime.now(),
        );
      }
      await widget.services.rescheduleReminders();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败，请检查主题后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(
        title: Text(item == null ? '新增复习内容' : '编辑复习内容'),
        actions: <Widget>[
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                TextField(
                  key: const ValueKey('review-content-field'),
                  controller: _contentController,
                  autofocus: item == null,
                  minLines: 8,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: '复习内容',
                    hintText: '粘贴或输入需要复习的文字',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<int>(
                  key: const ValueKey('review-topic-field'),
                  initialValue: _selectedTopicId,
                  decoration: const InputDecoration(
                    labelText: '所属主题',
                    border: OutlineInputBorder(),
                  ),
                  items: _topics
                      .map(
                        (topic) => DropdownMenuItem<int>(
                          value: topic.id,
                          child: Text(topic.name),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _selectedTopicId = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('参与提醒'),
                  value: _enabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_saving) const LinearProgressIndicator(),
              ],
            ),
    );
  }
}
