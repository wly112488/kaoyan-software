import 'dart:async';

final class NotificationTapBus {
  NotificationTapBus._();

  static final NotificationTapBus instance = NotificationTapBus._();

  final StreamController<int> _controller = StreamController<int>.broadcast();
  int? _pendingItemId;

  Stream<int> get stream => _controller.stream;

  int? takePendingItemId() {
    final value = _pendingItemId;
    _pendingItemId = null;
    return value;
  }

  void record(int itemId) {
    _pendingItemId = itemId;
    _controller.add(itemId);
  }
}
