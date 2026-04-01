import 'package:flutter/material.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'update_service.dart';
import 'update_info.dart';
import 'permission_manager.dart';
import 'update_manual_check.dart';

/// 更新管理器组件
class UpdateManager extends StatefulWidget {
  final Widget child;
  final String? serverUrl;
  final String? updatePath;
  final bool enabled;

  const UpdateManager({
    super.key,
    required this.child,
    this.serverUrl,
    this.updatePath,
    this.enabled = true,
  });

  @override
  State<UpdateManager> createState() => _UpdateManagerState();
}

class _UpdateManagerState extends State<UpdateManager> {
  bool _isChecking = false;
  bool _isDownloading = false;
  bool _isInstalling = false;  // 添加安装状态标志
  double _downloadProgress = 0.0;
  bool _permissionChecked = false;
  Timer? _countdownTimer;  // 添加Timer引用用于管理
  int _forceUpdateCountdown = 10;  // 强制更新倒计时状态
  StreamSubscription<void>? _manualCheckSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      // 应用启动时先检查权限，再检查更新
      _initializeUpdateManager();
      _manualCheckSubscription = UpdateManualCheck.requests.listen((_) {
        if (mounted) {
          _checkUpdate(
            showToast: true,
            forceCheck: true,
            userInitiated: true,
          );
        }
      });
    }
  }

  /// 初始化更新管理器
  Future<void> _initializeUpdateManager() async {
    // 延迟一点时间，确保UI已经构建完成
    await Future.delayed(const Duration(milliseconds: 500));
    
    // 检查安装权限
    final hasPermission = await _checkInstallPermission();
    
    // 只有在有权限的情况下才检查更新
    if (hasPermission) {
      _checkUpdate(showToast: false);
    } else {
      print('没有安装权限，跳过自动更新检查');
    }
  }

  /// 检查安装权限
  Future<bool> _checkInstallPermission() async {
    if (_permissionChecked || !mounted) return false;
    
    try {
      final permissionManager = PermissionManager();
      final permissionStatus = await permissionManager.checkInstallPermissionOnStartup(context);
      _permissionChecked = true;
      return permissionStatus == PermissionStatus.granted;
    } catch (e) {
      print('启动时检查权限失败: $e');
      _permissionChecked = true;
      return false;
    }
  }





  /// 检查更新
  Future<void> _checkUpdate({
    bool showToast = true,
    bool forceCheck = false,
    bool userInitiated = false,
  }) async {
    if (_isChecking) {
      if (userInitiated && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('正在检查更新，请稍候再试')),
        );
      }
      return;
    }

    setState(() {
      _isChecking = true;
    });

    try {
      final outcome = await UpdateService().performUpdateCheck(
        serverUrl: widget.serverUrl,
        updatePath: widget.updatePath,
        showToast: showToast,
        forceCheck: forceCheck,
      );

      if (!mounted) return;

      final updateInfo = outcome.info;
      if (updateInfo != null) {
        print('发现新版本: ${updateInfo.version} (${updateInfo.versionCode})');

        if (userInitiated && updateInfo.updateType == UpdateType.silent) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('发现新版本 ${updateInfo.version}，正在后台下载…'),
              duration: const Duration(seconds: 4),
            ),
          );
        }

        // 根据更新类型处理
        switch (updateInfo.updateType) {
          case UpdateType.silent:
            _silentUpdate(updateInfo);
            break;
          case UpdateType.force:
            _showForceUpdateDialog(updateInfo);
            break;
          case UpdateType.normal:
            _showNormalUpdateDialog(updateInfo);
            break;
        }
      } else if (userInitiated && outcome.message.isNotEmpty) {
        final msg = outcome.message;
        if (!msg.contains('未到检查间隔') && !msg.contains('仅内部逻辑')) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(msg),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      print('检查更新失败: $e');
      if (userInitiated && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('检查更新异常：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  /// 静默更新
  Future<void> _silentUpdate(UpdateInfo updateInfo) async {
    if (_isDownloading || _isInstalling) {
      print('更新已在进行中，忽略静默更新请求');
      return;
    }

    // 取消任何可能的倒计时Timer
    _countdownTimer?.cancel();
    _countdownTimer = null;

    setState(() {
      _isDownloading = true;
      _isInstalling = false;
      _downloadProgress = 0.0;
    });

    try {
      // 下载更新
      final filePath = await UpdateService().downloadUpdate(
        updateInfo,
        onProgress: (progress) {
          if (_isDownloading && !_isInstalling) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (filePath != null) {
        // 更新状态为安装中
        setState(() {
          _isDownloading = false;
          _isInstalling = true;
        });

        // 安装更新
        final installResult = await UpdateService().installUpdate(filePath);
        
        if (installResult) {
          print('静默安装流程启动成功');
          // 安装成功后不要立即重置状态
          return;
        } else {
          print('静默安装流程启动失败');
        }
      }
    } catch (e) {
      print('静默更新失败: $e');
    } finally {
      // 只有在安装失败的情况下才重置状态
      if (!_isInstalling) {
        setState(() {
          _isDownloading = false;
          _isInstalling = false;
        });
      }
    }
  }

  /// 显示强制更新对话框
  void _showForceUpdateDialog(UpdateInfo updateInfo) {
    // 先取消任何现有的倒计时
    _countdownTimer?.cancel();
    _countdownTimer = null;
    
    // 重置倒计时
    _forceUpdateCountdown = 10;
    
    showDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (context) => PopScope(
        canPop: false, // 禁止返回键
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            // 启动倒计时（只启动一次）
            void startCountdown() {
              if (_countdownTimer != null) return; // 防止重复启动
              
              print('启动强制更新倒计时: $_forceUpdateCountdown 秒');
              _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                if (mounted) {
                  if (_forceUpdateCountdown > 0) {
                    _forceUpdateCountdown--;
                    print('倒计时: $_forceUpdateCountdown 秒');
                    setDialogState(() {}); // 触发UI更新
                  } else {
                    // 倒计时结束，取消定时器并开始下载
                    print('倒计时结束，开始下载更新');
                    timer.cancel();
                    _countdownTimer = null;
                    if (!_isDownloading && !_isInstalling) {
                      _downloadAndInstall(updateInfo, setDialogState);
                    }
                  }
                } else {
                  // 如果组件已经销毁，取消timer
                  timer.cancel();
                  _countdownTimer = null;
                }
              });
            }

            // 组件挂载后启动倒计时
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_isDownloading && !_isInstalling && _countdownTimer == null) {
                startCountdown();
              }
            });

            return AlertDialog(
              title: const Text('发现新版本'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('新版本: ${updateInfo.version}'),
                  const SizedBox(height: 8),
                  Text(updateInfo.description),
                  const SizedBox(height: 16),
                  if (_isDownloading) ...[
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 8),
                    Text(
                      '下载进度: ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                    ),
                  ] else if (_isInstalling) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('正在安装...'),
                  ] else ...[
                    Text(
                      '将在 $_forceUpdateCountdown 秒后自动更新',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 显示普通更新对话框
  void _showNormalUpdateDialog(UpdateInfo updateInfo) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('发现新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('新版本: ${updateInfo.version}'),
              const SizedBox(height: 8),
              Text(updateInfo.description),
              if (_isDownloading || _isInstalling) ...[
                const SizedBox(height: 16),
                if (_isDownloading) ...[
                  LinearProgressIndicator(value: _downloadProgress),
                  const SizedBox(height: 8),
                  Text(
                    '下载进度: ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  ),
                ] else if (_isInstalling) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('正在安装...'),
                ],
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: (_isDownloading || _isInstalling) ? null : () => Navigator.of(context).pop(),
              child: const Text('稍后再说'),
            ),
            TextButton(
              onPressed: (_isDownloading || _isInstalling)
                  ? null
                  : () => _downloadAndInstall(updateInfo, setDialogState),
              child: Text(_isDownloading ? '下载中...' : _isInstalling ? '安装中...' : '立即更新'),
            ),
          ],
        ),
      ),
    );
  }

  /// 下载并安装更新
  Future<void> _downloadAndInstall(
    UpdateInfo updateInfo, [
    Function(Function())? setDialogState,
  ]) async {
    if (_isDownloading || _isInstalling) {
      print('更新已在进行中，忽略重复请求');
      return;
    }

    print('开始更新流程，取消所有倒计时Timer');
    // 立即取消所有可能的倒计时Timer
    _countdownTimer?.cancel();
    _countdownTimer = null;

    // 更新组件状态
    setState(() {
      _isDownloading = true;
      _isInstalling = false;
      _downloadProgress = 0.0;
    });

    // 如果有对话框状态更新函数，也更新对话框状态
    setDialogState?.call(() {
      _isDownloading = true;
      _isInstalling = false;
      _downloadProgress = 0.0;
    });

    try {
      print('开始下载更新: ${updateInfo.version}');

      // 下载更新
      final filePath = await UpdateService().downloadUpdate(
        updateInfo,
        onProgress: (progress) {
          // 只有在下载状态时才更新进度
          if (_isDownloading && !_isInstalling) {
            setState(() {
              _downloadProgress = progress;
            });

            setDialogState?.call(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (filePath != null) {
        print('下载完成，准备安装: $filePath');

        // 更新状态为安装中
        setState(() {
          _isDownloading = false;
          _isInstalling = true;
        });

        setDialogState?.call(() {
          _isDownloading = false;
          _isInstalling = true;
        });

        print('开始安装流程，状态已设置为安装中');

        // 安装更新
        final installResult = await UpdateService().installUpdate(filePath);

        if (installResult) {
          print('安装流程启动成功');
          // 安装成功后不要立即重置状态，让应用自然退出或重启
          // 这样可以避免在安装过程中状态被重置导致重复下载
          return;
        } else {
          print('安装流程启动失败');
        }
      } else {
        print('下载更新失败，未获取到文件路径');
      }
    } catch (e) {
      print('下载安装更新失败: $e');
    } finally {
      // 只有在安装失败的情况下才重置状态
      if (!_isInstalling) {
        setState(() {
          _isDownloading = false;
          _isInstalling = false;
        });

        setDialogState?.call(() {
          _isDownloading = false;
          _isInstalling = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // 清理Timer
    _countdownTimer?.cancel();
    _manualCheckSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// 更新管理器触发器
/// 用于在应用中包装需要自动更新的组件
class UpdateManagerTrigger extends StatelessWidget {
  final Widget child;
  final String? serverUrl;
  final String? updatePath;
  final bool enabled;

  const UpdateManagerTrigger({
    super.key,
    required this.child,
    this.serverUrl,
    this.updatePath,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return UpdateManager(
      serverUrl: serverUrl,
      updatePath: updatePath,
      enabled: enabled,
      child: child,
    );
  }
}
