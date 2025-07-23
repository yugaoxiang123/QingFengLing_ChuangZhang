import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class SocketService {
  bool isServerRunning = false;
  String statusMessage = "服务未启动";
  List<String> connectedClients = [];
  ServerSocket? server;
  List<Socket> sockets = [];
  String serverIp = "0.0.0.0";
  int serverPort = 8888;

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
  }

  void dispose() {
    stopServer();
    _statusController.close();
    _clientsController.close();
    _runningController.close();
  }

  // 启动Socket服务器
  Future<void> startServer() async {
    if (isServerRunning) return;

    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, serverPort);
      await _getLocalIpAddress();

      isServerRunning = true;
      statusMessage = "服务已启动：$serverIp:$serverPort";
      _notifyStatusChange();

      server!.listen(
        (socket) {
          _handleConnection(socket);
        },
        onError: (error) {
          statusMessage = "服务错误: $error";
          _notifyStatusChange();
          stopServer();
        },
        onDone: () {
          if (isServerRunning) {
            statusMessage = "服务意外关闭";
            _notifyStatusChange();
            stopServer();
          }
        },
      );
    } catch (e) {
      statusMessage = "启动服务失败: $e";
      _notifyStatusChange();
    }
  }

  // 停止Socket服务器
  void stopServer() {
    for (var socket in sockets) {
      socket.destroy();
    }
    server?.close();
    server = null;

    isServerRunning = false;
    statusMessage = "服务已停止";
    connectedClients.clear();
    sockets.clear();
    _notifyStatusChange();
  }

  // 处理新的连接
  void _handleConnection(Socket socket) {
    sockets.add(socket);
    final clientAddress =
        "${socket.remoteAddress.address}:${socket.remotePort}";

    connectedClients.add(clientAddress);
    statusMessage = "已连接客户端：${connectedClients.length}个";
    _notifyStatusChange();

    // 监听客户端消息
    socket.listen(
      (Uint8List data) {
        // 处理接收到的数据
        final message = String.fromCharCodes(data);
        print("收到来自 $clientAddress 的消息: $message");
        // 这里可以添加处理接收数据的逻辑
      },
      onError: (error) {
        print("连接错误 $clientAddress: $error");
        _removeClient(socket, clientAddress);
      },
      onDone: () {
        print("客户端断开连接 $clientAddress");
        _removeClient(socket, clientAddress);
      },
    );
  }

  // 移除断开连接的客户端
  void _removeClient(Socket socket, String clientAddress) {
    socket.destroy();
    sockets.remove(socket);

    connectedClients.remove(clientAddress);
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
            statusMessage = "服务已启动：$serverIp:$serverPort";
            _notifyStatusChange();
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
    if (sockets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有连接的客户端')));
      return;
    }

    // 发送充气命令到所有连接的客户端
    for (var socket in sockets) {
      try {
        // 假设充气命令格式为："INFLATE:压力值"
        final command = "INFLATE:$pressure";
        socket.write(command);
      } catch (e) {
        print("发送命令失败: $e");
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
