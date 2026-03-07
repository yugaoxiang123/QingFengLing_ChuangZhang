import 'dart:io';

/// Root检测服务
/// 
/// 用于检测Android设备是否已经被root。
/// 检测原理：
/// 1. 尝试执行`su`命令。
/// 2. 检查系统目录中是否存在常见的root二进制文件（如`/system/bin/su`）。
/// 3. 检查是否安装了常见的root管理应用（如SuperSU, Magisk）。
/// 
/// 仅用于判断是否可以使用静默安装功能。
class RootDetectionService {
  static final RootDetectionService _instance =
      RootDetectionService._internal();

  factory RootDetectionService() => _instance;

  RootDetectionService._internal();

  /// 检测设备是否已root
  /// 返回布尔值，true表示已root，false表示未root
  Future<bool> isDeviceRooted() async {
    try {
      // 如果不是Android设备，直接返回false
      if (!Platform.isAndroid) {
        print('非Android设备，不进行root检测');
        return false;
      }

      // 使用多种方法检测设备是否已root
      final bool isRooted = await _checkRootAccess();

      // 记录检测结果到日志
      if (isRooted) {
        print('检测到设备已被root');
      } else {
        print('设备未被root');
      }

      return isRooted;
    } catch (e) {
      // 如果检测过程出错，记录错误并返回false
      print('检测设备root状态时出错: $e');
      return false;
    }
  }

  /// 检查root访问权限
  Future<bool> _checkRootAccess() async {
    try {
      // 方法1: 尝试执行su命令
      try {
        final result = await Process.run('su', ['-c', 'echo test'], 
          runInShell: false);
        if (result.exitCode == 0) {
          print('root检测: su命令执行成功');
          return true;
        }
      } catch (e) {
        print('root检测: su命令执行失败 - $e');
      }

      // 方法2: 检查常见的root文件
      final rootFiles = [
        '/system/app/Superuser.apk',
        '/sbin/su',
        '/system/bin/su',
        '/system/xbin/su',
        '/data/local/xbin/su',
        '/data/local/bin/su',
        '/system/sd/xbin/su',
        '/system/bin/failsafe/su',
        '/data/local/su',
        '/su/bin/su',
      ];

      for (final path in rootFiles) {
        try {
          if (await File(path).exists()) {
            print('root检测: 发现root文件 - $path');
            return true;
          }
        } catch (e) {
          // 忽略文件访问错误
        }
      }

      // 方法3: 检查常见的root应用包名
      try {
        final result = await Process.run('pm', ['list', 'packages'], 
          runInShell: false);
        final packages = result.stdout.toString();
        final rootPackages = [
          'com.noshufou.android.su',
          'com.thirdparty.superuser',
          'eu.chainfire.supersu',
          'com.koushikdutta.superuser',
          'com.zachspong.temprootremovejb',
          'com.ramdroid.appquarantine',
          'com.topjohnwu.magisk',
        ];

        for (final pkg in rootPackages) {
          if (packages.contains(pkg)) {
            print('root检测: 发现root应用 - $pkg');
            return true;
          }
        }
      } catch (e) {
        print('root检测: 包检查失败 - $e');
      }

      print('root检测: 未检测到root权限');
      return false;
    } catch (e) {
      print('root检测异常: $e');
      return false;
    }
  }

  /// 检测设备是否已root并记录结果
  /// 仅记录日志，不返回结果
  Future<void> checkAndLogRootStatus() async {
    try {
      final bool isRooted = await isDeviceRooted();

      if (isRooted) {
        print('安全警告：检测到设备已被root');
      } else {
        print('设备安全检查：未检测到root');
      }
    } catch (e) {
      print('检测并记录root状态时出错: $e');
    }
  }
} 