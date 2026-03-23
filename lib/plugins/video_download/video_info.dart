/// 视频信息模型
class VideoInfo {
  final int index; // 1-8
  final String name; // 视频名称，默认是 "1.mp4" 到 "8.mp4"
  final int? size; // 文件大小（字节）
  final DateTime? updateTime; // 更新时间
  final String localPath; // 本地文件路径
  final bool isDownloaded; // 是否已下载
  final String? remoteUrl; // 远程下载地址（从data.json读取）

  VideoInfo({
    required this.index,
    required this.name,
    this.size,
    this.updateTime,
    required this.localPath,
    required this.isDownloaded,
    this.remoteUrl,
  });

  /// 从JSON创建
  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      index: json['index'] as int,
      name: json['name'] as String? ?? '${json['index']}.mp4',
      size: json['size'] as int?,
      updateTime: json['updateTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['updateTime'] as int)
          : null,
      localPath: json['localPath'] as String,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      remoteUrl: json['remoteUrl'] as String?,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'name': name,
      'size': size,
      'updateTime': updateTime?.millisecondsSinceEpoch,
      'localPath': localPath,
      'isDownloaded': isDownloaded,
      'remoteUrl': remoteUrl,
    };
  }

  /// 复制并更新
  VideoInfo copyWith({
    int? index,
    String? name,
    int? size,
    DateTime? updateTime,
    String? localPath,
    bool? isDownloaded,
    String? remoteUrl,
  }) {
    return VideoInfo(
      index: index ?? this.index,
      name: name ?? this.name,
      size: size ?? this.size,
      updateTime: updateTime ?? this.updateTime,
      localPath: localPath ?? this.localPath,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      remoteUrl: remoteUrl ?? this.remoteUrl,
    );
  }

  /// 格式化文件大小
  String get formattedSize {
    if (size == null) return '未知';
    if (size! < 1024) return '${size}B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)}KB';
    if (size! < 1024 * 1024 * 1024) {
      return '${(size! / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(size! / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  /// 格式化更新时间
  String get formattedUpdateTime {
    if (updateTime == null) return '未知';
    final now = DateTime.now();
    final diff = now.difference(updateTime!);
    
    if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }
}
