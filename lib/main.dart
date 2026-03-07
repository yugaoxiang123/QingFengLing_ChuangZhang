import 'package:flutter/material.dart';
import 'ui/socket_server_page.dart';
import 'ui/control_panel.dart';
import 'services/socket_service.dart'; // 导入SocketService
import 'ui/ship_manual_control.dart'; // 导入飞船手动控制组件

import 'plugins/auto_update/auto_update.dart';

/// 应用程序入口点
/// 
/// 初始化Flutter绑定，启动应用，并初始化Socket服务。
/// 包含自动更新功能的检查。
void main() {
  // 确保Flutter框架初始化完成
  WidgetsFlutterBinding.ensureInitialized();

  // 启动应用
  runApp(const MyApp());
}

/// 应用程序根组件
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 在应用构建完成后初始化SocketService
    // 使用addPostFrameCallback确保在第一帧绘制后执行，避免阻塞UI构建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      socketService.initialize();
    });

    return MaterialApp(
      title: '青峰岭控制面板',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      // 使用UpdateManager包裹主页，启用自动更新检查
      home: UpdateManager(
        enabled: true,
        child: const HomePage(),
      ),
    );
  }
}

/// 主页组件
/// 
/// 包含底部导航栏，用于在"飞船操控"和"Socket服务器"页面之间切换。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('青峰岭控制面板'),
      ),
      // 使用IndexedStack保持页面状态，切换tab时不会销毁页面
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // 飞船状态页面：包含状态面板和手动控制面板
          SingleChildScrollView(
            child: Column(
              children: [
                // 顶部控制面板：显示时间、坐标、速度等信息
                const ControlPanel(),
                // 飞船手动控制面板：提供方向控制和跃迁功能
                const ShipManualControl(),
              ],
            ),
          ),
          // 服务器页面：显示服务器状态、连接的客户端和日志
          const SocketServerPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.flight_takeoff),
            label: '飞船操控',
          ),
          NavigationDestination(icon: Icon(Icons.router), label: 'Socket服务器'),
        ],
      ),
    );
  }
}
