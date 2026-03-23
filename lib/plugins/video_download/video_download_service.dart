import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_info.dart';

/// 视频下载服务
class VideoDownloadService {
  static final VideoDownloadService _instance = VideoDownloadService._internal();
  factory VideoDownloadService() => _instance;
  VideoDownloadService._internal() {
    _configureDio();
  }

  final Dio _dio = Dio();
  static const String _ossBaseUrl = 'https://shv-medias.oss-cn-zhangjiakou.aliyuncs.com/QFL/chuanzhang/';
  static const String _dataJsonUrl = 'https://shv-medias.oss-cn-zhangjiakou.aliyuncs.com/QFL/chuanzhang/data.json';
  static const String _videoCount = '8'; // 视频数量（默认值，实际从data.json读取）
  static const String _prefsKey = 'video_info_list';
  static const String _prefsDataJsonKey = 'video_data_json'; // 缓存data.json内容

  /// 配置Dio网络客户端
  void _configureDio() {
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 600), // 10分钟超时
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': 'QFL-Publicity-App/1.0',
      },
    );
  }

  /// 从OSS获取data.json配置
  Future<Map<String, dynamic>?> fetchDataJson() async {
    try {
      print('开始从OSS获取data.json: $_dataJsonUrl');
      final response = await _dio.get(
        _dataJsonUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          print('成功获取data.json');
          // 缓存到SharedPreferences
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_prefsDataJsonKey, jsonEncode(data));
          } catch (e) {
            print('缓存data.json失败: $e');
          }
          return data;
        }
      }
    } catch (e) {
      print('从OSS获取data.json失败: $e');
      // 如果网络获取失败，尝试从缓存读取
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedJson = prefs.getString(_prefsDataJsonKey);
        if (cachedJson != null) {
          print('使用缓存的data.json');
          return jsonDecode(cachedJson) as Map<String, dynamic>;
        }
      } catch (e) {
        print('读取缓存的data.json失败: $e');
      }
    }
    return null;
  }

  /// 获取视频下载URL（从data.json或使用默认URL）
  Future<String?> getVideoUrl(int index) async {
    final dataJson = await fetchDataJson();
    if (dataJson != null && dataJson['videos'] != null) {
      final videos = dataJson['videos'] as List;
      final video = videos.firstWhere(
        (v) => (v as Map<String, dynamic>)['index'] == index,
        orElse: () => null,
      );
      if (video != null) {
        return (video as Map<String, dynamic>)['url'] as String?;
      }
    }
    // 如果无法从data.json获取，使用默认URL
    return '$_ossBaseUrl$index.mp4';
  }

  /// 获取本地视频目录
  Future<Directory> getVideoDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${dir.path}/videos');
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }
    return videoDir;
  }

  /// 获取本地视频文件路径
  Future<String> getLocalVideoPath(int index) async {
    final videoDir = await getVideoDirectory();
    return '${videoDir.path}/$index.mp4';
  }

  /// 获取临时文件路径
  Future<String> getTempVideoPath(int index) async {
    final videoDir = await getVideoDirectory();
    return '${videoDir.path}/$index.mp4.temp';
  }

  /// 清理所有临时文件
  Future<void> cleanupTempFiles() async {
    try {
      final videoDir = await getVideoDirectory();
      final files = videoDir.listSync();
      for (final file in files) {
        if (file is File && file.path.endsWith('.temp')) {
          try {
            await file.delete();
            print('清理临时文件: ${file.path}');
          } catch (e) {
            print('清理临时文件失败: ${file.path}, 错误: $e');
          }
        }
      }
    } catch (e) {
      print('清理临时文件时出错: $e');
    }
  }

  /// 检查视频是否已下载
  Future<bool> isVideoDownloaded(int index) async {
    final path = await getLocalVideoPath(index);
    final file = File(path);
    return await file.exists();
  }

  /// 获取视频信息列表（从data.json读取）
  Future<List<VideoInfo>> getVideoInfoList() async {
    final List<VideoInfo> videoList = [];
    
    // 先从OSS获取data.json
    final dataJson = await fetchDataJson();
    List<Map<String, dynamic>>? videoConfigs;
    
    if (dataJson != null && dataJson['videos'] != null) {
      videoConfigs = (dataJson['videos'] as List)
          .cast<Map<String, dynamic>>();
      print('从data.json读取到 ${videoConfigs.length} 个视频配置');
    } else {
      // 如果无法获取data.json，使用默认配置（1-8）
      print('无法获取data.json，使用默认配置');
      videoConfigs = [];
      for (int i = 1; i <= int.parse(_videoCount); i++) {
        videoConfigs.add({
          'index': i,
          'name': '$i.mp4',
          'url': '$_ossBaseUrl$i.mp4',
        });
      }
    }
    
    for (final config in videoConfigs) {
      final index = config['index'] as int;
      final name = config['name'] as String? ?? '$index.mp4';
      final remoteUrl = config['url'] as String?;
      
      final localPath = await getLocalVideoPath(index);
      final isDownloaded = await isVideoDownloaded(index);
      
      VideoInfo videoInfo = VideoInfo(
        index: index,
        name: name,
        localPath: localPath,
        isDownloaded: isDownloaded,
        remoteUrl: remoteUrl,
      );

      // 如果已下载，获取文件信息
      if (isDownloaded) {
        try {
          final file = File(localPath);
          if (await file.exists()) {
            final stat = await file.stat();
            videoInfo = videoInfo.copyWith(
              size: stat.size,
              updateTime: stat.modified,
            );
          }
        } catch (e) {
          print('获取视频文件信息失败: $e');
        }
      }

      // 尝试从SharedPreferences加载保存的信息
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedJson = prefs.getString('${_prefsKey}_$index');
        if (savedJson != null) {
          try {
            final savedMap = jsonDecode(savedJson) as Map<String, dynamic>;
            final savedInfo = VideoInfo.fromJson(savedMap);
            // 如果本地文件存在，使用实际文件信息；否则使用保存的信息
            // 注意：remoteUrl优先使用从data.json获取的最新值
            if (isDownloaded) {
              final file = File(localPath);
              if (await file.exists()) {
                final stat = await file.stat();
                videoInfo = videoInfo.copyWith(
                  size: stat.size,
                  updateTime: stat.modified,
                  // 优先使用从data.json获取的remoteUrl，如果不存在则使用保存的
                  remoteUrl: remoteUrl ?? savedInfo.remoteUrl,
                );
              }
            } else {
              videoInfo = savedInfo.copyWith(
                // 优先使用从data.json获取的remoteUrl，如果不存在则使用保存的
                remoteUrl: remoteUrl ?? savedInfo.remoteUrl,
                name: name,
              );
            }
          } catch (e) {
            print('解析保存的视频信息失败: $e');
          }
        }
      } catch (e) {
        print('加载保存的视频信息失败: $e');
      }
      
      // 确保remoteUrl被保存（从data.json获取的最新值）
      if (remoteUrl != null) {
        videoInfo = videoInfo.copyWith(remoteUrl: remoteUrl);
      }

      videoList.add(videoInfo);
    }
    
    // 保存更新后的视频信息列表（包含最新的remoteUrl）
    await saveVideoInfoList(videoList);

    return videoList;
  }

  /// 保存视频信息列表
  Future<void> saveVideoInfoList(List<VideoInfo> videoList) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final info in videoList) {
        final jsonStr = jsonEncode(info.toJson());
        await prefs.setString('${_prefsKey}_${info.index}', jsonStr);
      }
    } catch (e) {
      print('保存视频信息失败: $e');
    }
  }

  /// 检查OSS上的视频信息（通过HEAD请求获取大小和更新时间）
  Future<Map<String, dynamic>?> checkVideoInfoOnOss(int index) async {
    try {
      final url = await getVideoUrl(index);
      if (url == null) return null;
      final response = await _dio.head(url);
      
      if (response.statusCode == 200) {
        final headers = response.headers;
        final contentLength = headers.value('content-length');
        final lastModified = headers.value('last-modified');
        
        return {
          'size': contentLength != null ? int.tryParse(contentLength) : null,
          'lastModified': lastModified,
        };
      }
    } catch (e) {
      print('检查OSS视频信息失败: $e');
    }
    return null;
  }

  /// 下载单个视频
  Future<bool> downloadVideo(
    int index, {
    Function(double)? onProgress,
    String? url, // 可选，如果提供则使用此URL，否则从data.json获取
  }) async {
    final tempPath = await getTempVideoPath(index);
    final finalPath = await getLocalVideoPath(index);
    File? tempFile;
    
    try {
      // 如果未提供URL，从data.json获取或使用默认URL
      final downloadUrl = url ?? await getVideoUrl(index);
      if (downloadUrl == null) {
        print('❌ 无法获取视频下载地址');
        return false;
      }
      
      // 获取视频名称
      final videoList = await getVideoInfoList();
      final videoInfo = videoList.firstWhere(
        (v) => v.index == index,
        orElse: () => VideoInfo(
          index: index,
          name: '$index.mp4',
          localPath: finalPath,
          isDownloaded: false,
        ),
      );
      
      print('开始下载视频: ${videoInfo.name}');
      print('下载地址: $downloadUrl');
      print('临时文件路径: $tempPath');
      print('最终文件路径: $finalPath');

      // 清理可能存在的临时文件
      tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
        print('清理旧的临时文件');
      }

      // 先尝试获取服务器上的文件大小（用于验证）
      int? expectedSize;
      try {
        final headResponse = await _dio.head(downloadUrl);
        final contentLength = headResponse.headers.value('content-length');
        if (contentLength != null) {
          expectedSize = int.tryParse(contentLength);
          print('服务器文件大小: $expectedSize 字节');
        }
      } catch (e) {
        print('获取服务器文件大小失败: $e（继续下载）');
      }

      // 下载到临时文件
      await _dio.download(
        downloadUrl,
        tempPath,
        options: Options(
          receiveTimeout: const Duration(seconds: 600), // 10分钟超时
          headers: {
            'Accept': '*/*',
            'Connection': 'keep-alive',
          },
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            final percentString = (progress * 100).toStringAsFixed(1);
            print('下载进度: $percentString% ($received/$total bytes)');
            onProgress?.call(progress);
          }
        },
      );

      // 验证临时文件
      tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        print('❌ 临时文件下载后不存在');
        return false;
      }

      final actualSize = await tempFile.length();
      print('下载文件大小: $actualSize 字节');

      // 如果知道期望大小，验证文件大小
      if (expectedSize != null && actualSize != expectedSize) {
        print('❌ 文件大小不匹配: 期望 $expectedSize 字节，实际 $actualSize 字节');
        await tempFile.delete();
        return false;
      }

      // 如果文件大小为0，认为下载失败
      if (actualSize == 0) {
        print('❌ 下载的文件大小为0，下载失败');
        await tempFile.delete();
        return false;
      }

      // 删除旧文件（如果存在）
      final oldFinalFile = File(finalPath);
      if (await oldFinalFile.exists()) {
        await oldFinalFile.delete();
        print('删除旧文件');
      }

      // 将临时文件重命名为最终文件
      await tempFile.rename(finalPath);
      print('✅ 临时文件已重命名为最终文件');

      // 验证最终文件
      final finalFile = File(finalPath);
      if (!await finalFile.exists()) {
        print('❌ 重命名后文件不存在');
        return false;
      }

      final finalSize = await finalFile.length();
      final stat = await finalFile.stat();
      print('✅ 视频文件下载完成，大小: $finalSize字节');

      // 更新视频信息（重用之前获取的videoList）
      final videoIndex = videoList.indexWhere((v) => v.index == index);
      if (videoIndex >= 0) {
        videoList[videoIndex] = videoList[videoIndex].copyWith(
          size: finalSize,
          updateTime: stat.modified,
          isDownloaded: true,
        );
        await saveVideoInfoList(videoList);
      }

      return true;
    } catch (e) {
      print('❌ 下载视频失败: $e');
      if (e is DioException) {
        print('   错误类型: ${e.type}');
        print('   错误消息: ${e.message}');
        if (e.response != null) {
          print('   响应状态: ${e.response?.statusCode}');
        }
      }
      
      // 清理临时文件
      try {
        tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
          print('已清理失败的临时文件');
        }
      } catch (cleanupError) {
        print('清理临时文件时出错: $cleanupError');
      }
      
      return false;
    }
  }

  /// 批量下载视频
  Future<Map<int, bool>> downloadAllVideos({
    Function(int index, double progress)? onProgress,
  }) async {
    final results = <int, bool>{};
    
    // 从data.json获取视频列表
    final videoList = await getVideoInfoList();
    
    for (final video in videoList) {
      final success = await downloadVideo(
        video.index,
        url: video.remoteUrl,
        onProgress: (progress) {
          onProgress?.call(video.index, progress);
        },
      );
      results[video.index] = success;
    }
    
    return results;
  }

  /// 检查并下载缺失的视频（应用启动时调用）
  /// 从OSS的data.json读取视频列表，检查本地是否存在，不存在则下载
  Future<void> checkAndDownloadMissingVideos() async {
    print('开始检查缺失的视频...');
    
    // 先清理所有临时文件
    await cleanupTempFiles();
    
    // 从OSS获取data.json并获取视频列表
    final videoList = await getVideoInfoList();
    print('从data.json获取到 ${videoList.length} 个视频配置');
    
    for (final video in videoList) {
      // 检查文件是否真的存在且有效
      final localPath = await getLocalVideoPath(video.index);
      final file = File(localPath);
      final exists = await file.exists();
      
      // 如果文件不存在，或者文件大小为0，认为需要下载
      bool needsDownload = !exists;
      if (exists) {
        try {
          final fileSize = await file.length();
          if (fileSize == 0) {
            print('发现损坏的视频文件（大小为0）: ${video.name}');
            await file.delete();
            needsDownload = true;
          }
        } catch (e) {
          print('检查视频文件时出错: ${video.name}, 错误: $e');
          needsDownload = true;
        }
      }
      
      if (needsDownload) {
        print('发现缺失的视频: ${video.name}，开始下载...');
        if (video.remoteUrl != null) {
          print('使用data.json中的URL: ${video.remoteUrl}');
        }
        await downloadVideo(
          video.index,
          url: video.remoteUrl,
        );
      }
    }
    
    // 再次清理临时文件（防止有残留）
    await cleanupTempFiles();
    
    print('视频检查完成');
  }
}
