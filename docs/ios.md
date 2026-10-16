# iOS / iPadOS 原生客户端

[返回项目首页](../README.md)

当前 iOS 客户端使用 SwiftUI / Swift，最低支持 iOS 15。工程为 [`../flutter_app/ios/NativeRunner.xcodeproj`](../flutter_app/ios/NativeRunner.xcodeproj/)，独立构建，不依赖 Flutter 运行时。

## 功能与使用

| 入口 | 功能 |
| --- | --- |
| 今日 | 按学期汇总待交、逾期和近期作业，进入任务详情 |
| 作业 | 状态筛选、搜索、列表与北京时间月历，查看说明、提交状态和成绩 |
| 课程 | 学期选择、课程搜索、课程详情、成绩趋势、分组得分与文件下载 |
| 我的 | 登录与退出、外观、同步范围、通知开关、摘要配置与诊断日志 |

作业详情可将作业标记为“无需提交”，从待交任务与提醒中移除，不改变成绩计算。提交仍需前往学校 eLearning；客户端提供跳转入口。

课程文件支持单个、多选及整课下载，按 `学期 / 课程 / Canvas 子文件夹 / 文件名` 保存到应用文档目录的 `eLearning/` 下。工程开启了文件共享，可通过系统“文件”App 访问。

## 提醒与系统日历

提醒默认关闭。用户允许通知并启用提醒后，应用依据本地已同步的作业数据安排每日汇总；支持静音单项任务。通知不是服务端实时推送，网页提交或截止变化后应再次同步。

“添加到系统日历”打开系统事件编辑器，由用户保存。它是单向添加：应用不自动更新或删除旧事件，重新添加可能产生重复事件。没有截止时间的作业不能导出日历。

## 登录与本地数据

Swift 服务实现 UIS / CAS 登录、RSA PKCS#1 v1.5 加密、验证码预检、手动重定向与 Cookie 管理，再通过 Canvas 个人信息接口校验登录态。

密码默认不持久化；选择记住密码后保存在 Keychain。Cookie、课程快照与偏好保存在本地。AI 接口密钥也使用 Keychain；启用 AI 摘要会将作业标题和说明发送到配置的模型服务。长说明在未配置模型或请求失败时可显示文本截取作为降级摘要。

从旧 Flutter iOS 版本切换后，不迁移原会话、快照、密码和偏好；原生版首次启动清理对应旧数据和待处理通知，需要重新登录。系统日历已有事件不会被删除。

## 开发入口

| 文件或目录 | 职责 |
| --- | --- |
| `NativeRunner/NativeRunnerApp.swift` | 应用入口 |
| `NativeRunner/NativeViews.swift` | 标签页、登录及详情界面 |
| `NativeRunner/NativeAppStore.swift` | 登录、同步、缓存、下载与设置状态 |
| `NativeRunner/Domain.swift` | 数据模型、作业状态、成绩、北京时间与月历聚合 |
| `NativeRunner/NativeServices.swift` | HTTP、Cookie、认证、Canvas、下载及摘要服务 |
| `NativeRunner/NativePlatform.swift` | 通知、系统日历和旧版状态清理 |
| `NativeRunnerTests/` | 领域逻辑、Cookie、认证预检、分页与下载路径测试 |
| `NativeRunnerUITests/` | 原生表单、动态字体、标签页、课程导航与作业月历测试 |

以上路径相对于 `flutter_app/ios/`。`Runner.xcodeproj`、`Runner.xcworkspace`、`Runner/` 和 `Flutter/` 属于旧 Flutter 工程；`flutter_app/lib/ui/ios/` 也是旧 Flutter 实现，当前原生 iOS 构建不使用这些界面。

## 本地构建与测试

需要 Mac 与可用的 Xcode / iOS SDK。在 Xcode 打开 `NativeRunner.xcodeproj`，选择 `NativeRunner` scheme，可运行模拟器；连接真机时配置自己的开发团队与签名。

命令行示例，在仓库根目录执行：

```bash
cd flutter_app/ios
xcodebuild -list -project NativeRunner.xcodeproj
xcodebuild build -project NativeRunner.xcodeproj -scheme NativeRunner \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath ../build/native-iphoneos CODE_SIGNING_ALLOWED=NO
```

测试需先使用 `xcrun simctl list devices available` 查询当前模拟器，替换下面的 `<SIMULATOR_UDID>`：

```bash
xcodebuild test -project NativeRunner.xcodeproj -scheme NativeRunnerCI \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath ../build/native-test -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

`NativeRunnerCI` 包含学校认证入口的联网 Cookie 预检，这部分依赖学校服务可达；它不等同于真实账号登录测试。Flutter 的 `flutter analyze`、Dart 测试和 golden 截图不验证原生 SwiftUI 客户端。

## GitHub Actions 与安装包

[原生 iOS 构建工作流](../.github/workflows/ios-build.yml) 在推送 `master` 或手动触发后执行：

1. 在 iPhone 与 iPad 模拟器运行原生单元和界面测试。
2. 导出界面测试截图，上传 `native-ui-screenshots` 产物。
3. 构建原生应用并打包未签名 IPA，上传 `fudan-elearning-ipa` 产物。

测试步骤失败会阻止后续 IPA 构建；截图上传配置为允许失败。请以具体运行日志为准。

该工作流还包含独立的 macOS Flutter 构建任务。推送 `v*` 标签则走 [Release 工作流](../.github/workflows/release.yml)，构建 Windows、iOS 和 macOS 并发布 Release；其中 iOS 任务执行构建与打包，不运行上述模拟器测试。

未签名 IPA 需要自行签名后才能安装到 iPhone / iPad。仓库不包含签名证书；签名工具、账号及有效期以实际使用环境为准。
