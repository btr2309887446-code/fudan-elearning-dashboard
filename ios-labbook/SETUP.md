# 自用 iOS App 上线流程（不公开、不上架）

目标：把一个自己写的 iOS App 装到自己 iPhone 上，只有自己用，不进 App Store。

---

## 一、先接受三个硬约束

这三条是苹果的规则，绕不开，先知道就不会中途踩坑。

### 1. 免费 Apple ID：签名 7 天过期

用免费 Apple ID 签名，App 的有效期只有 **7 天**。到期后点图标会直接闪退，不是 App 坏了。

- 续期方法：连上 Mac，Xcode 里按一次 ▶ Run，就续上 7 天
- 不需要重新配置任何东西，Build 一次即可
- 免费账号同时最多 3 个 App ID，装多了删掉旧的

### 2. 免费账号只有 7 天；付费 $99/年 是 1 年

如果嫌 7 天一续太烦：

| 方案 | 费用 | 签名有效期 | 附加好处 |
|---|---|---|---|
| 免费 Apple ID | 0 | 7 天 | 无 |
| Apple Developer Program | $99/年 | 1 年 | 可用 TestFlight，装到多台设备，不用连电脑 |

**建议**：先免费走通全流程，确认自己真的会持续写，再决定要不要花这 $99。

### 3. 云 Mac 必须能连你的 iPhone

相机、蓝牙、HealthKit 这类原生能力**在模拟器里完全没有**，必须真机。
所以你要在租机器时确认：**这个云 Mac 支持连接物理 iOS 设备**（有些商家提供 USB 透传/设备直通，下单前问清楚）。

---

## 二、租云 Mac 前必须确认的清单

下单前把这 6 条问清楚，否则钱白花：

- [ ] **macOS 版本 ≥ 26.2**（否则装不了当前 Xcode）—— 最重要
- [ ] Xcode 是否已预装，版本多少（要 26.x）
- [ ] 磁盘剩余空间 ≥ 60 GB（Xcode + 模拟器很占地方）
- [ ] **能否连接物理 iPhone**（USB 透传 / 设备直通）
- [ ] 计费方式：按小时还是按月（按小时更适合你这种"一周编译一次"的用法）
- [ ] 是否支持持久化存储（否则关机后工程和 Xcode 都没了，每次要重装）

---

## 三、推荐工作流：本地写代码，云 Mac 只编译

云 Mac 又贵又卡，**不要在上面写代码**。正确分工：

```
Windows（你现在的机器）         云 Mac
├─ 写 Swift 代码          ──→    ├─ git pull
├─ 本地 Git 提交                 ├─ Xcode 打开
└─ push 到 GitHub                ├─ 连 iPhone，Run
                                 └─ 断开，关机省钱
```

好处：
- 云 Mac 按小时计费，一周只需要开 1~2 次，每次 20 分钟
- 代码在本地有完整历史，不怕云机器回收
- 在本地就能让 AI 帮你写和改代码

### 首次搭建

1. 本地建 Git 仓库并推到 GitHub（私有仓库即可）
2. 云 Mac 上 `git clone`
3. 在云 Mac 上按 `README-BUILD.md` 建 Xcode 工程、把源文件拖进去
4. 连 iPhone，选自己的设备，点 Run

---

## 四、iPhone 端要做的准备（首次）

1. **设置 → 隐私与安全性 → 开发者模式 → 打开**（第一次传 App 后才会出现这一项），然后重启手机
2. 手机连上 Mac 后，手机上点「信任此电脑」
3. 第一次打开自签 App 会提示「未受信任的开发者」：
   **设置 → 通用 → VPN 与设备管理 → 信任你的 Apple ID**

---

## 五、Xcode 里签名的具体操作（首次）

1. Xcode → Settings → Accounts → 左下角 `+` → 登录你的 **免费 Apple ID**
2. 打开工程，左侧点最顶上的工程图标
3. 选 **TARGETS → 你的 App → Signing & Capabilities**
4. 勾上 **Automatically manage signing**
5. **Team** 选你的个人团队（显示为 `你的名字 (Personal Team)`）
6. **Bundle Identifier** 改成全球唯一的，比如 `com.你的名字.labbook`
   - 冲突就换一个，免费账号 7 天内不能重复用同一个 ID
7. 顶部设备栏选你的 iPhone（不要选模拟器），点 ▶ Run

第一次会弹钥匙串授权，输入 Mac 登录密码，选 **始终允许**。

---

## 六、Apple ID 双重验证（必做）

如果不做这一步，Xcode 登录会直接失败：

1. 先在 **浏览器里**登录 [appleid.apple.com](https://appleid.apple.com)
2. 开启**双重认证**，绑定手机号
3. 登录 Xcode 时若提示需要验证码，直接在 iPhone 上读取并输入

---

## 七、常见报错对照表

| 报错 | 原因 | 解决 |
|---|---|---|
| `Failed to register bundle identifier` | ID 被占用 | 换一个 Bundle ID，加随机后缀 |
| `Untrusted Developer` | 手机没信任证书 | 设置 → 通用 → VPN 与设备管理 → 信任 |
| App 图标点了闪退 | 7 天签名过期 | 连 Mac 重新 Run 一次续期 |
| `No profiles for 'xxx' were found` | 签名配置问题 | 确认勾了自动签名 + 选对 Team |
| 找不到 iPhone 设备 | 云 Mac 没透传 | 确认云商家支持物理设备连接 |
| `Xcode requires macOS 26.2 or later` | 云 Mac 系统太旧 | 换机器，下单前必须先确认版本 |
| 编译报 `Cannot find 'XxxView' in scope` | 文件没加进 target | 选中文件，右侧 File Inspector 勾上 Target Membership |

---

## 八、什么时候可以不租云 Mac

如果你后面发现**只需要 UI 和数据逻辑**，不需要相机/蓝牙/健康数据：

- 模拟器就能看到 90% 的效果，但**模拟器也只能在 macOS 上跑**
- 替代方案：把 App 改成网页版（PWA）加桌面图标，Windows 上就能做完，零成本
- 但这个方案拿不到原生相机、蓝牙、HealthKit

所以选哪条路，取决于你对原生能力的依赖程度。
