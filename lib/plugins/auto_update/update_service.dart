import 'dart:io';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'update_info.dart';
import 'app_install_helper.dart';

/// 更新服务
/// 
/// 核心更新逻辑的实现类。负责：
/// 1. **检查更新**：向服务器请求最新的版本信息（YAML格式）。
/// 2. **版本比较**：对比本地版本和服务器版本。
/// 3. **文件下载**：支持大文件下载、断点续传（通过Dio）。
/// 4. **完整性校验**：下载完成后校验MD5和SHA256，防止文件损坏或被篡改。
/// 5. **安装流程**：调用`AppInstallHelper`执行安装。
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal() {
    _configureDio();
  }

  final Dio _dio = Dio();
  bool _isChecking = false;
  bool _isDownloading = false;

  /// 配置Dio网络客户端
  void _configureDio() {
    _dio.options = BaseOptions(
      connectTimeout: Duration(seconds: 30),  // 连接超时30秒
      receiveTimeout: Duration(seconds: 600), // 接收超时10分钟 (大文件下载)
      sendTimeout: Duration(seconds: 30),     // 发送超时30秒
      headers: {
        'User-Agent': 'QFL-Publicity-App/1.0',
      },
    );

    // 添加请求和响应拦截器用于调试
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('🌐 HTTP请求: ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        print('✅ HTTP响应: ${response.statusCode} ${response.requestOptions.uri}');
        handler.next(response);
      },
      onError: (error, handler) {
        print('❌ HTTP错误: ${error.message}');
        print('   请求地址: ${error.requestOptions.uri}');
        if (error.response != null) {
          print('   响应状态: ${error.response?.statusCode}');
        }
        handler.next(error);
      },
    ));
  }

  /// 比较版本号，如果newVersion大于currentVersion则返回true
  bool _isNewerVersion(String newVersion, String currentVersion) {
    List<int> newVersionParts = newVersion.split('.').map((part) => int.parse(part)).toList();
    List<int> currentVersionParts = currentVersion.split('.').map((part) => int.parse(part)).toList();

    // 确保两个列表长度相同
    while (newVersionParts.length < currentVersionParts.length) {
      newVersionParts.add(0);
    }
    while (currentVersionParts.length < newVersionParts.length) {
      currentVersionParts.add(0);
    }

    // 逐个比较版本号的各部分
    for (int i = 0; i < newVersionParts.length; i++) {
      if (newVersionParts[i] > currentVersionParts[i]) {
        return true;
      } else if (newVersionParts[i] < currentVersionParts[i]) {
        return false;
      }
    }

    // 所有部分都相等，表示版本相同
    return false;
  }

  /// 检查更新
  /// 
  /// 向服务器发送请求，获取最新的版本信息。
  /// 支持通过[serverUrl]和[updatePath]自定义更新源。
  /// 
  /// 返回[UpdateInfo]对象如果发现新版本，否则返回null。
  Future<UpdateInfo?> checkUpdate({
    String? serverUrl,
    String? updatePath,
    bool showToast = true,
    bool forceCheck = false,
  }) async {
    if (_isChecking) return null;
    _isChecking = true;

    try {
      // 获取当前应用信息
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final buildNumber = int.parse(packageInfo.buildNumber);

      print('当前版本: $currentVersion (${packageInfo.buildNumber})');

      // 检查是否需要检查更新（避免频繁检查）
      if (!forceCheck && !await _shouldCheckUpdate() && !showToast) {
        _isChecking = false;
        print('短时间（${UpdateConfig.checkIntervalSeconds}秒）内重复检测无需检查更新');
        return null;
      }

      // 构建请求URL
      final url = '${serverUrl ?? UpdateConfig.defaultServerUrl}${updatePath ?? UpdateConfig.defaultUpdatePath}';
      print('检查更新URL: $url');

      // 请求服务器检查更新
      final response = await _dio.get(
        url,
        queryParameters: {
          'version': currentVersion,
          'versionCode': buildNumber,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        },
      );

      // 保存最后检查时间
      await _saveLastCheckTime();

      if (response.statusCode == 200 && response.data != null) {
        // 解析YAML响应
        final yamlContent = response.data.toString();
        final updateInfo = _parseYamlResponse(yamlContent, currentVersion, buildNumber);
        
        if (updateInfo != null) {
          // 检查版本号是否大于当前版本
          if (_isNewerVersion(updateInfo.version, currentVersion)) {
            _isChecking = false;
            return updateInfo;
          }
        }
      }

      if (showToast) {
        print('当前已是最新版本');
      }

      _isChecking = false;
      return null;
    } catch (e) {
      print('检查更新失败: $e');
      _isChecking = false;
      return null;
    }
  }

  /// 解析YAML响应
  UpdateInfo? _parseYamlResponse(String yamlContent, String currentVersion, int currentVersionCode) {
    try {
      // 简单的YAML解析（这里简化处理，实际项目中可以使用yaml包）
      final lines = yamlContent.split('\n');
      Map<String, dynamic> updateData = {};
      Map<String, dynamic> fileInfo = {};
      
      String currentSection = '';
      bool inFileInfo = false;
      
      for (String line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        
        // 检测主要section
        if (line == 'latest_version:') {
          currentSection = 'latest_version';
          inFileInfo = false;
          continue;
        }
        
        if (line == 'file_info:' && currentSection == 'latest_version') {
          inFileInfo = true;
          continue;
        }
        
        if (line.contains(':') && !line.endsWith(':')) {
          final parts = line.split(':');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            String value = parts.sublist(1).join(':').trim();
            
            // 移除注释部分（# 及其后面的内容）
            if (value.contains('#')) {
              value = value.split('#')[0].trim();
            }
            
            // 移除引号
            if (value.startsWith('"') && value.endsWith('"')) {
              value = value.substring(1, value.length - 1);
            }
            
            if (currentSection == 'latest_version') {
              if (inFileInfo) {
                // 处理file_info下的字段
                if (key == 'size') {
                  fileInfo[key] = int.tryParse(value) ?? 0;
                } else {
                  fileInfo[key] = value;
                }
              } else {
                // 处理latest_version下的其他字段
                if (key == 'version_code' || key == 'update_type') {
                  updateData[key] = int.tryParse(value) ?? 0;
                } else if (key == 'description' && value == '|') {
                  // 跳过多行描述的起始符
                  continue;
                } else {
                  updateData[key] = value;
                }
              }
            }
          }
        } else if (currentSection == 'latest_version' && !inFileInfo && line.startsWith('-')) {
          // 处理多行描述
          if (!updateData.containsKey('description')) {
            updateData['description'] = '';
          }
          final descLine = line.substring(1).trim();
          updateData['description'] = '${updateData['description'] as String}$descLine\n';
        }
        
        // 检测section结束
        if (line.endsWith(':') && !line.contains(' ') && line != 'file_info:') {
          currentSection = '';
          inFileInfo = false;
        }
      }
      
      // 添加file_info到updateData
      if (fileInfo.isNotEmpty) {
        updateData['file_info'] = fileInfo;
      }
      
      // 检查是否有更新
      final latestVersion = updateData['version'] ?? '';
      final latestVersionCode = updateData['version_code'] ?? 0;
      
      if (latestVersion.isNotEmpty && latestVersionCode > currentVersionCode) {
        print('发现新版本: $latestVersion ($latestVersionCode)');
        return UpdateInfo.fromJson(updateData);
      }
      
      return null;
    } catch (e) {
      print('解析YAML响应失败: $e');
      return null;
    }
  }

  /// 下载更新
  /// 
  /// 根据[UpdateInfo]中的下载地址下载APK文件。
  /// 下载完成后会自动进行MD5和SHA256校验。
  /// 
  /// 返回下载后的文件绝对路径，如果下载失败或校验失败则返回null。
  Future<String?> downloadUpdate(
    UpdateInfo updateInfo, {
    Function(double)? onProgress,
  }) async {
    if (_isDownloading) return null;
    _isDownloading = true;

    try {
      // 获取下载目录
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        print('无法获取存储目录');
        _isDownloading = false;
        return null;
      }

      // 构建保存路径
      final fileName = 'update_${updateInfo.version}.apk';
      final savePath = '${dir.path}/$fileName';
      print('下载路径: $savePath');

      // 检查文件是否已存在
      final file = File(savePath);
      if (await file.exists()) {
        // 如果文件已存在，先删除再重新下载，确保文件完整性
        await file.delete();
      }

      // 下载文件
      print('开始下载更新: ${updateInfo.version}');
      print('下载地址: ${updateInfo.downloadUrl}');
      print('保存路径: $savePath');
      
      await _dio.download(
        updateInfo.downloadUrl,
        savePath,
        options: Options(
          receiveTimeout: Duration(seconds: 600), // 10分钟超时
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

      // 验证文件是否下载成功
      if (await file.exists()) {
        final fileSize = await file.length();
        print('✅ APK文件下载完成，大小: $fileSize字节');

        // 验证文件完整性
        if (await _verifyFileIntegrity(file, updateInfo)) {
          _isDownloading = false;
          return savePath;
        } else {
          print('文件完整性验证失败');
          await file.delete();
          _isDownloading = false;
          return null;
        }
      } else {
        print('APK文件下载后不存在');
        _isDownloading = false;
        return null;
      }
    } catch (e) {
      print('❌ 下载更新失败: $e');
      if (e is DioException) {
        print('   错误类型: ${e.type}');
        print('   错误消息: ${e.message}');
        if (e.response != null) {
          print('   响应状态: ${e.response?.statusCode}');
          print('   响应数据: ${e.response?.data}');
        }
      }
      print('下载更新失败，未获取到文件路径');
      _isDownloading = false;
      return null;
    }
  }

  /// 验证文件完整性
  Future<bool> _verifyFileIntegrity(File file, UpdateInfo updateInfo) async {
    try {
      if (updateInfo.md5.isNotEmpty) {
        final fileBytes = await file.readAsBytes();
        final fileMd5 = md5.convert(fileBytes).toString();
        if (fileMd5 != updateInfo.md5) {
          print('MD5校验失败: 期望=${updateInfo.md5}, 实际=$fileMd5');
          return false;
        }
      }
      
      if (updateInfo.sha256.isNotEmpty) {
        final fileBytes = await file.readAsBytes();
        final fileSha256 = sha256.convert(fileBytes).toString();
        if (fileSha256 != updateInfo.sha256) {
          print('SHA256校验失败: 期望=${updateInfo.sha256}, 实际=$fileSha256');
          return false;
        }
      }
      
      return true;
    } catch (e) {
      print('文件完整性验证异常: $e');
      return false;
    }
  }

  /// 安装更新
  Future<bool> installUpdate(String filePath) async {
    try {
      if (Platform.isAndroid) {
        print('开始安装APK: $filePath');
        
        // 调用AppInstallHelper进行安装
        final appInstallHelper = AppInstallHelper();
        final result = await appInstallHelper.installApk(filePath);

        if (result) {
          print('APK安装请求已发送');
          return true;
        } else {
          print('APK安装失败');
          return false;
        }
      } else {
        print('当前平台不支持安装');
        return false;
      }
    } catch (e) {
      print('安装更新失败: $e');
      return false;
    }
  }

  /// 判断是否应该检查更新
  Future<bool> _shouldCheckUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckTime = prefs.getInt('last_update_check_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 检查是否超过检查间隔
      final diff = now - lastCheckTime;
      final secondsDiff = diff / 1000;

      return secondsDiff >= UpdateConfig.checkIntervalSeconds;
    } catch (e) {
      print('检查更新时间失败: $e');
      return true;
    }
  }

  /// 保存最后检查时间
  Future<void> _saveLastCheckTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_update_check_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      print('保存检查时间失败: $e');
    }
  }
}
