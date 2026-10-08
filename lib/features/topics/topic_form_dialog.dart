import 'package:flutter/material.dart';

import '../../data/local/topic_repository.dart';
import '../../domain/topic.dart';

Future<Topic?> showTopicFormDialog(
  BuildContext context, {
  required TopicRepository repository,
  Topic? topic,
}) {
  return showDialog<Topic>(
    context: context,
    builder: (_) => _TopicFormDialog(repository: repository, topic: topic),
  );
}

class _TopicFormDialog extends StatefulWidget {
  const _TopicFormDialog({required this.repository, this.topic});

  final TopicRepository repository;
  final Topic? topic;

  @override
  State<_TopicFormDialog> createState() => _TopicFormDialogState();
}

class _TopicFormDialogState extends State<_TopicFormDialog> {
  late final TextEditingController _nameController;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.topic?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text;
    if (name.trim().isEmpty) {
      setState(() => _error = '主题名称不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final saved = widget.topic == null
          ? await widget.repository.createTopic(name: name, now: now)
          : await widget.repository.renameTopic(
              id: widget.topic!.id,
              name: name,
              now: now,
            );
      if (mounted) Navigator.pop(context, saved);
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message.contains('already exists')
            ? '已存在同名主题'
            : '无法保存主题，请检查后重试';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '无法保存主题，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.topic != null;
    return AlertDialog(
      title: Text(isEditing ? '重命名主题' : '新建主题'),
      content: TextField(
        key: const ValueKey('topic-name-field'),
        controller: _nameController,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: '主题名称', errorText: _error),
        onSubmitted: (_) => _save(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(isEditing ? '保存' : '保存主题'),
        ),
      ],
    );
  }
}
