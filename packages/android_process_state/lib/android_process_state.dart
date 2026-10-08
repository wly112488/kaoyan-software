import 'package:flutter/services.dart';

final class AndroidProcessState {
  const AndroidProcessState();

  static const MethodChannel _channel = MethodChannel(
    'kaoyan_review/android_process_state',
  );

  Future<bool> isForeground() async {
    return await _channel.invokeMethod<bool>('isForeground') ?? false;
  }
}
