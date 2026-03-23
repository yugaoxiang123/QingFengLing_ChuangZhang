import 'dart:convert';
import '../config/app_config.dart';

/// 用户配置模型
class UserConfig {
  /// 控制面板服务器IP地址
  final String serverIp;

  /// 是否自动连接服务器
  final bool autoConnect;

  /// 最后更新时间
  final DateTime lastUpdate;

  UserConfig({
    String? serverIp,
    bool? autoConnect,
    DateTime? lastUpdate,
  }) : serverIp = serverIp ?? AppConfig.defaultServerIp,
       autoConnect = autoConnect ?? AppConfig.defaultAutoConnect,
       lastUpdate = lastUpdate ?? DateTime.now();

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'serverIp': serverIp,
      'autoConnect': autoConnect,
      'lastUpdate': lastUpdate.toIso8601String(),
    };
  }

  /// 从JSON创建
  factory UserConfig.fromJson(Map<String, dynamic> json) {
    return UserConfig(
      serverIp: json['serverIp'] as String? ?? AppConfig.defaultServerIp,
      autoConnect: json['autoConnect'] as bool? ?? AppConfig.defaultAutoConnect,
      lastUpdate: json['lastUpdate'] != null
          ? DateTime.parse(json['lastUpdate'] as String)
          : DateTime.now(),
    );
  }

  /// 转换为JSON字符串
  String toJsonString() {
    return jsonEncode(toJson());
  }

  /// 从JSON字符串创建
  factory UserConfig.fromJsonString(String jsonString) {
    return UserConfig.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  @override
  String toString() {
    return 'UserConfig(serverIp: $serverIp, autoConnect: $autoConnect, lastUpdate: $lastUpdate)';
  }
}
