# 青峰岭船长（chuanzhang-szahh-v4）

一个以“分阶段剧情视频播放”为核心的 Android Flutter 应用，支持：
- 8 段视频的全屏播放、阶段切换、播放结束自动跳转/回到初始段循环
- 从 OSS 拉取 `data.json` 动态配置视频下载地址，自动下载缺失资源并本地缓存
- 与“控制面板”通过 TCP Socket 通信，阶段变化时推送 `STAGE:n` 消息
- 自动更新：定期拉取 `update.yaml`，支持普通/强制/静默更新，并下载 APK 校验后发起安装

## 主要功能

### 1) 分阶段视频播放
- 首页为 8 个阶段的全屏视频播放与切换（按钮显示下一阶段）
- 第 1 段循环播放；第 2~8 段播放结束后自动切下一段；第 8 段结束后回到第 1 段
- 播放只依赖本地文件；若文件不存在会触发下载并保持加载态

入口与逻辑集中在：
- [lib/main.dart](lib/main.dart)

### 2) 视频资源下载与管理（OSS + data.json）
- App 启动后会从 OSS 拉取 `data.json`，读取 `videos` 列表并检查本地是否存在对应视频
- 下载采用临时文件 `*.temp`，下载完成后校验并 `rename` 为最终文件，避免半包文件被播放
- 本地路径：应用 Documents/videos/{index}.mp4
- 隐藏入口：右下角透明区域 2 秒内连点 3 次进入设置页，可单个/批量更新视频

相关代码：
- [lib/plugins/video_download/video_download_service.dart](lib/plugins/video_download/video_download_service.dart)
- [lib/plugins/video_download/video_settings_page.dart](lib/plugins/video_download/video_settings_page.dart)

`data.json` 结构示例（仓库根目录提供样例）：
- [data.json](data.json)

```json
{
  "videos": [
    { "index": 1, "name": "登船准备", "url": "https://.../1.mp4" }
  ]
}
```

### 3) 控制面板 TCP 通信
- App 可配置控制面板服务器 IP（端口固定 8888）
- 阶段初始化/切换后发送：`STAGE:n`（n 从 1 开始）
- 具备自动重连（指数退避，最大 30s）

相关代码：
- [lib/services/controller_client_service.dart](lib/services/controller_client_service.dart)
- [lib/services/user_config_service.dart](lib/services/user_config_service.dart)

注意：TCP 没有消息边界；当前接收端实现按“单次回调即一条消息”处理，适用于对端按帧发送或自行保证边界的场景。

### 4) 自动更新（update.yaml）
- 启动后先检查“安装未知来源应用”权限，通过后再检测更新
- 支持更新类型：
  - 普通更新：用户确认后更新
  - 强制更新：弹窗倒计时后自动开始下载
  - 静默更新：后台下载并发起安装（在已 root 设备上会尝试静默安装）
- 下载完成后支持 md5/sha256 完整性校验（字段有值才校验）

相关代码：
- [lib/plugins/auto_update/update_manager.dart](lib/plugins/auto_update/update_manager.dart)
- [lib/plugins/auto_update/update_service.dart](lib/plugins/auto_update/update_service.dart)
- [lib/plugins/auto_update/app_install_helper.dart](lib/plugins/auto_update/app_install_helper.dart)

更新清单示例：
- [update_plugin/update.yaml](update_plugin/update.yaml)

## 技术架构与目录

- `lib/main.dart`：主页面（分阶段播放、下载缺失视频、发送阶段到控制面板）
- `lib/plugins/video_download/*`：视频资源配置与下载、设置页（含控制面板配置）
- `lib/services/controller_client_service.dart`：TCP 客户端（连接/重连/日志流）
- `lib/plugins/auto_update/*`：更新检查、下载校验、安装与权限处理
- `update_plugin/`：发布产物与更新清单（`update.yaml`）相关脚本
- `android/`：Android 工程与 Gradle 配置

## 环境版本要求

以工程配置为准：
- Flutter：建议使用包含 Dart 3.8.1+ 的稳定版（本地校验提示可用 Flutter 3.41.4）
- Dart SDK：`^3.8.1`（见 [pubspec.yaml](pubspec.yaml)）
- Gradle：8.12（见 [android/gradle/wrapper/gradle-wrapper.properties](android/gradle/wrapper/gradle-wrapper.properties)）
- Android Gradle Plugin：8.7.3，Kotlin：2.1.0（见 [android/settings.gradle.kts](android/settings.gradle.kts)）
- Java：11（见 [android/app/build.gradle.kts](android/app/build.gradle.kts)）
- Android NDK：27.0.12077973（见 [android/app/build.gradle.kts](android/app/build.gradle.kts)）

## 常用命令

### 开发调试

```bash
flutter pub get
flutter run
```

可用设备查看：

```bash
flutter devices
```

### 构建发布（APK）

```bash
flutter build apk --release
```

带版本号/构建号（与发布脚本一致的参数形式）：

```bash
flutter build apk --release --build-name=0.1.9 --build-number=109
```

 用 fvm 的 Flutter 命令来构建这个项目

 ### 开发调试

```bash
fvm flutter pub get
fvm flutter run
```
```bash
fvm flutter build apk --release --build-name=0.1.9 --build-number=109
```

使用指定flutter版本打包
```bash
D:\sdk\flutter_3.41.4\bin\flutter.bat pub get
D:\sdk\flutter_3.41.4\bin\flutter.bat build apk --release --build-name=0.1.9 --build-number=109
```
### 一键构建并生成更新信息（推荐发布链路）

```bash
./build_with_update.sh
```

仓库提供脚本用于：
- 自动递增 `pubspec.yaml` patch 版本
- 构建 release APK 并复制到 `update_plugin/`
- 计算 md5/sha256/size 并更新 `update_plugin/update.yaml`

脚本入口：
- [build_with_update.sh](build_with_update.sh)

备注：在 Windows 环境通常需要 WSL 或 Git-Bash（并确保 `python3`、`sed`、`grep`、`stat` 可用）才能直接运行该脚本。

### 仅更新 APK 哈希信息

- [update_plugin/update_apk_info.sh](update_plugin/update_apk_info.sh)
- [update_plugin/generate_file_info.py](update_plugin/generate_file_info.py)

## 注意事项

- 自动更新安装权限：Android 需要“安装未知来源应用”权限，否则会跳过自动更新检查或无法发起安装。
- 静默安装：已 root 设备会尝试 `su -c pm install -r ...` 等方式；不同 ROM/系统策略差异较大，需要按现场机型验证。
- 更新 YAML 解析：当前实现为轻量字符串解析，修改 `update.yaml` 结构或缩进规则可能导致解析失败。
- 控制面板协议：当前默认端口固定为 8888；发送消息不带换行分隔符；若对端存在拆包/粘包风险，建议在协议层增加分隔符或长度前缀。
