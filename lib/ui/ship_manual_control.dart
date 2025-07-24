import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

class ShipManualControl extends StatefulWidget {
  const ShipManualControl({super.key});

  @override
  State<ShipManualControl> createState() => _ShipManualControlState();
}

class _ShipManualControlState extends State<ShipManualControl>
    with SingleTickerProviderStateMixin {
  // 控制按钮按下状态
  bool _forwardPressed = false;
  bool _backwardPressed = false;
  bool _leftPressed = false;
  bool _rightPressed = false;
  bool _thrustPressed = false;

  // 跃迁充能状态
  double _jumpChargeLevel = 0;
  bool _isJumpCharging = false;
  Timer? _jumpChargeTimer;

  // 飞船动画控制器
  late AnimationController _shipAnimController;
  double _shipRotation = 0;
  double _shipScale = 1.0;
  double _engineGlowOpacity = 0.0;

  @override
  void initState() {
    super.initState();
    // 初始化动画控制器
    _shipAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _shipAnimController.addListener(() {
      setState(() {
        // 当推进按下时，增加引擎发光效果
        if (_thrustPressed) {
          _engineGlowOpacity = (0.8 + (_shipAnimController.value * 0.2)).clamp(
            0.0,
            1.0,
          );
          _shipScale = 1.0 + (_shipAnimController.value * 0.05);
        }

        // 当左转或右转按下时，旋转飞船
        if (_leftPressed) {
          _shipRotation = -0.2 * _shipAnimController.value;
        } else if (_rightPressed) {
          _shipRotation = 0.2 * _shipAnimController.value;
        } else {
          // 当没有按下左转或右转时，立即重置旋转角度
          _shipRotation = 0;
        }
      });
    });
  }

  @override
  void dispose() {
    _jumpChargeTimer?.cancel();
    _shipAnimController.dispose();
    super.dispose();
  }

  // 发送控制命令到服务器
  void _sendCommand(String command) {
    // 遍历所有连接的客户端
    for (var client in socketService.clientConnections) {
      socketService.sendTestMessage(client.connection, command);
    }
  }

  // 开始按下控制按钮
  void _startCommand(String command) {
    _sendCommand('START_$command');
    _shipAnimController.forward(from: 0.0);
  }

  // 结束按下控制按钮
  void _endCommand(String command) {
    _sendCommand('END_$command');

    // 如果所有方向键都释放了，重置动画
    if (!_forwardPressed &&
        !_backwardPressed &&
        !_leftPressed &&
        !_rightPressed &&
        !_thrustPressed) {
      setState(() {
        _engineGlowOpacity = 0.0;
        _shipScale = 1.0;
      });
    }

    // 如果是左转或右转结束，立即重置旋转角度
    if (command == 'LEFT' || command == 'RIGHT') {
      setState(() {
        _shipRotation = 0;
      });
    }
  }

  // 开始充能跃迁
  void _startJumpCharge() {
    if (_isJumpCharging) return;

    setState(() {
      _isJumpCharging = true;
      _jumpChargeLevel = 0;
    });

    _jumpChargeTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      setState(() {
        if (_jumpChargeLevel < 1.0) {
          _jumpChargeLevel = (_jumpChargeLevel + 0.02).clamp(0.0, 1.0);
        } else {
          _jumpChargeLevel = 1.0;
          _jumpChargeTimer?.cancel();
        }
      });
    });

    _sendCommand('START_JUMP_CHARGE');
  }

  // 执行跃迁
  void _executeJump() {
    if (!_isJumpCharging) return;

    _jumpChargeTimer?.cancel();
    setState(() {
      _isJumpCharging = false;
    });

    // 根据充能程度发送不同的跃迁命令
    if (_jumpChargeLevel >= 0.95) {
      _sendCommand('EXECUTE_JUMP_FULL');
    } else if (_jumpChargeLevel >= 0.5) {
      _sendCommand('EXECUTE_JUMP_MEDIUM');
    } else {
      _sendCommand('EXECUTE_JUMP_SHORT');
    }

    // 重置充能
    setState(() {
      _jumpChargeLevel = 0;
    });
  }

  // 取消跃迁
  void _cancelJump() {
    _jumpChargeTimer?.cancel();
    setState(() {
      _isJumpCharging = false;
      _jumpChargeLevel = 0;
    });
    _sendCommand('CANCEL_JUMP');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceVariant.withAlpha((0.7 * 255).round()),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.primary.withAlpha((0.3 * 255).round()),
          width: 2,
        ),
      ),
      margin: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 标题
          Text(
            '飞船手动控制',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),

          // 飞船图标显示
          _buildShipIcon(context),
          const SizedBox(height: 24),

          // 主控制区域
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 左侧方向控制
              Column(
                children: [
                  // 前进按钮
                  _buildControlButton(
                    icon: Icons.arrow_upward_rounded,
                    label: '前进',
                    isPressed: _forwardPressed,
                    onPressed: () {
                      setState(() => _forwardPressed = true);
                      _startCommand('FORWARD');
                    },
                    onReleased: () {
                      setState(() => _forwardPressed = false);
                      _endCommand('FORWARD');
                    },
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 8),

                  // 左右控制按钮
                  Row(
                    children: [
                      // 左转按钮
                      _buildControlButton(
                        icon: Icons.arrow_back_rounded,
                        label: '左转',
                        isPressed: _leftPressed,
                        onPressed: () {
                          setState(() => _leftPressed = true);
                          _startCommand('LEFT');
                        },
                        onReleased: () {
                          setState(() => _leftPressed = false);
                          _endCommand('LEFT');
                        },
                        color: Colors.green,
                      ),
                      const SizedBox(width: 44),

                      // 右转按钮
                      _buildControlButton(
                        icon: Icons.arrow_forward_rounded,
                        label: '右转',
                        isPressed: _rightPressed,
                        onPressed: () {
                          setState(() => _rightPressed = true);
                          _startCommand('RIGHT');
                        },
                        onReleased: () {
                          setState(() => _rightPressed = false);
                          _endCommand('RIGHT');
                        },
                        color: Colors.green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 后退按钮
                  _buildControlButton(
                    icon: Icons.arrow_downward_rounded,
                    label: '减速',
                    isPressed: _backwardPressed,
                    onPressed: () {
                      setState(() => _backwardPressed = true);
                      _startCommand('BACKWARD');
                    },
                    onReleased: () {
                      setState(() => _backwardPressed = false);
                      _endCommand('BACKWARD');
                    },
                    color: Colors.orange,
                  ),
                ],
              ),

              const SizedBox(width: 32),

              // 右侧推进和跃迁控制
              Column(
                children: [
                  // 推进按钮
                  _buildControlButton(
                    icon: Icons.rocket_launch,
                    label: '推进',
                    isPressed: _thrustPressed,
                    onPressed: () {
                      setState(() => _thrustPressed = true);
                      _startCommand('THRUST');
                    },
                    onReleased: () {
                      setState(() => _thrustPressed = false);
                      _endCommand('THRUST');
                    },
                    color: Colors.red,
                    size: 80,
                  ),
                  const SizedBox(height: 16),

                  // 跃迁控制
                  _buildJumpControl(context),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 构建飞船图标
  Widget _buildShipIcon(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.primary.withAlpha((0.3 * 255).round()),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Transform.rotate(
          angle: _shipRotation,
          child: Transform.scale(
            scale: _shipScale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 飞船主体
                Container(
                  width: 60,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                // 飞船机翼
                Positioned(
                  top: 40,
                  child: Container(
                    width: 100,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                // 飞船引擎
                Positioned(
                  bottom: 10,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 引擎发光效果
                      if (_engineGlowOpacity > 0)
                        Container(
                          width: 40,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(
                              (_engineGlowOpacity.clamp(0.0, 1.0) * 255)
                                  .round(),
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withAlpha(
                                  ((_engineGlowOpacity * 0.8).clamp(0.0, 1.0) *
                                          255)
                                      .round(),
                                ),
                                blurRadius: 15,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      // 引擎主体
                      Container(
                        width: 30,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ],
                  ),
                ),
                // 飞船窗口
                Positioned(
                  top: 20,
                  child: Container(
                    width: 30,
                    height: 15,
                    decoration: BoxDecoration(
                      color: Colors.lightBlue.withAlpha((0.7 * 255).round()),
                      borderRadius: BorderRadius.circular(7.5),
                    ),
                  ),
                ),
                // 跃迁充能效果
                if (_isJumpCharging)
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.purple.withAlpha(
                          (_jumpChargeLevel.clamp(0.0, 1.0) * 255).round(),
                        ),
                        width: 3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 构建控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isPressed,
    required VoidCallback onPressed,
    required VoidCallback onReleased,
    required Color color,
    double size = 60,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTapDown: (_) => onPressed(),
          onTapUp: (_) => onReleased(),
          onTapCancel: () => onReleased(),
          onLongPress: null, // 移除长按事件，只使用按下和释放
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: isPressed
                  ? color.withAlpha((0.8 * 255).round())
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(size / 2),
              border: Border.all(color: color, width: 2),
              boxShadow: isPressed
                  ? []
                  : [
                      BoxShadow(
                        color: color.withAlpha((0.3 * 255).round()),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
            ),
            child: Icon(
              icon,
              color: isPressed ? Colors.white : color,
              size: size * 0.5,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w500, color: color),
        ),
      ],
    );
  }

  // 构建跃迁控制
  Widget _buildJumpControl(BuildContext context) {
    return Column(
      children: [
        // 跃迁充能指示器
        Container(
          width: 120,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _jumpChargeLevel,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                _jumpChargeLevel < 0.5
                    ? Colors.blue
                    : _jumpChargeLevel < 0.8
                    ? Colors.yellow
                    : Colors.red,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 跃迁按钮
        GestureDetector(
          onLongPressStart: (_) => _startJumpCharge(),
          onLongPressEnd: (_) => _executeJump(),
          onTap: _isJumpCharging ? _cancelJump : null,
          child: Container(
            width: 120,
            height: 50,
            decoration: BoxDecoration(
              color: _isJumpCharging
                  ? Colors.purple.withAlpha((0.8 * 255).round())
                  : Colors.purple.withAlpha((0.3 * 255).round()),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.purple, width: 2),
              boxShadow: _isJumpCharging
                  ? [
                      BoxShadow(
                        color: Colors.purple.withAlpha((0.5 * 255).round()),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: Text(
                _isJumpCharging ? '跃迁充能中...' : '长按开始跃迁',
                style: TextStyle(
                  color: _isJumpCharging ? Colors.white : Colors.purple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isJumpCharging ? '松开执行跃迁' : '',
          style: TextStyle(
            fontSize: 12,
            color: Colors.purple.withAlpha((0.8 * 255).round()),
          ),
        ),
      ],
    );
  }
}
