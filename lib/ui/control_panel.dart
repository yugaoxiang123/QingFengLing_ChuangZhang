import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/event_bus.dart';

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
  double _shipSpeed = 0.0;
  String _shipAttitude = "稳定";

  // 控制状态
  bool _isForward = false;
  bool _isBackward = false;
  bool _isLeft = false;
  bool _isRight = false;
  bool _isThrust = false;
  bool _isJumpCharging = false;
  bool _isJumpExecuting = false;

  // 跃迁相关
  double _jumpChargeLevel = 0.0;
  Timer? _jumpRecoveryTimer;

  // 目标速度和当前速度
  double _targetSpeed = 0.0;
  double _maxNormalSpeed = 370.0;
  double _maxThrustSpeed = 570.0;
  double _warpSpeed = 299792458.0; // 光速 m/s

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _currentTime = DateTime.now();
        // 更新飞船数据
        _updateShipData();
      });
    });

    // 监听控制事件
    _listenToControlEvents();
  }

  // 监听控制事件
  void _listenToControlEvents() {
    shipControlEventBus.commandStream.listen((data) {
      final command = data['command'] as String;

      // 处理跃迁相关命令
      if (command == 'JUMP_CHARGE_COMPLETE') {
        _handleJumpChargeComplete();
      } else if (command.startsWith('EXECUTE_JUMP_')) {
        _handleExecuteJump(command);
      } else if (command == 'JUMP_COMPLETE') {
        _handleJumpComplete();
      } else if (command == 'CANCEL_JUMP') {
        _handleCancelJump();
      } else if (command == 'START_JUMP_CHARGE') {
        _handleStartJumpCharge();
      } else {
        // 处理普通控制命令
        final isStart = data['isStart'] as bool;
        if (isStart) {
          _handleStartCommand(command);
        } else {
          _handleEndCommand(command);
        }
      }
    });
  }

  // 处理开始命令
  void _handleStartCommand(String command) {
    setState(() {
      switch (command) {
        case 'FORWARD':
          _isForward = true;
          _updateTargetSpeed();
          _shipAttitude = "加速前进";
          break;
        case 'BACKWARD':
          _isBackward = true;
          _updateTargetSpeed();
          _shipAttitude = "减速";
          break;
        case 'LEFT':
          _isLeft = true;
          _shipAttitude = "左转";
          break;
        case 'RIGHT':
          _isRight = true;
          _shipAttitude = "右转";
          break;
        case 'THRUST':
          _isThrust = true;
          _updateTargetSpeed();
          _shipAttitude = "全速推进";
          break;
      }
    });
  }

  // 处理结束命令
  void _handleEndCommand(String command) {
    setState(() {
      switch (command) {
        case 'FORWARD':
          _isForward = false;
          _updateTargetSpeed();
          if (!_isBackward &&
              !_isLeft &&
              !_isRight &&
              !_isThrust &&
              !_isJumpExecuting) {
            _shipAttitude = "巡航";
          }
          break;
        case 'BACKWARD':
          _isBackward = false;
          _updateTargetSpeed();
          if (!_isForward &&
              !_isLeft &&
              !_isRight &&
              !_isThrust &&
              !_isJumpExecuting) {
            _shipAttitude = "巡航";
          }
          break;
        case 'LEFT':
          _isLeft = false;
          if (!_isForward &&
              !_isBackward &&
              !_isRight &&
              !_isThrust &&
              !_isJumpExecuting) {
            _shipAttitude = "巡航";
          }
          break;
        case 'RIGHT':
          _isRight = false;
          if (!_isForward &&
              !_isBackward &&
              !_isLeft &&
              !_isThrust &&
              !_isJumpExecuting) {
            _shipAttitude = "巡航";
          }
          break;
        case 'THRUST':
          _isThrust = false;
          _updateTargetSpeed();
          if (!_isForward &&
              !_isBackward &&
              !_isLeft &&
              !_isRight &&
              !_isJumpExecuting) {
            _shipAttitude = "巡航";
          }
          break;
      }
    });
  }

  // 处理开始跃迁充能
  void _handleStartJumpCharge() {
    setState(() {
      _isJumpCharging = true;
      _jumpChargeLevel = 0.0;
      _shipAttitude = "跃迁充能中";
    });
  }

  // 处理跃迁充能完成
  void _handleJumpChargeComplete() {
    setState(() {
      _jumpChargeLevel = 1.0;
      _shipAttitude = "跃迁准备就绪";
    });
  }

  // 处理执行跃迁
  void _handleExecuteJump(String command) {
    setState(() {
      _isJumpExecuting = true;
      _isJumpCharging = false;
      _shipAttitude = "跃迁中";
      _shipStatus = "跃迁航行";

      // 根据跃迁类型设置不同的速度
      if (command.contains('FULL')) {
        _targetSpeed = _warpSpeed * 2.0; // 全功率跃迁
      } else if (command.contains('MEDIUM')) {
        _targetSpeed = _warpSpeed * 1.5; // 中等功率跃迁
      } else {
        _targetSpeed = _warpSpeed; // 低功率跃迁
      }
    });
  }

  // 处理跃迁完成
  void _handleJumpComplete() {
    setState(() {
      _isJumpExecuting = false;
      _jumpChargeLevel = 0.0;
      _shipStatus = "跃迁完成";
      _shipAttitude = "减速";
      _targetSpeed = 100.0; // 跃迁后初始速度

      // 启动跃迁恢复计时器
      _jumpRecoveryTimer?.cancel();
      _jumpRecoveryTimer = Timer(const Duration(seconds: 5), () {
        setState(() {
          _shipStatus = "正常航行";
          if (!_isForward &&
              !_isBackward &&
              !_isLeft &&
              !_isRight &&
              !_isThrust) {
            _shipAttitude = "稳定";
          }
        });
      });
    });
  }

  // 处理取消跃迁
  void _handleCancelJump() {
    setState(() {
      _isJumpCharging = false;
      _jumpChargeLevel = 0.0;
      if (!_isForward && !_isBackward && !_isLeft && !_isRight && !_isThrust) {
        _shipAttitude = "稳定";
      }
    });
  }

  // 更新目标速度
  void _updateTargetSpeed() {
    if (_isJumpExecuting) return; // 跃迁中不更新目标速度

    if (_isThrust) {
      _targetSpeed = _maxThrustSpeed; // 推进状态下的最大速度
    } else if (_isForward) {
      _targetSpeed = _maxNormalSpeed; // 前进状态下的最大速度
    } else if (_isBackward) {
      _targetSpeed = 0.0; // 减速状态下的目标速度
    } else {
      _targetSpeed = 0.0; // 默认目标速度
    }
  }

  // 更新飞船数据
  void _updateShipData() {
    // 更新速度 - 平滑过渡到目标速度
    if (_shipSpeed < _targetSpeed) {
      // 加速
      double accelerationRate = _isJumpExecuting ? _warpSpeed / 20 : 5.0;
      _shipSpeed = math.min(_targetSpeed, _shipSpeed + accelerationRate);
    } else if (_shipSpeed > _targetSpeed) {
      // 减速
      double decelerationRate = _isJumpExecuting ? _warpSpeed / 30 : 2.0;
      _shipSpeed = math.max(_targetSpeed, _shipSpeed - decelerationRate);
    }

    // 更新角度
    if (_isLeft) {
      _shipAngles['yaw'] = _shipAngles['yaw']! - 0.3;
      _shipAngles['roll'] = _shipAngles['roll']! - 0.1;
    } else if (_isRight) {
      _shipAngles['yaw'] = _shipAngles['yaw']! + 0.3;
      _shipAngles['roll'] = _shipAngles['roll']! + 0.1;
    } else {
      // 逐渐恢复到平衡状态
      _shipAngles['roll'] = _shipAngles['roll']! * 0.95;
    }

    // 根据前进/后退更新俯仰角
    if (_isForward) {
      _shipAngles['pitch'] = math.max(10.0, _shipAngles['pitch']! - 0.2);
    } else if (_isBackward) {
      _shipAngles['pitch'] = math.min(25.0, _shipAngles['pitch']! + 0.2);
    } else {
      // 逐渐恢复到平衡状态
      if (_shipAngles['pitch']! > 15.2) {
        _shipAngles['pitch'] = _shipAngles['pitch']! - 0.1;
      } else if (_shipAngles['pitch']! < 15.2) {
        _shipAngles['pitch'] = _shipAngles['pitch']! + 0.1;
      }
    }

    // 添加一些随机小变化，让数据看起来更真实
    if (!_isJumpExecuting) {
      _shipCoordinates['x'] =
          _shipCoordinates['x']! + (_random.nextDouble() * 2 - 1) * 0.3;
      _shipCoordinates['y'] =
          _shipCoordinates['y']! + (_random.nextDouble() * 2 - 1) * 0.2;
      _shipCoordinates['z'] =
          _shipCoordinates['z']! + (_random.nextDouble() * 2 - 1) * 0.25;

      // 小幅度随机调整角度
      _shipAngles['pitch'] =
          _shipAngles['pitch']! + (_random.nextDouble() * 2 - 1) * 0.05;
      _shipAngles['yaw'] =
          _shipAngles['yaw']! + (_random.nextDouble() * 2 - 1) * 0.05;
      _shipAngles['roll'] =
          _shipAngles['roll']! + (_random.nextDouble() * 2 - 1) * 0.02;
    } else {
      // 跃迁过程中坐标变化更剧烈
      _shipCoordinates['x'] =
          _shipCoordinates['x']! + (_random.nextDouble() * 2 - 1) * 2.0;
      _shipCoordinates['y'] =
          _shipCoordinates['y']! + (_random.nextDouble() * 2 - 1) * 2.0;
      _shipCoordinates['z'] =
          _shipCoordinates['z']! + (_random.nextDouble() * 2 - 1) * 2.0;
    }
  }

  // 重置剧情状态
  void _resetShipStatus() {
    setState(() {
      _shipStatus = "飞船起飞";
      _shipCoordinates = {'x': 120.5, 'y': 45.8, 'z': 78.2};
      _shipAngles = {'pitch': 15.2, 'yaw': 3.7, 'roll': 0.5};
      _shipSpeed = 0.0;
      _targetSpeed = 0.0;
      _shipAttitude = "稳定";
      _isForward = false;
      _isBackward = false;
      _isLeft = false;
      _isRight = false;
      _isThrust = false;
      _isJumpCharging = false;
      _isJumpExecuting = false;
      _jumpChargeLevel = 0.0;
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _jumpRecoveryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String hours = _currentTime.hour.toString().padLeft(2, '0');
    String minutes = _currentTime.minute.toString().padLeft(2, '0');
    String seconds = _currentTime.second.toString().padLeft(2, '0');

    // 格式化速度显示
    String speedDisplay;
    if (_isJumpExecuting || _shipSpeed > _maxThrustSpeed * 2) {
      // 跃迁状态下显示光速的倍数
      double lightSpeedMultiple = _shipSpeed / 299792458.0;
      speedDisplay = '${lightSpeedMultiple.toStringAsFixed(2)}c';
    } else {
      // 正常状态下显示 m/s
      speedDisplay = '${_shipSpeed.toStringAsFixed(1)} m/s';
    }

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
          _buildInfoRow(
            context,
            '剧情状态',
            _shipStatus,
            Colors.blue,
            button: IconButton(
              onPressed: _resetShipStatus,
              icon: const Icon(Icons.refresh),
              tooltip: '重置剧情',
              style: IconButton.styleFrom(
                backgroundColor: Colors.blue.withOpacity(0.1),
                foregroundColor: Colors.blue,
              ),
            ),
          ),
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
            speedDisplay,
            _isJumpExecuting ? Colors.purple : Colors.red,
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
    Color color, {
    Widget? button,
  }) {
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
        if (button != null) const SizedBox(width: 8),
        if (button != null) button,
      ],
    );
  }
}
