import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 消息日志类
/// 
/// 用于记录和展示Socket通信中的收发消息。
/// 包含客户端地址、消息内容、时间戳和消息方向（接收/发送）。
class MessageLog {
  final String clientAddress; // 客户端地址
  final String message;       // 消息内容
  final DateTime timestamp;   // 记录时间
  final bool isIncoming;      // true表示接收的消息，false表示发送的消息

  MessageLog({
    required this.clientAddress,
    required this.message,
    required this.timestamp,
    required this.isIncoming,
  });

  /// 获取格式化的时间字符串 HH:mm:ss
  String get formattedTime =>
      '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';

  @override
  String toString() {
    final direction = isIncoming ? '收到' : '发送';
    return '[$formattedTime] $direction ($clientAddress): $message';
  }
}

/// 客户端连接类
/// 
/// 封装了连接的客户端信息，统一管理TCP Socket和WebSocket连接。
class ClientConnection {
  final String clientAddress; // 客户端IP:端口
  final String clientType;    // 连接类型："Socket" 或 "WebSocket"
  final DateTime connectTime; // 连接建立时间
  final dynamic connection;   // 底层连接对象：Socket 或 WebSocket

  ClientConnection({
    required this.clientAddress,
    required this.clientType,
    required this.connectTime,
    required this.connection,
  });

  /// 获取显示名称
  String get displayName => "$clientType客户端: $clientAddress";

  /// 获取格式化的连接时间 MM-dd HH:mm:ss
  String get formattedConnectTime {
    return '${connectTime.month}-${connectTime.day} ${connectTime.hour}:${connectTime.minute.toString().padLeft(2, '0')}:${connectTime.second.toString().padLeft(2, '0')}';
  }
}

// 全局单例访问点
final socketService = SocketService();

/// Socket服务类
/// 
/// 负责管理TCP Socket和WebSocket服务器的生命周期。
/// 提供启动/停止服务、处理连接、广播消息、发送特定消息等功能。
/// 实现了单例模式，确保全局只有一个服务实例。
class SocketService {
  bool isServerRunning = false;
  String statusMessage = "服务未启动";
  List<ClientConnection> clientConnections = []; // 当前所有活跃连接
  ServerSocket? server;      // TCP Socket服务器实例
  HttpServer? httpServer;    // WebSocket服务器实例（基于HttpServer升级）
  List<Socket> sockets = []; // 活跃的TCP Socket列表
  List<WebSocket> webSockets = []; // 活跃的WebSocket列表
  String serverIp = "0.0.0.0";
  int serverPort = 8888;     // TCP服务端口
  int webSocketPort = 8889;  // WebSocket服务端口

  // 消息日志
  final List<MessageLog> _messageLogs = [];

  // 消息日志通知
  final _messageLogController = StreamController<List<MessageLog>>.broadcast();
  Stream<List<MessageLog>> get messageLogStream => _messageLogController.stream;

  // 特定消息类型监听
  final _specificMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get specificMessageStream =>
      _specificMessageController.stream;

  // 状态变化通知
  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  // 客户端列表变化通知
  final _clientsController =
      StreamController<List<ClientConnection>>.broadcast();
  Stream<List<ClientConnection>> get clientsStream => _clientsController.stream;

  // 服务器状态变化通知
  final _runningController = StreamController<bool>.broadcast();
  Stream<bool> get runningStream => _runningController.stream;

  // Ping定时器
  Timer? _pingTimer;
  static const String _pingMessage = "__PING__";
  static const Duration _pingInterval = Duration(seconds: 30);

  // 单例模式
  static final SocketService _instance = SocketService._internal();

  factory SocketService() {
    return _instance;
  }

  SocketService._internal() {
    // 不在构造函数中启动服务，改为延迟初始化
    // 只设置生命周期监听
    _setupAppLifecycleListener();
  }

  // 添加初始化方法，在应用启动后调用
  Future<void> initialize() async {
    // 启动服务器
    await startServer();
  }

  void _setupAppLifecycleListener() {
    // 添加应用生命周期状态监听
    SystemChannels.lifecycle.setMessageHandler((msg) async {
      if (msg == AppLifecycleState.resumed.toString()) {
        print("应用恢复前台，检查Socket服务状态");
        // 应用从后台恢复时重新检查并启动服务
        if (isServerRunning) {
          // 先停止现有服务
          print("重启Socket服务");
          stopServer();
          // 延迟一小段时间确保资源释放
          await Future.delayed(Duration(milliseconds: 500));
          // 再重新启动服务
          await startServer();
          statusMessage =
              "服务已启动：\nNativeSocket：$serverIp:$serverPort\nWebSocket：$serverIp:$webSocketPort";
          _notifyStatusChange();
        } else {
          // 如果服务未运行，尝试启动服务
          await startServer();
        }
      }
      return null;
    });
  }

  void dispose() {
    stopServer();
    _statusController.close();
    _clientsController.close();
    _runningController.close();
    _messageLogController.close();
    _specificMessageController.close();
  }

  // 启动Socket服务器和WebSocket服务器
  Future<void> startServer() async {
    if (isServerRunning) return;

    try {
      print("开始启动Socket服务...");
      await _getLocalIpAddress();
      print("获取到本地IP地址: $serverIp");

      try {
        // 启动原生Socket服务器
        print("尝试绑定Socket服务器到端口: $serverPort");
        server = await ServerSocket.bind(InternetAddress.anyIPv4, serverPort);
        print("Socket服务器绑定成功");
      } catch (e) {
        print("Socket服务器绑定失败: $e");
        throw e;
      }

      try {
        // 启动WebSocket服务器
        print("尝试绑定WebSocket服务器到端口: $webSocketPort");
        httpServer = await HttpServer.bind(
          InternetAddress.anyIPv4,
          webSocketPort,
        );
        print("WebSocket服务器绑定成功");
      } catch (e) {
        print("WebSocket服务器绑定失败: $e");
        // 如果Socket服务器已启动但WebSocket启动失败，需要关闭Socket服务器
        server?.close();
        server = null;
        throw e;
      }

      isServerRunning = true;
      statusMessage =
          "服务已启动：\nSocket：$serverIp:$serverPort\nWebSocket：$serverIp:$webSocketPort";
      _notifyStatusChange();

      // 启动Ping定时器
      _startPingTimer();

      // 处理Socket连接
      server!.listen(
        (socket) {
          _handleConnection(socket);
        },
        onError: (error) {
          print("Socket服务错误: $error");
          statusMessage = "Socket服务错误: $error";
          _notifyStatusChange();
        },
        onDone: () {
          print("Socket服务已关闭");
          if (isServerRunning && httpServer == null) {
            stopServer();
          }
        },
      );

      // 处理WebSocket连接
      httpServer!.listen(
        (HttpRequest request) async {
          if (request.uri.path == '/ws') {
            try {
              // 将HTTP请求升级为WebSocket连接
              final webSocket = await WebSocketTransformer.upgrade(request);
              _handleWebSocketConnection(
                webSocket,
                request.connectionInfo?.remoteAddress.address,
              );
            } catch (e) {
              print("WebSocket握手失败: $e");
              request.response.statusCode = HttpStatus.internalServerError;
              request.response.close();
            }
          } else {
            // 返回简单的HTML页面，提示WebSocket服务正在运行
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(
                '<html><body><h1>WebSocket服务正在运行</h1>'
                '<p>WebSocket端点: ws://$serverIp:$webSocketPort/ws</p></body></html>',
              )
              ..close();
          }
        },
        onError: (error) {
          print("WebSocket服务错误: $error");
          statusMessage = "WebSocket服务错误: $error";
          _notifyStatusChange();
        },
        onDone: () {
          print("WebSocket服务已关闭");
          if (isServerRunning && server == null) {
            stopServer();
          }
        },
      );
    } catch (e) {
      print("启动服务失败，详细错误: $e");
      statusMessage = "启动服务失败: $e";
      _notifyStatusChange();
      stopServer();
    }
  }

  // 停止Socket服务器
  void stopServer() {
    // 停止Ping定时器
    _pingTimer?.cancel();
    _pingTimer = null;

    // 关闭所有Socket连接
    for (var socket in sockets) {
      try {
        socket.destroy();
      } catch (e) {
        print("关闭Socket连接时出错: $e");
      }
    }
    server?.close();
    server = null;

    // 关闭所有WebSocket连接
    for (var ws in webSockets) {
      try {
        ws.close();
      } catch (e) {
        print("关闭WebSocket连接时出错: $e");
      }
    }
    httpServer?.close(force: true);
    httpServer = null;

    isServerRunning = false;
    statusMessage = "服务已停止";
    clientConnections.clear();
    sockets.clear();
    webSockets.clear();
    _messageLogs.clear(); // 清空消息日志
    _notifyStatusChange();
    _notifyMessageLogChange();
  }

  // 处理Socket新连接
  void _handleConnection(Socket socket) {
    final clientIp = socket.remoteAddress.address;
    final clientAddress =
        "${socket.remoteAddress.address}:${socket.remotePort}";

    // 按IP地址去重：如果已存在相同IP的连接，先移除旧连接
    final existingConnections = clientConnections.where((conn) {
      if (conn.clientType == "Socket" && conn.connection is Socket) {
        final existingSocket = conn.connection as Socket;
        return existingSocket.remoteAddress.address == clientIp;
      }
      return false;
    }).toList();

    // 移除相同IP的旧连接
    for (var oldConn in existingConnections) {
      final oldSocket = oldConn.connection as Socket;
      final oldAddress = "${oldSocket.remoteAddress.address}:${oldSocket.remotePort}";
      print("检测到相同IP的新连接，移除旧连接: $oldAddress");
      _removeSocketClient(oldSocket, oldAddress);
    }

    sockets.add(socket);

    // 注意：TCP Keepalive通过ping机制实现
    // Dart的Socket API不直接支持设置keepalive选项
    // 但我们的ping机制（每30秒发送一次ping）可以检测连接状态

    clientConnections.add(
      ClientConnection(
        clientAddress: clientAddress,
        clientType: "Socket",
        connectTime: DateTime.now(),
        connection: socket,
      ),
    );
    _notifyClientsChange();

    // 监听客户端消息
    socket.listen(
      (Uint8List data) {
        // 处理接收到的数据（使用UTF-8解码）
        final message = utf8.decode(data);
        
        // 忽略ping消息，不记录日志
        if (message == _pingMessage) {
          return;
        }
        
        print("收到来自Socket客户端 $clientAddress 的消息: $message");

        // 添加消息日志
        _addMessageLog(
          clientAddress: clientAddress,
          message: message,
          isIncoming: true,
        );

        // 处理特定消息类型
        _processSpecificMessage(message);
      },
      onError: (error) {
        print("Socket连接错误 $clientAddress: $error");
        _removeSocketClient(socket, clientAddress);
      },
      onDone: () {
        print("Socket客户端断开连接 $clientAddress");
        _removeSocketClient(socket, clientAddress);
      },
    );
  }

  // 处理WebSocket新连接
  void _handleWebSocketConnection(WebSocket webSocket, String? remoteAddress) {
    webSockets.add(webSocket);
    // 构建WebSocket客户端地址
    final clientAddress = remoteAddress ?? '未知IP';

    clientConnections.add(
      ClientConnection(
        clientAddress: clientAddress,
        clientType: "WebSocket",
        connectTime: DateTime.now(),
        connection: webSocket,
      ),
    );
    _notifyClientsChange();

    // 监听WebSocket消息
    webSocket.listen(
      (dynamic data) {
        // WebSocket数据可能是String或Uint8List
        final message = data is String ? data : String.fromCharCodes(data);
        
        // 忽略ping消息，不记录日志
        if (message == _pingMessage) {
          return;
        }
        
        print("收到来自WebSocket客户端 $clientAddress 的消息: $message");

        // 添加消息日志
        _addMessageLog(
          clientAddress: "WebSocket客户端: $clientAddress",
          message: message,
          isIncoming: true,
        );

        // 处理特定消息类型
        _processSpecificMessage(message);
      },
      onError: (error) {
        print("WebSocket连接错误 $clientAddress: $error");
        _removeWebSocketClient(webSocket, clientAddress);
      },
      onDone: () {
        print("WebSocket客户端断开连接 $clientAddress");
        _removeWebSocketClient(webSocket, clientAddress);
      },
    );
  }

  // 移除断开连接的Socket客户端
  void _removeSocketClient(Socket socket, String clientAddress) {
    try {
      socket.destroy();
    } catch (e) {
      print("销毁Socket连接时出错 $clientAddress: $e");
    }
    sockets.remove(socket);

    clientConnections.removeWhere((conn) => conn.connection == socket);
    _notifyClientsChange();
    print("已从连接列表移除Socket客户端: $clientAddress");
  }

  // 移除断开连接的WebSocket客户端
  void _removeWebSocketClient(WebSocket webSocket, String clientAddress) {
    try {
      webSocket.close();
    } catch (e) {
      print("关闭WebSocket连接时出错 $clientAddress: $e");
    }
    webSockets.remove(webSocket);

    // 使用WebSocket对象引用来移除客户端连接
    clientConnections.removeWhere((conn) => conn.connection == webSocket);
    _notifyClientsChange();
    print("已从连接列表移除WebSocket客户端: $clientAddress");
  }

  // 获取本地IP地址
  Future<void> _getLocalIpAddress() async {
    try {
      print("开始获取本地IP地址...");
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      print("找到网络接口数量: ${interfaces.length}");
      // 打印所有网络接口信息，用于调试
      for (var interface in interfaces) {
        print("接口名称: ${interface.name}, 地址数量: ${interface.addresses.length}");
        for (var addr in interface.addresses) {
          print(
            "  - ${addr.address} (${addr.isLoopback ? '回环' : '非回环'}, ${addr.isLinkLocal ? '本地链接' : '非本地链接'})",
          );
        }
      }

      // 首先尝试找到非回环、非本地链接的地址
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            print("选择非回环、非本地链接地址: ${addr.address}");
            serverIp = addr.address;
            return;
          }
        }
      }

      // 如果没有找到理想的地址，尝试找到任何非回环地址
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            print("选择非回环地址: ${addr.address}");
            serverIp = addr.address;
            return;
          }
        }
      }

      // 如果还是没有找到，使用回环地址
      print("未找到合适的IP地址，使用回环地址: 127.0.0.1");
      serverIp = "127.0.0.1";
    } catch (e) {
      print("获取IP地址失败: $e");
      // 发生错误时使用回环地址
      serverIp = "127.0.0.1";
    }
  }

  // 添加消息日志
  void _addMessageLog({
    required String clientAddress,
    required String message,
    required bool isIncoming,
  }) {
    final log = MessageLog(
      clientAddress: clientAddress,
      message: message,
      timestamp: DateTime.now(),
      isIncoming: isIncoming,
    );

    _messageLogs.add(log);
    _notifyMessageLogChange();
  }

  // 通知消息日志变化
  void _notifyMessageLogChange() {
    _messageLogController.add(List.from(_messageLogs));
  }

  // 通知状态变化
  void _notifyStatusChange() {
    _statusController.add(statusMessage);
    _clientsController.add(List.from(clientConnections));
    _runningController.add(isServerRunning);
  }

  // 通知客户端列表变化
  void _notifyClientsChange() {
    _clientsController.add(List.from(clientConnections));
  }

  // 发送测试消息到特定客户端
  void sendTestMessage(dynamic connection, String message) {
    try {
      if (connection is Socket) {
        // 发送到Socket客户端
        final clientAddress =
            "${connection.remoteAddress.address}:${connection.remotePort}";
        connection.add(utf8.encode(message));

        // 添加消息日志
        _addMessageLog(
          clientAddress: "Socket客户端: $clientAddress",
          message: message,
          isIncoming: false,
        );
      } else if (connection is WebSocket) {
        // 发送到WebSocket客户端
        final clientIndex = clientConnections.indexWhere(
          (conn) => conn.connection == connection,
        );
        if (clientIndex >= 0) {
          final clientAddress = clientConnections[clientIndex].clientAddress;
          connection.add(message);

          // 添加消息日志
          _addMessageLog(
            clientAddress: clientAddress,
            message: message,
            isIncoming: false,
          );
        }
      }
    } catch (e) {
      print("发送测试消息失败: $e");
    }
  }

  // 广播消息到所有连接的客户端
  void broadcastMessage(String message) {
    if (!isServerRunning || (sockets.isEmpty && webSockets.isEmpty)) {
      print("没有连接的客户端，广播消息失败");
      return;
    }

    try {
      // 广播到所有Socket客户端
      for (var socket in sockets) {
        final clientAddress =
            "${socket.remoteAddress.address}:${socket.remotePort}";
        socket.add(utf8.encode(message));

        // 添加消息日志
        _addMessageLog(
          clientAddress: "Socket客户端: $clientAddress",
          message: message,
          isIncoming: false,
        );
      }

      // 广播到所有WebSocket客户端
      for (var webSocket in webSockets) {
        final clientIndex = clientConnections.indexWhere(
          (conn) => conn.connection == webSocket,
        );
        if (clientIndex >= 0) {
          final clientAddress = clientConnections[clientIndex].clientAddress;
          webSocket.add(message);

          // 添加消息日志
          _addMessageLog(
            clientAddress: "WebSocket客户端: $clientAddress",
            message: message,
            isIncoming: false,
          );
        }
      }

      print("消息已广播到 ${sockets.length + webSockets.length} 个客户端");
    } catch (e) {
      print("广播消息失败: $e");
    }
  }

  // 处理特定类型的消息
  void _processSpecificMessage(String message) {
    try {
      // 处理特定格式的消息
      if (message.contains(':')) {
        final parts = message.split(':');
        if (parts.length >= 2) {
          final messageType = parts[0].trim();
          final messageContent = parts.sublist(1).join(':').trim();

          // 发送到特定消息流
          _specificMessageController.add({
            'type': messageType,
            'content': messageContent,
            'raw': message,
            'timestamp': DateTime.now(),
          });
        }
      }
    } catch (e) {
      print("处理特定消息失败: $e");
    }
  }

  // 监听特定类型的消息
  StreamSubscription listenToMessageType(
    String messageType,
    Function(String content) callback,
  ) {
    return specificMessageStream.listen((messageData) {
      if (messageData['type'] == messageType) {
        callback(messageData['content']);
      }
    });
  }

  // 启动Ping定时器
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (timer) {
      if (isServerRunning) {
        _pingAllClients();
      } else {
        timer.cancel();
      }
    });
    print("Ping定时器已启动，间隔: ${_pingInterval.inSeconds}秒");
  }

  // Ping所有客户端，检测连接状态
  void _pingAllClients() {
    if (!isServerRunning || clientConnections.isEmpty) {
      return;
    }

    // 创建连接列表的副本，避免在遍历时修改列表
    final clientsToCheck = List<ClientConnection>.from(clientConnections);

    for (var client in clientsToCheck) {
      try {
        if (client.connection is Socket) {
          final socket = client.connection as Socket;
          // 尝试发送ping消息
          socket.add(utf8.encode(_pingMessage));
          // 如果发送成功，连接正常，不做任何操作
        } else if (client.connection is WebSocket) {
          final webSocket = client.connection as WebSocket;
          // 尝试发送ping消息
          webSocket.add(_pingMessage);
          // 如果发送成功，连接正常，不做任何操作
        }
      } catch (e) {
        // 发送失败，说明连接已断开，移除客户端
        print("Ping客户端失败 ${client.clientAddress}: $e，移除连接");
        if (client.connection is Socket) {
          _removeSocketClient(client.connection as Socket, client.clientAddress);
        } else if (client.connection is WebSocket) {
          _removeWebSocketClient(
            client.connection as WebSocket,
            client.clientAddress,
          );
        }
      }
    }
  }
}
