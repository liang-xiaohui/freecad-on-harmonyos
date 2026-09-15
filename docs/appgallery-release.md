# AppGallery 上架清单（FreeCAD on HarmonyOS）

AGC 侧登记的信息：

| 项 | 值 |
| --- | --- |
| 应用类型 | HarmonyOS 应用 |
| 应用名称 | FreeCAD |
| APP ID | `6917614499915791877` |
| 应用包名 | `com.liangxiaohui.freecad` |
| 支持设备 | 手机（**项目已决定只发 PC/2in1**，AGC 勾选范围必须 ≤ 包内声明范围） |
| 默认语言 | 简体中文 |

本仓库当前状态：包名已对齐、`deviceTypes` 收敛为 `["2in1"]`（PC-only）、权限声明
`INTERNET` + `READ_PASTEBOARD`（ACL 已获批并已进签名 Profile）、签名仍用 **debug** 材料。
构建已恢复绿，新包已装上真机，启动时运行时权限申请返回 `authResults=[0]`。

---

## 1. 包名（已改）

`AppScope/app.json5` 的 `bundleName` 从 `com.freecad.headless.acceptance` 改为
`com.liangxiaohui.freecad`（历史遗留的 acceptance 名字在 AGC 上不存在）。同一字符串还出现在：

- `scripts/install-gui-hap.sh`（`BUNDLE` 默认值）
- `docs/device-run-guide.md`、`docs/handoff-device-steps.md`、`AGENTS.md` 的 `aa start -b ...`

**副作用（必须知道）**：签名 Profile 里也带着 `bundle-name`，改名后本机证书立即失效，
构建在 `SignHap` 阶段失败：

```
00303074 Configuration Error
The bundleName in app.json5/hvigorfile.ts does not match the bundleName in
the generated SigningConfigs. At file: build-profile.json5
```

修复入口有两个，**实测走的是第二条**：

1. DevEco：`File > Project Structure > Signing Configs > Fix`（自动签名，按新包名重签）。
   注意自动签名**会沿用申请前已存在的 Profile**，ACL 不会因此带上（见第 3 节）。
2. AGC 手动新建调试 Profile：勾设备 + 勾「申请受限权限」→ 下载 `.p7b` →
   手工填进 `build-profile.json5`（`profile` 指向 p7b，`certpath`/`storeFile` 指向
   **该 Profile 绑定的那张调试证书**的 `.cer`/`.p12`）。

**实测结果**：新 Profile 的 `bundle-name=com.liangxiaohui.freecad`、
`app-identifier=6917614499915791877`、`acls.allowed-acls=["ohos.permission.READ_PASTEBOARD"]`、
`debug-info.device-ids` 只剩 1 条 = 本机 UDID `本机 UDID（不记录）`。构建
`Finishing :entry:default@SignHap` 通过，`bm install` 成功，启动后 hilog 出现
`QAbility: READ_PASTEBOARD requested -> authResults=[0]`（PC/2in1 不弹框，系统直接授予）。

**一个易踩的坑**：AGC 里可以选的历史调试证书很多（每建一次工程/证书就多一张），
Profile 绑的是哪张，本地就必须用哪张 `.cer`+`.p12`。这次 Profile 绑的正是
`cloudcompare-on-harmonyos` 那张（序列号 `（序列号不记录）`，签发于
2026-09-08），所以 `build-profile.json5` 现在指向
`~/Documents/ohos/config/default_cloudcompare-on-harmonyos*.{cer,p12}`。
用 `scripts/check-signing-profile.py` 能看出 Profile 与工程是否对得上，但**看不住证书**；
对不上时 `SignHap` 会报签名错误（私钥与证书不匹配）。若不希望跨工程共用，就在 AGC 用
本工程的 `.csr` 新建一张调试证书，再重新签发 Profile。

设备上旧包的数据（含 `freecad-home/`）不会被继承，旧包可以直接卸载：
`bm uninstall com.freecad.headless.acceptance`。

## 2. 设备类型

规则（华为官方答复，`architecture-guides/tools-v1_2-ts_128-...`）：**包内 `deviceTypes`
声明的范围必须 ≥ AGC 上勾选的"支持设备"范围**。AGC 勾选范围更大时，上传软件包会被拒：
"上传的软件包与声明支持设备不一致，请重新上传或修改可支持设备"。反向（包内多声明）
是允许的。

另一条要记住的限制：**应用发布后，AGC 上的支持设备只能增加、不能删除** —— 所以"先只发
PC、以后再扩手机"是合规且安全的顺序（增加设备类型本来就被允许）。

### 合法取值（别手写 `"pc"`）

官方 `deviceTypes` 枚举（device.harmonyos.com 的 module.json5 文档）：`phone` / `tablet` /
**`2in1`（PC/2in1）** / `tv` / `wearable` / `car` / `default`。HarmonyOS PC（MateBook）
上报的就是 **`2in1`**，**没有 `"pc"` 这个值**，实测写 `["2in1","pc"]` 直接构建失败：

```
hvigor ERROR: Failed :entry:default@PreBuild
hvigor ERROR: 00303038 Configuration Error
Schema validate failed ... instancePath: 'module.deviceTypes[1]',
keyword: 'enum', params: { allowedValues: ['default','tablet','tv','wearable','car','2in1'] }
```

（顺带一个反例警告：这个报错打印出来的 `allowedValues` 里居然没有 `phone`，但
`["phone","tablet","2in1"]` 实测打包通过 —— 说明这条报错的枚举来自另一套 schema 分支，
别拿它当权威取值表，以官方文档为准。）

### 两种可选配置

| 方案 | `deviceTypes` | AGC 勾选 | 适用 |
| --- | --- | --- | --- |
| 只发 PC | `["2in1"]` | PC/2in1 | 当前推荐：开发机就是 2in1，无需手机适配素材 |
| 手机 + PC | `["phone","tablet","2in1"]` | 手机 / 平板 / PC-2in1 任意子集 | 想一次覆盖多端 |

**切换前必须核对 AGC 当前勾了什么**：包内声明一旦比 AGC 勾选窄，上传即被拒。已经勾了
"手机"就不能单方面把包收窄成 `["2in1"]`，要么在 AGC 取消勾选（发布前可以改），
要么保留 `phone`。

PC-only 时 `tablet` 可以不留；只有在"想保开发机兼容"或"AGC 还勾着平板"时才需要它。

### 平板：首版不上的决策记录（2026-09-15）

结论：**首版只发 PC/2in1，不声明 `tablet`**。依据分三层，从规则到实现都有硬证据。

**第一层，华为自己的口径就推荐这么做。** 官方《鸿蒙应用审核 FAQ》第九条原文：

> 系统提示"检测到您的应用已适配平板设备，请在'应用信息页面-支持设备'中勾选平板设备"。
> 然而勾选后再次提交审核，却因存在平板端适配问题被驳回。该如何修改？
> **答**：……如暂无多端部署计划，建议您排查包体中的 devicetype 字段是否存在 tablet 类型，
> **可将 devicetype 中的 tablet 类型删除后再尝试提交上架**。

也就是说，"没做平板适配就别声明 tablet"是官方给的解法，不是我们在绕开要求。

**第二层，PC 和平板是两套互不相通的要求，本工程只满足其中一套。**

| PC / 2in1 审核要点 | 本工程 | 平板《多设备体验设计标准》 | 本工程 |
| --- | --- | --- | --- |
| 可交互元素需有鼠标悬停 + 点击反馈 | 满足（预选高亮是 FreeCAD 固有行为） | 点击热区 ≥ 48vp 推荐 / **≥ 40vp 必须** | **不满足** |
| 标准窗口控制（最小化/最大化/还原/关闭） | 满足（Qt 窗口栈天然具备） | 底部导航条避让 | 未做 |
| 合理场景提供右键菜单 | 满足（大量上下文菜单） | 竖向悬浮窗 / 左右分屏 / 上下分屏且能跑完全流程 | 未做 |
| 常用操作快捷键 | 满足（Ctrl+C/V/S…） | 离手减速动效一致性（可滑动页面） | 不适用 |
| 键鼠交互热区 ≥ 5mm | 满足 | 横竖屏与全屏切换 | 未做 |

热区这条有具体数字可对：`src/Gui/ToolBarManager.cpp:474` 的 `ToolbarIconSize` **默认 24**
（可选档 16/24/32），即 24vp 左右，**低于平板 40vp 的下限**，离 48vp 推荐值差一倍。
分屏这条更硬：dock 面板最小宽度约 **634 逻辑像素**（来自 freecad-ai `ui/chat_widget.py`
顶栏），平板左右分屏后单侧只有 400~500vp，**物理上放不下**。

**第三层，触摸链路上有真实的 QPA 缺口 —— 不是"体验差"，是"做不到"。**
查 Qt 6.8.3 OHOS QPA（`qtbase/src/plugins/platforms/ohos/qohosinputmethodeventhandler.cpp`）：

- **滚轮事件只认鼠标和触控板**：`UI_INPUT_EVENT_TOOL_TYPE_MOUSE` 与 `TOUCHPAD` 各有一条
  分支，**`TOUCH` 落到 `else` 直接 `return`**（打 `Received unsupported input event tool
  type … skipping`）。⇒ 平板上**手指无法滚动列表、无法缩放视图**。对 FreeCAD 意味着
  参数面板、模型树、3D 视口缩放一并失效。
- **触摸不合成鼠标**：走 `onTouchEventFromXComponent()` → `QWindowSystemInterface::
  handleTouchEvent()`，交给 Qt 的是原生 `QTouchEvent`。Qt 层会把单指触摸合成为鼠标左键，
  于是：**没有 hover**（FreeCAD 的预选高亮永远不亮）、**没有中键/右键拖动**（3D 视图
  旋转/平移的默认操作没了）、手指精度选不中顶点和边。

这三条叠起来，平板版不是"再调调布局"就能交付的，而是要给 Qt 加补丁（触摸滚轮/手势）+
重做交互热区 + 改 freecad-ai 的最小宽度 + 导航条与分屏适配，属于一轮独立的工作量。

**什么时候值得做**：若确实要覆盖平板，优先级是 ① Qt 侧补触摸滚轮分支（否则连列表都滑
不动）② 热区达标 ③ 导航条避让与分屏。① 是"能不能用"的门槛，③ 是"会不会被拒"的门槛。
更稳的节奏是**等 PC 版第一次审核通过、商店页面立住之后再单独立项**。

**一个连带风险**：华为的分发规则里，AGC 勾了"手机"时，**即便包内没声明 tablet，也会以
兼容模式默认分发到平板**。所以将来若把 `phone` 加回来，平板会被顺带覆盖（兼容模式下布局
拉伸，反而是审核风险）——平板这件事必须主动决策，不能当赠品捎带。

## 3. 权限与 ACL

权限等级决定要不要 ACL：`availableLevel ≤ 应用 APL` 的权限普通声明即可；**高于 APL 的
"受限权限"必须走 Profile ACL**。本应用 APL = `normal`（当前调试 Profile 实测
`"apl": "normal"`）。

| 权限 | availableLevel | grantMode | 需 ACL？ | 本工程用途 |
| --- | --- | --- | --- | --- |
| `ohos.permission.INTERNET` | `normal` | `system_grant` | 否 | freecad-ai 调 LLM |
| `ohos.permission.READ_PASTEBOARD` | `system_basic` | `user_grant` | **是** | 应用内 Ctrl+V 粘贴 |

（权限表来源：`$OHOS_SDK/ohos/toolchains/lib/PermissionDefinitions.json`，753 条。
没有 `WRITE_PASTEBOARD` 这个权限。）

**为什么"粘贴没反应"就是这条权限**：Qt 的 OHOS 剪贴板插件走原生 C API
（`qtbase/src/plugins/platforms/ohos/qohosclipboardobject.cpp`，`#include
<database/pasteboard/oh_pasteboard.h>`）。读取路径是
`tryGetUdmfDataFromPasteboard()` → 先 `OH_Pasteboard_HasData()`，为 false 直接
`return nullptr`（连 `OH_Pasteboard_GetData` 都不调用）。没有 `READ_PASTEBOARD` 时
`HasData` 返回 false，剪贴板在 Qt 眼里就是空的，Ctrl+V 用空数据替换选区 —— 表现就是
"粘贴没反应/选区被清空"，且**没有任何报错**。

### 申请门槛（PC-only 路线上的好消息）

华为《受限开放权限》对这条权限写得很明确：

- **"PC/2in1 设备上的应用均可申请"**（其他设备类型才需要论证"银行卡号/口令/文档编辑/
  输入法"等特定场景）。本工程 `deviceTypes = ["2in1"]`，正好落在最宽松那一档。
- **"申请后立即通过"** —— 不像其他受限权限要等 3 个工作日。
- **"在 PC/2in1 设备上，应用首次申请剪贴板权限时不会向用户弹窗申请，系统默认授予
  '允许'"**，用户可事后在「设置 > 隐私与安全」改。也就是说 PC 上不会出现授权弹框，
  但 `requestPermissionsFromUser` 这个调用仍然要发（它才是触发系统授予的动作）。
- 上架时 AGC 会按使用场景复核受限权限，需要**逐条填写权限说明并上传场景视频**。我们的
  理由天然成立：应用基于开源框架（Qt/FreeCAD）自绘控件，**无法使用系统粘贴控件**，
  官方把这列为允许申请的场景之一。

### 工程侧改动（已完成）

- `module.json5` 的 `requestPermissions` 增加 `READ_PASTEBOARD`（`reason` 指向
  `$string:reason_read_pasteboard`，`usedScene.abilities = ["QAbility"]`，`when = inuse`）。
- `entry/src/main/resources/base/element/string.json` 增加 `reason_read_pasteboard` 文案。
- `QAbility.ets` 新增 `requestPasteboardPermission()`，在 `onWindowStageCreate()` 里
  fire-and-forget 调用：先 `checkAccessTokenSync()` 看是否已授权，未授权才
  `requestPermissionsFromUser()`，结果写 hilog（`READ_PASTEBOARD requested ->
  authResults=[0]` 表示已授予）。

**顺序铁律**：先在 AGC 通过 ACL 申请、重新签发 Profile，**再**回工程声明权限。

- 反序（先声明，Profile 里没有 ACL）→ **所有** HAP 安装失败，错误 9568289
  （`install failed due to grant request permissions failed`）。
- 用非 AGC 渠道签发的 Profile → 9568322。

**ACL 通过 ≠ 立刻生效**：`acls.allowed-acls` 写在 Profile 里，**必须重新签发一次
Profile**才会带上。DevEco 的自动签名若沿用申请前已存在的 Profile，就不会包含 ACL ——
表现为"审批通过了但装上去还是没权限"。验证方式（**装之前先跑，别靠安装失败来发现**）：

```bash
./scripts/check-signing-profile.py
# 读 build-profile.json5 里正在用的 p7b，检查 bundleName 是否等于工程的，
# 以及 module.json5 声明的每条权限：availableLevel 高于 apl 的必须出现在
# acls.allowed-acls 里，否则退出码 1 并点名（对应安装报 9568289）。
# 不需要 java：p7b 载荷就是里面一段 OCTET STRING，脚本自己遍历 DER + 解 zlib。
```

期望：`bundle-name: com.liangxiaohui.freecad`、`acls: ['ohos.permission.READ_PASTEBOARD']`，
末行 `✓ Profile 与工程一致，受限权限齐备。`。
（`hap-sign-tool verify-profile` 也能看，但本机所有 `hap-sign-tool.jar` 都是 1~2 KB 的
bridge 壳，跑不起来，所以用上面的脚本。）

若自动签名没带上：AGC →「证书、App ID 和 Profile」→ Profile 管理 → 新增（类型=调试）→
选证书、勾设备、勾「申请受限权限」里的 `READ_PASTEBOARD` → 下载 `.p7b` →
在 DevEco 手工配置签名。审批完成前 AGC 会给一个**有效期短的临时 Profile**（社区反馈约
5 天），够本地联调但**不能用于上架**。

## 4. 签名

`build-profile.json5` 只有一套 `default`（**debug**）配置；**该文件在 `.gitignore` 里**，
签名材料都在 `~/Documents/ohos/config/`。当前生效的一套（2026-09-15 重签后）：

| 项 | 值 |
| --- | --- |
| profile | `~/Documents/ohos/config/default_freecad-on-harmonyos-acl-debug.p7b`（AGC 下载，含 ACL） |
| bundle-name | `com.liangxiaohui.freecad` |
| app-identifier | `6917614499915791877` |
| acls | `["ohos.permission.READ_PASTEBOARD"]` |
| device-ids | 1 条 = 本机 UDID `本机 UDID（不记录）` |
| cert / key | `default_cloudcompare-on-harmonyos*.cer` / `.p12`，密钥别名 `debugKey` |

**为什么证书用的是 cloudcompare 那套**：AGC 里 Profile 必须绑定一张调试证书，这次新建
Profile 时选中的是 2026-09-08 签发的那张（序列号 `（序列号不记录）`），
它的私钥在本机只存在于 cloudcompare 那套 `.p12` 里，所以 `certpath`/`storeFile` 指过去、
口令沿用它的（`storePassword`/`keyPassword` 是 DevEco 加密串，跨工程可直接复用）。
hvigor 会校验"证书公钥 == .p12 私钥"，配错在 `SignHap` 阶段直接失败。

若不想跨工程共用材料：在 AGC 用本工程的 `.csr` 新建一张调试证书，重新签发 Profile，
再把三件套（p7b/cer/p12）都指回本工程的文件。

改动前的旧材料（`default_freecad-on-harmonyosjQeoJc1u7….p7b`）绑的是旧包名
`com.freecad.headless.acceptance` 且 `acls: []`，已作废 —— 那时构建报的就是：

```
00303074 Configuration Error
The bundleName in app.json5/hvigorfile.ts does not match the bundleName in
the generated SigningConfigs
```

备份留在 `codex-freecad-artifacts/appgallery-20260915/old-profile-no-acl.p7b`。

**Profile 到期 / 换机 / 换包名时的动作**：AGC 重新签发 → 下载 p7b → 覆盖
`default_freecad-on-harmonyos-acl-debug.p7b` → 跑 `./scripts/check-signing-profile.py`
（退出码 0 才继续）→ 重建 HAP → 重装。**换设备必须把新 UDID 勾进 Profile**
（`debug-info.device-ids` 是设备白名单），否则装不上。

上架要用的**发布**材料完全是另一套（AGC → 证书、App ID 和 Profile 管理）：

1. 创建发布证书（.cer，配本机 .p12 私钥）；
2. 用发布证书 + 新包名创建发布 Profile，ACL 获批后在这里勾选 `READ_PASTEBOARD`；
3. 在 `build-profile.json5` 增加 release 签名配置，`BUILD_MODE=release` 出包。

## 5. 图标：PC/2in1 同样必须分层（已完成）

**权威依据**是华为《通用应用 UX 体验标准》2.1.4.3.1，标准等级 **必须**：

> 应用图标资源必须分为前景图和背景图两层，尺寸要求必须为 1024 px * 1024 px，资源不允许
> 自行裁切圆角，不允许在资源内添加内间距，应用图标的背景图不允许含有透明像素。

**适用设备类型明确包含"电脑"**（手机、折叠屏、平板、**电脑**、智慧屏）。所以这不是只针对
手机的软要求 —— 本文档上一版把它判定为"PC 路线下的建议项"是错的，已更正。

**"不允许含透明像素"管的是两张图，不只是背景层。** 华为《上架检测 FAQ · 应用图标》原文：

> 应用图标的背景图不允许含有透明像素（包括圆角裁切或带有透明内边距的情况）。
> **AppGallery Connect 提审页面上传的图标 / 包体内配置的图标，均不允许含透明像素。**

三个角色、两种相反的透明要求，别混：

| 角色 | 透明要求 | 本项目的实测值 |
| --- | --- | --- |
| 分层**前景** `foreground.png` | **必须**有透明区域 | alpha `0~255`，307749 个全透 + 1429 个抗锯齿半透 |
| 分层**背景** `background.png` | **必须**全不透明 | alpha `255~255`，0 个透明像素 |
| **AGC 上传图** `freecad-appgallery-1024.png` | **不允许**含透明像素 | alpha `255~255`，0 个透明像素 |

判据是 **alpha 极值**，不是肉眼——"看着像实心"的图常年带着几千个半透明抗锯齿像素而被驳回。
自查一行搞定：

```sh
python3 -c "import sys;sys.path.insert(0,'tools/icon');import pngtool as P;\
w,h,p=P.read_png('store-assets/icon/freecad-appgallery-1024.png');\
a=sorted(set(p[3::4]));print(f'{w}x{h} alpha {a[0]}~{a[-1]} 透明像素{p[3::4].count(0)}个')"
```

例外：**手表**那一档（《Asset Specifications》Watches）要求"上传背景透明的正方形图标"，
与上述结论相反；本项目只发 PC/2in1，不适用。

四条硬约束，照做即可，别自作聪明：

| 约束 | 含义 |
| --- | --- |
| 前景 + 背景两层，各 1024×1024 | 不是一张合成图 |
| **不自行裁圆角** | 遮罩由系统加；自己裁了会被二次裁切，出白边/黑边 |
| **不加内间距** | 图形撑满画布，不要人为留边 |
| 背景层**不允许含透明像素** | 背景必须是实心不透明图（或 `$color:`） |

AGC 上传图按《素材规范》PC/2in1 档：1 张，**216×216 或 1024×1024**，PNG ≤ 3MB，
**必须正方形**。上传的那张是"合成图"（前景叠在背景上），且要与包内显示的图标一致。

### 已落地的资源

| 文件 | 位置 | 说明 |
| --- | --- | --- |
| `foreground.png` | `AppScope/resources/base/media/` 与 `entry/src/main/resources/base/media/` | 透明底官方 logo，1024×1024，图形撑满（无内间距） |
| `background.png` | 同上 | 纯色 `#1F2430`，1024×1024，**完全不透明** |
| `layered_image.json` | 同上 | `{"layered-image":{"background":"$media:background","foreground":"$media:foreground"}}` |

**两处都要放**：`app.json5` 的 `app.icon` 在 AppScope 作用域解析，`module.json5` 里 ability
的 `icon` 在 entry 模块作用域解析，各自都要能找到 `layered_image`。`startWindowIcon` 仍指向
单层 `$media:icon`（启动页图标不要求分层）。

```json5
// AppScope/app.json5
"icon": "$media:layered_image",
// entry/src/main/module.json5（QAbility 的 icon）
"icon": "$media:layered_image",
```

### AGC 上传用的图（`store-assets/icon/`）

| 文件 | 用途 |
| --- | --- |
| `freecad-appgallery-1024.png` | **上传这一张**：1024×1024、15.5 KB、PNG、正方形 |
| `freecad-appgallery-216.png` | 同一张图的 216×216 版本，备用 |
| `foreground-1024.png` / `background-1024.png` | 分层素材原样留档，方便以后用 DevEco 的 Image Asset 重新生成 |

**背景色为什么是 `#1F2430`**：官方 logo 由 FreeCAD 红 `#CB333B`、蓝 `#418FDE`、白 `#FEFEFE`
三色构成，白色 "F" 是主体之一。纯白/浅灰底会让白 F 与背景融为一体（红块视觉上被切成两片），
红底/蓝底会让同色元素消失，只有深色底能把三个元素全保住；而华为又要求背景**不透明**，
所以深色实心底是最优解。

> 想换背景色：把 `store-assets/icon/background-1024.png` 与两处 `background.png` 换成同色
> 重新生成，保持包内包外一致即可。生成脚本 `tools/icon/pngtool.py`——本机没有 Pillow，
> 也没有任何 SVG 渲染器，PNG 的读/写/缩放是纯 Python 手写的（`zlib` + `struct`）。

## 6. 版本号

当前 `versionCode: 1` / `versionName: "0.1.0"`。发布后 `versionCode` 只能递增；
首版建议对齐上游版本（例如 `versionName: "1.1.2"`、`versionCode: 1001002`）。这份数字会
同时出现在 AGC 版本页、包内元数据和更新说明里，三处要一致。

## 7. 审核可能问询的点（提前准备说明）

- **包内有大量 Python 脚本 + 内嵌 CPython 解释器**：`rawfile/python311.zip`、
  `rawfile/freecad-runtime.zip` 里是随包固定的 FreeCAD Python 模块，**不下载、不热更新、
  不执行外部代码**。hvigor 打包时已经给出警告
  `Unexpected source code files packaged in 'entry'`（指向
  `rawfile/freecad_headless_acceptance.py`）。建议随提审附一句说明。
- **INTERNET 权限用途**：freecad-ai 工作台访问用户自选的 LLM 端点。
- **隐私政策**：有网络访问 + 用户输入（含 API Key），需要提供隐私政策链接，并在其中说明
  Key 的存放位置（沙箱 `freecad-home/` 配置文件）。**正文已完成**，见下文「隐私政策」小节。
- 包内 185 个 `.so` 全部走 HAP `libs/`（保持签名），rawfile 里不放 native ELF。
- **PC-only 时还要过桌面交互这一关**（审核会在 PC 上实测）：鼠标悬停态、键盘快捷键、
  自由窗口的拉伸/最大化/最小化、不同分辨率与缩放下不出现固定尺寸或留白。本移植是
  Qt 桌面栈，菜单/快捷键/窗口缩放天然具备（QPA 已处理窗口装饰高度与像素密度），
  提审时可以在备注里点明这些桌面特性。
- **素材按勾选设备准备**：只勾 PC/2in1 就只需要 PC 分辨率的截图（3-5 张 16:9
  1920×1080，PNG/JPG ≤5MB，需真实界面截图、不能用模拟器截图），不需要手机竖屏截图。
- **真机截图天然不是 16:9**：《素材规范》PC/2in1 档写死"**16:9 / 1920×1080**"，而 2in1 窗口截图是
  **2472×1608**（≈1.537，3:2）；**拉伸/变形是审核明确禁止的**。已按"套图"方案解决 —— 见下一节。

### 应用截图：16:9 介绍套图（已完成 2026-09-15）

真机窗口截图是 3:2，直接缩放会变形、拉伸被明令禁止。参考 AppGallery 上成熟应用的通行做法
（如 WorkBuddy 的上架图），**不把截图当整张图上传，而是做成"标题 + 副标题 + 圆角截图卡"的介绍图**：
画布本身是严格的 1920×1080，截图按原始宽高比等比缩放进卡片，**几何上不可能变形**。

生成器在本仓库里，可随时改文案重跑：

```
tools/promo/render.js        # 纯 JS 渲染内核（画布/渐变/光晕/圆角遮罩/阴影/文字栅格化）
tools/promo/make_promo.js    # 版式与流水线
tools/promo/promo-copy.json  # 每张图的 kicker/标题/副标题/强调色/所用截图 ← 改这里即可
store-assets/screenshots/            # 输入：真机窗口截图（2472×1608）
store-assets/screenshots-16x9/       # 输出：5 张 1920×1080 PNG
```

```sh
node tools/promo/make_promo.js                # 全部重出
node tools/promo/make_promo.js --only 03      # 只重出第 3 张
node tools/promo/make_promo.js --contact-sheet  # 额外拼一张预览（写 artifacts，不进仓库）
```

**为什么是手写渲染而不是用现成库**：本机没有 Pillow、没有 ImageMagick、没有 ffmpeg、没有
`canvas`，`sharp` 也只装了壳（`@img/colour`，缺 libvips 平台包）。真正能用的是三个纯 JS 包
`jpeg-js`（解 JPEG）+ `pngjs`（编解码 PNG）+ `opentype.js`（取字形轮廓），字体用系统自带的
`/system/fonts/HarmonyOS_Sans_SC.ttf` —— 恰好就是鸿蒙自己的字体，做出来天然是鸿蒙味。
没有粗体就用"填充 + 沿轮廓描边 `size*0.024`"做仿粗体，实测在 46px 中文标题上肉眼无差。
依赖路径可用 `PROMO_JPEG_JS` / `PROMO_PNGJS` / `PROMO_OPENTYPE` 覆盖。

**5 张的内容与顺序**（文案与截图逐张对应，不写截图里没有的东西）：

| # | 主题 | 截图 | 强调色 |
| --- | --- | --- | --- |
| 01 | 参数化建模 · 改尺寸就改模型 | PartDesign 特征树 + 实体 | `#4A9EFF` |
| 02 | 草图约束 · 拖一下就变形 | Sketcher 尺寸/角度约束 | `#2FD4A8` |
| 03 | 仿真分析 · 算完直接看云图 | FEM 应力云图 | `#FFB020` |
| 04 | 建筑设计 · 体块与图纸同源 | BIM 建筑模型 + 构件树 | `#A78BFA` |
| 05 | 工程图 · 三维自动出二维 | TechDraw A3 图纸 | `#5AD1F0` |

版式固定：左上品牌（logo + `FreeCAD` + `for HarmonyOS PC`）、右上 `01 / 05` 页码、
居中"英文 kicker + 中文主标题 + 中文副标题"、下方圆角截图卡（带 1px 描边 + 顶部强调色高光 +
投影 + 强调色外发光）、背景是深色渐变 + 蓝图网格 + 四角制图括号 + 左侧标尺 + 等轴测线框立方体。
**每张只换强调色与文案，版式完全一致**，这样才像一套。

实测规格（全部满足，且远低于上限）：

| 文件 | 尺寸 | 比例 | 大小 |
| --- | --- | --- | --- |
| `freecad-agc-01-parametric-1920x1080.png` | 1920×1080 | 1.7778 | 371 KB |
| `freecad-agc-02-sketcher-1920x1080.png` | 1920×1080 | 1.7778 | 259 KB |
| `freecad-agc-03-fem-1920x1080.png` | 1920×1080 | 1.7778 | 403 KB |
| `freecad-agc-04-bim-1920x1080.png` | 1920×1080 | 1.7778 | 457 KB |
| `freecad-agc-05-techdraw-1920x1080.png` | 1920×1080 | 1.7778 | 407 KB |

**两点提审口径**：

1. 卡片里放的是**真机窗口截图的原样等比缩放**（含窗口标题栏、菜单栏、状态栏），没有拼接、
   没有合成不存在的界面元素，符合"真实界面截图、不能用模拟器截图"的要求。
2. 另有 3 张备选原图可换（`184104`/`184108` 首次启动设置、`184534` Draft 三维剖切、
   `184629` Draft 二维图元、`184116` 开始页）——AGC 每档最多 5 张，如要替换只改
   `promo-copy.json` 里的 `shot` 再重跑即可。

### 应用分类与标签（AGC 填写项）

权威来源是华为分类表《鸿蒙应用分类及其应用标签》
（`developer.huawei.com/consumer/cn/doc/app/classify-1`）：一级分类 → 二级分类 → 应用标签。
AGC 的「管理标签」对话框按一级分类分组，**最多 5 个，可以跨分类选**（"相关分类"下拉默认
"全部"，切到具体分类可只列该分类下的标签）。

FreeCAD 的标签建议（已选 3 个，留 2 个余量）：

| 标签 | 所属分类 | 理由 | 状态 |
| --- | --- | --- | --- |
| `工具` | 工具 | 主定位，桌面工程工具 | 已选 |
| `设计` | 艺术与设计 | 参数化建模、工程图、装配 | 已选 |
| `AI` | 工具 | 内置 FreeCAD AI 工作台（LLM 对话） | 已选 |
| `效率` | 商务 | 生产力/效率工具定位 | 建议补 |
| `学习` 或 `设计学习` | 教育 / 艺术与设计 | 面向学生与自学用户，CAD 是典型学习型软件 | 建议补 |

不建议凑满：标签与实际功能不符会被判定"功能描述与实际不符"，宁缺毋滥。**尤其注意 `AI`
标签**——它会把应用暴露给关注 AI 能力的用户，若应用内提供 LLM 对话，审核可能追问生成式
AI 相关资质或说明。我们的实际情况是"用户自带 API Key 调用第三方端点、不自建生成式服务"，
提审说明里要写清这一点（与第 7 节 INTERNET 权限的说明合并即可）。

### 应用介绍与一句话简介（AGC 填写项，已完成 2026-09-15）

提交文案在 **`store-assets/appgallery-text-zh-CN.txt`**，纯文本、可直接全选复制，分两段：
一句话简介（≤17 字，推荐"开源三维CAD，参数化建模出图"共 15 字）与应用介绍（1848 字符，
上限 8000，用量不足四分之一，不必凑字数）。

文案的事实口径都是**从包里核对过的**，不是照着上游宣传页抄的：

| 写法 | 依据 |
| --- | --- |
| 基于 FreeCAD 1.1.2 移植、Qt 6 + OpenGL ES | `share` 与 `Mod` 来自 v1.1.2 前缀；`QPA` 走原生 GLES |
| 工作台清单（Part/PartDesign/Sketcher/Assembly/TechDraw/Surface/Draft/Mesh/Points/Inspection/BIM/Fem/CAM/Spreadsheet/Measure/Material/Robot/AddonManager/freecad-ai） | `freecad-runtime.zip` 里 `Mod/` 实际存在的目录 + `libs/` 里有对应的成对 `<Mod>.so` / `<Mod>Gui.so`（逐个对过），**空壳不算数**。**MeshPart、OpenSCAD、Web、Plot、Raytracing 不在包里，所以一个字都没提**。Assembly 的具体能力（关节、求解、运动仿真、BOM）是照 `Mod/Assembly/Command*.py` 的实际命令写的，没有照抄宣传页 |
| **ReverseEngineering 被剔除出文案** | 它的 `InitGui.py` 只有 `class ...Workbench` + `import ReverseEngineeringGui`，目录下除 `Init.py`/`InitGui.py` 外**没有任何实现文件**，上游长期处于 legacy 状态；`.so` 虽在，但没有可验证的可用工具。宁可不写，也不给审核留下"功能描述与实际不符"的口子 |
| 文件格式（FCStd/BREP/STEP/IGES/STL/OBJ/PLY/AMF/3MF/DXF/SVG） | 逐个核对**依赖**，不是只看代码里有没有字面量：`importDXF.py` 里 `ezdxf` 出现 **0 次**（FreeCAD 1.x 自带纯 Python 的 legacy DXF 读写器）⇒ 可用；`Mod/Mesh`、`Mod/Part` 的对应实现均为 C++ 或纯 Python ⇒ 可用 |
| **DWG、IFC 被明确排除** | 两个都是"代码在、依赖不在"：`importDWG.py` 只是薄壳，要调 **ODA File Converter / LibreDWG** 外部可执行文件（找 `/usr/bin/ODAFileConverter`、`%ProgramFiles%\ODA\...`），包内没有；`importIFC.py` 自己的 docstring 写着 "Internally it uses **IfcOpenShell**, which must be installed before using"，而 `Ext/` 里只有 `PySide/PySide6/shiboken6/pivy/numpy/yaml/packaging/lazy_loader/freecad`，`python311.zip` 里也没有 ⇒ 设备上不可用。文案里整段删掉，并在"使用说明"里主动声明一次 |
| Python 3.11 控制台 | 包内 `rawfile/python311.zip` 与 OHOS CPython 3.11.4 |
| **界面语言为简体中文（默认，可切换）** | ⚠️ 这里曾判错过一次。磁盘上确实没有核心翻译：全包 117 个 `.qm` **全部来自 `Mod/AddonManager/`、`Mod/BIM/`、`Mod/freecad-ai/`**，`share/translations/` 不存在，`FreeCAD_zh-CN.qm` 一个都没有。但**译文并不需要以文件形式存在**：`patches/freecad-1.1.2/headless-translations.patch` 改的就是 `src/*/CMakeLists.txt` 里的 `qt_find_and_add_translation` + `qt_create_resource_file` + `qt_add_resources`，把 `.ts`→`.qm` **编译进每个模块库的 Qt 资源**；`ohos-default-language.patch` 再把 OHOS 下的默认语言硬设为 `Chinese (Simplified)`。所以 `libFreeCADGui.so`/`PartDesignGui.so`/`StartGui.so` 里能直接搜到 UTF-16BE 的 `文件`/`草图`/`零件设计`/`欢迎使用`，另外还嵌了法/日/俄等语言（实测命中 `Fichier`/`ファイル`/`Файл`）。**真机截图（用户提供的 10 张）处处是中文菜单，是最终判据** |
| 工作台名称与对象名仍为英文 | 工作台下拉框（Part Design / Sketcher / TechDraw…）与 `Pad`/`Pocket`/`Sketch` 等对象名是 FreeCAD 原生的英文专名，译文不改它们；属性面板里 `Label`/`Refine`/`ThroughAll` 同理。文案因此写"工作台名称与对象名称沿用英文"，不写"全中文界面" |
| 触摸体验有限、建议鼠标 | QPA 滚轮不认 `TOUCH`、原生 QTouchEvent 不合成鼠标（见第 2 节平板决策） |
| "应用自身不提供大模型服务" | 与 `AI` 标签的追问口径对齐，避免被认定为生成式 AI 服务提供者 |

**两个必须自己拍板的点（其一已于 2026-09-15 定案）**：

1. ~~**LGPL-2.1 的源码提供义务**~~ **已解决（2026-09-15，仓库转为 public）**。
   仓库 `https://github.com/liang-xiaohui/freecad-on-harmonyos` 现在公开可访问，修改过的
   LGPL 组件（FreeCAD 主体、Qt 补丁、Coin3D 等）所在工程的源码可公开获取，义务履行。
   原顾虑是文案只写了"各组件均按其原始许可分发，许可文本随应用提供"、**没写"源码以开源方式提供"**；
   现在可以（也建议）在文案里把这一句加强成"源码以开源方式提供，见项目仓库"。
   公开前的核查已做：历史中**从未**提交过 FlexiMind 私有 worker 脚本，没有密钥类文件，
   最大的历史对象是 splash PNG（1.4MB），仓库总量 13.3MB。
2. **应用名沿用 `FreeCAD`**（AGC 已登记）。这是上游项目名，非官方移植沿用同名有被判"名称侵权/
   攀附"的可能。低成本的做法是在介绍首句与开头元数据里把"非官方社区移植、与官方无隶属关系"
   放在最显眼处（当前文案已在首段与开源声明各写了一次）。

### 隐私政策（已完成 2026-09-15）

一份内容出三个文件，口径完全一致：

| 文件 | 用途 |
| --- | --- |
| `PRIVACY.md` | 简体中文主版本，AGC 提审口径以此为准 |
| `PRIVACY.en.md` | 英文版，供英文审核或海外渠道对照 |
| `docs/privacy/index.html` | 中文网页版，AGC 里填写的链接就指向它 |
| `docs/privacy/en.html` | 英文网页版，与中文页互相链接 |

两个 HTML 都是**自带内联样式、零外部请求的单文件**（不引 CDN、不引字体、不跑脚本），
所以 `docs/privacy/` 整目录扔到任何静态托管上都能原样工作；用浏览器"打印成 PDF"也不会散版。

声明内容同样是**逐条从包里核对过的**，不是套模板：

| 声明 | 依据 |
| --- | --- |
| 不收集个人信息、无账号、无广告、无统计埋点 | `module.json5` 只声明 2 个权限；包内不含任何统计/广告 SDK；`freecad-ai` 源码里 `telemetry`/`analytics`/`sentry`/`posthog` grep 结果为 0 |
| 共 2 项权限、各自用途与触发时机 | `ohos.permission.INTERNET`（`system_grant`，不弹窗）+ `ohos.permission.READ_PASTEBOARD`（`system_basic`+`user_grant`，已在 AGC 申请并写入 Profile），见第 3 节 |
| **API Key 以明文存放**在沙箱 `config.json` | `freecad-ai/config.py:305` 是 `CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")`，写入用 `json.dump`（`:809`），全文件没有 `encrypt`/`keyring`/混淆逻辑 —— 所以政策里如实写"明文"，并提示不要存他人的 Key |
| 联网场景只有三处 | ① AddonManager 的 GitHub / `wiki.freecad.org` 端点（`AddonCatalogCacheCreator.py:48`、`MacroCacheCreator.py:38`）；② `freecad-ai/llm/providers.py` 列出的 LLM 服务商端点（OpenAI/Anthropic/DeepSeek/Moonshot/通义/Gemini/xAI/Groq/OpenRouter 等，也可自填本地端点）；③ 用户自己点击的外部链接 |
| 数据全在本机、卸载即删 | 沙箱路径 `/data/storage/el2/base/haps/entry/files/freecad-home/`，开发者无副本 |
| 与上游无隶属关系 | 与第 7 节末"应用名沿用 `FreeCAD`"的拍板点同口径，政策第 12 节再声明一次 |

**链接：仓库 2026-09-15 已转为 public，但"公开"解决的是归属与 LGPL，不等于"审核员一定打得开"**

AGC 的隐私政策 URL 是给审核员点的，而审核侧同样在国内网络。四个候选在本机实测：

| 链接 | 本机实测 | 域名归属 | 页面形态 |
| --- | --- | --- | --- |
| `https://2c2701d6a0784c1eb0de0535c7c365f2.app.workbuddy.host`（WorkBuddy 托管） | **即时 200** | 非自有 | 纯网页，中英双语 |
| `https://github.com/liang-xiaohui/freecad-on-harmonyos/blob/main/PRIVACY.md` | 3 次里 **1 次 20s 超时**，成功也需 8–20s | 自有账号 | GitHub 文件视图（带 Raw/Blame 工具栏），非纯网页 |
| `https://raw.githubusercontent.com/.../main/PRIVACY.md` | 200 | 自有账号 | `text/plain`，浏览器里是纯文本 Markdown，不适合当政策页 |
| GitHub Pages（**尚未启用**，API `has_pages: false`） | 未测 | 自有账号 | 开启后为 `https://liang-xiaohui.github.io/freecad-on-harmonyos/privacy/`，归属与形态最合适 |

**结论**：AGC 里填的那个 URL 首要看**能不能顺利打开**，所以当前仍是 **WorkBuddy 链接首选**；
`github.com` 的地址建议只当"源码/仓库地址"写在开源声明与文案里，不要作为政策 URL 提交。
想两全就开 GitHub Pages（`liang-xiaohui.github.io`，归属自有 + 纯网页），开完再实测一次可达性。

**已随公开解决**：政策第 1 节的联系方式是仓库 Issues 页，此前因仓库私有打不开，现在可达，
不必再换成邮箱（想更稳妥也可以补一个邮箱）。

**仍缺的一项**：
1. **应用内入口**。隐私政策除提审填链接外，通常还要求在应用内可打开。当前应用内没有任何入口，
   属于待补项，实现方式未定（见第 8 节）。

### FlexiMind 面的清除（已完成 2026-09-15）

FlexiMind 在这个包里其实有**两层**面，两层现在都从对外包里清掉了。全程只用**一个开关**：

| 变量 | 默认 | 行为 |
| --- | --- | --- |
| `PACKAGE_FLEXIMIND` | **`OFF`** | 对外包：`freecad-runtime.zip` 不含 `FlexiMind/`；rawfile 不含 `freecad_headless_acceptance.py`；构建期把 `EntryAbility` 从 `module.json5` 去掉 |
| `PACKAGE_FLEXIMIND=ON` | — | 内部包：三者都在，设备侧验收与 FlexiMind 作业照旧 |

**第一层：载荷（`freecad-runtime.zip` 里的 `FlexiMind/`）。**
它**不是残留**，而是 `stage-gui-hap.sh` 有意打进去的（输入硬检查 +
「Package FlexiMind headless jobs」整段打包），所以做法是**加开关而不是删代码**：
`OFF` 时跳过这两段，并**兜底校验** zip 里不存在 `^FlexiMind/`（残留则 `zip -d` 清掉，
仍残留就 `exit 1`）。

**第二层：`EntryAbility` 这条导出的能力声明。** 它是无头桥：`want.parameters.freecadJobJson`
存在就跑 FlexiMind 作业，否则跑无头验收，实现在 `entry/src/main/cpp/acceptance.cpp`。
留在对外包里的问题不是"多余"，而是**它是 `exported: true`，任何应用都能拉起它并投喂参数**，
而载荷又被拿掉了、作业分支只会报 `FlexiMind job runner is missing from the staged runtime`。
所以 `OFF` 时在**构建期**把它从 `module.json5` 里裁掉：

- 落点是 `entry/hvigorfile.ts`，用 hvigor 官方的 `OhosHapContext.getModuleJsonOpt()` /
  `setModuleJsonOpt()`（`afterNodeEvaluate` 里执行）。`setModuleJsonOpt` 会走 schema 校验，
  改错会在构建期直接报错，不会悄悄产出坏包。
- **为什么不用 `build-profile.json5` 的多 target**：模块级 target 的 `source.abilities` 只支持
  **FA 模型**工程定制 Ability 下的 page 页面，管不了 Stage 模型的能力清单（官方"模块级
  build-profile.json5"表 6）；`source.sourceRoots` 只换源码目录，也不行。
- 开关由 `build-gui-hap-ohos.sh` 归一化成 `ON`/`OFF` 后 `export`，`hvigorfile.ts` 读环境变量。
  **读不到就按 `OFF` 处理** —— 在 DevEco 里直接 Sync/Build 也是对外包的形态，免得手滑把无头桥传上架。

**`libfreecadacceptance.so` 必须留下，这一条与最初的设想相反。**
`QAbilityStage.prepareOpenGL()`、`QAbility.setupFreecadEnv()` / `materializeFreecadRuntimeAsync()`
都 `import acceptance from 'libfreecadacceptance.so'` —— 它是这台设备上 **GUI 自己的 NAPI 模块**，
不是 FlexiMind 专属件，删了 GUI 起不来。ability 声明被裁掉之后，它导出的 `runJob`/`runAcceptance`
就没有调用方了（死分支），但 `.so` 本身照进包。`verify-gui-hap.sh` 专门断言它必须在。

**三种用法**：

```sh
./scripts/stage-gui-hap.sh                              # 对外包（默认，干净）
./scripts/build-gui-hap-ohos.sh                         # 同上，剥掉 EntryAbility
./scripts/verify-gui-hap.sh                             # 按对外包断言（无 EntryAbility / 无验收脚本）
PACKAGE_FLEXIMIND=ON ./scripts/stage-gui-hap.sh         # 内部包，三个脚本要带同一个值
PACKAGE_FLEXIMIND=ON ./scripts/build-gui-hap-ohos.sh
PACKAGE_FLEXIMIND=ON ./scripts/verify-gui-hap.sh
```

或者跑完默认 stage 之后再用 `scripts/stage-fleximind-runtime.sh` 单独把载荷刷进 zip
（那条路本来就是"不带 SDK 的增量刷新"，但它**不管** `EntryAbility` 声明与验收脚本）。

默认值故意设成 `OFF`：这个 HAP 是对外分发/上架的产物，"默认干净"比"默认带私有脚本"安全，
万一忘了加开关，代价是丢功能（自己会发现）而不是泄露（发出去收不回）。
README「可复跑入口」、`docs/fleximind-runtime.md` 顶部、`docs/device-run-guide.md`
的设备侧验收一节都已同步这个开关。

**实测（2026-09-15，两个方向各跑一遍 stage → build → verify）**：

| 阶段 | OFF（对外包，默认） | ON（内部包） |
| --- | --- | --- |
| 构建日志 | 打出 `[freecad] PACKAGE_FLEXIMIND is not ON: dropped the exported EntryAbility (headless bridge) from module.json5; abilities = [QAbility]` | 无剥离提示（开关生效） |
| HAP 内 `module.json` | `abilities=[QAbility]` | `abilities=[EntryAbility, QAbility]` |
| rawfile 验收脚本 | 无 | `✓ rawfile/freecad_headless_acceptance.py` |
| `libfreecadacceptance.so` | 保留（两处都断言必须在） | 保留 |
| hvigor | BUILD SUCCESSFUL 21.5 s | BUILD SUCCESSFUL 22.0 s |
| `verify-gui-hap.sh` | exit 0 | exit 0 |
| 落地 HAP | `507,550,495 B`（`runtime 5509 条 / FlexiMind 命中 []`） | — |

`verify-gui-hap.sh` 现在会把**能力清单**也纳入断言（原来只查 native 文件与 rawfile）：
多一个 `EntryAbility` 或少一个 `QAbility` 都会 fail，两个方向各断言一次，所以"开关没传下去"
这种半途状态不会漏网。日志在
`codex-freecad-artifacts/t1-{stage,build,verify}-{off,on}.log`。

#### 仓库转为 public 后的保密复核（2026-09-15）

对外包清干净了，但**仓库本身现在也公开**，所以又核了一遍 FlexiMind 的暴露面。结论：

| 项 | 状态 |
| --- | --- |
| FlexiMind 的 **worker 实现**（夹指参数化 / 人工设计的几何脚本本体） | **从未进入 git 历史** ✓ —— `git log --all --format="" --name-only --diff-filter=A \| sort -u` 全量枚举后只匹配到下面三个宿主侧文件 |
| `docs/fleximind-runtime.md` | **可见**：无头作业契约（job JSON 字段、四种路径参数）、`FlexiMindGripDesign` 工作台名、FlexiMind 仓库自持 workbench 生命周期的做法 |
| `runtime/fleximind_job_runner.py` | **可见**：worker 脚本名 `worker-a.py`、`worker-b.py`、`worker-c.py`，操作名 `procedural-finger` / `parametric-finger` / `manual-design`，以及各参数键 |
| `scripts/stage-fleximind-runtime.sh`（及若干脚本里 39/37/26/24/16… 处引用） | **可见**：载荷取自 FlexiMind 交付 ZIP、打包进 `freecad-runtime.zip` 的细节 |
| `.workbuddy/`（内部工作记录） | **未跟踪** ✓，`git ls-files` 命中 0 |
| 密钥类文件 / 大对象 | 无（`*.p12`/`*.p7b`/`*.key` 均未跟踪；最大历史对象是 1.4MB 的 splash PNG；仓库总量 13.3MB） |

也就是说：**接口与命名可见，实现不可见**。若 FlexiMind 的接口设计本身也要保密，
仅删当前文件**不够** —— git 历史里同样查得到，必须重写历史并 force push，
而且要认清公开期间可能已被爬虫/镜像抓走。三个选项：
① 维持现状（只公开宿主侧接口）；② 撤掉上述文件并重写历史；③ 拆一个只放桥接的私有 fork。

## 8. 待办顺序

1. ~~重签调试 Profile（新包名 + ACL）~~ **已完成（2026-09-15）**：AGC 手动新建调试
   Profile（勾设备 + 勾 `READ_PASTEBOARD`）→ 下载 p7b → 改 `build-profile.json5`。
   `./scripts/check-signing-profile.py` 退出码 0，`build-gui-hap-ohos.sh` 恢复绿，
   `bm install` 成功。
2. ~~真机复验粘贴~~ **已完成（2026-09-15）**：hilog
   `QAbility: READ_PASTEBOARD requested -> authResults=[0]`（PC/2in1 首次不弹框、系统直接
   授予），用户在 FreeCAD AI Settings 的 API Key 输入框按 Ctrl+V **成功粘入**。
3. ~~分层图标~~ **已完成（2026-09-15）**：见第 5 节。包内两处作用域都改成
   `$media:layered_image`，AGC 上传图在 `store-assets/icon/freecad-appgallery-1024.png`。
4. **AGC 填写项**：应用分类与标签（第 7 节末）、版本号（第 6 节，当前 `0.1.0`，首版建议
   对齐上游 `1.1.2`）、应用简介与详细描述（文案已成稿：`store-assets/appgallery-text-zh-CN.txt`）、
   ~~隐私政策链接~~ **已完成（2026-09-15）**：正文三份（`PRIVACY.md` / `PRIVACY.en.md`）
   + 双语网页版（`docs/privacy/`），公网 URL 已发布并可访问，AGC 直接填那个链接 —— 见
   第 7 节「隐私政策」小节。仓库已于同日转为 public；链接怎么选按该节的实测结论
   （当前 WorkBuddy 地址首选，`github.com` 地址只当仓库地址写）。
5. ~~截图素材~~ **已完成（2026-09-15）**：5 张 1920×1080 介绍套图，见第 6 节末
   「应用截图：16:9 介绍套图」，产物在 `store-assets/screenshots-16x9/`，可用
   `node tools/promo/make_promo.js` 重出。
6. ~~定仓库公开性~~ **已完成（2026-09-15）**：仓库已转为 **public**。三件事一次解决：
   ① 隐私政策链接与政策里的联系方式都可公网直达；② **LGPL-2.1 的源码提供义务已履行**
   （第 7 节拍板点 1 结案）；③ 介绍文案里"源码以开源方式提供"这句现在可以写了。
   公开前的核查：历史中从未提交过 FlexiMind 私有 worker 脚本、无密钥类文件、
   最大历史对象 1.4MB splash PNG、仓库总量 13.3MB。**仍待办的两件小事**：
   ① `docs/appgallery-release.md` 与 `AppScope/app.json5` 里写着调试证书序列号
   （`63E4DC…EDA`）与签名材料本机路径（`~/Documents/ohos/config/default_cloudcompare-…`）——
   公开仓库里通常不写密钥材料的存放位置，建议改成占位描述；
   ② 仓库 `license` 仍为 `None`（GitHub 识别不到 LICENSE 文件），公开仓库建议明确许可声明。
7. **补应用内隐私政策入口**：政策要在应用内也能打开。实现方式未定（建议挂在 Help 菜单或
   Start 工作台的一个链接上，指向公网 URL 或包内随附的副本）。
8. AGC 建发布证书与发布 Profile → 加 release 签名配置 → 出正式包 → 提审时补
   `READ_PASTEBOARD` 的权限说明 + 场景视频 + 内嵌 CPython 的说明。

