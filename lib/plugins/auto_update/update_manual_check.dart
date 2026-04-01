import 'dart:async';

/// 由 [SocketServerPage] 等界面触发；[UpdateManager] 订阅后执行与定时器相同的强制检查。
class UpdateManualCheck {
  UpdateManualCheck._();

  static final StreamController<void> _requests = StreamController.broadcast();

  static Stream<void> get requests => _requests.stream;

  static void request() {
    if (!_requests.isClosed) {
      _requests.add(null);
    }
  }
}
