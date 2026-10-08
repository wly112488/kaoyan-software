import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import '../runtime/notification_tap_bus.dart';
import '../runtime/reminder_scheduler.dart';
import '../features/review/review_item_detail_page.dart';
import '../features/review/review_list_page.dart';
import '../features/settings/reminder_settings_page.dart';
import '../features/topics/topic_management_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.services, super.key});

  final AppServices services;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final List<Widget?> _pages;
  final _reviewPageKey = GlobalKey<ReviewListPageState>();
  final _topicsPageKey = GlobalKey<TopicManagementPageState>();
  final _settingsPageKey = GlobalKey<ReminderSettingsPageState>();
  StreamSubscription<int>? _notificationTapSubscription;
  final Set<int> _openingItemIds = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pages = <Widget?>[
      ReviewListPage(key: _reviewPageKey, services: widget.services),
      null,
      null,
    ];
    _notificationTapSubscription = NotificationTapBus.instance.stream.listen((
      itemId,
    ) {
      NotificationTapBus.instance.takePendingItemId();
      _openFromNotification(itemId);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeReminderRuntime());
      final pendingItemId = NotificationTapBus.instance.takePendingItemId();
      if (pendingItemId != null) _openFromNotification(pendingItemId);
    });
  }

  Future<void> _initializeReminderRuntime() async {
    await widget.services.initializeReminderRuntime();
    final runtimeError = widget.services.runtimeInitializationError;
    if (!mounted || runtimeError == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('提醒服务初始化失败（${runtimeError.runtimeType}），本地复习内容仍可使用。'),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationTapSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_settingsPageKey.currentState?.refreshPermissionStatus());
      // Repair a missing task without changing an already registered deadline.
      unawaited(
        widget.services.rescheduleReminders(policy: ReminderWorkPolicy.keep),
      );
    } else if (state == AppLifecycleState.paused) {
      unawaited(
        widget.services.rescheduleReminders(policy: ReminderWorkPolicy.keep),
      );
    }
  }

  Future<void> _openFromNotification(int itemId) async {
    if (!mounted || !_openingItemIds.add(itemId)) return;
    try {
      final item = await widget.services.reviewItems.getReviewItem(itemId);
      if (!mounted) return;
      if (item == null) {
        setState(() {
          _selectedIndex = 0;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _reviewPageKey.currentState?.refresh();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('内容已不可用')));
        });
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReviewItemDetailPage(services: widget.services, itemId: item.id),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开这条复习内容')));
    } finally {
      _openingItemIds.remove(itemId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = List<Widget>.generate(_pages.length, (index) {
      return _pages[index] ?? const SizedBox.shrink();
    });
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectPage,
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.menu_book), label: '复习'),
          NavigationDestination(icon: Icon(Icons.label_outline), label: '主题'),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            label: '设置',
          ),
        ],
      ),
    );
  }

  void _selectPage(int index) {
    final alreadyCreated = _pages[index] != null;
    setState(() {
      _selectedIndex = index;
      _pages[index] ??= switch (index) {
        0 => ReviewListPage(key: _reviewPageKey, services: widget.services),
        1 => TopicManagementPage(
          key: _topicsPageKey,
          services: widget.services,
        ),
        _ => ReminderSettingsPage(
          key: _settingsPageKey,
          services: widget.services,
        ),
      };
    });
    if (alreadyCreated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (index) {
          case 0:
            _reviewPageKey.currentState?.refresh();
          case 1:
            _topicsPageKey.currentState?.refresh();
          default:
            _settingsPageKey.currentState?.refreshTopics();
        }
      });
    }
  }
}
