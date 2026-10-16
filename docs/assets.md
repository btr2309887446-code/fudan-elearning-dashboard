# 图标与视觉资源

[返回项目首页](../README.md)

## 生成方式

源图位于 `build/icon-new-source.png`。在仓库根目录运行：

```bash
python recon/make-icons.py
cd flutter_app
dart run flutter_launcher_icons
```

第二步用于 Flutter 平台资源；原生 iOS 的图标资源引用以 `NativeRunner.xcodeproj/project.pbxproj` 为准，发布前应检查实际安装包图标。

| 资源 | 用途 |
| --- | --- |
| `build/icon.ico` | Windows 多尺寸图标 |
| `build/icon.png` | Electron 打包资源 |
| `flutter_app/assets/icon/icon_ios.png` | iOS 满幅方图，不含透明角 |
| `flutter_app/assets/icon/icon.png` | macOS / Web 图标 |
| `flutter_app/assets/icon/icon_foreground.png` | Android 自适应图标前景 |
| `flutter_app/assets/brand/mark.png` | 应用内不带文字的品牌图形 |

以上路径均相对于仓库根目录。生成过程中的检查图与预览图不纳入版本控制。

## 平台注意事项

- iOS 图标使用满幅方图，圆角由系统添加。Flutter 图标配置使用扁平字段 `image_path_ios`。
- Android 自适应图标还会经过系统与生成配置的缩进处理；检查时应预览最终合成效果，避免源图和平台同时缩小。
- 小尺寸下完整标识中的文字难以辨认，应用内小图标使用不带文字的 `mark.png`。
- Windows 桌面端保留自己的侧栏和卡片布局；原生 iOS 使用系统列表、表单、导航和语义颜色。

桌面界面截图位于 `docs/`，用于文档展示。Flutter 截图测试基线位于 `flutter_app/test/goldens/`，原生 iOS 界面截图由模拟器测试导出，三者用途不同。
