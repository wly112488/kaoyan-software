import 'package:flutter/material.dart';

import '../../app/app_error_details.dart';
import '../../app/app_services.dart';
import '../../domain/review_item.dart';
import '../../domain/topic.dart';
import '../topics/topic_form_dialog.dart';
import 'review_item_detail_page.dart';
import 'review_item_form_page.dart';

class ReviewListPage extends StatefulWidget {
  const ReviewListPage({required this.services, super.key});

  final AppServices services;

  @override
  ReviewListPageState createState() => ReviewListPageState();
}

class ReviewListPageState extends State<ReviewListPage> {
  final TextEditingController _searchController = TextEditingController();
  List<ReviewItem> _items = const <ReviewItem>[];
  List<Topic> _topics = const <Topic>[];
  int? _topicFilter;
  String _search = '';
  bool _loading = true;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!_hasLoaded) setState(() => _loading = true);
    var stage = '复习内容';
    try {
      final items = await widget.services.reviewItems.listReviewItems();
      stage = '主题数据';
      final topics = await widget.services.topics.listTopics();
      if (!mounted) return;
      setState(() {
        _items = items;
        _topics = topics;
        _loading = false;
        _hasLoaded = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Review list reload failed at $stage: $error\n$stackTrace');
      if (mounted) setState(() => _loading = false);
      if (mounted) {
        showAppErrorSnackBar(
          context,
          message: '$stage读取失败',
          details: AppErrorDetails.format(
            stage: '$stage读取',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
  }

  Future<void> refresh() => _reload();

  List<ReviewItem> get _visibleItems {
    final query = _search.trim().toLowerCase();
    return _items.where((item) {
      return (_topicFilter == null || item.topicId == _topicFilter) &&
          (query.isEmpty || item.content.toLowerCase().contains(query));
    }).toList();
  }

  Future<void> _addItem() async {
    if (_topics.isEmpty) {
      final topic = await showTopicFormDialog(
        context,
        repository: widget.services.topics,
      );
      if (topic == null || !mounted) return;
      setState(() => _topics = <Topic>[..._topics, topic]);
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => ReviewItemFormPage(
            services: widget.services,
            initialTopicId: topic.id,
          ),
        ),
      );
      if (saved == true) await _reload();
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => ReviewItemFormPage(services: widget.services),
      ),
    );
    if (saved == true) await _reload();
  }

  Future<void> _openItem(ReviewItem item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) =>
            ReviewItemDetailPage(services: widget.services, itemId: item.id),
      ),
    );
    if (changed == true) await _reload();
  }

  Future<void> _toggleItem(ReviewItem item, bool enabled) async {
    var stage = '复习内容提醒状态更新';
    try {
      await widget.services.reviewItems.updateReviewItem(
        id: item.id,
        content: item.content,
        topicId: item.topicId,
        enabled: enabled,
        now: DateTime.now(),
      );
      stage = '提醒调度更新';
      await widget.services.rescheduleReminders();
      await _reload();
    } catch (error, stackTrace) {
      debugPrint('Review item toggle failed at $stage: $error\n$stackTrace');
      if (!mounted) return;
      showAppErrorSnackBar(
        context,
        message: '$stage失败',
        details: AppErrorDetails.format(
          stage: stage,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final items = _visibleItems;
    return Scaffold(
      appBar: AppBar(title: const Text('复习内容')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('review-add-button'),
        heroTag: 'review-list-add',
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('添加复习内容'),
      ),
      body: _items.isEmpty
          ? _emptyState()
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    key: const ValueKey('review-search-field'),
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: '搜索复习内容',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                _topicFilters(),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('没有符合条件的内容'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                          itemCount: items.length,
                          itemBuilder: (context, index) =>
                              _itemTile(items[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.menu_book_outlined, size: 56),
            const SizedBox(height: 12),
            const Text('还没有复习内容'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              label: Text(_topics.isEmpty ? '创建第一个主题' : '添加复习内容'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topicFilters() {
    return SizedBox(
      height: 52,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          ChoiceChip(
            label: const Text('全部主题'),
            selected: _topicFilter == null,
            onSelected: (_) => setState(() => _topicFilter = null),
          ),
          for (final topic in _topics)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChoiceChip(
                label: Text(topic.name),
                selected: _topicFilter == topic.id,
                onSelected: (_) => setState(() => _topicFilter = topic.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemTile(ReviewItem item) {
    final topicName = _topics
        .where((topic) => topic.id == item.topicId)
        .map((topic) => topic.name)
        .firstOrNull;
    return Card(
      child: ListTile(
        onTap: () => _openItem(item),
        title: Text(item.content, maxLines: 3, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${topicName ?? '主题已删除'} · ${item.enabled ? '参与提醒' : '已暂停'}',
        ),
        trailing: Switch(
          key: ValueKey('item-enabled-${item.id}'),
          value: item.enabled,
          onChanged: (value) => _toggleItem(item, value),
        ),
      ),
    );
  }
}
