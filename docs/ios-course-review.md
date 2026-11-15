# iOS 课程复习（CI 验证记录）

2026-11-13：新增课程复习入口、计划与知识点编辑、自测参考答案、独立掌握程度和跨课程预算排期。生成的单次个人任务支持完成、撤销及返回计划；锁定和已完成安排在重排时保留。计划与任务按账号一次原子写入，旧数据没有 review 字段时保持兼容。

AI 仅在用户确认后发送所选课堂摘要，复用安全存储中的模型配置。每批最多 12,000 字，逐字核验摘录；中断保留成功结果，继续时重新检查摘要指纹与关联。预览允许编辑和选择，不自动创建任务或修改学校作业。以上为功能说明，实际测试覆盖范围见下文。

## 验证基线

2026-11-15 核对 [Stability validation #6，run 43266978040](https://github.com/btr2309887446-code/fudan-elearning-dashboard/actions/runs/43266978040)：运行已完成，结论为 success；windows、ios (phone)、ios (tablet) 三个 job 全部成功。测试发生于北京时间 2026-11-13 01:12–01:18。

日志中的 checkout SHA 与 IPA manifest 的 source 均为 `f0faf44642788957d5514e10e19dd13bf1348541`。本文记录该代码提交的结果；后续文档提交或其他提交不能自动沿用为自身已通过 CI 的证明。

## iPhone / iPad 实测结果

两个独立 macOS runner 使用 Xcode 26.6、iOS 26.5 Simulator。每端执行同一组 47 项测试，均为 0 failures；合计 94 次执行，不是 94 个不同用例。

| 设备与日志 | 核心测试 | UI 测试 | 结论 |
| --- | --- | --- | --- |
| [iPhone 15 Plus](https://github.com/btr2309887446-code/fudan-elearning-dashboard/actions/runs/43266978040/job/131353026975) | 45：LectureTests 6、NativeDomainTests 24、PersonalAndChangeTests 8、ReviewTests 5、StabilityTests 2 | LectureUITests 1、ReviewUITests 1 | TEST SUCCEEDED |
| [iPad Pro 13-inch (M5)](https://github.com/btr2309887446-code/fudan-elearning-dashboard/actions/runs/43266978040/job/131353027666) | 同上 45 项 | 同上 2 项 | TEST SUCCEEDED |

此前 run 43186193203 的 iPad destination 阻塞，在本次 phone/tablet 独立 runner 运行中未复现，iPad 实际启动并完成了全部选定测试。诊断步骤因未失败而跳过；tablet 的 IPA 构建与安装包 manifest 步骤按 `matrix.device == 'phone'` 条件跳过，属于预期行为。

### 复习测试覆盖

两端的 `ReviewTests` 各通过以下 5 项：

- `testSharedBudgetMergesCourseDayAndPreservesOtherPlansOnDelete`：同课程同日任务合并、删除计划后保留其他计划。
- `testBudgetShortageCompletionUndoAndLock`：预算缺口、完成/撤销计入时长、完成不自动改变掌握程度、锁定安排保留。
- `testStalePreviewAndPassedTimeNeverCreateOverdueTasks`：拒绝过时预览与修订号，避免生成已过时段任务。
- `testLegacyDataAndAccountIsolation`：无 review 字段的旧数据兼容、复习数据存取与账号隔离。
- `testAIRejectsInventedQuotesAndPreservesAllChunks`：摘要分批无内容遗漏、接受原文摘录并拒绝编造摘录；不含真实模型请求。

`ReviewUITests.testCreatePlanAndKnowledgePoint` 在两端分别用时 24.876 秒、26.799 秒并通过。测试使用 `--ui-testing` 演示数据，从课程页进入复习，创建默认“期末复习”计划，添加“Synthetic knowledge”知识点，断言保存后显示，并附加 `review-plan` 截图。两张导出截图已人工查看，均显示该计划和知识点。截图中的“自测（0）”“暂无安排”也表明该用例没有执行自测或排期。

`LectureUITests.testCourseReaderAndTaskDraft` 在两端均通过，保留课程阅读、摘要/转写切换及任务草稿流程回归。工作流通过 `-only-testing` 选择上述两个 UI 测试类，不能据此宣称全部 UI 测试或全部复习交互已覆盖。

## 交付产物核验

以下为该 run 的 Actions artifacts，截至 2026-11-15 均未过期，GitHub 标示 2026-11-26 UTC 到期（北京时间 2026-11-27 01:17–01:18）。它们不是 GitHub Release。

| 产物 | 实际内容 / 核验范围 |
| --- | --- |
| [ios-delivery-phone](https://github.com/btr2309887446-code/fudan-elearning-dashboard/actions/runs/43266978040/artifacts/13966368696) | 未签名 IPA、`ios-manifest.json`、`ios-SHA256SUMS.txt`，以及 7 张 PNG（6 张阅读流程、1 张复习）、附件 manifest 和预算测量 JSON；已下载并核验。 |
| [ios-delivery-tablet](https://github.com/btr2309887446-code/fudan-elearning-dashboard/actions/runs/43266978040/artifacts/13965744142) | 7 张 PNG（6 张阅读流程、1 张复习）、附件 manifest 和预算测量 JSON；已下载核验，无 IPA 或安装包校验清单。 |
| [ios-test-results-phone](https://github.com/btr2309887446-code/fudan-elearning-dashboard/actions/runs/43266978040/artifacts/13966114038) | `stability-1.xcresult`，已下载确认结果包存在、ZIP 完整且归档 SHA-256 与 GitHub digest 一致。 |
| [ios-test-results-tablet](https://github.com/btr2309887446-code/fudan-elearning-dashboard/actions/runs/43266978040/artifacts/13965619009) | 独立的 `stability-1.xcresult`，同样核验通过；与 phone 包分开保存，避免同名目录覆盖。 |
| [windows-validation](https://github.com/btr2309887446-code/fudan-elearning-dashboard/actions/runs/43266978040/artifacts/13967470793) | 已核对上传记录与成功日志：Windows 类型检查、测试、各 UI harness、0.13.0 安装包构建及 manifest 生成成功；本次未下载或安装 Windows 包。 |

四份 iOS artifact 归档的实际 SHA-256 均与 GitHub 返回的 digest 一致。当前 Windows 审核环境没有重新运行 Xcode 或用 xcresulttool 重解析结果包；测试数量与通过状态取自原始 job 日志，并与测试源码、导出附件 manifest 交叉核对。

phone job 的 Release / iphoneos 构建明确记录 `BUILD SUCCEEDED`。IPA 内容核对如下：

- 文件：`Fudan-eLearning-iOS-stability-unsigned.ipa`，4,358,779 bytes。
- 版本：1.2.1（build 7）；bundle ID：`cn.edu.fudan.fudanElearning`；`UIDeviceFamily = [1, 2]`。
- 源提交：`f0faf44642788957d5514e10e19dd13bf1348541`。
- SHA-256：`eb2831a5f34848b0fc3ab8f1d5ccbc0c5078da817c737abe1be93ea55ca859f3`。重新计算的大小与哈希均匹配 manifest 和 SHA256SUMS，ZIP 完整，包含 `Payload/NativeRunner.app`。
- 构建使用 `CODE_SIGNING_ALLOWED=NO`。已产出未签名构建包，但没有签名、安装或真机运行证据。

## 仍未验证与审阅建议

真实 eLearning/iCourse 账号登录、真实课程数据及网络同步、真实模型请求与计费、通知权限与实际投递、IPA 签名后在 iPhone/iPad 真机安装和运行，均未由本次 CI 验证。

复习 UI 自动化仅覆盖创建计划与知识点。自测答案、修改掌握程度、跨课程排期预览及确认生成任务、完成/撤销/锁定、AI 同意发送/取消/继续/编辑保存，以及账号或来源变化时的完整界面交互，尚无本次 UI 测试证据。部分领域规则已有上述单元测试，但不能替代界面端到端验证；尤其预算合并用例的两份计划使用同一个 courseID，不能把它描述为多课程分配场景已验证。复习页面的深色模式、动态字号、横竖屏及 iPad 分屏也未由该复习 UI 用例覆盖。

建议可据此进入 ready for review 的代码审阅阶段：原先“等待 Xcode / iPad 验证”的阻塞已有成功 CI 证据，未验证事项应作为后续验收清单保留。是否转为 ready 由维护者审阅决定；PR 当前保持 draft，base 为 `codex/course-review-20261108`，本次仅更新验证记录与 PR 元数据，没有合并或发布。
