# iOS 课堂内容整合

原生 SwiftUI 客户端直接读取 iCourse Subscriber 的版本 4 加密索引、gzip SQLite 分片，与 Windows 使用同一上游数据协议。没有新增订阅控制、邮件读取或 AI 生成请求。

## 实现

- `LectureDomain.swift`：稳定课次身份、加密格式、解压、SQLite 索引和正文查询。
- `LectureService.swift`：GitHub 提交固定下载、哈希缓存、课程绑定、读取状态和钥匙串。
- `LectureStore.swift`：账号切换取消、前台状态、变化记录及 Canvas 简介缓存。
- `LectureViews.swift`：概览、分页列表、阅读器、连接表单与课程关联。
- `lecture-reader.html`：随包提供的离线 Markdown / KaTeX 阅读组件，禁止联网、原始 HTML 和远程图片。

解密、解压和数据库访问在独立 actor 上执行。解密后的 SQLite 通过系统文件保护的临时文件导入内存，关闭源文件后立即移除临时文件；启动时清理中断遗留的临时文件。长期磁盘缓存只保存加密分片，连接元数据单独原子写入。记住的派生密钥采用 `WhenUnlockedThisDeviceOnly` 钥匙串保护，原始 UIS 密码不写入缓存。

课堂任务来源是可选字段，旧任务文件仍可解码。变化记录保存摘要 SHA-256 指纹，详情不展示指纹，也不伪造全文差异。

## 本地与 CI 检查

`LectureTests` 使用 Node 生成的合成加密夹具，验证跨语言解密、错误密码、5,000 条课次、旧任务兼容、分页、离线解锁、已读保存、写入失败、账号隔离、静默基线和重复同步。`LectureUITests` 在演示账号上检查概览、三个阅读页签、任务草稿、保存及来源入口。

离线阅读资源可使用 `node scripts/build-ios-lecture-reader.mjs` 重新生成，夹具使用 `node scripts/build-ios-lecture-fixture.mjs` 生成；需要根目录中对应的 React、react-markdown、remark-gfm、remark-math、rehype-katex、KaTeX、esbuild 和 sql.js 开发依赖。生成的资源已入库，Xcode 构建无需 Node 或运行时下载。

Windows 上的 `scripts/test-ios-reader.cjs` 通过 Electron 检查共享网页组件的公式、表格、目录、文本安全、离线资源、主题与字号；它不替代 WKWebView 和 iOS 原生界面的验证。

专用工作流 `.github/workflows/ios-classroom.yml` 在 macOS 上执行 iPhone 15 Plus / iOS 26 和 iPad 测试，导出模拟器截图，再构建未签名 IPA。未签名 IPA 需要自行签名后侧载到手机。真实账号解锁、学校大纲内容、私有仓库令牌和真机长时间使用需要实际验证，演示截图不能当作真机截图。
