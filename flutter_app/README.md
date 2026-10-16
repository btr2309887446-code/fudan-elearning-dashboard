# Android / macOS Flutter 客户端

[返回项目首页](../README.md) · [iOS 原生客户端](../docs/ios.md)

当前 Flutter 代码用于 Android 与 macOS。iPhone / iPad 使用 `ios/NativeRunner.xcodeproj` 中的独立 SwiftUI 工程，不通过 Flutter 构建。目录内保留了旧 Flutter iOS 工程和界面作为历史参考。

## 快速开始

以下命令在 `flutter_app/` 目录执行。`pubspec.yaml` 要求 Dart 3.10 或更高、低于 4.0；当前 GitHub 工作流配置 Flutter 3.47.5。

```bash
flutter pub get
flutter run --dart-define=DEMO=true
```

演示模式无需账号。连接设备后使用 `flutter run` 启动正常登录流程；需要能访问学校认证与 eLearning 服务的网络环境。

## 目录

| 目录 | 用途 |
| --- | --- |
| `lib/core/` | Dart 认证、Cookie、Canvas、成绩、作业、文件和摘要逻辑 |
| `lib/platform/` | 存储、目录与平台能力 |
| `lib/state/` | 应用状态 |
| `lib/ui/` | Flutter 界面，其中 `ui/ios/` 是旧 iOS 实现 |
| `test/` | 核心逻辑、界面与 golden 截图测试 |
| `tool/` | 加密与协议验证工具 |
| `android/`、`macos/` | 当前 Flutter 平台工程 |
| `ios/NativeRunner*` | 独立原生 iOS 工程和测试，见专门文档 |

Windows 桌面端使用仓库根目录的 TypeScript 实现，未复用这里的 Dart 业务代码。各端通过协议约定及对应测试保持行为一致。

## 检查与测试

```bash
flutter analyze
flutter test --exclude-tags golden
```

需要更新 Flutter 截图基线时：

```bash
flutter test test/golden_test.dart test/ios_golden_test.dart --update-goldens
```

更新后应人工检查截图差异。Flutter iOS golden 仅验证旧 Flutter 界面，不代表原生 iOS 页面。

在仓库根目录可运行 Dart / Node 加密交叉验证：

```bash
node recon/test-dart-rsa-interop.mjs
```

## Android 构建

配置 Flutter、JDK 与 Android SDK 后执行：

```bash
flutter build apk --release
```

产物为 `build/app/outputs/flutter-apk/app-release.apk`。当前 GitHub 发布工作流不生成 Android APK；发布前需要另行确认正式签名与真机运行情况。

Windows 下建议从纯英文路径构建。当前仓库路径含中文，历史上出现过 Android release AOT 构建无法正确读取路径的问题。如遇到相关错误，使用纯英文路径下的独立检出进行构建。

历史排错记录还包括 Gradle 下载、Kotlin 增量编译及签名配置，见 [历史开发记录](../docs/archive/flutter-notes.md)；其中版本、费用和验证状态不作为当前结论。

## macOS 构建

需要 macOS 与 Flutter 对应的构建环境：

```bash
flutter build macos --release
```

GitHub 工作流使用 ad-hoc 签名并打包为 `fudan-elearning-macos.zip`，未做 Apple 公证；首次打开可能需要在系统中允许。

## 数据与文件

Flutter 端直接对接 UIS / Canvas，使用 `dart:io` 传输层保留登录链的 Cookie，使用 Dart RSA 实现学校需要的 PKCS#1 v1.5 加密。Web 构建主要用于界面预览，不能作为真实数据客户端使用。

课程文件按 `学期 / 课程 / Canvas 子文件夹 / 文件名` 保存。Android 使用应用专属外部目录。文件名做跨平台净化，重名时避免大小写冲突；下载中间文件使用 `.part` 扩展名。

记住的密码通过平台安全存储保存；会话、偏好与课程快照保存在本机。Flutter 端的模型配置随偏好保存，不能将其视为原生 iOS 的 Keychain 存储。启用 AI 摘要会向你配置的模型接口发送作业文本。
