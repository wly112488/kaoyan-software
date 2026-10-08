import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaoyan_review/runtime/foreground_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kaoyan_review/android_process_state');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('Android foreground status uses the process-state channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isForeground');
      return true;
    });

    final foreground = await AndroidForegroundStatus().isForeground();

    expect(foreground, isTrue);
  });
}
