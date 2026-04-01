import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'plugins/auto_update/auto_update.dart';
import 'plugins/video_download/video_download_service.dart';
import 'plugins/video_download/video_settings_page.dart';
import 'services/controller_client_service.dart';
import 'services/user_config_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '青峰岭船长',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: UpdateManagerTrigger(
        enabled: true, // 启用自动更新检查
        child: const StageVideoPage(),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class StageVideoPage extends StatefulWidget {
  const StageVideoPage({super.key});

  @override
  State<StageVideoPage> createState() => _StageVideoPageState();
}

class _StageVideoPageState extends State<StageVideoPage> {
  // 阶段名称（含舷窗关闭）
  // 索引与控制面板阶段号映射见 _sendCurrentStage
  final List<String> stages = [
    '舷窗关闭', // stageIndex = 0，视频 0.mp4；控制面板阶段 1（与“登船准备”共享）
    '雷电防护',
    '登船准备',
    '飞船起飞',
    '捕捉垃圾',
    '击碎陨石',
    '行星科普',
    '加速飞行',
    '抵达月球',
  ];

  /// 舷窗关闭：`0.mp4`；其它阶段播完主视频后的待机：`99.mp4`（见 data.json）
  static const int _portholeClosedVideoIndex = 0;
  static const int _stageIdleVideoIndex = 99;

  int currentStageIndex = 0;
  // 当前阶段进入时间（用于计算2分钟停留时长，仅非舷窗关闭阶段使用）
  DateTime? _stageEnterTime;
  // 标记当前是否处于阶段内待机（99.mp4），与舷窗关闭的 0.mp4 不同
  bool _isStageStandbyPlaying = false;
  // 最新更新信息（用于右上角更新日志展示）
  UpdateInfo? _latestUpdateInfo;
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasAutoSwitched = false;
  Timer? _videoCheckTimer;
  DateTime? _lastManualStageSwitchAt;
  static const Duration _manualSwitchCooldown = Duration(seconds: 5);
  
  // 右下角点击检测
  int _bottomRightClickCount = 0;
  DateTime? _lastClickTime;
  static const Duration _clickResetDuration = Duration(seconds: 2);
  
  final VideoDownloadService _downloadService = VideoDownloadService();
  final ControllerClientService _controllerClient = ControllerClientService();
  final UserConfigService _userConfigService = UserConfigService();
  
  // 下载进度相关
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _downloadStatus;
  
  // 配置加载标志
  bool _hasLoadedConfig = false;

  @override
  void initState() {
    super.initState();
    // 加载配置并自动连接（如果配置了）
    _loadAndApplyConfig();
    // 应用启动时检查并下载缺失的视频
    _checkAndDownloadMissingVideos();
    // 默认进入舷窗关闭阶段
    _initializeVideo(0);
    // 检查是否有新版本，用于右上角更新日志展示（独立于自动更新弹窗）
    _loadLatestUpdateInfo();
  }

  /// 加载最新更新信息（仅用于展示更新日志，不触发更新对话框）
  Future<void> _loadLatestUpdateInfo() async {
    try {
      final info = await UpdateService().checkUpdate(
        showToast: false,
        forceCheck: true,
      );
      if (!mounted) return;
      if (info != null) {
        setState(() {
          _latestUpdateInfo = info;
        });
      }
    } catch (e) {
      debugPrint('加载更新日志信息失败: $e');
    }
  }
  
  /// 加载配置并自动连接
  Future<void> _loadAndApplyConfig() async {
    if (_hasLoadedConfig) return;
    
    try {
      final config = await _userConfigService.loadConfig();
      
      if (config != null) {
        debugPrint('加载到服务器IP: ${config.serverIp}');
        _hasLoadedConfig = true;
        
        // 根据配置决定是否自动连接到控制面板服务器
        if (config.autoConnect && config.serverIp.isNotEmpty) {
          try {
            await _controllerClient.connect(config.serverIp);
            debugPrint('已自动连接到控制面板服务器: ${config.serverIp}');
          } catch (e) {
            debugPrint('自动连接控制面板服务器失败: $e');
          }
        } else {
          debugPrint('自动连接已禁用或IP地址为空，跳过自动连接');
        }
      } else {
        debugPrint('未找到用户配置');
      }
    } catch (e) {
      debugPrint('加载配置失败: $e');
    }
  }
  
  /// 发送当前阶段给控制面板
  Future<void> _sendCurrentStage([int? stageIndex]) async {
    if (_controllerClient.status != ConnectionStatus.connected) {
      debugPrint('控制面板未连接，跳过发送阶段信息');
      return;
    }
    
    // 使用传入的 stageIndex，如果没有则使用 currentStageIndex
    final index = stageIndex ?? currentStageIndex;

    // 控制面板阶段号映射：
    //  - 1：舷窗关闭（index 0）和 登船准备（index 1）
    //  - 2~8：其他阶段与原先保持一致（飞船起飞 -> 2，...，抵达月球 -> 8）
    int stageNumber;
    if (index <= 1) {
      stageNumber = 1;
    } else {
      stageNumber = index;
    }
    final message = 'STAGE:$stageNumber';
    
    final success = await _controllerClient.sendMessage(message);
    if (success) {
      debugPrint('已发送当前阶段给控制面板: $message (${stages[index]})');
    } else {
      debugPrint('发送阶段信息失败: $message');
    }
  }
  
  /// 检查并下载缺失的视频
  Future<void> _checkAndDownloadMissingVideos() async {
    try {
      final videoList = await _downloadService.getVideoInfoList();
      final missingVideos = videoList.where((v) => !v.isDownloaded).toList();
      
      if (missingVideos.isEmpty) {
        debugPrint('所有视频已下载');
        return;
      }
      
      debugPrint('发现 ${missingVideos.length} 个缺失的视频，开始下载...');
      
      for (final video in missingVideos) {
        if (!mounted) break;
        
        setState(() {
          _isDownloading = true;
          _downloadProgress = 0.0;
          _downloadStatus = '正在下载 ${video.name}...';
        });
        
        final success = await _downloadService.downloadVideo(
          video.index,
          url: video.remoteUrl,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _downloadProgress = progress;
              });
            }
          },
        );
        
        if (success) {
          debugPrint('${video.name} 下载完成');
          // 如果当前播放的视频刚下载完成，重新初始化
          final int expectedVideoIndex;
          if (currentStageIndex == 0) {
            expectedVideoIndex = _portholeClosedVideoIndex;
          } else if (_isStageStandbyPlaying) {
            expectedVideoIndex = _stageIdleVideoIndex;
          } else {
            expectedVideoIndex = currentStageIndex;
          }
          if (expectedVideoIndex == video.index) {
            _initializeVideo(currentStageIndex);
          }
        } else {
          debugPrint('${video.name} 下载失败');
        }
      }
      
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
          _downloadStatus = null;
        });
      }
    } catch (e) {
      debugPrint('检查缺失视频失败: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
          _downloadStatus = null;
        });
      }
    }
  }

  void _initializeVideo(int stageIndex) async {
    // 先停止定时器
    _videoCheckTimer?.cancel();
    _videoCheckTimer = null;
    _hasAutoSwitched = false;
    
    // 先设置未初始化状态，避免使用旧的controller
    if (mounted) {
      setState(() {
        _isInitialized = false;
      });
    }
    
    // 等待一帧，确保UI更新
    await Future.delayed(const Duration(milliseconds: 50));
    
    // 现在安全地dispose旧的controller
    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      try {
        await oldController.dispose();
      } catch (e) {
        debugPrint('Dispose旧controller时出错: $e');
      }
    }
    
    if (!mounted) return;
    
    try {
      // 阶段索引 -> 实际播放的视频索引
      //  - 阶段 0（舷窗关闭）：0.mp4
      //  - 其他阶段：主视频 = stageIndex；待机 = 99.mp4
      final int videoIndex;
      if (stageIndex == 0) {
        videoIndex = _portholeClosedVideoIndex;
      } else if (_isStageStandbyPlaying) {
        videoIndex = _stageIdleVideoIndex;
      } else {
        videoIndex = stageIndex;
      }

      // 使用本地下载的视频
      final localPath = await _downloadService.getLocalVideoPath(videoIndex);
      final localFile = File(localPath);
      
      if (!await localFile.exists()) {
        debugPrint('视频文件不存在: $localPath，等待下载...');
        if (mounted) {
          setState(() {
            _isInitialized = false;
          });
        }
        // 如果视频不存在，触发下载检查
        _checkAndDownloadMissingVideos();
        return;
      }
      
      // 使用本地文件
      debugPrint('使用本地视频: $localPath');
      final newController = VideoPlayerController.file(localFile);
      _controller = newController;
      
      await newController.initialize();
      
      if (!mounted || _controller != newController) {
        // 如果widget已经被销毁或controller已经被替换，清理这个controller
        await newController.dispose();
        return;
      }
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      
      // 设置循环播放：
      //  - 舷窗关闭阶段（stageIndex == 0）：无限循环
      //  - 其他阶段：
      //      * 主阶段视频：不循环，播完后切到阶段内待机视频
      //      * 阶段内待机视频：循环播放，直到2分钟结束自动切下一阶段
      if (stageIndex == 0) {
        newController.setLooping(true);
      } else {
        if (_isStageStandbyPlaying) {
          newController.setLooping(true);
        } else {
          newController.setLooping(false);
        }
        // 非舷窗关闭阶段都需要检查停留时长/播放状态
        _startVideoCompletionCheck();
      }
      
      newController.play();
      
      // 视频初始化完成后，发送当前阶段给控制面板
      // 使用传入的 stageIndex 确保发送正确的阶段
      _sendCurrentStage(stageIndex);
    } catch (error) {
      debugPrint('视频初始化错误: $error');
      if (mounted) {
        setState(() {
          _isInitialized = false;
        });
      }
      // 清理出错的controller
      try {
        await _controller?.dispose();
        _controller = null;
      } catch (e) {
        debugPrint('清理出错controller时出错: $e');
      }
    }
  }

  void _startVideoCompletionCheck() {
    _videoCheckTimer?.cancel();
    // 记录阶段进入时间（仅非舷窗关闭阶段）
    _stageEnterTime ??= DateTime.now();

    _videoCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final controller = _controller;
      if (controller == null) {
        timer.cancel();
        return;
      }
      
      try {
        if (controller.value.isInitialized &&
            !_hasAutoSwitched) {
          final position = controller.value.position;
          final duration = controller.value.duration;
          const maxStay = Duration(minutes: 2);

          // 计算当前阶段累计停留时间（从进入阶段开始算）
          final elapsed = _stageEnterTime != null
              ? DateTime.now().difference(_stageEnterTime!)
              : Duration.zero;

          // 1）主阶段视频：播完后切换到阶段内待机视频（99.mp4，循环）
          if (!_isStageStandbyPlaying) {
            final isVideoFinished =
                position >= duration - const Duration(milliseconds: 200);
            if (isVideoFinished) {
              // 切换到阶段内待机视频，但保持当前阶段索引不变
              _isStageStandbyPlaying = true;
              // 重新初始化视频，播放阶段待机（99.mp4）
              _initializeVideo(currentStageIndex);
              return;
            }
          }

          // 2）无论当前是否在播放阶段内待机视频，只要累计停留时间 >= 2 分钟，
          //    就自动切换到下一个阶段（最后一个阶段则回到初始舷窗关闭）
          if (elapsed >= maxStay) {
            _hasAutoSwitched = true;
            timer.cancel();

            // 清理阶段状态
            _stageEnterTime = null;
            _isStageStandbyPlaying = false;

            if (currentStageIndex >= stages.length - 1) {
              // 最后一个阶段：返回初始舷窗关闭
              _resetToInitialStage();
            } else {
              // 其他阶段：进入下一个阶段
              _switchToNextStage();
            }
          }
        }
      } catch (e) {
        // Controller可能已经被dispose，取消定时器
        debugPrint('检查视频完成时出错: $e');
        timer.cancel();
      }
    });
  }

  void _switchToNextStage() {
    if (currentStageIndex < stages.length - 1) {
      setState(() {
        _hasAutoSwitched = false;
        _stageEnterTime = DateTime.now();
        _isStageStandbyPlaying = false;
        currentStageIndex++;
      });
      _initializeVideo(currentStageIndex);
      // 阶段变更后发送当前阶段给控制面板
      // 注意：这里会在 _initializeVideo 完成后再次发送，但为了确保发送，这里也发送一次
      // 实际上 _initializeVideo 中已经会发送，这里可以注释掉避免重复
      // _sendCurrentStage();
    }
  }

  void _resetToInitialStage() {
    setState(() {
      _hasAutoSwitched = false;
      _stageEnterTime = null;
      _isStageStandbyPlaying = false;
      currentStageIndex = 0;
    });
    _initializeVideo(0);
    // 阶段变更后发送当前阶段给控制面板
    // 注意：这里会在 _initializeVideo 完成后再次发送，但为了确保发送，这里也发送一次
    // 实际上 _initializeVideo 中已经会发送，这里可以注释掉避免重复
    // _sendCurrentStage();
  }

  /// 处理底部按钮点击（带5秒冷却）
  void _handleBottomStageButtonPressed() {
    final now = DateTime.now();
    if (_lastManualStageSwitchAt != null) {
      final elapsed = now.difference(_lastManualStageSwitchAt!);
      if (elapsed < _manualSwitchCooldown) {
        final remaining =
            (_manualSwitchCooldown - elapsed).inMilliseconds / 1000.0;
        final remainingSeconds = remaining.ceil();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('飞船充能中，请 $remainingSeconds s之后再试'),
            duration: const Duration(milliseconds: 1200),
          ),
        );
        return;
      }
    }

    _lastManualStageSwitchAt = now;
    if (currentStageIndex < stages.length - 1) {
      _switchToNextStage();
    } else {
      _resetToInitialStage();
    }
  }

  @override
  void dispose() {
    _videoCheckTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// 处理右下角点击
  void _handleBottomRightTap() {
    final now = DateTime.now();
    
    // 如果距离上次点击超过重置时间，重置计数
    if (_lastClickTime == null || 
        now.difference(_lastClickTime!) > _clickResetDuration) {
      _bottomRightClickCount = 0;
    }
    
    _lastClickTime = now;
    _bottomRightClickCount++;
    
    debugPrint('右下角点击次数: $_bottomRightClickCount');
    
    // 如果点击了3次，打开设置页面
    if (_bottomRightClickCount >= 3) {
      _bottomRightClickCount = 0;
      _lastClickTime = null;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const VideoSettingsPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 全屏视频
          if (_isInitialized && _controller != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
          
          // 左上角显示当前阶段（赛博朋克风格，弱化显示）
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 12),
                child: _CyberpunkStatusText(
                  text: stages[currentStageIndex],
                ),
              ),
            ),
          ),

          // 右上角“更新日志”入口（检测到新版本时显示）
          if (_latestUpdateInfo != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, top: 12),
                  child: GestureDetector(
                    onTap: () {
                      final info = _latestUpdateInfo;
                      if (info == null) return;
                      // 取描述中的前 8 行作为最新更新日志
                      final lines = info.description
                          .split('\n')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .take(8)
                          .toList();
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('更新日志  v${info.version}'),
                          content: SizedBox(
                            width: 320,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (info.buildDate.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        '发布日期：${info.buildDate}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  for (final line in lines)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• $line',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('关闭'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF00FFFF).withValues(alpha: 0.6),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        '更新日志',
                        style: TextStyle(
                          color: Color(0xFF00FFFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          
          // 底部按钮
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: currentStageIndex < stages.length - 1
                    ? _FuturisticButton(
                        text: stages[currentStageIndex + 1],
                        onPressed: _handleBottomStageButtonPressed,
                      )
                    : _FuturisticButton(
                        text: '返程维护',
                        onPressed: _handleBottomStageButtonPressed,
                      ),
              ),
            ),
          ),
          
          // 下载进度显示
          if (_isDownloading)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00FFFF).withValues(alpha: 0.6),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_downloadStatus != null) ...[
                          Text(
                            _downloadStatus!,
                            style: const TextStyle(
                              color: Color(0xFF00FFFF),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                        ],
                        LinearProgressIndicator(
                          value: _downloadProgress,
                          backgroundColor: Colors.grey.withValues(alpha: 0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00FFFF)),
                          minHeight: 4,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          
          // 右下角点击区域（透明，用于检测点击）
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: GestureDetector(
                onTap: _handleBottomRightTap,
                child: Container(
                  width: 100,
                  height: 100,
                  color: Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CyberpunkStatusText extends StatefulWidget {
  final String text;

  const _CyberpunkStatusText({
    required this.text,
  });

  @override
  State<_CyberpunkStatusText> createState() => _CyberpunkStatusTextState();
}

class _CyberpunkStatusTextState extends State<_CyberpunkStatusText>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glowIntensity = 0.3 + (_glowController.value * 0.2);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF00FFFF).withValues(alpha: 0.4 * glowIntensity),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00FFFF).withValues(alpha: 0.15 * glowIntensity),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 左侧装饰点
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF00FFFF).withValues(alpha: 0.6 * glowIntensity),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FFFF).withValues(alpha: 0.8 * glowIntensity),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 文字
              Text(
                widget.text,
                style: TextStyle(
                  color: const Color(0xFF00FFFF).withValues(alpha: 0.5),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                  fontFeatures: const [
                    FontFeature.tabularFigures(),
                  ],
                  shadows: [
                    Shadow(
                      color: const Color(0xFF00FFFF).withValues(alpha: 0.3 * glowIntensity),
                      blurRadius: 6,
                      offset: Offset.zero,
                    ),
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FuturisticButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;

  const _FuturisticButton({
    required this.text,
    required this.onPressed,
  });

  @override
  State<_FuturisticButton> createState() => _FuturisticButtonState();
}

class _FuturisticButtonState extends State<_FuturisticButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final glowIntensity = 0.7 + (_glowController.value * 0.3);
          return Transform.scale(
            scale: _isPressed ? 0.95 : 1.0,
            child: IntrinsicWidth(
              child: IntrinsicHeight(
                child: Container(
                  // 外层黑色金属边框
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF2a2a2a),
                        const Color(0xFF0a0a0a),
                        const Color(0xFF2a2a2a),
                      ],
                    ),
                    boxShadow: [
                      // 外层3D阴影
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.8),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3), // 外层金属边框厚度
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      // 深色金属背景（包含高光效果）
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF1a1a1a).withValues(alpha: 0.8),
                          const Color(0xFF0d0d0d),
                          const Color(0xFF1a1a1a).withValues(alpha: 0.8),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      // 内发光效果
                      boxShadow: [
                        // 内发光
                        BoxShadow(
                          color: const Color(0xFF00FFFF).withValues(alpha: 0.5 * glowIntensity),
                          blurRadius: 15,
                          spreadRadius: -5,
                        ),
                        // 青色发光外圈
                        BoxShadow(
                          color: const Color(0xFF00FFFF).withValues(alpha: 0.6 * glowIntensity),
                          blurRadius: 20 * glowIntensity,
                          spreadRadius: 2 * glowIntensity,
                        ),
                        BoxShadow(
                          color: const Color(0xFF00FFFF).withValues(alpha: 0.4 * glowIntensity),
                          blurRadius: 30 * glowIntensity,
                          spreadRadius: 0,
                        ),
                        // 3D高光效果
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(-2, -2),
                        ),
                        // 3D阴影效果
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 12,
                          offset: const Offset(2, 4),
                        ),
                      ],
                      // 加粗的青色边框
                      border: Border.all(
                        color: const Color(0xFF00FFFF).withValues(alpha: 0.95 * glowIntensity),
                        width: 4,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 内发光层：模糊的青色文字作为发光源
                        ClipRect(
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: 6 * glowIntensity,
                              sigmaY: 6 * glowIntensity,
                            ),
                            child: Text(
                              widget.text,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF00FFFF).withValues(alpha: 0.8 * glowIntensity),
                                letterSpacing: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        // 文字层：使用较暗的颜色和向内的阴影来模拟嵌入效果
                        Text(
                          widget.text,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF00FFFF).withValues(alpha: 0.6 + 0.4 * glowIntensity),
                            shadows: [
                              // 内阴影效果：使用深色阴影向下偏移，模拟凹陷
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.9),
                                blurRadius: 3,
                                offset: const Offset(0, 2),
                              ),
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.7),
                                blurRadius: 5,
                                offset: const Offset(0, 1),
                              ),
                              // 内发光：使用青色阴影向上偏移，模拟内发光
                              Shadow(
                                color: const Color(0xFF00FFFF).withValues(alpha: 0.5 * glowIntensity),
                                blurRadius: 4,
                                offset: const Offset(0, -1),
                              ),
                              Shadow(
                                color: const Color(0xFF00FFFF).withValues(alpha: 0.3 * glowIntensity),
                                blurRadius: 6,
                                offset: const Offset(0, -2),
                              ),
                            ],
                            letterSpacing: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
