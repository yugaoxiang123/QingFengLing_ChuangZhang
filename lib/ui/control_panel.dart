import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

class ControlPanel extends StatefulWidget {
  const ControlPanel({super.key});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  late DateTime _currentTime;
  late Timer _timer;
  final math.Random _random = math.Random();

  // 飞船状态数据
  String _shipStatus = "飞船起飞";
  Map<String, double> _shipCoordinates = {'x': 120.5, 'y': 45.8, 'z': 78.2};
  Map<String, double> _shipAngles = {'pitch': 15.2, 'yaw': 3.7, 'roll': 0.5};
  double _shipSpeed = 345.8;
  String _shipAttitude = "稳定";

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentTime = DateTime.now();
        // 这里可以添加模拟数据变化的逻辑
        _simulateShipDataChanges();
      });
    });
  }

  // 模拟飞船数据变化
  void _simulateShipDataChanges() {
    // 随机小幅度变化坐标
    _shipCoordinates['x'] =
        _shipCoordinates['x']! + (_random.nextDouble() * 2 - 1) * 0.5;
    _shipCoordinates['y'] =
        _shipCoordinates['y']! + (_random.nextDouble() * 2 - 1) * 0.3;
    _shipCoordinates['z'] =
        _shipCoordinates['z']! + (_random.nextDouble() * 2 - 1) * 0.4;

    // 随机小幅度变化角度
    _shipAngles['pitch'] =
        _shipAngles['pitch']! + (_random.nextDouble() * 2 - 1) * 0.2;
    _shipAngles['yaw'] =
        _shipAngles['yaw']! + (_random.nextDouble() * 2 - 1) * 0.1;
    _shipAngles['roll'] =
        _shipAngles['roll']! + (_random.nextDouble() * 2 - 1) * 0.05;

    // 随机小幅度变化速度
    _shipSpeed = _shipSpeed + (_random.nextDouble() * 2 - 1) * 2.0;

    // 保持数值在合理范围内
    _shipSpeed = _shipSpeed.clamp(340.0, 350.0);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String hours = _currentTime.hour.toString().padLeft(2, '0');
    String minutes = _currentTime.minute.toString().padLeft(2, '0');
    String seconds = _currentTime.second.toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8.0),
      ),
      margin: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间显示部分
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('当前时间', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTimeSegment(context, hours),
                    _buildTimeSeparator(context),
                    _buildTimeSegment(context, minutes),
                    _buildTimeSeparator(context),
                    _buildTimeSegment(context, seconds),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 飞船状态部分
          Text('飞船状态', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          // 剧情状态
          _buildInfoRow(context, '剧情状态', _shipStatus, Colors.blue),
          const SizedBox(height: 8),

          // 飞船坐标
          _buildInfoRow(
            context,
            '飞船坐标',
            'X: ${_shipCoordinates['x']!.toStringAsFixed(1)}, Y: ${_shipCoordinates['y']!.toStringAsFixed(1)}, Z: ${_shipCoordinates['z']!.toStringAsFixed(1)}',
            Colors.green,
          ),
          const SizedBox(height: 8),

          // 飞船角度
          _buildInfoRow(
            context,
            '飞船角度',
            '俯仰: ${_shipAngles['pitch']!.toStringAsFixed(1)}°, 偏航: ${_shipAngles['yaw']!.toStringAsFixed(1)}°, 翻滚: ${_shipAngles['roll']!.toStringAsFixed(1)}°',
            Colors.orange,
          ),
          const SizedBox(height: 8),

          // 飞船速度
          _buildInfoRow(
            context,
            '飞船速度',
            '${_shipSpeed.toStringAsFixed(1)} m/s',
            Colors.red,
          ),
          const SizedBox(height: 8),

          // 飞船姿态
          _buildInfoRow(context, '飞船姿态', _shipAttitude, Colors.purple),
        ],
      ),
    );
  }

  Widget _buildTimeSegment(BuildContext context, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        value,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildTimeSeparator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        ':',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  // 构建信息行
  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.3), width: 1),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: color.withOpacity(0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
