import 'package:flutter/material.dart';
import '../services/socket_service.dart';

class SocketServerPage extends StatefulWidget {
  const SocketServerPage({super.key});

  @override
  State<SocketServerPage> createState() => _SocketServerPageState();
}

class _SocketServerPageState extends State<SocketServerPage> {
  final SocketService _socketService = SocketService();
  int _inflationPressure = 0; // 充气压力值
  bool _isServerRunning = false;
  String _statusMessage = "服务未启动";
  List<String> _connectedClients = [];

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
  }

  @override
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('清风岭操控面板'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildServerStatusCard(),
            const SizedBox(height: 16),
            Text('已连接客户端', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _buildClientsList(),
            const SizedBox(height: 16),
            _buildInflationControlCard(),
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
    return Expanded(
      child: _connectedClients.isEmpty
          ? const Center(child: Text('暂无连接的客户端'))
          : ListView.builder(
              itemCount: _connectedClients.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: const Icon(Icons.devices),
                  title: Text(_connectedClients[index]),
                  dense: true,
                );
              },
            ),
    );
  }

  // 充气控制卡片
  Widget _buildInflationControlCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('充气控制', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('压力值: $_inflationPressure'),
                Expanded(
                  child: Slider(
                    value: _inflationPressure.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: _inflationPressure.toString(),
                    onChanged: (double value) {
                      setState(() {
                        _inflationPressure = value.round();
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isServerRunning
                  ? () => _socketService.sendInflationCommand(
                      _inflationPressure,
                      context,
                    )
                  : null,
              child: const Text('发送充气命令'),
            ),
          ],
        ),
      ),
    );
  }
}
