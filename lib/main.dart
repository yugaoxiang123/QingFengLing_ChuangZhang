import 'package:flutter/material.dart';
import 'ui/socket_server_page.dart';
import 'ui/control_panel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '清峰岭控制面板',
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
        title: const Text('清峰岭控制面板'),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // 服务器页面，包含控制面板和SocketServerPage
          Column(
            children: [
              // 顶部控制面板
              const ControlPanel(),
              // SocketServerPage
              const Expanded(child: SocketServerPage()),
            ],
          ),
          // 设置页面
          const Center(child: Text('设置页面 - 开发中')),
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
          NavigationDestination(icon: Icon(Icons.router), label: '服务器'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
