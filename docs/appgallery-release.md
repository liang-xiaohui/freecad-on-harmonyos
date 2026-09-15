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
  Key 的存放位置（沙箱 `freecad-home/` 配置文件）。
- 包内 185 个 `.so` 全部走 HAP `libs/`（保持签名），rawfile 里不放 native ELF。
- **PC-only 时还要过桌面交互这一关**（审核会在 PC 上实测）：鼠标悬停态、键盘快捷键、
  自由窗口的拉伸/最大化/最小化、不同分辨率与缩放下不出现固定尺寸或留白。本移植是
  Qt 桌面栈，菜单/快捷键/窗口缩放天然具备（QPA 已处理窗口装饰高度与像素密度），
  提审时可以在备注里点明这些桌面特性。
- **素材按勾选设备准备**：只勾 PC/2in1 就只需要 PC 分辨率的截图（3-5 张 16:9
  1920×1080，PNG/JPG ≤5MB，需真实界面截图、不能用模拟器截图），不需要手机竖屏截图。

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
   对齐上游 `1.1.2`）、应用简介与详细描述、隐私政策链接。
5. **截图素材**：PC/2in1 档 3-5 张 16:9 1920×1080（PNG/JPG ≤5MB），真实界面截图。
6. AGC 建发布证书与发布 Profile → 加 release 签名配置 → 出正式包 → 提审时补
   `READ_PASTEBOARD` 的权限说明 + 场景视频 + 内嵌 CPython 的说明。

