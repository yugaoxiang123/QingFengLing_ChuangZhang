import 'package:flutter/material.dart';
import 'dart:async';
import 'video_info.dart';
import 'video_download_service.dart';
import '../../models/user_config.dart';
import '../../services/user_config_service.dart';
import '../../services/controller_client_service.dart';
import '../../config/app_config.dart';

/// 视频设置页面（Tab页形式）
class VideoSettingsPage extends StatefulWidget {
  const VideoSettingsPage({super.key});

  @override
  State<VideoSettingsPage> createState() => _VideoSettingsPageState();
}

class _VideoSettingsPageState extends State<VideoSettingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final VideoDownloadService _downloadService = VideoDownloadService();
  List<VideoInfo> _videoList = [];
  bool _isLoading = true;
  final Map<int, double> _downloadProgress = {}; // 下载进度
  final Map<int, bool> _isDownloading = {}; // 是否正在下载

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadVideoList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 加载视频列表
  Future<void> _loadVideoList() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final videoList = await _downloadService.getVideoInfoList();
      setState(() {
        _videoList = videoList;
        _isLoading = false;
      });
    } catch (e) {
      print('加载视频列表失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 更新单个视频
  Future<void> _updateVideo(int index) async {
    if (_isDownloading[index] == true) return;

    setState(() {
      _isDownloading[index] = true;
      _downloadProgress[index] = 0.0;
    });

    try {
      // 重新从OSS获取最新的data.json，确保使用最新的URL
      final latestVideoList = await _downloadService.getVideoInfoList();
      final videoInfo = latestVideoList.firstWhere(
        (v) => v.index == index,
        orElse: () => VideoInfo(
          index: index,
          name: '$index.mp4',
          localPath: '',
          isDownloaded: false,
        ),
      );
      
      if (videoInfo.remoteUrl == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('无法获取视频下载地址，请检查网络连接'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      final success = await _downloadService.downloadVideo(
        index,
        url: videoInfo.remoteUrl,
        onProgress: (progress) {
          setState(() {
            _downloadProgress[index] = progress;
          });
        },
      );

      // 从URL中提取文件名
      String fileName = '${index}.mp4';
      if (videoInfo.remoteUrl != null) {
        final uri = Uri.tryParse(videoInfo.remoteUrl!);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          fileName = uri.pathSegments.last;
        }
      } else if (videoInfo.localPath.isNotEmpty) {
        final path = videoInfo.localPath.split('/');
        if (path.isNotEmpty) {
          fileName = path.last;
        }
      }
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${videoInfo.name} ($fileName) 更新成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadVideoList(); // 重新加载列表
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${videoInfo.name} ($fileName) 更新失败'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('更新视频失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isDownloading[index] = false;
        _downloadProgress.remove(index);
      });
    }
  }

  /// 更新所有视频
  Future<void> _updateAllVideos() async {
    // 检查是否有正在下载的视频
    if (_isDownloading.values.any((v) => v == true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请等待当前下载完成'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认更新'),
        content: const Text('将更新所有视频，这可能会消耗较多流量，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 重新从OSS获取最新的data.json，确保使用最新的URL
    final latestVideoList = await _downloadService.getVideoInfoList();
    
    // 初始化所有视频的下载状态
    setState(() {
      for (final video in latestVideoList) {
        _isDownloading[video.index] = true;
        _downloadProgress[video.index] = 0.0;
      }
    });

    try {
      // downloadAllVideos内部会调用getVideoInfoList，但我们已经提前获取了
      // 为了确保使用最新的data.json，这里直接使用downloadAllVideos
      final results = await _downloadService.downloadAllVideos(
        onProgress: (index, progress) {
          setState(() {
            _downloadProgress[index] = progress;
          });
        },
      );

      int successCount = 0;
      int failCount = 0;
      for (final entry in results.entries) {
        if (entry.value) {
          successCount++;
        } else {
          failCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新完成：成功 $successCount 个，失败 $failCount 个'),
            backgroundColor: failCount == 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      await _loadVideoList(); // 重新加载列表
    } catch (e) {
      print('批量更新视频失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('批量更新失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        for (final video in _videoList) {
          _isDownloading[video.index] = false;
          _downloadProgress.remove(video.index);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          color: Colors.black,
          child: SafeArea(
            child: Row(
              children: [
                // 关闭按钮
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF00FFFF)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                // Tab切换
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: '视频设置', icon: Icon(Icons.video_library)),
                      Tab(text: '控制面板', icon: Icon(Icons.settings_ethernet)),
                    ],
                    labelColor: const Color(0xFF00FFFF),
                    unselectedLabelColor: Colors.grey[400],
                    indicatorColor: const Color(0xFF00FFFF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: 视频设置
          _buildVideoSettingsTab(),
          // Tab 2: 控制面板设置
          _buildControllerSettingsTab(),
        ],
      ),
    );
  }

  /// 构建视频设置Tab
  Widget _buildVideoSettingsTab() {
    return _isLoading
        ? const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF00FFFF),
            ),
          )
        : Column(
            children: [
              // OSS文件夹位置
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00FFFF).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OSS文件夹位置',
                      style: TextStyle(
                        color: Color(0xFF00FFFF),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'https://shv-medias.oss-cn-zhangjiakou.aliyuncs.com/QFL/chuanzhang/',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // 视频列表
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _videoList.length,
                  itemBuilder: (context, index) {
                    final video = _videoList[index];
                    final isDownloading = _isDownloading[video.index] == true;
                    final progress = _downloadProgress[video.index] ?? 0.0;

                    return _VideoCard(
                      video: video,
                      isDownloading: isDownloading,
                      progress: progress,
                      onUpdate: () => _updateVideo(video.index),
                    );
                  },
                ),
              ),

              // 全部更新按钮
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _updateAllVideos,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFFF).withValues(alpha: 0.2),
                    foregroundColor: const Color(0xFF00FFFF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(
                        color: Color(0xFF00FFFF),
                        width: 2,
                      ),
                    ),
                  ),
                  child: const Text(
                    '全部更新',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );
  }

  /// 构建控制面板设置Tab
  Widget _buildControllerSettingsTab() {
    return _ControllerSettingsTab();
  }
}

/// 视频卡片组件
class _VideoCard extends StatelessWidget {
  final VideoInfo video;
  final bool isDownloading;
  final double progress;
  final VoidCallback onUpdate;

  const _VideoCard({
    required this.video,
    required this.isDownloading,
    required this.progress,
    required this.onUpdate,
  });

  /// 从URL或路径中提取文件名
  String _getFileName() {
    // 优先从remoteUrl中提取
    if (video.remoteUrl != null) {
      final uri = Uri.tryParse(video.remoteUrl!);
      if (uri != null) {
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          return pathSegments.last;
        }
      }
    }
    // 如果remoteUrl不存在，从localPath中提取
    if (video.localPath.isNotEmpty) {
      final path = video.localPath.split('/');
      if (path.isNotEmpty) {
        return path.last;
      }
    }
    // 如果都提取不到，使用默认格式
    return '${video.index}.mp4';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF00FFFF).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 视频名称和文件名
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.name,
                      style: const TextStyle(
                        color: Color(0xFF00FFFF),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getFileName(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (video.isDownloaded)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.green,
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    '已下载',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.orange,
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    '未下载',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 文件大小和更新时间
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Text(
                '大小: ${video.formattedSize}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.access_time,
                size: 16,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Text(
                '更新: ${video.formattedUpdateTime}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),

          // 下载进度条
          if (isDownloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00FFFF)),
            ),
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 12),

          // 更新按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isDownloading ? null : onUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFFF).withValues(alpha: 0.2),
                foregroundColor: const Color(0xFF00FFFF),
                disabledBackgroundColor: Colors.grey.withValues(alpha: 0.2),
                disabledForegroundColor: Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color: isDownloading
                        ? Colors.grey
                        : const Color(0xFF00FFFF),
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                isDownloading ? '下载中...' : '更新',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 控制面板设置Tab
class _ControllerSettingsTab extends StatefulWidget {
  @override
  State<_ControllerSettingsTab> createState() => _ControllerSettingsTabState();
}

class _ControllerSettingsTabState extends State<_ControllerSettingsTab> {
  final _userConfigService = UserConfigService();
  final _controllerClient = ControllerClientService();
  
  bool _isSaving = false;
  final TextEditingController _serverIpController = TextEditingController();
  bool _autoConnect = AppConfig.defaultAutoConnect;
  
  // 连接状态订阅
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  StreamSubscription<List<ConnectionLog>>? _logsSubscription;
  StreamSubscription<String?>? _errorSubscription;
  
  // 连接状态
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  List<ConnectionLog> _logs = [];
  String? _currentError;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    
    // 初始化连接状态
    _connectionStatus = _controllerClient.status;
    _logs = _controllerClient.logs;
    _currentError = _controllerClient.currentError;
    
    // 订阅连接状态变化
    _statusSubscription = _controllerClient.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _connectionStatus = status;
        });
      }
    });
    
    _logsSubscription = _controllerClient.logsStream.listen((logs) {
      if (mounted) {
        setState(() {
          _logs = logs;
        });
      }
    });
    
    _errorSubscription = _controllerClient.errorStream.listen((error) {
      if (mounted) {
        setState(() {
          _currentError = error;
        });
      }
    });
  }

  /// 加载配置
  Future<void> _loadConfig() async {
    try {
      final config = await _userConfigService.loadConfig();
      if (config != null && mounted) {
        setState(() {
          _serverIpController.text = config.serverIp;
          _autoConnect = config.autoConnect;
        });
      }
    } catch (e) {
      debugPrint('加载配置失败: $e');
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _logsSubscription?.cancel();
    _errorSubscription?.cancel();
    _serverIpController.dispose();
    super.dispose();
  }
  
  /// 连接到服务器
  Future<void> _connectToServer(String serverIp) async {
    try {
      await _controllerClient.connect(serverIp);
    } catch (e) {
      debugPrint('连接服务器失败: $e');
    }
  }
  
  /// 断开连接
  Future<void> _disconnect() async {
    await _controllerClient.disconnect();
  }
  
  /// 清空日志
  void _clearLogs() {
    _controllerClient.clearLogs();
  }
  
  /// 获取连接状态文本
  String _getStatusText(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.disconnected:
        return '未连接';
      case ConnectionStatus.connecting:
        return '连接中...';
      case ConnectionStatus.connected:
        return '已连接';
      case ConnectionStatus.error:
        return '连接错误';
    }
  }
  
  /// 获取连接状态颜色
  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.disconnected:
        return Colors.grey;
      case ConnectionStatus.connecting:
        return Colors.orange;
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.error:
        return Colors.red;
    }
  }

  /// 保存服务器IP配置
  Future<void> _saveServerIp() async {
    if (_isSaving) return;
    
    final serverIp = _serverIpController.text.trim();
    
    // 简单的IP地址验证
    if (serverIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入服务器IP地址'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() {
      _isSaving = true;
    });

    try {
      final config = UserConfig(
        serverIp: serverIp,
        autoConnect: _autoConnect,
      );
      
      final success = await _userConfigService.saveConfig(config);
      
      if (success) {
        if (mounted) {
          // 显示成功提示
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('服务器IP已保存: $serverIp'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          
          // 根据自动连接设置决定是否连接
          if (_autoConnect) {
            await _connectToServer(serverIp);
          }
          
          setState(() {
            _isSaving = false;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('保存失败，请重试'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isSaving = false;
          });
        }
      }
    } catch (e) {
      debugPrint('保存服务器IP异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '控制面板服务器设置',
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF00FFFF),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '设置控制面板主服务器的IP地址',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _serverIpController,
            enabled: !_isSaving,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              labelText: '服务器IP地址',
              hintText: AppConfig.defaultServerIp.isEmpty ? '192.168.1.100' : AppConfig.defaultServerIp,
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Colors.black,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: const Color(0xFF00FFFF).withValues(alpha: 0.5),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: const Color(0xFF00FFFF).withValues(alpha: 0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF00FFFF), width: 2),
              ),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          const Text(
            '端口信息：',
            style: TextStyle(fontSize: 14, color: Color(0xFF00FFFF)),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _serverIpController,
            builder: (context, value, child) {
              final serverIp = value.text.trim().isEmpty
                  ? (AppConfig.defaultServerIp.isEmpty ? '192.168.1.100' : AppConfig.defaultServerIp)
                  : value.text.trim();
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00FFFF).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.settings_input_svideo, color: Color(0xFF00FFFF), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Socket: ',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      '$serverIp:8888',
                      style: const TextStyle(color: Color(0xFF00FFFF), fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          // 自动连接开关
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF00FFFF).withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.power_settings_new, color: Color(0xFF00FFFF), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '自动连接服务器',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
                Switch(
                  value: _autoConnect,
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          setState(() {
                            _autoConnect = value;
                          });
                        },
                  activeColor: const Color(0xFF00FFFF),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _autoConnect
                ? '保存IP地址后将自动连接到服务器'
                : '保存IP地址后不会自动连接，需要手动点击"保存并连接"',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          // 连接状态显示
          const Text(
            '连接状态：',
            style: TextStyle(fontSize: 16, color: Color(0xFF00FFFF), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF00FFFF).withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_input_svideo, color: Color(0xFF00FFFF), size: 20),
                const SizedBox(width: 8),
                const Text(
                  '连接状态: ',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(_connectionStatus).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _getStatusColor(_connectionStatus),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _getStatusColor(_connectionStatus),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getStatusText(_connectionStatus),
                        style: TextStyle(
                          color: _getStatusColor(_connectionStatus),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 错误信息显示
          if (_currentError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          // 操作按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveServerIp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFFF).withValues(alpha: 0.2),
                    foregroundColor: const Color(0xFF00FFFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFF00FFFF), width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FFFF)),
                          ),
                        )
                      : const Text(
                          '保存并连接',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSaving ? null : _disconnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                child: const Text(
                  '断开',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 连接日志
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '连接日志：',
                style: TextStyle(fontSize: 16, color: Color(0xFF00FFFF), fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: _clearLogs,
                child: const Text(
                  '清空日志',
                  style: TextStyle(fontSize: 12, color: Color(0xFF00FFFF)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF00FFFF).withValues(alpha: 0.5), width: 1),
            ),
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          log.toString(),
                          style: TextStyle(
                            color: log.error != null
                                ? Colors.red
                                : log.isIncoming
                                    ? Colors.green
                                    : const Color(0xFF00FFFF),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
