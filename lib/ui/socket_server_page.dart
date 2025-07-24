import 'package:flutter/material.dart';
import '../services/socket_service.dart';

class SocketServerPage extends StatefulWidget {
  const SocketServerPage({super.key});

  @override
  State<SocketServerPage> createState() => _SocketServerPageState();
}

class _SocketServerPageState extends State<SocketServerPage> {
  // 使用全局单例实例
  final SocketService _socketService = socketService;
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
    // 初始化页面状态
    _updateInitialState();
  }

  // 添加初始状态更新方法
  void _updateInitialState() {
    // 直接从socketService获取当前状态
    setState(() {
      _isServerRunning = _socketService.isServerRunning;
      _statusMessage = _socketService.statusMessage;
      _connectedClients = List.from(_socketService.clientConnections);
      // 初始化空消息列表，后续通过Stream更新
      _messageLogs = [];
    });
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
    // 不再调用_socketService.dispose()，因为它是全局单例
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildServerStatusCard(),
            const SizedBox(height: 16),
            // 已连接客户端部分
            Text('已连接客户端', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _buildClientsList(),
            const SizedBox(height: 16),
            // 消息日志部分
            Text('消息日志', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _buildMessageLogsList(),
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
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(child: Text('暂无连接的客户端')),
          )
        : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Center(child: Text('暂无消息记录')),
          )
        : ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _messageLogs.length,
            // 不再需要reverse属性
            itemBuilder: (context, index) {
              // 直接使用反向索引，最新的消息（列表末尾）显示在顶部
              final log = _messageLogs[_messageLogs.length - 1 - index];
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
