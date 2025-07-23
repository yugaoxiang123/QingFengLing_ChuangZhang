import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';

class SocketService {
  bool isServerRunning = false;
  String statusMessage = "服务未启动";
  List<String> connectedClients = [];
  ServerSocket? server;
  HttpServer? httpServer;
  List<Socket> sockets = [];
  List<WebSocket> webSockets = [];
  String serverIp = "0.0.0.0";
  int serverPort = 8888;
  int webSocketPort = 8889; // WebSocket使用不同的端口

  // 状态变化通知
  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  // 客户端列表变化通知
  final _clientsController = StreamController<List<String>>.broadcast();
  Stream<List<String>> get clientsStream => _clientsController.stream;

  // 服务器状态变化通知
  final _runningController = StreamController<bool>.broadcast();
  Stream<bool> get runningStream => _runningController.stream;

  // 单例模式
  static final SocketService _instance = SocketService._internal();

  factory SocketService() {
    return _instance;
  }

  SocketService._internal() {
    // 在初始化时自动启动服务
    startServer();
    // 监听应用生命周期状态
    _setupAppLifecycleListener();
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
          statusMessage = "服务已重新启动：$serverIp:$serverPort";
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
  }

  // 启动Socket服务器和WebSocket服务器
  Future<void> startServer() async {
    if (isServerRunning) return;

    try {
      await _getLocalIpAddress();

      // 启动原生Socket服务器
      server = await ServerSocket.bind(InternetAddress.anyIPv4, serverPort);

      // 启动WebSocket服务器
      httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        webSocketPort,
      );

      isServerRunning = true;
      statusMessage =
          "服务已启动：\nSocket：$serverIp:$serverPort\nWebSocket：$serverIp:$webSocketPort";
      _notifyStatusChange();

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
              _handleWebSocketConnection(webSocket);
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
      statusMessage = "启动服务失败: $e";
      _notifyStatusChange();
      stopServer();
    }
  }

  // 停止Socket服务器
  void stopServer() {
    // 关闭所有Socket连接
    for (var socket in sockets) {
      socket.destroy();
    }
    server?.close();
    server = null;

    // 关闭所有WebSocket连接
    for (var ws in webSockets) {
      ws.close();
    }
    httpServer?.close(force: true);
    httpServer = null;

    isServerRunning = false;
    statusMessage = "服务已停止";
    connectedClients.clear();
    sockets.clear();
    webSockets.clear();
    _notifyStatusChange();
  }

  // 处理Socket新连接
  void _handleConnection(Socket socket) {
    sockets.add(socket);
    final clientAddress =
        "${socket.remoteAddress.address}:${socket.remotePort}";

    connectedClients.add("Socket客户端: $clientAddress");
    statusMessage = "已连接客户端：${connectedClients.length}个";
    _notifyStatusChange();

    // 监听客户端消息
    socket.listen(
      (Uint8List data) {
        // 处理接收到的数据
        final message = String.fromCharCodes(data);
        print("收到来自Socket客户端 $clientAddress 的消息: $message");
        // 这里可以添加处理接收数据的逻辑
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
  void _handleWebSocketConnection(WebSocket webSocket) {
    webSockets.add(webSocket);
    final clientAddress = "WebSocket客户端: ${webSockets.length}";

    connectedClients.add(clientAddress);
    statusMessage = "已连接客户端：${connectedClients.length}个";
    _notifyStatusChange();

    // 监听WebSocket消息
    webSocket.listen(
      (dynamic data) {
        // WebSocket数据可能是String或Uint8List
        final message = data is String ? data : String.fromCharCodes(data);
        print("收到来自$clientAddress的消息: $message");
        // 这里可以添加处理WebSocket消息的逻辑
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
    socket.destroy();
    sockets.remove(socket);

    connectedClients.remove("Socket客户端: $clientAddress");
    _updateStatusAfterClientRemoved();
  }

  // 移除断开连接的WebSocket客户端
  void _removeWebSocketClient(WebSocket webSocket, String clientAddress) {
    webSocket.close();
    webSockets.remove(webSocket);

    connectedClients.remove(clientAddress);
    _updateStatusAfterClientRemoved();
  }

  // 更新客户端移除后的状态
  void _updateStatusAfterClientRemoved() {
    if (connectedClients.isEmpty) {
      statusMessage = "无连接客户端";
    } else {
      statusMessage = "已连接客户端：${connectedClients.length}个";
    }
    _notifyStatusChange();
  }

  // 获取本地IP地址
  Future<void> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLinkLocal && !addr.isLoopback) {
            serverIp = addr.address;
            return;
          }
        }
      }
    } catch (e) {
      print("获取IP地址失败: $e");
    }
  }

  // 发送充气命令
  void sendInflationCommand(int pressure, BuildContext context) {
    if (sockets.isEmpty && webSockets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有连接的客户端')));
      return;
    }

    // 发送充气命令到所有Socket连接的客户端
    for (var socket in sockets) {
      try {
        // 假设充气命令格式为："INFLATE:压力值"
        final command = "INFLATE:$pressure";
        socket.write(command);
      } catch (e) {
        print("向Socket客户端发送命令失败: $e");
      }
    }

    // 发送充气命令到所有WebSocket连接的客户端
    for (var ws in webSockets) {
      try {
        final command = "INFLATE:$pressure";
        ws.add(command);
      } catch (e) {
        print("向WebSocket客户端发送命令失败: $e");
      }
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已发送充气命令：$pressure')));
  }

  // 通知状态变化
  void _notifyStatusChange() {
    _statusController.add(statusMessage);
    _clientsController.add(List.from(connectedClients));
    _runningController.add(isServerRunning);
  }
}
