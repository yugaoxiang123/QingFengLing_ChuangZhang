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

  // 跃迁状态
  double _jumpChargeLevel = 0;
  bool _isJumpCharging = false;
  bool _isJumpCharged = false;
  bool _isJumpExecuting = false; // 跃迁执行中状态
  Timer? _jumpChargeTimer;
  Timer? _jumpChargedBlinkTimer;
  Timer? _jumpExecuteTimer; // 跃迁执行计时器
  Timer? _jumpPulseTimer; // 跃迁脉冲效果计时器
  double _jumpChargedGlowOpacity = 0.0;
  double _jumpPulseEffect = 0.0; // 跃迁脉冲效果

  // 跃迁粒子效果
  List<JumpParticle> _jumpParticles = [];
  Timer? _particleTimer;

  // 飞船动画控制器
  late AnimationController _shipAnimController;
  double _shipRotation = 0;
  double _shipScale = 1.0;
  double _engineGlowOpacity = 0.0;
  // 添加飞船位移变量
  double _shipYOffset = 0.0;
  // 添加前进/减速发光效果
  double _forwardGlowOpacity = 0.0;
  double _backwardGlowOpacity = 0.0;
  // 跃迁动画变量
  double _jumpExecuteOpacity = 0.0; // 跃迁执行时的不透明度
  double _jumpExecuteScale = 1.0; // 跃迁执行时的缩放

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

        // 当前进按下时，向上微移并增加前进发光效果
        if (_forwardPressed) {
          _shipYOffset = -5.0 * _shipAnimController.value;
          _forwardGlowOpacity = (0.7 * _shipAnimController.value).clamp(
            0.0,
            0.7,
          );
        }
        // 当减速按下时，向下微移并增加减速发光效果
        else if (_backwardPressed) {
          _shipYOffset = 5.0 * _shipAnimController.value;
          _backwardGlowOpacity = (0.7 * _shipAnimController.value).clamp(
            0.0,
            0.7,
          );
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
    _jumpChargedBlinkTimer?.cancel();
    _particleTimer?.cancel();
    _jumpExecuteTimer?.cancel();
    _jumpPulseTimer?.cancel();
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
        _shipYOffset = 0.0;
        _forwardGlowOpacity = 0.0;
        _backwardGlowOpacity = 0.0;
      });
    }

    // 如果是左转或右转结束，立即重置旋转角度
    if (command == 'LEFT' || command == 'RIGHT') {
      setState(() {
        _shipRotation = 0;
      });
    }

    // 如果是前进或减速结束，重置Y轴位移和发光效果
    if (command == 'FORWARD') {
      setState(() {
        _shipYOffset = 0;
        _forwardGlowOpacity = 0.0;
      });
    } else if (command == 'BACKWARD') {
      setState(() {
        _shipYOffset = 0;
        _backwardGlowOpacity = 0.0;
      });
    }
  }

  // 开始充能跃迁
  void _startJumpCharge() {
    if (_isJumpCharging || _isJumpExecuting) return;

    setState(() {
      _isJumpCharging = true;
      _jumpChargeLevel = 0;
      _isJumpCharged = false;
    });

    _jumpChargeTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) {
      setState(() {
        if (_jumpChargeLevel < 1.0) {
          _jumpChargeLevel = (_jumpChargeLevel + 0.04).clamp(0.0, 1.0);
        } else {
          _jumpChargeLevel = 1.0;
          _jumpChargeTimer?.cancel();
          _onJumpChargeComplete();
        }
      });
    });

    _sendCommand('START_JUMP_CHARGE');
  }

  // 跃迁充能完成
  void _onJumpChargeComplete() {
    setState(() {
      _isJumpCharged = true;
    });

    // 发送充能完成命令
    _sendCommand('JUMP_CHARGE_COMPLETE');

    // 创建闪烁效果
    _jumpChargedBlinkTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) {
      setState(() {
        _jumpChargedGlowOpacity = _jumpChargedGlowOpacity > 0.5 ? 0.2 : 1.0;
      });
    });

    // 创建粒子效果
    _startJumpParticles();

    // 自动开始执行跃迁
    _executeJump();
  }

  // 创建跃迁粒子效果
  void _startJumpParticles() {
    // 清除现有粒子
    _jumpParticles.clear();
    _particleTimer?.cancel();

    // 创建初始粒子
    for (int i = 0; i < 20; i++) {
      _jumpParticles.add(JumpParticle.random());
    }

    // 更新粒子动画
    _particleTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_isJumpCharged && !_isJumpExecuting) {
        timer.cancel();
        _jumpParticles.clear();
        return;
      }

      setState(() {
        // 更新现有粒子
        for (var particle in _jumpParticles) {
          particle.update();
        }

        // 移除消失的粒子
        _jumpParticles.removeWhere((particle) => particle.alpha <= 0);

        // 添加新粒子 - 在跃迁执行过程中增加更多粒子
        if (_isJumpExecuting) {
          // 跃迁执行过程中，更积极地添加粒子
          if (_jumpParticles.length < 50 && math.Random().nextDouble() > 0.5) {
            _jumpParticles.add(
              JumpParticle.random(
                // 跃迁执行中，粒子寿命更长
                alphaDecay: 0.005,
                // 跃迁执行中，粒子速度更快
                speedMultiplier: 1.5,
              ),
            );
          }
        } else if (_jumpParticles.length < 30 &&
            math.Random().nextDouble() > 0.7) {
          _jumpParticles.add(JumpParticle.random());
        }
      });
    });
  }

  // 执行跃迁
  void _executeJump() {
    if (!_isJumpCharging && !_isJumpCharged) return;

    // 取消充能和闪烁计时器
    _jumpChargeTimer?.cancel();
    _jumpChargedBlinkTimer?.cancel();

    // 设置跃迁执行状态
    setState(() {
      _isJumpCharging = false;
      _isJumpCharged = false;
      _isJumpExecuting = true;
      _jumpExecuteOpacity = 0.0;
      _jumpExecuteScale = 1.0;
      _jumpPulseEffect = 0.0;
    });

    // 根据充能程度发送不同的跃迁命令
    if (_jumpChargeLevel >= 0.95) {
      _sendCommand('EXECUTE_JUMP_FULL');
    } else if (_jumpChargeLevel >= 0.5) {
      _sendCommand('EXECUTE_JUMP_MEDIUM');
    } else {
      _sendCommand('EXECUTE_JUMP_SHORT');
    }

    // 开始跃迁动画
    _startJumpExecuteAnimation();

    // 开始脉冲效果
    _startJumpPulseEffect();
  }

  // 开始跃迁脉冲效果
  void _startJumpPulseEffect() {
    _jumpPulseTimer?.cancel();
    _jumpPulseTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) {
      if (!_isJumpExecuting) {
        timer.cancel();
        return;
      }

      setState(() {
        // 脉冲效果在0.2和1.0之间变化
        _jumpPulseEffect = _jumpPulseEffect > 0.6 ? 0.2 : 1.0;
      });
    });
  }

  // 开始跃迁执行动画
  void _startJumpExecuteAnimation() {
    // 创建跃迁执行动画
    _jumpExecuteTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) {
      setState(() {
        // 前2秒：增加不透明度和缩放
        if (timer.tick < 40) {
          _jumpExecuteOpacity = (timer.tick / 40).clamp(0.0, 1.0);
          _jumpExecuteScale = 1.0 + (timer.tick / 40) * 0.5;
        }
        // 中间2秒：保持最大效果
        else if (timer.tick < 80) {
          _jumpExecuteOpacity = 1.0;
          _jumpExecuteScale = 1.5;
        }
        // 最后2秒：减少不透明度和缩放
        else if (timer.tick < 120) {
          _jumpExecuteOpacity = (1.0 - (timer.tick - 80) / 40).clamp(0.0, 1.0);
          _jumpExecuteScale = 1.5 - ((timer.tick - 80) / 40) * 0.5;
        }
        // 结束动画
        else {
          _jumpExecuteTimer?.cancel();
          _onJumpExecuteComplete();
        }
      });
    });
  }

  // 跃迁执行完成
  void _onJumpExecuteComplete() {
    _jumpPulseTimer?.cancel();
    setState(() {
      _isJumpExecuting = false;
      _jumpChargeLevel = 0;
      _jumpExecuteOpacity = 0.0;
      _jumpExecuteScale = 1.0;
      _jumpPulseEffect = 0.0;
      _jumpParticles.clear();
    });

    // 发送跃迁完成命令
    _sendCommand('JUMP_COMPLETE');

    // 清除粒子效果
    _particleTimer?.cancel();
  }

  // 取消跃迁
  void _cancelJump() {
    // 如果正在执行跃迁，则不允许取消
    if (_isJumpExecuting) return;

    _jumpChargeTimer?.cancel();
    _jumpChargedBlinkTimer?.cancel();
    _particleTimer?.cancel();
    setState(() {
      _isJumpCharging = false;
      _isJumpCharged = false;
      _jumpChargeLevel = 0;
      _jumpChargedGlowOpacity = 0.0;
      _jumpParticles.clear();
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
        ).colorScheme.surfaceContainerHighest.withAlpha((0.7 * 255).round()),
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
      clipBehavior: Clip.none, // 确保不裁剪子元素
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
      child: Stack(
        clipBehavior: Clip.none, // 确保Stack不裁剪子元素
        alignment: Alignment.center,
        children: [
          // 跃迁执行效果 - 使用环形光晕而不是方块
          if (_isJumpExecuting) ...[
            // 最外层光环 - 放在Container外部以避免被裁剪
            Positioned(
              left: -20, // 扩展到Container外部
              top: -20,
              child: Transform.scale(
                scale: _jumpExecuteScale,
                child: Container(
                  width: 160, // 增大尺寸确保完全覆盖
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
                    border: Border.all(
                      color: Colors.purple.withAlpha(
                        (_jumpExecuteOpacity * 180).round(),
                      ),
                      width: 8,
                    ),
                  ),
                ),
              ),
            ),

            // 中层光环
            Positioned(
              left: -10,
              top: -10,
              child: Transform.scale(
                scale: _jumpExecuteScale * 0.85,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
                    border: Border.all(
                      color: Colors.purple.withAlpha(
                        (_jumpExecuteOpacity * 150).round(),
                      ),
                      width: 4,
                    ),
                  ),
                ),
              ),
            ),

            // 内层光环
            Transform.scale(
              scale: _jumpExecuteScale * 0.7,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  border: Border.all(
                    color: Colors.purple.withAlpha(
                      (_jumpPulseEffect * 255).round(),
                    ),
                    width: 2,
                  ),
                ),
              ),
            ),
          ],

          // 跃迁充能效果
          if (_isJumpCharging && !_isJumpCharged && !_isJumpExecuting)
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

          // 跃迁充能完成闪烁效果
          if (_isJumpCharged && !_isJumpExecuting)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.purple, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withAlpha(
                      (_jumpChargedGlowOpacity * 255).round(),
                    ),
                    blurRadius: 15,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),

          // 跃迁粒子效果
          if (_isJumpCharged || _isJumpExecuting)
            ..._jumpParticles
                .map(
                  (particle) => Positioned(
                    left: particle.x,
                    top: particle.y,
                    child: Container(
                      width: particle.size,
                      height: particle.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.purple.withAlpha(
                          (particle.alpha * 255).round(),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),

          // 飞船主体 - 确保放在最上层
          Center(
            child: Transform.translate(
              offset: Offset(0, _shipYOffset),
              child: Transform.rotate(
                angle: _shipRotation,
                child: Transform.scale(
                  scale: _isJumpExecuting
                      ? _jumpExecuteScale * 0.8
                      : _shipScale,
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
                            if (_engineGlowOpacity > 0 || _isJumpExecuting)
                              Container(
                                width: 40,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: _isJumpExecuting
                                      ? Colors.purple.withAlpha(
                                          (_jumpExecuteOpacity * 255).round(),
                                        )
                                      : Colors.orange.withAlpha(
                                          (_engineGlowOpacity.clamp(0.0, 1.0) *
                                                  255)
                                              .round(),
                                        ),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _isJumpExecuting
                                          ? Colors.purple.withAlpha(
                                              (_jumpExecuteOpacity * 200)
                                                  .round(),
                                            )
                                          : Colors.orange.withAlpha(
                                              ((_engineGlowOpacity * 0.8).clamp(
                                                        0.0,
                                                        1.0,
                                                      ) *
                                                      255)
                                                  .round(),
                                            ),
                                      blurRadius: 15,
                                      spreadRadius: _isJumpExecuting ? 5 : 2,
                                    ),
                                  ],
                                ),
                              ),
                            // 引擎主体
                            Container(
                              width: 30,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _isJumpExecuting
                                    ? Colors.purple
                                    : Colors.orange,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 前进发光效果
                      if (_forwardGlowOpacity > 0 && !_isJumpExecuting)
                        Positioned(
                          top: -5,
                          child: Container(
                            width: 40,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.blue.withAlpha(
                                (_forwardGlowOpacity * 255).round(),
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withAlpha(
                                    (_forwardGlowOpacity * 0.8 * 255).round(),
                                  ),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),

                      // 减速发光效果
                      if (_backwardGlowOpacity > 0 && !_isJumpExecuting)
                        Positioned(
                          top: 70,
                          child: Container(
                            width: 40,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(
                                (_backwardGlowOpacity * 255).round(),
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withAlpha(
                                    (_backwardGlowOpacity * 0.8 * 255).round(),
                                  ),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),

                      // 飞船窗口
                      Positioned(
                        top: 20,
                        child: Container(
                          width: 30,
                          height: 15,
                          decoration: BoxDecoration(
                            color: Colors.lightBlue.withAlpha(
                              (0.7 * 255).round(),
                            ),
                            borderRadius: BorderRadius.circular(7.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
            boxShadow: _isJumpCharged
                ? [
                    BoxShadow(
                      color: Colors.purple.withAlpha(
                        (_jumpChargedGlowOpacity * 150).round(),
                      ),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : _isJumpExecuting
                ? [
                    BoxShadow(
                      color: Colors.purple.withAlpha(
                        (_jumpExecuteOpacity * 150).round(),
                      ),
                      blurRadius: 10 + (_jumpPulseEffect * 5),
                      spreadRadius: 2 + (_jumpPulseEffect * 3),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _isJumpExecuting ? _jumpExecuteOpacity : _jumpChargeLevel,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                _isJumpExecuting
                    ? Colors.purple.withAlpha((_jumpPulseEffect * 255).round())
                    : _isJumpCharged
                    ? Colors.purple
                    : _jumpChargeLevel < 0.5
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
          onLongPressStart: _isJumpExecuting ? null : (_) => _startJumpCharge(),
          onLongPressEnd: _isJumpExecuting ? null : (_) => {},
          onTap: _isJumpCharging && !_isJumpExecuting ? _cancelJump : null,
          child: Container(
            width: 120,
            height: 50,
            decoration: BoxDecoration(
              color: _isJumpExecuting
                  ? Colors.grey.withAlpha((0.5 * 255).round())
                  : _isJumpCharged
                  ? Colors.purple.withAlpha(
                      (_jumpChargedGlowOpacity * 255).round(),
                    )
                  : _isJumpCharging
                  ? Colors.purple.withAlpha((0.8 * 255).round())
                  : Colors.purple.withAlpha((0.3 * 255).round()),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: _isJumpExecuting ? Colors.grey : Colors.purple,
                width: 2,
              ),
              boxShadow: _isJumpCharging && !_isJumpExecuting
                  ? [
                      BoxShadow(
                        color: Colors.purple.withAlpha(
                          _isJumpCharged
                              ? (_jumpChargedGlowOpacity * 255).round()
                              : (0.5 * 255).round(),
                        ),
                        blurRadius: 15,
                        spreadRadius: _isJumpCharged ? 5 : 2,
                      ),
                    ]
                  : _isJumpExecuting
                  ? [
                      BoxShadow(
                        color: Colors.purple.withAlpha(
                          (_jumpPulseEffect * 100).round(),
                        ),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: Text(
                _isJumpExecuting
                    ? '跃迁中...'
                    : _isJumpCharged
                    ? '跃迁准备就绪!'
                    : _isJumpCharging
                    ? '跃迁充能中...'
                    : '长按开始跃迁',
                style: TextStyle(
                  color: _isJumpExecuting
                      ? Colors.white.withOpacity(0.7)
                      : _isJumpCharging || _isJumpCharged
                      ? Colors.white
                      : Colors.purple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isJumpExecuting
              ? '跃迁执行中，请稍候...'
              : _isJumpCharged
              ? ''
              : _isJumpCharging
              ? '充能完成将自动跃迁'
              : '',
          style: TextStyle(
            fontSize: 12,
            color: _isJumpExecuting
                ? Colors.purple
                : _isJumpCharged
                ? Colors.purple
                : Colors.purple.withAlpha((0.8 * 255).round()),
            fontWeight: _isJumpExecuting || _isJumpCharged
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

// 跃迁粒子类
class JumpParticle {
  double x;
  double y;
  double vx;
  double vy;
  double size;
  double alpha;
  double alphaDecay; // 透明度衰减速率

  JumpParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.alpha,
    required this.alphaDecay,
  });

  // 创建随机粒子
  factory JumpParticle.random({
    double alphaDecay = 0.01,
    double speedMultiplier = 1.0,
  }) {
    final random = math.Random();
    // 随机角度
    final angle = random.nextDouble() * 2 * math.pi;
    // 随机距离（从中心点)
    final distance = 30 + random.nextDouble() * 30;
    // 计算位置
    final x = 60 + math.cos(angle) * distance;
    final y = 60 + math.sin(angle) * distance;
    // 速度
    final speed = (0.2 + random.nextDouble() * 0.5) * speedMultiplier;
    final vx = math.cos(angle) * speed;
    final vy = math.sin(angle) * speed;

    return JumpParticle(
      x: x,
      y: y,
      vx: vx,
      vy: vy,
      size: 1 + random.nextDouble() * 3,
      alpha: 0.3 + random.nextDouble() * 0.7,
      alphaDecay: alphaDecay,
    );
  }

  // 更新粒子状态
  void update() {
    x += vx;
    y += vy;
    alpha -= alphaDecay;
  }
}
