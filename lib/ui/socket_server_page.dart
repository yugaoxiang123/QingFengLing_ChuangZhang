import 'package:flutter/material.dart';
import '../services/socket_service.dart';

class SocketServerPage extends StatefulWidget {
  const SocketServerPage({super.key});

  @override
  State<SocketServerPage> createState() => _SocketServerPageState();
}

class _SocketServerPageState extends State<SocketServerPage> {
  final SocketService _socketService = SocketService();
  bool _isServerRunning = false;
  String _statusMessage = "服务未启动";
  List<ClientConnection> _connectedClients = []; // 更新为ClientConnection类型
  List<MessageLog> _messageLogs = []; // 消息日志列表
  final TextEditingController _testMessageController = TextEditingController(
    text: "测试消息",
  );

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    _socketService.statusStream.listen((status) {
      setState(() {
        _statusMessage = status;
      });
    });

    _socketService.clientsStream.listen((clients) {
      setState(() {
        _connectedClients = clients;
      });
    });

    _socketService.runningStream.listen((running) {
      setState(() {
        _isServerRunning = running;
      });
    });

    // 监听消息日志变化
    _socketService.messageLogStream.listen((logs) {
      setState(() {
        _messageLogs = logs;
      });
    });
  }

  @override
  void dispose() {
    _testMessageController.dispose(); // 释放控制器
    _socketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('清峰岭控制面板'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildServerStatusCard(),
            const SizedBox(height: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部显示客户端列表
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '已连接客户端',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: _buildClientsList()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 底部显示消息日志
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '消息日志',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: _buildMessageLogsList()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 服务器状态卡片
  Widget _buildServerStatusCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('服务器状态', style: Theme.of(context).textTheme.titleLarge),
                Icon(
                  _isServerRunning ? Icons.cloud_done : Icons.cloud_off,
                  color: _isServerRunning ? Colors.green : Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_statusMessage),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isServerRunning
                  ? _socketService.stopServer
                  : _socketService.startServer,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isServerRunning ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text(_isServerRunning ? '停止服务' : '启动服务'),
            ),
          ],
        ),
      ),
    );
  }

  // 客户端列表
  Widget _buildClientsList() {
    return _connectedClients.isEmpty
        ? const Center(child: Text('暂无连接的客户端'))
        : ListView.builder(
            itemCount: _connectedClients.length,
            itemBuilder: (context, index) {
              final client = _connectedClients[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(
                    client.clientType == "Socket"
                        ? Icons.settings_ethernet
                        : Icons.language,
                    color: Theme.of(context).primaryColor,
                  ),
                  title: Text(client.displayName),
                  subtitle: Text('连接时间: ${client.formattedConnectTime}'),
                  trailing: ElevatedButton(
                    onPressed: () => _showSendMessageDialog(client),
                    child: const Text('发送测试消息'),
                  ),
                  dense: true,
                ),
              );
            },
          );
  }

  // 显示发送消息对话框
  void _showSendMessageDialog(ClientConnection client) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('发送测试消息给 ${client.displayName}'),
        content: TextField(
          controller: _testMessageController,
          decoration: const InputDecoration(
            labelText: '消息内容',
            hintText: '输入要发送的消息',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              _socketService.sendTestMessage(
                client.connection,
                _testMessageController.text,
              );
              Navigator.pop(context);
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  // 消息日志列表
  Widget _buildMessageLogsList() {
    return _messageLogs.isEmpty
        ? const Center(child: Text('暂无消息记录'))
        : ListView.builder(
            itemCount: _messageLogs.length,
            reverse: true, // 最新的消息显示在底部
            itemBuilder: (context, index) {
              final log =
                  _messageLogs[_messageLogs.length - 1 - index]; // 反转显示顺序
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: log.isIncoming ? Colors.blue[50] : Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            log.clientAddress,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            log.formattedTime,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${log.isIncoming ? '收到: ' : '发送: '}${log.message}'),
                    ],
                  ),
                ),
              );
            },
          );
  }
}
