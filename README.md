# 青峰岭控制面板 (Craft Controller)

这是一个基于 Flutter 开发的飞船控制面板应用，主要用于控制飞船模型的状态、接收遥测数据以及管理飞船的剧情流程。应用内置了 Socket 服务器和客户端功能，支持多端协同。

## ✨ 主要功能

*   **飞船操控**：
    *   提供可视化的仪表盘，显示飞船的坐标 (X, Y, Z)、姿态 (俯仰/偏航/滚转)、速度等实时数据。
    *   支持键盘控制 (WASD + 空格) 和触屏按钮控制。
    *   模拟真实的物理惯性和视觉反馈（引擎光效、跃迁粒子效果）。
*   **Socket 通信**：
    *   内置 TCP Socket 和 WebSocket 服务器，支持其他设备接入。
    *   实时广播飞船状态和控制指令。
    *   提供消息日志监控面板，方便调试。
*   **剧情管理**：
    *   支持手动切换飞船的剧情状态（如：起飞、跃迁、遭遇战等）。
    *   与 `QFChuanZhang` 系统联动，响应阶段变化指令。
*   **自动更新**：
    *   支持从远程服务器检查更新。
    *   **Root 设备静默安装**：检测到设备 Root 后，可自动后台静默安装更新，无需用户干预。
    *   **普通设备安装**：支持标准的 Android 安装流程。

## 🏗️ 项目架构

```
lib/
├── main.dart               # 应用入口
├── ui/                     # 界面层
│   ├── control_panel.dart      # 飞船状态仪表盘
│   ├── ship_manual_control.dart # 手动控制与动画效果
│   └── socket_server_page.dart  # 服务器状态监控页
├── services/               # 服务层
│   ├── socket_service.dart     # Socket通信核心服务
│   └── event_bus.dart          # 事件总线
└── plugins/                # 本地插件
    └── auto_update/            # 自动更新模块
        ├── update_service.dart     # 更新检查与下载逻辑
        ├── app_install_helper.dart # 安装逻辑（含Root静默安装）
        └── root_detection_service.dart # Root权限检测
```

## 🚀 快速开始

### 环境要求

*   Flutter SDK: `^3.8.1`
*   Dart SDK: `>=3.0.0`
*   Android Studio / VS Code

### 运行项目

```bash
# 获取依赖
flutter pub get

# 运行在连接的设备上
flutter run
```

### 打包 APK

```bash
# 构建 Release 版本 APK
flutter build apk --release
```

### Release 签名配置（必需）

首次打包 release 前，请先配置签名文件：

```bash
# 1) 复制模板
cp android/keystore.properties.example android/keystore.properties
```

然后编辑 `android/keystore.properties`，填写：

- `storeFile`：你的 `.jks` 路径（支持绝对路径，或相对 `android/` 路径）
- `storePassword`
- `keyAlias`
- `keyPassword`

未正确配置时，Gradle 会明确报错并提示你修正 `storeFile`。

## 📦 版本发布与部署

项目包含一套自动化的版本发布工具，位于 `update_plugin/` 目录下。

### 发布步骤

1.  **修改版本号**：在 `pubspec.yaml` 中更新 `version` 字段（例如 `1.0.0+1`）。
2.  **构建 APK**：运行 `flutter build apk --release`。
3.  **生成更新信息**：
    使用提供的脚本自动计算 APK 的 MD5/SHA256 并更新配置文件。

    ```bash
    cd update_plugin
    # 用法: ./update_apk_info.sh <构建好的APK路径>
    ./update_apk_info.sh ../build/app/outputs/flutter-apk/app-release.apk
    ```

    该脚本会更新 `update_plugin/update.yaml` 文件中的文件大小、MD5 和 SHA256 校验值。

4.  **部署**：
    *   将构建好的 APK 文件上传到文件服务器（如阿里云 OSS）。
    *   修改 `update_plugin/update.yaml` 中的 `download_url` 指向新的 APK 地址。
    *   将更新后的 `update.yaml` 上传到服务器指定位置（客户端默认配置读取的位置）。

## ⚠️ 安全说明

1.  **Keystore 密码**：
    当前项目的 `android/keystore.properties` 文件中包含了签名证书的明文密码。**在生产环境中，请务必将此文件从版本控制中移除，或使用环境变量/CI密钥管理来注入密码，防止凭证泄露。**

2.  **静默安装权限**：
    应用的自动更新模块包含 Root 权限检测和 `su` 命令执行逻辑，用于实现静默安装。这属于高权限操作，请确保下载源（`download_url`）的安全，防止中间人攻击导致恶意软件被静默安装。当前实现已包含 MD5/SHA256 完整性校验机制。
