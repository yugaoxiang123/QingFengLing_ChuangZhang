import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user_config.dart';

/// 用户配置服务 - 负责配置的读写
class UserConfigService {
  static const String _configFileName = 'user_config.json';
  
  /// 获取配置文件路径
  Future<String> _getConfigFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_configFileName';
  }

  /// 保存用户配置
  Future<bool> saveConfig(UserConfig config) async {
    try {
      final filePath = await _getConfigFilePath();
      final file = File(filePath);
      
      // 将配置转换为JSON字符串
      final jsonString = config.toJsonString();
      
      // 写入文件
      await file.writeAsString(jsonString);
      
      debugPrint('用户配置已保存: $filePath');
      debugPrint('配置内容: $jsonString');
      
      return true;
    } catch (e) {
      debugPrint('保存用户配置失败: $e');
      return false;
    }
  }

  /// 读取用户配置
  Future<UserConfig?> loadConfig() async {
    try {
      final filePath = await _getConfigFilePath();
      final file = File(filePath);
      
      // 检查文件是否存在
      if (!await file.exists()) {
        debugPrint('配置文件不存在: $filePath');
        return null;
      }
      
      // 读取文件内容
      final jsonString = await file.readAsString();
      
      if (jsonString.isEmpty) {
        debugPrint('配置文件为空');
        return null;
      }
      
      // 解析JSON
      final config = UserConfig.fromJsonString(jsonString);
      
      debugPrint('用户配置已加载: $config');
      return config;
    } catch (e) {
      debugPrint('读取用户配置失败: $e');
      return null;
    }
  }

  /// 删除配置文件
  Future<bool> deleteConfig() async {
    try {
      final filePath = await _getConfigFilePath();
      final file = File(filePath);
      
      if (await file.exists()) {
        await file.delete();
        debugPrint('用户配置已删除: $filePath');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('删除用户配置失败: $e');
      return false;
    }
  }

  /// 检查配置文件是否存在
  Future<bool> hasConfig() async {
    try {
      final filePath = await _getConfigFilePath();
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      debugPrint('检查配置文件失败: $e');
      return false;
    }
  }

  /// 获取配置文件路径（用于调试）
  Future<String> getConfigFilePathForDebug() async {
    return await _getConfigFilePath();
  }
}
