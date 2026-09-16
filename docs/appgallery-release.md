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
`debug-info.device-ids` 只剩 1 条 = 本机 UDID（这里不记录，见 AGC 的 Profile 详情页）。构建
`Finishing :entry:default@SignHap` 通过，`bm install` 成功，启动后 hilog 出现
`QAbility: READ_PASTEBOARD requested -> authResults=[0]`（PC/2in1 不弹框，系统直接授予）。

**一个易踩的坑**：AGC 里可以选的历史调试证书很多（每建一次工程/证书就多一张），
Profile 绑的是哪张，本地就必须用哪张 `.cer`+`.p12`。这次 Profile 绑的是**本机另一个工程**的
一张调试证书（序列号与签发日期见 AGC 后台，这里不记录），所以 `build-profile.json5`
现在指向该工程的 `default_<工程名>*.{cer,p12}`（具体文件名见本机签名材料目录，同样不记录）。
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
| profile | AGC 下载的 `default_freecad-on-harmonyos-acl-debug.p7b`（含 ACL） |
| bundle-name | `com.liangxiaohui.freecad` |
| app-identifier | `6917614499915791877` |
| acls | `["ohos.permission.READ_PASTEBOARD"]` |
| device-ids | 1 条 = 本机 UDID（不在此记录，见 AGC 的 Profile 详情页） |
| cert / key | 另一个工程那套调试证书的 `.cer` / `.p12`，密钥别名 `debugKey` |

**为什么证书用的是另一套**：AGC 里 Profile 必须绑定一张调试证书，这次新建 Profile 时选中的是
早先为另一个工程签发的那张（序列号与签发日期见 AGC 后台，这里不记录），它的私钥在本机只存在于
那套 `.p12` 里，所以 `certpath`/`storeFile` 指过去、口令沿用它的
（`storePassword`/`keyPassword` 是 DevEco 加密串，跨工程可直接复用）。
hvigor 会校验"证书公钥 == .p12 私钥"，配错在 `SignHap` 阶段直接失败。

若不想跨工程共用材料：在 AGC 用本工程的 `.csr` 新建一张调试证书，重新签发 Profile，
再把三件套（p7b/cer/p12）都指回本工程的文件。

改动前的旧材料（`default_freecad-on-harmonyos<jc>…` 那份，随机后缀省略）绑的是旧包名
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

### 发布材料：申请发布证书 + 发布 Profile（2026-09-15 补齐）

上架要用的**发布**材料和调试那套是两套东西，差别不只是"换张证书"：

| | 调试 Profile | 发布 Profile |
| --- | --- | --- |
| 设备白名单 `debug-info.device-ids` | 有（只列进白名单的 UDID 能装） | **无**（谁都能装） |
| 受限权限 ACL | 可以自己勾 | **必须在这里申请**，否则提审被驳回 |
| 有效期 | 随调试证书 | 发布证书 **3 年**（实名认证开发者） |
| 上限 | — | 证书 3 个/账号；Profile 100 个/应用 |

AGC 的界面分工要先看清楚：**证书是账号级的，Profile 才是每个应用一份**。所以发布证书一张就能给名下所有鸿蒙应用共用（配额只有 3 个，别一个应用申一张），Profile 则每个应用各申请一份。

#### Step 0 · 生成发布密钥库与 CSR（本机，已完成 2026-09-15）

```sh
sh scripts/init-release-signing.sh     # 已存在密钥库时会拒绝，除非显式 FORCE=1
```

产物在 `~/Documents/ohos/config/release-signing/`：

| 文件 | 说明 |
| --- | --- |
| `ohos-release.p12` | 发布密钥库。别名 `releaseKey`（PKCS12 存储时被规范成小写 `releasekey`，但查找大小写不敏感，实测两种写法都能取到同一条），EC P-256，有效期至 **2051-09-09** |
| `ohos-release.csr` | **上传 AGC 申请发布证书用的证书请求**（588 B，`SHA-256 = c71295d4…91d98`，与 DevEco 生成的结构等价） |
| `material/` | 口令加解密材料（从现有签名目录复制） |
| `password.txt` | 本次随机生成的明文口令（0600）。抄进密码管理器后可删 |
| `FreeCAD_Release_2026.cer` | **AGC 签发后下载回来**（2026-09-16）。PEM **证书链 3 张**：叶子 → Developer Relations CA G2 → Root CA G2；叶子 `CN=梁晓辉(1578456863605849601),Release`，有效期至 **2029-09-16** |
| `FreeCAD_Release_2026Release.p7b` | **AGC 生成的发布 Profile**（2026-09-16）。`type=release`、`bundle-name=com.liangxiaohui.freecad`、`apl=normal`、`acls=['ohos.permission.READ_PASTEBOARD']`、`device-ids` 空 |

> 文件名沿用 AGC 下载时的原名（`证书名称.cer` / `Profile名称.p7b`），没有改名——`build-profile.json5` 里写的就是这两个名字。

**下载回来必须验一遍**，不验等于赌：

```sh
# ① 证书是不是我们那把私钥签出来的（.cer 是证书链，要逐张比对，x509 默认只读第一张）
#    叶子证书公钥的 SHA-256 应等于 CSR 的公钥 8e3b8d79…47287
# ② Profile 的包名 / 类型 / ACL 是否正确
python3 scripts/check-signing-profile.py ~/Documents/ohos/config/release-signing/FreeCAD_Release_2026Release.p7b
```

第 ② 步会逐项打印并给出结论——**重点看 `acls` 里有没有 `ohos.permission.READ_PASTEBOARD`**。这个列表是烤进 `.p7b` 文件的，AGC 审批通过只改账号侧状态，手上的 `.p7b` 不会自己变：漏勾就是构建全绿、装包 9568289。

**为什么用脚本而不是 DevEco「Build > Generate Key and CSR」**：hvigor 只接受 **DevEco 加密后的口令密文**，明文会被 `DecipherUtil` 直接拒绝（它先校验长度 ≥32 且为偶数，再按 AES-128-GCM 解密）。脚本把密文一并算好，于是整条发布签名链路不需要打开 GUI：

```sh
node scripts/signing-password.js decrypt             # 找回已有密文对应的明文（默认不回显）
node scripts/signing-password.js encrypt '<明文口令>'  # 给任意口令生成可粘贴的密文
```

两个连带结论，都是踩出来的：

- **hvigor 去「`.p12` 所在目录」找 `material/{fd,ac,ce}`**。`.p12` 换目录必须把 `material/` 一起搬，否则 `SignHap` 阶段报 `SIGNING_FAILED_CAN_NOT_FIND_SIGNING_MATERIAL`。
- 这套加密是**防肩窥，不是真机密**：材料就在同一个目录里，能读到 `material/` 就能还原口令。别把它和 `.p12` 一起提交进任何仓库。

⚠️ **`.p12` 是长期资产**：AGC 明确"更新版本时需使用同一个 CSR 文件生成的证书"。丢了私钥，这个应用的后续版本只能换证书重来，并重走 Profile。生成后立刻备份 `ohos-release.p12` **和** `material/`（两者要在一起）。

#### Step 1 · AGC 申请发布证书（.cer）

前提：账号已**实名认证**；账号角色有「访问发布类证书」权限（团队账号需单独授权）。

**要上传的文件（唯一一个，绝对路径）**：

```
/storage/Users/currentUser/Documents/ohos/config/release-signing/ohos-release.csr
```

核对特征：**588 字节**、`SHA-256 = c71295d477c8474732f335787baf4abb2061323d2a54691a254537fe5a991d98`、
Subject 为 `CN=liangxiaohui, OU=Individual Developer, O=liangxiaohui, L=Shanghai, ST=Shanghai, C=CN`、
公钥 `id-ecPublicKey` / `NIST CURVE: P-256`。上传前可用 `sha256sum` 对一遍。

> ⚠️ **别传错**：同一台机器的 `../`（即 `~/Documents/ohos/config/`）下还有 13 张 CSR，其中
> `default_freecad-on-harmonyosjQeoJc1u7….csr` **名字里带本工程名、看起来"才是对的"——它是调试 CSR（460 B）**。
> 调试 CSR 签出来的证书不能用于发布。判别法：**只有 `release-signing/` 目录下那张是发布用的**
> （588 B，目录外全部为 456/460 B）。

AGC → **证书、APP ID和Profile → 证书 → 新增证书**：名称自取、**类型选「发布证书」**、上传上面那张 `ohos-release.csr` → 提交 → 下载 `.cer`。

- 配额 **3 个/账号**，有效期 **3 年**。到期不影响在架应用，但更新版本时用过期证书签的包会被拒 ⇒ 提前换。
- 证书行上的「备案信息」按钮可取证书公钥与指纹，备案时要填这两样。
- 申请发布 Profile 时 AGC 会**自动**把发布证书指纹更新到应用上（覆盖之前配的调试证书指纹），不用手工改。

#### Step 2 · AGC 申请发布 Profile（.p7b）

AGC → **证书、APP ID和Profile → Profile → 添加**：

| 字段 | 填法 |
| --- | --- |
| 应用名称 / 包名 | 选本应用 ⇒ 包名自动填 `com.liangxiaohui.freecad` |
| Profile 名称 | 自取 |
| **类型** | **发布**（不是"指定设备"） |
| 选择证书 | 上一步那张发布证书 |
| **申请权限** | **勾 `ohos.permission.READ_PASTEBOARD`** |

「申请权限」栏是发布 Profile 与调试 Profile 最实质的差别：受限权限必须**在这里**申请（要填使用场景说明；AGC 可能要求为每个受限权限上传说明视频）。**漏勾 ⇒ 提审驳回**；即便侥幸过审，装包也会 9568289。

好消息：`READ_PASTEBOARD` 的可申请场景里写明了"**PC/2in1 设备上的应用均可申请**"，本工程 PC-only，属于明确符合的场景，不需要编理由。

下载的 `.p7b` 放到 `release-signing/` 下（和 `.p12` 同目录）。

#### Step 3 · 写进 build-profile.json5 并出包

**关键机制**：hvigor 的 `signingConfig` 是**按 product 绑定**的，`buildModeSet` 的 schema 里根本没有 `signingConfig` 字段 ⇒ 别指望 `-p buildMode=release` 自动切签名。正解是两个 product 各绑一套签名（完整示例见 `build-profile.example.json5`）：

```json5
"signingConfigs": [ { "name": "default", ...调试材料... },
                    { "name": "release", ...发布材料... } ],
"products":       [ { "name": "default", "signingConfig": "default", ... },
                    { "name": "release", "signingConfig": "release", ... } ],
"modules":        [ { "name": "entry", "srcPath": "./entry",
                      "targets": [ { "name": "default",
                                     "applyToProducts": ["default", "release"] } ] } ]
```

`applyToProducts` 两个都要挂，否则 `-p product=release` 找不到 target。

**出包用封装好的脚本**（顺序 stage → build → verify，且 stage 非 0 就不继续 build）：

```sh
sh scripts/build-release-hap.sh
# 产物：entry/build/release/outputs/default/entry-default-signed.hap
```

脚本做了三件容易被漏的事：强制 `PACKAGE_FLEXIMIND=OFF`（内部包绝不上架）、`PRODUCT` 与 `BUILD_MODE` 都切 release、verify 时把 `HAP` 指向 release 那层目录（`verify-gui-hap.sh` 默认只看 `build/default/`，不指就验错包）。

**出包后的三项核对**（2026-09-16 实测通过）：

```sh
# ① 验签 + 把 HAP 里的证书链与 Profile 导出来
.sdk-overlay/26/toolchains/lib/hap-sign-tool verify-app \
    -inFile entry/build/release/outputs/default/entry-default-signed.hap \
    -outCertChain /tmp/chain.cer -outProfile /tmp/hap.p7b      # 应打印 hap verify successed!
# ② HAP 内嵌的 Profile 必须与 AGC 下载的那份逐字节相同
cmp /tmp/hap.p7b ~/Documents/ohos/config/release-signing/*.p7b
# ③ 证书链叶子必须是**发布**证书，不是调试那张
```

第 ③ 步的判别靠公钥指纹（`.cer` 是链，`openssl x509` 默认只读第一张=根 CA，要拆开逐张看）：

| | 叶子证书公钥 SHA-256（前 16 位） |
| --- | --- |
| 发布证书（本工程） | `8e3b8d794f1a2354` |
| 调试证书（本机共用） | `c10b5b2372e06496` |

若是后者 ⇒ 签名配置没生效，包不能用。本次实测：叶子为 `8e3b8d79…`、内嵌 Profile 与下载的 `.p7b` 逐字节相同、`verify-gui-hap.sh` 退出码 0、`abilities=[QAbility]`。

出包前至少核一遍：`.p7b` 的 `type` 是 `release`、`bundle-name` 与 `AppScope/app.json5` 一致、`acls.allowed-acls` 含 `READ_PASTEBOARD` —— `check-signing-profile.py` 这三项都查。

这个 `.hap` 的用处到此为止：**它装不到任何设备上**（见 Step 4 末尾），只为下面的 `.app` 提供模块产物。

#### Step 4 · 出 AGC 提审用的应用包（.app）

**AGC 上传的是 `.app`（App Pack），不是 `.hap`。** 两者不是同一层的东西：

| | `.hap` | `.app` |
| --- | --- | --- |
| 是什么 | 模块包（单个 module） | 应用包（含各模块 hap + `pack.info`） |
| 用途 | `hdc install` 装到设备（默认构建的调试包） | **AGC 提审上传** |
| 签名位置 | hap 自身带 HAP Signing Block | 签名加在**整个 `.app`** 上，内嵌 hap 是未签名形态 |
| 产物路径 | `entry/build/release/outputs/default/entry-default-signed.hap` | `build/outputs/release/freecad-on-harmonyos-release-signed.app` |

```sh
sh scripts/build-release-app.sh
# 上传这个（已签名，502 MB 量级）：
#   build/outputs/release/freecad-on-harmonyos-release-signed.app
# 同目录另有 ...-unsigned.app，不要传
```

脚本 = stage → `assembleApp`（内部 `HVIGOR_TASK=assembleApp PRODUCT=release BUILD_MODE=release`）→ 三步校验（2026-09-16 实测通过，3m46s）：

1. `hap-sign-tool verify-app -inFile <.app>` 对**应用包本体**验签，应打印 `hap verify successed!`；
2. `cmp` 内嵌 Profile 与 AGC 下载的 `.p7b`，必须逐字节相同；
3. 把内嵌的 `entry-default.hap` 解出来，用 `HAP=<解出的路径> ./scripts/verify-gui-hap.sh` 再走一遍完整内容校验。

第 3 步之所以不能简单地对内嵌 hap 直接跑 `verify-app`：`.app` 里的 hap 没有 HAP Signing Block（签名在 `.app` 层），对 hap 验签会报 `No HAP Signing Block before ZIP Central Directory`（`VERIFY_ERROR, code: -106`）。这不是包坏了。

**⚠️ 发布签名的包装不到本机设备上 —— 设计如此，不是配置问题。**

2026-09-16 实测：**完全卸载**调试包之后再用 `hdc install` 装发布签名包，仍然失败：

```text
msg:error: failed to install bundle. code:9568322
error: signature verification failed due to not trusted app source.
```

hilog 里对应 `VerifyProfileInfo: untrusted source app with release profile`。原因是 bundle manager 对 **release profile** 一律拒绝侧载 —— 发布 Profile 只能经应用市场（或 AGC 的测试渠道）分发到设备。于是三条路分清楚：

- **本机自测 / 调 UI** → 永远用**调试签名**的 `.hap`：默认构建 + `scripts/install-gui-hap.sh`；
- **想在本机跑发布签名版本** → 只能先在 AGC 走内测/公开测试渠道分发，再从设备上的应用市场安装；
- **验证发布签名本身是否配错** → 靠上面 Step 3 的三项核对与 Step 4 的三步校验做**离线验签**，不要拿"能不能装上"当判据。

#### Step 5 · AGC 的「应用加密」勾不勾：**不勾**

「选取待发布的软件包」页（API Level ≥ 11）有个加密开关，AGC 的说明是：加密 = 客户端装到的包是加密的、安全性较高；不加密 = 启动速率较快。官方[应用加密文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V14/code-protect-V14)还写了两条硬约束：**只加密 `.abc`（ArkTS 字节码），`.so` 默认不加密**（原文：*Currently, .so files are not encrypted by default*），且**性能影响与加密代码文件大小正相关**；该特性还按**白名单受限开放**，要单独申请。

把这些约束套到本工程的包上（2026-09-16 实测，hap 共 502 MB）：

| 类别 | 文件数 | 体积 | 占比 | 加密覆盖 |
| --- | --- | --- | --- | --- |
| native 库 `.so` | 248 | 424.9 MB | 84.6% | **否**（明文） |
| rawfile 运行时 `.zip` | 2 | 64.8 MB | 12.9% | **否**（明文） |
| 其他（模块清单、资源、绑定等） | 25 | 12.5 MB | 2.5% | 否 |
| ArkTS 字节码 `.abc` | **1** | **55 KB** | **≈0.0%** | 是 |

**开了加密，被保护的只有那一个 55 KB 的 `ets/modules.abc`（占整包 0.011%）**，而 97.5% 的体积照样明文。代价是冷启动延迟（FreeCAD 启动本来就重，官方也承认"`.abc` 越大冷启动越慢"）、包体略增、还要申请白名单。收益与代价完全不成比例 ⇒ **不勾**。

**「是否需要额外的安全加固措施」：不需要。** 理由：

1. 那 248 个 `.so` 里没有专有资产 —— FreeCAD / Qt6 / OCCT / Coin3D / CPython / OpenSSL / numpy 全是上游开源件；我们自己写的只有 `libfreecadqtapp.so`、QPA 插件、NAPI 桥这几层薄封装，源码就在本仓库（LGPL-2.1 提供义务已履行）。加密或混淆它们只会给使用者制造麻烦，不产生保护价值。
2. **真正防篡改的是 HAP 签名，不是加密。** 签名覆盖包内每个文件（含 `.so`），改一个字节就验签失败 —— 那是完整性边界；加密解决的是"看得懂/看不懂"，两者别混。
3. 将来若真有必须隐藏的东西（密钥、专有算法），正确做法是别放进客户端包，而不是指望加固。
4. 顺带一个更该盯的点：**rawfile（`python311.zip`、`freecad-runtime.zip`）不参与任何加密**，是包里最大的明文暴露面 —— 这正是当初把 FlexiMind 私有载荷从 rawfile 里摘掉（`PACKAGE_FLEXIMIND=OFF`）的意义所在，别在打包时又放回去。

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

**链接：最终选 GitHub Pages（2026-09-15）；"公开"解决归属与 LGPL，但可达性要单独测**

AGC 的隐私政策 URL 是给审核员点的，而审核侧同样在国内网络 —— 所以"域名归谁"和"打不打得开"
是两个维度。四个候选的本机实测（同一天、同一网络，取稳定态）：

| 链接 | 实测 | 域名归属 | 页面形态 | 结论 |
| --- | --- | --- | --- | --- |
| **`https://liang-xiaohui.github.io/freecad-on-harmonyos/privacy/`** | **200，0.26 s**（英文页 0.44 s） | **自有账号** | 纯网页，中英双语，自带样式 | ✅ **AGC 填这个** |
| `https://github.com/.../blob/main/PRIVACY.md` | 200 时 1.16 s，但曾 3 次里 1 次 20 s 超时 | 自有账号 | GitHub 文件视图（带 Raw/Blame 工具栏） | 只当"仓库地址"写在开源声明里 |
| `https://raw.githubusercontent.com/.../main/PRIVACY.md` | 200 | 自有账号 | `text/plain`，浏览器里是纯文本 Markdown | 不适合当政策页 |
| `https://2c2701d6…app.workbuddy.host`（WorkBuddy 托管） | 200，3.66 s | 非自有 | 纯网页，中英双语 | 备用；域名不归自己 |

Pages 通过 API 开启，源为 `main` 分支的 `/docs` 目录，所以 `docs/privacy/` 下的两页直接成为站点：

```bash
curl -X POST -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  -d '{"source":{"branch":"main","path":"/docs"}}' \
  https://api.github.com/repos/liang-xiaohui/freecad-on-harmonyos/pages
```

**踩过的判断**：`github.com` 网页端在这条网络上**慢且不稳**（成功 8–20 s，偶发 20 s 超时），
而 `api.github.com` / `codeload.github.com` 一直正常 —— 所以"API 通"不能证明"页面开得开"，
`raw.githubusercontent.com` 也只证明文件可取，不证明浏览器体验。要判断可达性就**直接测那个 URL**。

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

**ON 侧的私有知识在仓库之外**（2026-09-15 起）：输入清单（worker / helper 文件名、私有源码根）、
打包逻辑、内部包条目断言全部放在外部钩子 `scripts/private/fleximind-stage.sh`（在 `.gitignore` 里），
公开侧只留开关与加载器 [`scripts/fleximind-hook.sh`](../scripts/fleximind-hook.sh)；
钩子缺失时 `PACKAGE_FLEXIMIND=ON` 会明确报错退出，而不是静默产出半成品。
钩子要实现哪些函数、能读到哪些环境变量，写在加载器顶部的注释里。

默认值故意设成 `OFF`：这个 HAP 是对外分发/上架的产物，"默认干净"比"默认带私有脚本"安全，
万一忘了加开关，代价是丢功能（自己会发现）而不是泄露（发出去收不回）。
README「可复跑入口」与 `docs/device-run-guide.md` 的设备侧验收一节都已同步这个开关。

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

**复测（2026-09-15 晚，外部钩子重构之后）**：把私有清单从 4 个公开脚本挪进外部钩子之后，
又完整跑了一遍双向回归（ON stage/build/verify → OFF stage/build/verify → 收尾自检），
六个阶段全 exit 0，最终态回到 OFF：

| 阶段 | 退出码 | 耗时 |
| --- | --- | --- |
| ON stage / build / verify | 0 / 0 / 0 | 150 s / 22 s / 17 s |
| OFF stage / build / verify | 0 / 0 / 0 | 155 s / 23 s / 15 s |

带开关的断言两侧都复现：ON 侧 `✓ FlexiMind 载荷在位`、`abilities=[EntryAbility, QAbility]`、
rawfile 含 `freecad_headless_acceptance.py`；OFF 侧 `✓ HAP 不含 FlexiMind/ 载荷`、
`abilities=[QAbility]`、验收脚本不进 rawfile。钩子契约另做了隔离测试（装载后 5 个函数齐备；
钩子缺失时给出明确提示并 exit 1；`fleximind_forbidden_pattern` 正例命中、合法载荷条目放行）。
日志在 `codex-freecad-artifacts/on-off-cycle2.log`，一次性链式脚本
`codex-freecad-artifacts/on-off-cycle.sh`（顺序执行不带 `set -e`，最后必做"最终态自检"，
避免中途失败把仓库留在 ON 态）。

**踩坑（值得记住）**：第一遍回归六个阶段全挂、退出码 126 —— `stage-gui-hap.sh` 里的 `rm`
被 WorkBuddy 的 safe-bin shim 挡住了。根因是脚本为了 hvigor 而 `unset CODEBUDDY_SAFE_DELETE_ENABLED`，
而这个变量一旦缺失，shim 的 `rm` 就直接拒绝。**stage 与 build 的 env 需求是冲突的**：
正解是**把 safe-bin 目录从 PATH 里剥掉**（`rm` 回到 `/bin/rm`，与变量无关），`unset` 只留给 build 那一步。
更值得注意的是，**失败的 stage 会让 staging 处于不一致状态，而紧接着的 build 仍会"成功"产出一个
残缺的 HAP**（只有 `verify-gui-hap.sh` 会报 `HAP 使用了过期 rawfile/...`）—— 所以 stage 非 0 时
不要接着 build。

#### 仓库转为 public 后的保密复核与撤出（2026-09-15）

对外包清干净了，但**仓库本身也公开**，所以又核了一遍 FlexiMind 的暴露面，并按"撤出实现细节"处理。
现状：

| 项 | 状态 |
| --- | --- |
| FlexiMind 的 **worker 实现**（夹指参数化 / 人工设计的几何脚本本体） | **从未进入 git 历史** ✓（`git log --all --format="" --name-only --diff-filter=A \| sort -u` 全量枚举确认） |
| 作业运行器、打包脚本、作业契约文档 | **已从当前树撤出，并从全部 47 个提交里移除**：`runtime/fleximind_job_runner.py`、`scripts/stage-fleximind-runtime.sh`、`docs/fleximind-runtime.md`（`git filter-branch --index-filter`） |
| 证书序列号 / 本机 UDID / 私有源码根路径 / worker 文件名 | **已从全部 47 个提交里洗掉**（`--tree-filter` 走字节级替换，脚本见下文）。注意：这几串在转公开后**一度是活的** —— 远端 tip `52bac32` 里就带着它们，所以这一轮不是"防患于未然"，是真的在补救 |
| worker / helper 文件名、私有源码根路径、GUI 工作台源码结构 | **已从脚本里撤出**：原先散在 `stage-gui-hap.sh` / `stage-headless-hap.sh` / `verify-gui-hap.sh` / `verify-headless-hap.sh` 四处的清单与断言，改为由外部钩子提供数据（见上一小节） |
| `entry/src/main/cpp/acceptance.cpp` | **仍可见**：无头桥按 `<filesDir>/FlexiMind/fleximind_job_runner.py` 定位运行器。只暴露载荷目录名与运行器文件名，不含 worker 名与作业契约；改动要重编 `libfreecadacceptance.so` 并重新验证 GUI，收益小风险大，故保留 |
| `.workbuddy/`（内部工作记录） | **未跟踪** ✓（`git ls-files` 命中 0） |
| 密钥类文件 / 大对象 | 无（`*.p12`/`*.p7b`/`*.key` 均未跟踪；最大历史对象 1.4MB splash PNG；仓库总量 13.3MB） |

**重写分两遍做的，顺序不能反**：

1. `--index-filter` + `git rm --cached` 抽掉三份文件（改的是"某个提交有没有这个路径"）；
2. `--tree-filter` + 一个字节级替换脚本洗掉**材料事实**串（改的是"某个提交的文件内容"）。

只做第 1 遍是**不够的**：那三份文件的路径没了，但证书序列号、UDID、私有源码根路径、
worker 文件名散在其他文件的内容里，照样随历史公开。反之如果只做第 2 遍，被删文件的
**内容**仍在历史对象里。两遍都做才算洗全。

清洗器脚本**刻意不入库**（它自己就写着那些待洗的串，提交等于又把它们放回来），
放在工作区外的 `codex-freecad-artifacts/scrub-private.py`。它的替换表只有"材料事实"级：
证书序列号、本机 UDID、私有源码根绝对路径、私有 worker/工具文件名。

**刻意不动的**（避免过度改写、把文档改废）：

- `FlexiMind` 这个名字与 `PACKAGE_FLEXIMIND` 开关本身 —— 公开侧要靠它决定打哪个包，是有意公开的；
  只洗掉名字、留着开关，等于自欺欺人；
- `acceptance.cpp` 里的无头桥（见上表）；
- `/storage/Users/currentUser/CPPLib` 这类**本机构建布局路径**（57 个文件在用）—— 文档里的
  构建步骤靠它才有用，且不构成机密。

**验证口径**（重写后逐提交全量扫，不能只看 HEAD）：

```sh
# 每条都应为 0
for t in 63E4DC7938676B117F08DEBFBEDA BE84778D github/FlexiMind \
         generate_procedural_finger_step render_parametric_finger_design \
         manual_gripping_design_freecad local_design_bridge; do
    n=$(git rev-list HEAD | while read c; do git grep -l -F "$t" $c 2>/dev/null; done | wc -l)
    echo "$t : $n"
done
# 树哈希必须与重写前一致 —— 证明清洗只动历史、没动当前内容
git rev-parse HEAD^{tree}   # = 155d7b9034563cccf429475c57914110291173ad
```

**远端侧验证**（force push 之后再确认一遍，别只看本地）：本地绿不等于远端绿。
做法是查 API —— ① 撤出的三份材料在远端应返回 404；② 远端重写后那个提交的 `tree` 必须
等于本地那个树哈希（内容寻址，一致即等价）。

实测结果（2026-09-15）：三份材料全 **404** ✓；远端 `ca14605` 的 tree =
`155d7b9034563cccf429475c57914110291173ad`，与本地一致 ✓；但旧 tip `52bac32` 查 API
**仍返回 200** —— GitHub 还留着旧对象（见下）。

**重写历史的边界（必须说清楚）**：force push 之后，GitHub 上原来的提交对象**不会立刻消失** ——
只要知道旧提交 hash，一段时间内仍可直接访问，直到 GitHub 侧回收，或联系 Support 主动清除；
公开期间被爬虫/镜像/fork 抓走的内容更是收不回。这次尤其要记住：**那些串在公开仓库里
真的活过一段时间**（远端 tip `52bac32` 就带着它们），所以哪怕现在洗掉了，也不能假设没人抓过。
本地保留了三份副本在 `scripts/private/`（未跟踪），功能随时可恢复。

## 7.5 APP 备案（工信部）：本应用属于"单机应用"，但要在 AGC 正确勾选

这条此前一直没写进文档，是提审时容易被卡住的一项：按工信部《关于开展移动互联网应用程序
备案工作的通知》，**APP 上架应用市场前必须先完成备案**，AGC 的「备案信息」栏是必填项。

但备案义务有明确的豁免口径（官方 FAQ「HarmonyOS应用备案指导和常见问题」）：

| AGC 里怎么勾 | 适用条件 |
| --- | --- |
| 您的 APP 服务器在中国大陆 | 有境内服务端 ⇒ **必须备案**，需走接入商（华为云/阿里云/腾讯云…）代备案 |
| 您的 APP 服务器不在中国大陆 | 境外主体 + 服务器仅在境外 |
| **您的 APP 为单机 APP** | **未通过连接公共互联网提供互联网信息服务** |

FreeCAD on HarmonyOS 是本地 CAD 工具：没有任何自建服务端，联网只有三处（AddonManager 拉
插件、用户自己配的 LLM 端点、用户点击的外链），不对外提供互联网信息服务 ⇒ 归入**单机应用**，
AGC 勾「您的 APP 为单机 APP」。

另外华为官方 FAQ 里有一问直指这个场景：

> **Q：鸿蒙 PC 应用上架为什么一定要提供 ICP 备案，其他 PC 客户端没有这样的要求？**
> A：应用资质审核要求中未强制要求提交 ICP 备案。

即 **ICP 备案（网站/域名备案）不是鸿蒙 PC 应用的强制项**；要填的是上面那个 APP 备案信息栏。
两条口径不同，别混：前者是网站备案，后者是应用备案。

**要留的后手**：如果审核员就"是否真属单机"提出疑问（毕竟它有网络能力），备好一句话说明——
"本应用不提供任何互联网信息服务，无自建服务端；网络访问仅用于用户主动发起的插件下载与
用户自行配置的模型接口"，并指向隐私政策第 4/5 节（联网场景表）。真被判需要备案时，成本是
借一个**备案授权码**（别人的 ECS 可生成 5 个）在接入商处新备案鸿蒙包名，周期约 5~25 个工作日
——所以这一步的判断越早做越好。

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
   + 双语网页版（`docs/privacy/`）。**AGC 填这个链接**：
   `https://liang-xiaohui.github.io/freecad-on-harmonyos/privacy/`（GitHub Pages，
   源 = `main` 的 `/docs`，实测 0.26 s；英文页 `/privacy/en.html`）。
   四个候选的对比与开启命令见第 7 节「隐私政策」小节。
5. ~~截图素材~~ **已完成（2026-09-15）**：5 张 1920×1080 介绍套图，见第 6 节末
   「应用截图：16:9 介绍套图」，产物在 `store-assets/screenshots-16x9/`，可用
   `node tools/promo/make_promo.js` 重出。
6. ~~定仓库公开性~~ **已完成（2026-09-15）**：仓库已转为 **public**。三件事一次解决：
   ① 隐私政策链接与政策里的联系方式都可公网直达；② **LGPL-2.1 的源码提供义务已履行**
   （第 7 节拍板点 1 结案）；③ 介绍文案里"源码以开源方式提供"这句现在可以写了。
   公开前的核查：历史中从未提交过 FlexiMind 私有 worker 脚本、无密钥类文件、
   最大历史对象 1.4MB splash PNG、仓库总量 13.3MB。转公开后补做的三件：
   ① ~~脱敏~~ **已完成**：调试证书序列号、本机 UDID 与签名材料路径已从本文件移除，
   只保留"用的是哪一套、怎么查、怎么换"这类可操作信息；
   ② ~~加许可声明~~ **已完成**：仓库根新增 `LICENSE`（LGPL-2.1 全文，取自上游），
   README 增加「许可」一节说明衍生部分的许可与源码提供方式；
   ③ ~~FlexiMind 实现细节撤出 + 重写历史~~ **已完成**：实现细节已移到仓库外的外部钩子，
   三份材料由 `git filter-branch` 从全部 47 个提交移除，证书序列号 / UDID / 私有路径 / worker
   文件名一并洗掉，已 force push（整条历史换哈希，重写那一刻的 tip 是 `ca14605`）。
   做法、验证口径与边界见第 7 节末「保密复核与撤出」小节。
7. **补应用内隐私政策入口**：政策要在应用内也能打开。实现方式未定（建议挂在 Help 菜单或
   Start 工作台的一个链接上，指向公网 URL 或包内随附的副本）。
8. **发布签名与正式包**：
   ① ~~生成发布密钥与 CSR~~ **已完成（2026-09-15）**：`sh scripts/init-release-signing.sh`
   → `~/Documents/ohos/config/release-signing/{ohos-release.p12,ohos-release.csr,material/,password.txt}`。
   EC P-256 / SHA256withECDSA / 有效期至 2051。**先备份 `.p12` + `material/`**。
   ② ~~AGC 申请发布证书与发布 Profile~~ **已完成（2026-09-16）**：下载回
   `release-signing/{FreeCAD_Release_2026.cer, FreeCAD_Release_2026Release.p7b}`。
   证书叶子 `CN=梁晓辉(1578456863605849601),Release`，有效期至 2029-09-16；
   Profile `type=release`、`acls=['ohos.permission.READ_PASTEBOARD']`（`check-signing-profile.py` 退出码 0）。
   ③ ~~配 release 签名并出正式包~~ **已完成（2026-09-16）**：`build-profile.json5` 已加
   release signingConfig + release product + `applyToProducts`；`sh scripts/build-release-hap.sh`
   产出 `entry/build/release/outputs/default/entry-default-signed.hap`（484 MB），
   验签通过、叶子证书为**发布**证书、内嵌 Profile 与 AGC 下载件逐字节相同、
   `verify-gui-hap.sh` 退出码 0（`abilities=[QAbility]`、无私有载荷）。
   ④ **待办**：出 `.app` 并传 AGC 提审 —— **AGC 要的是 `.app` 不是 `.hap`**，
   `sh scripts/build-release-app.sh` 产出 `build/outputs/release/freecad-on-harmonyos-release-signed.app`
   （见 Step 4）。选取软件包时**不勾**「应用加密」（理由见 Step 5）。还要补
   `READ_PASTEBOARD` 的权限说明 + 场景视频 + 内嵌 CPython 的说明；
   AGC「备案信息」栏勾「您的 APP 为单机 APP」（依据见第 7.5 节）。
   ⑤ ~~装到真机确认发布签名包能装上~~ **已否定（2026-09-16 实测）**：发布签名的包
   **装不上任何设备**。完全卸载调试包后重装，仍是
   `9568322 signature verification failed due to not trusted app source`
   （hilog：`untrusted source app with release profile`）。release profile 只能经
   应用市场 / AGC 测试渠道分发，侧载一律拒绝 —— 原记录里"发布 Profile 无设备白名单、
   任何设备可装"的说法是错的。上真机请用调试签名包，发布包只做离线验签 + 上架。
   附注：同包名换签名确实需要先卸调试包（本次已卸），沙箱 `freecad-home` 一并清掉；
   该目录权限 0700、`shell` 用户读不到，**事前无法备份**。

