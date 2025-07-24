import 'dart:async';

// 定义一个事件总线类，用于组件间通信
class ShipControlEventBus {
  // 单例模式
  static final ShipControlEventBus _instance = ShipControlEventBus._internal();

  factory ShipControlEventBus() {
    return _instance;
  }

  ShipControlEventBus._internal();

  // 控制命令流
  final _controlCommandController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get commandStream =>
      _controlCommandController.stream;

  // 发送控制命令
  void emitCommand(String command, {bool isStart = true}) {
    _controlCommandController.add({'command': command, 'isStart': isStart});
  }

  // 发送跃迁相关命令
  void emitJumpCommand(String command, {double? chargeLevel}) {
    _controlCommandController.add({
      'command': command,
      'chargeLevel': chargeLevel,
    });
  }

  void dispose() {
    _controlCommandController.close();
  }
}

// 全局访问点
final shipControlEventBus = ShipControlEventBus();
