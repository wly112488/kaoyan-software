import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../domain/review_item.dart';
import '../../domain/topic.dart';
import 'review_item_form_page.dart';

class ReviewItemDetailPage extends StatefulWidget {
  const ReviewItemDetailPage({
    required this.services,
    required this.itemId,
    super.key,
  });

  final AppServices services;
  final int itemId;

  @override
  State<ReviewItemDetailPage> createState() => _ReviewItemDetailPageState();
}

class _ReviewItemDetailPageState extends State<ReviewItemDetailPage> {
  late Future<ReviewItem?> _itemFuture;
  late Future<List<Topic>> _topicsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
    _topicsFuture = widget.services.topics.listTopics();
  }

  void _reload() {
    _itemFuture = widget.services.reviewItems.getReviewItem(widget.itemId);
  }

  Future<void> _edit(ReviewItem item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) =>
            ReviewItemFormPage(services: widget.services, item: item),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _reload();
        _topicsFuture = widget.services.topics.listTopics();
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除复习内容？'),
        content: const Text('删除后无法恢复。'),
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
      await widget.services.reviewItems.deleteReviewItem(widget.itemId);
      await widget.services.rescheduleReminders();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败，内容可能已被移除')));
      setState(_reload);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('复习内容详情')),
      body: FutureBuilder<ReviewItem?>(
        future: _itemFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final item = snapshot.data;
          if (snapshot.hasError || item == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('内容已不可用'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回列表'),
                  ),
                ],
              ),
            );
          }
          return _buildItem(context, item);
        },
      ),
    );
  }

  Widget _buildItem(BuildContext context, ReviewItem item) {
    return FutureBuilder(
      future: _topicsFuture,
      builder: (context, topicsSnapshot) {
        final topics = topicsSnapshot.data ?? const [];
        final topicName = topics
            .where((topic) => topic.id == item.topicId)
            .map((topic) => topic.name)
            .firstOrNull;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            if (topicName != null) Chip(label: Text(topicName)),
            SelectableText(
              item.content,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Text(item.enabled ? '参与提醒' : '已暂停提醒'),
            if (item.lastShownAt != null)
              Text('最近提醒：${item.lastShownAt!.toLocal()}'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _edit(item),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑'),
            ),
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除'),
            ),
          ],
        );
      },
    );
  }
}
