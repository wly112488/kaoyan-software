import 'package:android_process_state/android_process_state.dart';

abstract interface class ForegroundStatus {
  Future<bool> isForeground();
}

final class AndroidForegroundStatus implements ForegroundStatus {
  AndroidForegroundStatus({AndroidProcessState? processState})
    : _processState = processState ?? const AndroidProcessState();

  final AndroidProcessState _processState;

  @override
  Future<bool> isForeground() => _processState.isForeground();
}
