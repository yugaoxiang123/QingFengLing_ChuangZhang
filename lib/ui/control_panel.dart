import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/event_bus.dart';
import '../services/socket_service.dart'; // 添加socket服务导入

/// 飞船状态控制面板
/// 
/// 显示飞船的实时状态信息，包括：
/// - 当前时间
/// - 剧情状态（支持手动切换）
/// - 飞船坐标 (X, Y, Z)
/// - 飞船姿态 (俯仰角, 偏航角)
/// - 飞船速度
/// - 飞船当前动作状态（巡航、加速、跃迁等）
/// 
/// 负责监听控制命令和Socket消息来更新这些状态。
class ControlPanel extends StatefulWidget {
  const ControlPanel({super.key});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  late DateTime _currentTime;
  late Timer _timer;
  final math.Random _random = math.Random();

  // 剧情状态
  int _storyStatus = 0; // 默认为0无

  // 剧情状态常量映射
  static const Map<int, String> storyStatusMap = {
    0: "无",
    1: "登船准备",
    2: "飞船起飞",
    3: "雷电防护",
    4: "捕捉垃圾",
    5: "击碎陨石",
    6: "行星科普",
    7: "加速飞行",
    8: "抵达月球",
  };

  // 飞船状态数据
  Map<String, double> _shipCoordinates = {'x': 120.5, 'y': 45.8, 'z': 78.2};
  final Map<String, double> _shipAngles = {'pitch': 15.2, 'yaw': 3.7, 'roll': 0.5};
  double _shipSpeed = 20.0; // 初始速度设置为20
  String _shipAttitude = "巡航"; // 初始姿态为巡航

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
  double _targetSpeed = 20.0; // 初始目标速度设置为20
  final double _maxNormalSpeed = 370.0;
  final double _maxThrustSpeed = 570.0;
  final double _warpSpeed = 299792458.0; // 光速 m/s

  // Socket消息订阅
  StreamSubscription? _socketMessageSubscription;
  // Socket阶段消息订阅
  StreamSubscription? _socketStageSubscription;
  // Socket服务状态订阅
  StreamSubscription? _socketStatusSubscription;

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

    // 监听Socket消息
    _listenToSocketMessages();

    // 监听Socket服务状态变化
    _listenToSocketServiceStatus();

    // 初始化时广播一次剧情状态
    Future.delayed(const Duration(seconds: 1), () {
      _broadcastStoryStatus();
    });
  }

  // 监听Socket消息
  void _listenToSocketMessages() {
    // 监听STORY_STATUS消息（用于手动设置）
    _socketMessageSubscription = socketService.listenToMessageType(
      'STORY_STATUS',
      (content) {
        try {
          // 解析剧情状态值
          final statusValue = int.parse(content.trim());
          if (storyStatusMap.containsKey(statusValue)) {
            setState(() {
              _storyStatus = statusValue;
            });
          }
        } catch (e) {
          print('解析剧情状态消息失败: $e');
        }
      },
    );

    // 监听STAGE消息（来自QFChuanZhang的阶段信息）
    _socketStageSubscription = socketService.listenToMessageType(
      'STAGE',
      (content) {
        try {
          // 解析阶段编号（1-8）
          final stageNumber = int.parse(content.trim());
          // 阶段编号和剧情状态是一一对应的
          // STAGE:1 -> 剧情状态1, STAGE:2 -> 剧情状态2, 以此类推
          if (stageNumber >= 1 && stageNumber <= 8) {
            // 使用_updateStoryStatus来更新状态，这样会触发相应的功能
            _updateStoryStatus(stageNumber);
            print('收到阶段信息: STAGE:$stageNumber，已更新剧情状态为: ${storyStatusMap[stageNumber]}');
          } else {
            print('收到无效的阶段编号: $stageNumber（应为1-8）');
          }
        } catch (e) {
          print('解析阶段消息失败: $e');
        }
      },
    );
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
          break;
        case 'BACKWARD':
          _isBackward = true;
          _updateTargetSpeed();
          break;
        case 'LEFT':
          _isLeft = true;
          break;
        case 'RIGHT':
          _isRight = true;
          break;
        case 'THRUST':
          _isThrust = true;
          _updateTargetSpeed();
          break;
      }
      _updateShipAttitude();
    });
  }

  // 处理结束命令
  void _handleEndCommand(String command) {
    setState(() {
      switch (command) {
        case 'FORWARD':
          _isForward = false;
          _updateTargetSpeed();
          break;
        case 'BACKWARD':
          _isBackward = false;
          _updateTargetSpeed();
          break;
        case 'LEFT':
          _isLeft = false;
          break;
        case 'RIGHT':
          _isRight = false;
          break;
        case 'THRUST':
          _isThrust = false;
          _updateTargetSpeed();
          break;
      }
      _updateShipAttitude();
    });
  }

  // 处理开始跃迁充能
  void _handleStartJumpCharge() {
    setState(() {
      _isJumpCharging = true;
      _jumpChargeLevel = 0.0;
      _updateShipAttitude();
    });
  }

  // 处理跃迁充能完成
  void _handleJumpChargeComplete() {
    setState(() {
      _jumpChargeLevel = 1.0;
      _updateShipAttitude();
    });
  }

  // 处理执行跃迁
  void _handleExecuteJump(String command) {
    setState(() {
      _isJumpExecuting = true;
      _isJumpCharging = false;

      // 根据跃迁类型设置不同的速度
      if (command.contains('FULL')) {
        _targetSpeed = _warpSpeed * 2.0; // 全功率跃迁
      } else if (command.contains('MEDIUM')) {
        _targetSpeed = _warpSpeed * 1.5; // 中等功率跃迁
      } else {
        _targetSpeed = _warpSpeed; // 低功率跃迁
      }

      // 开始跃迁时立即重置坐标到跃迁起点范围内
      // 这样可以防止之前累积的大坐标值影响跃迁过程
      _shipCoordinates = {
        'x': 100.0 + _random.nextDouble() * 20.0,
        'y': 40.0 + _random.nextDouble() * 10.0,
        'z': 70.0 + _random.nextDouble() * 15.0,
      };

      _updateShipAttitude();
    });
  }

  // 处理跃迁完成
  void _handleJumpComplete() {
    setState(() {
      _isJumpExecuting = false;
      _jumpChargeLevel = 0.0;

      // 跃迁完成后重置坐标到一个新的合理范围
      // 模拟跃迁到了一个新的区域
      _shipCoordinates = {
        'x': 100.0 + _random.nextDouble() * 50.0,
        'y': 40.0 + _random.nextDouble() * 20.0,
        'z': 70.0 + _random.nextDouble() * 30.0,
      };

      // 检查跃迁前是否已经停止
      bool wasStoppedBeforeJump = _shipSpeed <= 0.1 && _targetSpeed <= 0.1;

      // 如果跃迁前已停止，保持停止状态；否则设置为默认巡航速度
      if (wasStoppedBeforeJump) {
        _targetSpeed = 0.0;
        _shipSpeed = 0.0;
      } else {
        _targetSpeed = 20.0;
        _shipSpeed = 20.0;
      }

      _updateShipAttitude();

      // 取消跳跃恢复计时器
      _jumpRecoveryTimer?.cancel();
    });
  }

  // 处理取消跃迁
  void _handleCancelJump() {
    setState(() {
      _isJumpCharging = false;
      _jumpChargeLevel = 0.0;
      _updateShipAttitude();
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
      // 如果当前速度为0，保持目标速度为0，否则设为默认速度20
      _targetSpeed = _shipSpeed <= 0.1 ? 0.0 : 20.0;
    }
  }

  // 更新飞船数据
  void _updateShipData() {
    // 更新速度 - 平滑过渡到目标速度
    if (_shipSpeed < _targetSpeed) {
      // 加速
      double accelerationRate;
      if (_isJumpExecuting) {
        accelerationRate = _warpSpeed / 20;
      } else if (_isThrust) {
        accelerationRate = 12.0; // 推进状态下加速更快
      } else {
        accelerationRate = 5.0; // 普通加速
      }
      _shipSpeed = math.min(_targetSpeed, _shipSpeed + accelerationRate);
    } else if (_shipSpeed > _targetSpeed) {
      // 减速
      double decelerationRate;

      // 从跃迁速度减速时使用更快的减速率
      if (_shipSpeed > _maxNormalSpeed * 2) {
        decelerationRate = _warpSpeed / 10; // 从光速快速减速
      } else if (_isBackward) {
        // 主动减速时，减速更快
        decelerationRate = _isJumpExecuting ? _warpSpeed / 15 : 8.0;
      } else {
        // 自动减速时，减速较慢
        decelerationRate = _isJumpExecuting ? _warpSpeed / 30 : 2.0;
        // 如果不是主动减速且目标速度不是0，确保不会低于20
        if (!_isBackward &&
            _targetSpeed > 0 &&
            _shipSpeed - decelerationRate < 20.0) {
          _shipSpeed = 20.0;
          return;
        }
      }
      _shipSpeed = math.max(_targetSpeed, _shipSpeed - decelerationRate);
    }

    // 更新飞船姿态
    _updateShipAttitude();

    // 更新角度 - 无论速度如何，都根据用户操作更新角度
    // 偏航角(yaw)变化 - 左右转向
    if (_isLeft) {
      // 左转时，偏航角减小，滚转角向左倾斜
      double turnRate = _isThrust ? 0.5 : 0.3; // 推进时转向更快
      _shipAngles['yaw'] = _shipAngles['yaw']! - turnRate;
      _shipAngles['roll'] = math.max(
        -15.0,
        _shipAngles['roll']! - 0.3,
      ); // 限制最大倾斜角度
    } else if (_isRight) {
      // 右转时，偏航角增加，滚转角向右倾斜
      double turnRate = _isThrust ? 0.5 : 0.3; // 推进时转向更快
      _shipAngles['yaw'] = _shipAngles['yaw']! + turnRate;
      _shipAngles['roll'] = math.min(
        15.0,
        _shipAngles['roll']! + 0.3,
      ); // 限制最大倾斜角度
    } else {
      // 没有转向输入时，滚转角逐渐恢复到平衡状态
      _shipAngles['roll'] = _shipAngles['roll']! * 0.95;
    }

    // 俯仰角(pitch)变化 - 前进/后退
    if (_isForward) {
      // 前进时，俯仰角降低（机头向下）
      double pitchRate = _isThrust ? 0.3 : 0.2; // 推进时俯仰变化更快
      _shipAngles['pitch'] = math.max(
        5.0,
        _shipAngles['pitch']! - pitchRate,
      ); // 限制最小俯仰角
    } else if (_isBackward) {
      // 后退时，俯仰角增加（机头向上）
      double pitchRate = 0.2;
      _shipAngles['pitch'] = math.min(
        30.0,
        _shipAngles['pitch']! + pitchRate,
      ); // 限制最大俯仰角
    } else {
      // 没有前进/后退输入时，俯仰角逐渐恢复到平衡状态
      double defaultPitch = 15.2; // 默认平衡俯仰角
      if (_shipAngles['pitch']! > defaultPitch + 0.1) {
        _shipAngles['pitch'] = _shipAngles['pitch']! - 0.1;
      } else if (_shipAngles['pitch']! < defaultPitch - 0.1) {
        _shipAngles['pitch'] = _shipAngles['pitch']! + 0.1;
      } else {
        _shipAngles['pitch'] = defaultPitch; // 直接设置为默认值，避免微小抖动
      }
    }

    // 只有在速度不为0时才更新坐标
    if (_shipSpeed > 0.1) {
      if (!_isJumpExecuting) {
        // 根据当前速度和角度计算坐标变化
        // 将偏航角转换为弧度
        double yawRadians = _shipAngles['yaw']! * (math.pi / 180.0);
        // 将俯仰角转换为弧度
        double pitchRadians = _shipAngles['pitch']! * (math.pi / 180.0);

        // 计算速度分量
        double speedFactor = _shipSpeed * 0.01; // 缩放因子，使坐标变化更合理

        // 根据偏航角和俯仰角计算三维方向向量
        double dx = speedFactor * math.sin(yawRadians) * math.cos(pitchRadians);
        double dy = speedFactor * math.sin(pitchRadians);
        double dz = speedFactor * math.cos(yawRadians) * math.cos(pitchRadians);

        // 更新坐标
        _shipCoordinates['x'] = _shipCoordinates['x']! + dx;
        _shipCoordinates['y'] = _shipCoordinates['y']! + dy;
        _shipCoordinates['z'] = _shipCoordinates['z']! + dz;

        // 添加小幅度随机调整，增加真实感
        _shipCoordinates['x'] =
            _shipCoordinates['x']! + (_random.nextDouble() * 2 - 1) * 0.05;
        _shipCoordinates['y'] =
            _shipCoordinates['y']! + (_random.nextDouble() * 2 - 1) * 0.05;
        _shipCoordinates['z'] =
            _shipCoordinates['z']! + (_random.nextDouble() * 2 - 1) * 0.05;

        // 小幅度随机调整角度，增加真实感
        _shipAngles['pitch'] =
            _shipAngles['pitch']! + (_random.nextDouble() * 2 - 1) * 0.03;
        _shipAngles['yaw'] =
            _shipAngles['yaw']! + (_random.nextDouble() * 2 - 1) * 0.03;
        _shipAngles['roll'] =
            _shipAngles['roll']! + (_random.nextDouble() * 2 - 1) * 0.01;

        // 即使在正常飞行中也确保坐标不会超出合理范围
        _constrainCoordinates();
      } else {
        // 跃迁过程中的坐标变化 - 使用完全不同的计算方式
        // 不再基于实际速度，而是模拟一个跃迁隧道中的小范围振荡

        // 在跃迁隧道中的振荡效果
        _shipCoordinates['x'] =
            100.0 +
            math.sin(_currentTime.millisecondsSinceEpoch * 0.001) * 10.0;
        _shipCoordinates['y'] =
            40.0 + math.cos(_currentTime.millisecondsSinceEpoch * 0.0015) * 5.0;
        _shipCoordinates['z'] =
            70.0 + math.sin(_currentTime.millisecondsSinceEpoch * 0.0012) * 8.0;

        // 添加一点随机性
        _shipCoordinates['x'] =
            _shipCoordinates['x']! + (_random.nextDouble() * 2 - 1) * 0.5;
        _shipCoordinates['y'] =
            _shipCoordinates['y']! + (_random.nextDouble() * 2 - 1) * 0.3;
        _shipCoordinates['z'] =
            _shipCoordinates['z']! + (_random.nextDouble() * 2 - 1) * 0.4;
      }
    }
    // 当速度为0时，坐标不变化
  }

  // 限制坐标在合理范围内
  void _constrainCoordinates() {
    // 定义坐标的合理范围
    const double minX = 50.0;
    const double maxX = 200.0;
    const double minY = 30.0;
    const double maxY = 70.0;
    const double minZ = 40.0;
    const double maxZ = 150.0;

    // 限制X坐标
    if (_shipCoordinates['x']! < minX) {
      _shipCoordinates['x'] = minX;
    } else if (_shipCoordinates['x']! > maxX) {
      _shipCoordinates['x'] = maxX;
    }

    // 限制Y坐标
    if (_shipCoordinates['y']! < minY) {
      _shipCoordinates['y'] = minY;
    } else if (_shipCoordinates['y']! > maxY) {
      _shipCoordinates['y'] = maxY;
    }

    // 限制Z坐标
    if (_shipCoordinates['z']! < minZ) {
      _shipCoordinates['z'] = minZ;
    } else if (_shipCoordinates['z']! > maxZ) {
      _shipCoordinates['z'] = maxZ;
    }
  }

  // 统一更新飞船姿态
  void _updateShipAttitude() {
    // 优先级顺序：跃迁状态 > 操作状态 > 速度状态

    // 跃迁相关状态
    if (_isJumpExecuting) {
      _shipAttitude = "跃迁中";
      return;
    }

    if (_isJumpCharging) {
      if (_jumpChargeLevel >= 1.0) {
        _shipAttitude = "跃迁准备就绪";
      } else {
        _shipAttitude = "跃迁充能中";
      }
      return;
    }

    // 操作状态
    if (_isThrust) {
      _shipAttitude = "全速推进";
      return;
    }

    if (_isForward) {
      _shipAttitude = "加速前进";
      return;
    }

    if (_isBackward) {
      _shipAttitude = "减速";
      return;
    }

    if (_isLeft) {
      _shipAttitude = "左转";
      return;
    }

    if (_isRight) {
      _shipAttitude = "右转";
      return;
    }

    // 速度状态
    if (_shipSpeed < 0.1) {
      _shipAttitude = "停止";
    } else if (_shipSpeed < 50) {
      _shipAttitude = "巡航";
    } else if (_shipSpeed < _maxNormalSpeed) {
      _shipAttitude = "高速巡航";
    } else if (_shipSpeed < _maxThrustSpeed) {
      _shipAttitude = "超速航行";
    } else {
      _shipAttitude = "极速航行";
    }
  }

  // 更新剧情状态
  void _updateStoryStatus(int newStatus) {
    if (_storyStatus == newStatus) return; // 如果状态没变，不处理

    setState(() {
      _storyStatus = newStatus;
    });

    // 通过Socket广播剧情状态变化
    _broadcastStoryStatus();
  }

  // 广播剧情状态
  void _broadcastStoryStatus() {
    if (socketService.isServerRunning) {
      socketService.broadcastMessage('STORY_STATUS:$_storyStatus');
    }
  }

  // 重置剧情状态
  void _resetStoryStatus() {
    _updateStoryStatus(0); // 重置为"无"
  }

  // 监听Socket服务状态变化
  void _listenToSocketServiceStatus() {
    _socketStatusSubscription = socketService.runningStream.listen((isRunning) {
      if (isRunning) {
        // Socket服务启动时，广播当前剧情状态
        Future.delayed(const Duration(milliseconds: 500), () {
          _broadcastStoryStatus();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _jumpRecoveryTimer?.cancel();
    _socketMessageSubscription?.cancel();
    _socketStageSubscription?.cancel();
    _socketStatusSubscription?.cancel();
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
            storyStatusMap[_storyStatus] ?? "未知",
            Colors.blue,
            button: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _resetStoryStatus,
                  icon: const Icon(Icons.refresh),
                  tooltip: '重置剧情',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    foregroundColor: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                _buildStorySelector(context),
              ],
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
            '俯仰: ${_shipAngles['pitch']!.toStringAsFixed(1)}°, 偏航: ${_shipAngles['yaw']!.toStringAsFixed(1)}°',
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

  // 构建剧情选择器
  Widget _buildStorySelector(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '选择剧情状态',
      icon: const Icon(Icons.movie_outlined),
      itemBuilder: (context) {
        return storyStatusMap.entries.map((entry) {
          return PopupMenuItem<int>(value: entry.key, child: Text(entry.value));
        }).toList();
      },
      onSelected: _updateStoryStatus,
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
