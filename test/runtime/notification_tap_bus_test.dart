import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/runtime/notification_tap_bus.dart';

void main() {
  test('tap bus broadcasts IDs and keeps the latest pending ID', () async {
    final bus = NotificationTapBus.instance;
    bus.takePendingItemId();
    final received = <int>[];
    final subscription = bus.stream.listen(received.add);

    bus.record(17);
    bus.record(42);
    await Future<void>.delayed(Duration.zero);

    expect(received, <int>[17, 42]);
    expect(bus.takePendingItemId(), 42);
    expect(bus.takePendingItemId(), isNull);
    await subscription.cancel();
  });
}
