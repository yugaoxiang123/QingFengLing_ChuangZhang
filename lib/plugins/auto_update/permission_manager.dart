import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_install_helper.dart';

/// 权限管理器
/// 专门处理应用启动时的权限检查和管理
class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  bool _permissionChecked = false;
  final AppInstallHelper _appInstallHelper = AppInstallHelper();

  /// 是否已经检查过权限
  bool get isPermissionChecked => _permissionChecked;

  /// 重置权限检查状态（用于测试或重新检查）
  void resetPermissionCheck() {
    _permissionChecked = false;
  }

  /// 启动时检查安装权限
  /// 
  /// [context] - 用于显示对话框的上下文
  /// [showDialog] - 是否显示权限请求对话框，默认为true
  /// 
  /// 返回权限状态
  Future<PermissionStatus> checkInstallPermissionOnStartup(
    BuildContext context, {
    bool showDialog = true,
  }) async {
    if (_permissionChecked) {
      return await _appInstallHelper.checkInstallPermissionStatus();
    }

    try {
      final permissionStatus = await _appInstallHelper.checkInstallPermissionStatus();
      print('启动时权限检查结果: $permissionStatus');

      if (showDialog && context.mounted) {
        switch (permissionStatus) {
          case PermissionStatus.denied:
            // 权限被拒绝，显示权限请求对话框，等待用户处理
            await _showStartupPermissionDialog(context);
            break;
          case PermissionStatus.permanentlyDenied:
            // 权限被永久拒绝，显示设置引导，等待用户处理
            await _showPermissionPermanentlyDeniedDialog(context);
            break;
          case PermissionStatus.granted:
            print('安装权限已授权');
            break;
          default:
            print('权限状态未知: $permissionStatus');
            break;
        }
      }

      _permissionChecked = true;
      // 重新检查权限状态，因为用户可能已经授权了
      return await _appInstallHelper.checkInstallPermissionStatus();
    } catch (e) {
      print('启动时检查权限失败: $e');
      _permissionChecked = true;
      return PermissionStatus.denied;
    }
  }

  /// 显示启动时的权限请求对话框
  Future<void> _showStartupPermissionDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('需要安装权限'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('为了能够自动安装应用更新，需要授予"安装未知来源应用"权限。'),
            SizedBox(height: 8),
            Text('这个权限只在有应用更新时使用，不会影响您的设备安全。'),
            SizedBox(height: 8),
            Text('您可以选择：'),
            Text('• 现在授权 - 支持自动更新'),
            Text('• 稍后授权 - 届时手动安装更新'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后再说'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('授权'),
          ),
        ],
      ),
    );

    if (result == true) {
      // 用户选择授权，请求权限
      await _appInstallHelper.checkAndRequestInstallPermission();
    }
  }

  /// 显示权限被永久拒绝的对话框
  Future<void> _showPermissionPermanentlyDeniedDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('权限被拒绝'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('安装权限已被永久拒绝。'),
            SizedBox(height: 8),
            Text('如需自动安装更新，请手动到设置中开启"安装未知来源应用"权限。'),
            SizedBox(height: 8),
            Text('或者您可以在有更新时手动安装APK文件。'),
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

  /// 静默检查权限状态（不显示对话框）
  Future<PermissionStatus> checkPermissionStatusSilently() async {
    return await _appInstallHelper.checkInstallPermissionStatus();
  }

  /// 请求权限（显示系统权限对话框）
  Future<bool> requestPermission() async {
    return await _appInstallHelper.checkAndRequestInstallPermission();
  }
} 