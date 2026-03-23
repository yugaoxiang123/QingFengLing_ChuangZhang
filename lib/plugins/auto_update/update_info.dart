/// 更新信息模型
class UpdateInfo {
  final String version;
  final int versionCode;
  final String description;
  final int updateType;
  final String downloadUrl;
  final int fileSize;
  final String md5;
  final String sha256;
  final String buildDate;

  UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.description,
    required this.updateType,
    required this.downloadUrl,
    required this.fileSize,
    required this.md5,
    required this.sha256,
    required this.buildDate,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] ?? '',
      versionCode: json['version_code'] ?? 0,
      description: json['description'] ?? '',
      updateType: json['update_type'] ?? 0,
      downloadUrl: json['download_url'] ?? '',
      fileSize: json['file_info']?['size'] ?? 0,
      md5: json['file_info']?['md5'] ?? '',
      sha256: json['file_info']?['sha256'] ?? '',
      buildDate: json['build_date'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'version_code': versionCode,
      'description': description,
      'update_type': updateType,
      'download_url': downloadUrl,
      'file_info': {
        'size': fileSize,
        'md5': md5,
        'sha256': sha256,
      },
      'build_date': buildDate,
    };
  }

  @override
  String toString() {
    return 'UpdateInfo(version: $version, versionCode: $versionCode, updateType: $updateType)';
  }
}

/// 更新类型常量
class UpdateType {
  static const int normal = 0;    // 普通更新（用户可选择）
  static const int force = 1;     // 强制更新（必须更新）
  static const int silent = 2;    // 静默更新（后台自动更新）
}

/// 更新配置常量
class UpdateConfig {
  static const int checkIntervalSeconds = 60;  // 检查间隔：1分钟
  static const int downloadTimeoutSeconds = 300; // 下载超时：5分钟
  static const String defaultServerUrl = 'https://shv-software.oss-cn-zhangjiakou.aliyuncs.com/Android-Packages/qfl-chuanzhang';
  static const String defaultUpdatePath = '/update.yaml';
}
