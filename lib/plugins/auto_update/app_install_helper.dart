import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

import 'root_detection_service.dart';


/// APK安装辅助类
/// 
/// 提供多种安装APK的方法，旨在提高在不同Android版本和设备状态下的安装成功率。
/// 
/// 主要功能：
/// 1. **权限管理**：检查并请求"安装未知来源应用"权限。
/// 2. **Root静默安装**：检测设备是否Root，如果已Root，尝试使用`su`命令进行后台静默安装。
/// 3. **常规安装**：对于非Root设备，使用标准的`Intent`机制（通过`open_file`插件）调用系统安装程序。
class AppInstallHelper {
  static final AppInstallHelper _instance = AppInstallHelper._internal();
  factory AppInstallHelper() => _instance;
  AppInstallHelper._internal();

  /// 检查安装权限状态（不请求）
  Future<PermissionStatus> checkInstallPermissionStatus() async {
    try {
      return await Permission.requestInstallPackages.status;
    } catch (e) {
      print('检查安装权限状态失败: $e');
      return PermissionStatus.denied;
    }
  }

  /// 检查并请求安装权限
  /// 
  /// 如果权限未授予，会尝试请求权限。
  /// 如果权限被永久拒绝，会引导用户去设置页面开启。
  Future<bool> checkAndRequestInstallPermission() async {
    try {
      // 检查当前权限状态
      final status = await Permission.requestInstallPackages.status;
      print('当前安装权限状态: $status');

      if (status.isGranted) {
        print('安装权限已授权');
        return true;
      }

      if (status.isDenied) {
        print('请求安装权限...');
        final result = await Permission.requestInstallPackages.request();
        print('权限请求结果: $result');
        
        if (result.isGranted) {
          print('安装权限授权成功');
          return true;
        } else {
          print('安装权限被拒绝');
          return false;
        }
      }

      if (status.isPermanentlyDenied) {
        print('安装权限被永久拒绝，需要手动开启');
        // 可以引导用户到设置页面
        await openAppSettings();
        return false;
      }

      return false;
    } catch (e) {
      print('检查安装权限失败: $e');
      return false;
    }
  }

  /// 显示权限请求对话框
  /// 
  /// 向用户解释为什么需要安装权限，并在用户同意后请求权限。
  Future<bool> showPermissionDialog(BuildContext context) async {
    final completer = Completer<bool>();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('需要安装权限'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('为了自动安装更新，应用需要"安装未知来源应用"权限。'),
            SizedBox(height: 8),
            Text('请在弹出的权限请求中选择"允许"。'),
            SizedBox(height: 8),
            Text('如果权限被拒绝，您需要手动到设置中开启此权限。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              completer.complete(false);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final hasPermission = await checkAndRequestInstallPermission();
              completer.complete(hasPermission);
            },
            child: const Text('授权'),
          ),
        ],
      ),
    );

    return completer.future;
  }

  /// 显示权限被拒绝的提示对话框
  void showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('权限被拒绝'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('安装权限被拒绝，无法自动安装更新。'),
            SizedBox(height: 8),
            Text('您可以：'),
            Text('1. 手动到设置中开启"安装未知来源应用"权限'),
            Text('2. 下载完成后手动安装APK文件'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我知道了'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  /// 安装APK文件
  /// 
  /// 尝试多种方式安装APK，流程如下：
  /// 1. 检查文件是否存在及大小。
  /// 2. 检测设备是否Root：
  ///    - 如果Root，尝试多种静默安装方法。
  ///    - 如果静默安装成功，直接返回。
  /// 3. 如果非Root或静默安装失败：
  ///    - 检查并请求安装权限。
  ///    - 使用`OpenFile`调用系统标准安装流程。
  Future<bool> installApk(String filePath) async {
    try {
      print('开始安装APK: $filePath');

      // 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        print('APK文件不存在: $filePath');
        return false;
      }

      // 检查文件大小
      final fileSize = await file.length();
      print('APK文件大小: $fileSize字节');

      // 确保文件有正确的权限
      try {
        await file.setLastModified(DateTime.now());
        print('APK文件权限设置成功');
      } catch (e) {
        print('设置APK文件权限失败: $e');
      }

      // 检查设备是否已root，如果是则尝试静默安装
      if (Platform.isAndroid) {
        final isRooted = await RootDetectionService().isDeviceRooted();
        if (isRooted) {
          print('检测到设备已root，尝试静默安装');

          // 确保在开始root安装之前，没有其他安装过程正在进行
          await Future.delayed(const Duration(seconds: 1));

          // 尝试使用root权限静默安装
          final success = await _installSilentlyOnRootedDevice(filePath);

          // 无论成功与否，给系统足够的时间处理
          await Future.delayed(const Duration(seconds: 5));

          if (success) {
            print('root静默安装成功');
            return true;
          }

          print('静默安装方法失败，正在准备尝试常规安装方式');
          // 在尝试常规安装前再等待一段时间，确保root安装进程完全结束
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      // 再次检查安装权限（此时应该已经有权限了）
      final hasPermission = await checkAndRequestInstallPermission();
      if (!hasPermission) {
        print('未获得安装权限，无法继续安装');
        return false;
      }

      // 尝试使用OpenFile安装
      try {
        print('尝试使用OpenFile安装');
        final result = await OpenFile.open(filePath);
        print('OpenFile结果: ${result.type} - ${result.message}');

        if (result.type == ResultType.done) {
          print('OpenFile安装请求已发送');
          await Future.delayed(const Duration(seconds: 2)); // 给系统一些时间处理
          return true;
        } else {
          print('OpenFile打开失败: ${result.message}');
        }
      } catch (e) {
        print('OpenFile安装失败: $e');
      }

      print('所有安装方法都失败');
      return false;
    } catch (e) {
      print('安装过程发生异常: $e');
      return false;
    }
  }

  /// 在已root的设备上静默安装APK
  /// 
  /// 尝试多种root安装命令，提高兼容性。
  /// 方法包括：
  /// 1. `su -c pm install`
  /// 2. `su 0 cmd package install` (Android 8.0+)
  /// 3. Magisk 方式
  /// 4. `echo | su` 管道方式
  /// 5. 临时 Shell 脚本方式
  /// 6. `busybox` 方式
  /// 
  /// 返回布尔值，表示安装是否成功。
  Future<bool> _installSilentlyOnRootedDevice(String filePath) async {
    try {
      print('尝试在已root设备上静默安装APK');

      // 再次确认文件存在且可访问
      final file = File(filePath);
      if (!await file.exists()) {
        print('静默安装失败：APK文件不存在');
        return false;
      }

      // 确保使用绝对路径
      final absolutePath = file.absolute.path;
      print('APK绝对路径: $absolutePath');

      // 直接尝试使用su命令安装
      try {
        print('尝试使用su命令安装');

        // 使用Process.run执行su命令
        final result = await Process.run('su', [
          '-c',
          'pm install -r "$absolutePath"',
        ]);

        final stdout = result.stdout.toString();
        print('su命令安装结果: $stdout');

        if (result.exitCode == 0 ||
            stdout.contains('Success') ||
            stdout.contains('success')) {
          print('su命令安装成功');
          return true;
        }
      } catch (e) {
        print('使用su命令安装失败: $e');
      }

      // 继续尝试之前的方法
      final installMethods = [
        // 方法1: 使用root UID直接执行命令
        () async {
          print('尝试静默安装方法1: 使用root UID');
          final result = await Process.run('su', [
            '0',
            'pm',
            'install',
            '-r',
            absolutePath,
          ]);
          return result;
        },

        // 方法2: 使用cmd package命令 (Android 8.0+推荐方式)
        () async {
          print('尝试静默安装方法2: 使用cmd package命令');
          final result = await Process.run('su', [
            '0',
            'cmd',
            'package',
            'install',
            '-r',
            absolutePath,
          ]);
          return result;
        },

        // 方法3: 使用Magisk常用方式
        () async {
          print('尝试静默安装方法3: Magisk方式');
          final result = await Process.run('su', [
            '--command',
            'pm install -r "$absolutePath"',
          ]);
          return result;
        },

        // 方法4: 使用echo通过stdin传递命令
        () async {
          print('尝试静默安装方法4: 通过stdin传递命令');
          final result = await Process.run('sh', [
            '-c',
            "echo 'pm install -r \"$absolutePath\"' | su",
          ]);
          return result;
        },

        // 方法5: 使用shell脚本执行
        () async {
          print('尝试静默安装方法5: 使用shell脚本');

          // 创建临时脚本文件
          final tempDir = Directory.systemTemp;
          final scriptFile = File('${tempDir.path}/install_apk.sh');
          await scriptFile.writeAsString('''
#!/system/bin/sh
pm install -r "$absolutePath"
exit \$?
''');

          // 设置执行权限
          await Process.run('chmod', ['755', scriptFile.path]);

          // 执行脚本
          final result = await Process.run('su', ['-c', scriptFile.path]);

          // 清理脚本文件
          try {
            await scriptFile.delete();
          } catch (e) {
            print('清理临时脚本文件失败: $e');
          }

          return result;
        },

        // 方法6: 使用busybox (如果可用)
        () async {
          print('尝试静默安装方法6: 使用busybox');
          final result = await Process.run('su', [
            '-c',
            'busybox sh -c "pm install -r \'$absolutePath\'"',
          ]);
          return result;
        },
      ];

      // 依次尝试每种安装方法
      for (int i = 0; i < installMethods.length; i++) {
        try {
          // 在尝试新方法前添加短暂延迟
          if (i > 0) {
            await Future.delayed(const Duration(seconds: 1));
          }

          final result = await installMethods[i]();

          final stdout = result.stdout.toString();
          final stderr = result.stderr.toString();

          print('静默安装方法${i + 1}结果: 退出码=${result.exitCode}, 输出=$stdout');

          if (stderr.isNotEmpty) {
            print('静默安装方法${i + 1}错误输出: $stderr');
          }

          if (result.exitCode == 0 || stdout.contains('Success')) {
            print('静默安装成功: 方法${i + 1}');

            // 安装成功后等待一段时间确保系统处理完毕
            await Future.delayed(const Duration(seconds: 3));
            return true;
          } else {
            print('静默安装方法${i + 1}失败: 退出码=${result.exitCode}');
          }
        } catch (e) {
          print('静默安装方法${i + 1}异常: $e');
        }

        // 在尝试下一种方法前等待足够长的时间
        await Future.delayed(const Duration(seconds: 2));
      }

      print('所有静默安装方法都失败');
      return false;
    } catch (e) {
      print('静默安装过程发生异常: $e');
      return false;
    }
  }
}
