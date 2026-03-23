import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 连接状态枚举
enum ConnectionStatus {
  disconnected, // 未连接
  connecting, // 连接中
  connected, // 已连接
  error, // 错误
}

/// 消息日志
class ConnectionLog {
  final String message;
  final DateTime timestamp;
  final bool isIncoming; // true: 接收, false: 发送
  final String? error;

  ConnectionLog({
    required this.message,
    required this.timestamp,
    this.isIncoming = false,
    this.error,
  });

  String get formattedTime =>
      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';

  @override
  String toString() {
    final direction = isIncoming ? '收到' : '发送';
    final errorText = error != null ? ' [错误: $error]' : '';
    return '[$formattedTime] $direction: $message$errorText';
  }
}

/// 控制面板客户端服务
class ControllerClientService {
  // 单例模式
  static final ControllerClientService _instance = ControllerClientService._internal();
  factory ControllerClientService() => _instance;
  ControllerClientService._internal();

  // Socket连接
  Socket? _socket;

  // 连接状态
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;

  // 消息日志
  final List<ConnectionLog> _logs = [];
  static const int _maxLogs = 500; // 最多保存500条日志

  // 自动重连相关
  String? _serverIp; // 保存服务器IP用于重连
  bool _isManualDisconnect = false; // 是否为主动断开
  bool _isReconnecting = false; // 是否正在重连
  Timer? _reconnectTimer; // 重连定时器
  int _reconnectAttempts = 0; // 重连尝试次数
  static const int _maxReconnectDelay = 30; // 最大重连延迟（秒）
  static const int _initialReconnectDelay = 2; // 初始重连延迟（秒）

  // 状态流控制器
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _logsController = StreamController<List<ConnectionLog>>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  final _messageController = StreamController<String>.broadcast();

  // 获取状态流
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<List<ConnectionLog>> get logsStream => _logsController.stream;
  Stream<String?> get errorStream => _errorController.stream;
  Stream<String> get messageStream => _messageController.stream;

  // 获取当前状态
  ConnectionStatus get status => _connectionStatus;
  List<ConnectionLog> get logs => List.unmodifiable(_logs);
  String? get currentError => _currentError;
  String? _currentError;

  /// 连接到控制面板服务器
  Future<void> connect(String serverIp) async {
    _serverIp = serverIp;
    _isManualDisconnect = false;
    _reconnectAttempts = 0;
    _cancelReconnectTimer();

    await _doConnect(serverIp);
  }

  /// 执行连接
  Future<void> _doConnect(String serverIp) async {
    _currentError = null;
    _errorController.add(null);

    // 如果已连接，先断开
    if (_socket != null) {
      try {
        await _socket!.close();
      } catch (e) {
        debugPrint('关闭旧连接失败: $e');
      }
      _socket = null;
    }

    _connectionStatus = ConnectionStatus.connecting;
    _statusController.add(_connectionStatus);
    _addLog('正在连接: $serverIp:8888', isIncoming: false);

    try {
      _socket = await Socket.connect(
        serverIp,
        8888,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('连接超时', const Duration(seconds: 5));
        },
      );

      _connectionStatus = ConnectionStatus.connected;
      _statusController.add(_connectionStatus);
      _reconnectAttempts = 0; // 连接成功，重置重连次数
      _isReconnecting = false;
      _addLog('连接成功', isIncoming: false);

      // 监听接收消息
      _socket!.listen(
        (Uint8List data) {
          // 输出原始字节数据用于调试
          debugPrint('原始字节数据: $data');
          debugPrint('原始字节十六进制: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          
          // 尝试UTF-8解码
          String message;
          try {
            message = utf8.decode(data, allowMalformed: false);
          } catch (e) {
            // 如果UTF-8解码失败，尝试使用fromCharCodes作为备选
            debugPrint('UTF-8解码失败: $e，尝试使用fromCharCodes');
            message = String.fromCharCodes(data);
          }
          
          _addLog(message, isIncoming: true);
          // 通过消息流发送消息，供外部订阅处理
          _messageController.add(message);
        },
        onError: (error) {
          _handleDisconnection('连接错误: $error', error.toString());
        },
        onDone: () {
          _handleDisconnection('连接已断开', null);
        },
        cancelOnError: false,
      );
    } catch (e) {
      _handleDisconnection('连接失败: $e', e.toString());
    }
  }

  /// 处理断开连接
  void _handleDisconnection(String errorMsg, String? errorDetail) {
    _connectionStatus = ConnectionStatus.error;
    _statusController.add(_connectionStatus);
    _currentError = errorMsg;
    _errorController.add(errorMsg);
    _addLog(errorMsg, isIncoming: false, error: errorDetail);
    _socket = null;

    // 重置重连标志，允许重新安排重连
    _isReconnecting = false;

    // 如果不是主动断开，则自动重连
    if (!_isManualDisconnect && _serverIp != null) {
      _scheduleReconnect();
    }
  }

  /// 安排重连
  void _scheduleReconnect() {
    if (_isReconnecting || _isManualDisconnect || _serverIp == null) {
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    // 计算重连延迟（指数退避，但不超过最大值）
    final delay = (_initialReconnectDelay * (1 << (_reconnectAttempts - 1))).clamp(
      _initialReconnectDelay,
      _maxReconnectDelay,
    );

    _addLog('将在 ${delay}秒 后尝试第 $_reconnectAttempts 次重连...', isIncoming: false);

    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_isManualDisconnect && _serverIp != null) {
        _addLog('开始重连: $_serverIp:8888', isIncoming: false);
        _doConnect(_serverIp!);
      } else {
        _isReconnecting = false;
      }
    });
  }

  /// 取消重连定时器
  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
  }

  /// 断开连接（主动断开，不会自动重连）
  Future<void> disconnect() async {
    _isManualDisconnect = true;
    _cancelReconnectTimer();
    _serverIp = null;

    if (_socket != null) {
      try {
        await _socket!.close();
        _addLog('已主动断开连接', isIncoming: false);
      } catch (e) {
        debugPrint('断开连接失败: $e');
      }
      _socket = null;
    }
    _connectionStatus = ConnectionStatus.disconnected;
    _statusController.add(_connectionStatus);
  }

  /// 发送消息
  Future<bool> sendMessage(String message) async {
    if (_socket == null || _connectionStatus != ConnectionStatus.connected) {
      _addLog('未连接，无法发送消息', isIncoming: false, error: '未连接');
      return false;
    }

    try {
      _socket!.add(message.codeUnits);
      _addLog(message, isIncoming: false);
      return true;
    } catch (e) {
      _addLog('发送消息失败: $message', isIncoming: false, error: e.toString());
      return false;
    }
  }

  /// 添加日志
  void _addLog(String message, {bool isIncoming = false, String? error}) {
    final log = ConnectionLog(
      message: message,
      timestamp: DateTime.now(),
      isIncoming: isIncoming,
      error: error,
    );

    // 输出到终端
    print(log.toString());

    _logs.add(log);

    // 限制日志数量
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    _logsController.add(List.from(_logs));
  }

  /// 清空日志
  void clearLogs() {
    _logs.clear();
    _logsController.add([]);
  }

  /// 释放资源
  void dispose() {
    _isManualDisconnect = true;
    _cancelReconnectTimer();
    disconnect();
    _statusController.close();
    _logsController.close();
    _errorController.close();
    _messageController.close();
  }
}
