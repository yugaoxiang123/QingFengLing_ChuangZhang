import 'package:flutter/material.dart';
import 'ui/socket_server_page.dart';
import 'ui/control_panel.dart';
import 'services/socket_service.dart'; // 导入SocketService
import 'ui/ship_manual_control.dart'; // 导入飞船手动控制组件

void main() {
  // 确保Flutter框架初始化完成
  WidgetsFlutterBinding.ensureInitialized();

  // 启动应用
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 在应用构建完成后初始化SocketService
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
      home: const HomePage(),
    );
  }
}

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
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // 飞船状态页面
          SingleChildScrollView(
            child: Column(
              children: [
                // 顶部控制面板
                const ControlPanel(),
                // 飞船手动控制面板
                const ShipManualControl(),
              ],
            ),
          ),
          // 服务器页面
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
