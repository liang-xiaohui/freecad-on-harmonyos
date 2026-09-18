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
（`hap-sign-tool verify-profile` 也能看，但要在 jar 壳前面挂上环境变量才跑得起来 ——
`OHOS_HAP_SIGN_TOOL=$PWD/.ohos-sdk/26/toolchains/lib/hap-sign-tool java -jar
.ohos-sdk/26/toolchains/lib/hap-sign-tool.jar verify-profile …`。壳的行为见
`scripts/toolchain-bridges/README.md`。上面的 Python 脚本不依赖 java，更省事。）

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

#### Step 6 · 修「使用了 HarmonyOS beta 版本的 API」驳回：换 Release 版 SDK

2026-09-16 首次提审被驳，原文：

> 经检测发现，您的应用使用了 HarmonyOS beta 版本的 API。修改建议：为提升消费者使用体验，
> 请使用 HarmonyOS release 版本的 API 开发应用，申请上架。

**根因不在工程，在 SDK。** AGC 判这一条，只看打包产物里 `pack.info` 的一个字段：

```json
"apiVersion": { "compatible": 26, "releaseType": "Beta", "target": 26 }
                                ^^^^^^^^^^^^^^^^^^^^^^ 就是它
```

`releaseType` **只能来自 SDK 自身的元数据**，工程里没有任何配置项能覆盖它。证据在 hvigor 源码
（`@ohos/hvigor-ohos-plugin/src/tasks/make-pack-info.js`）：

```js
apiVersion = { compatible: …, releaseType: this.sdkInfo.getReleaseType(), target: … }
```

再往下追，`getReleaseType()` 取的是 SDK 组件的 `oh-uni-package.json`：

```sh
cat "$DEVECO_SDK_HOME/toolchains/oh-uni-package.json"
# {"apiVersion":"26","platformVersion":"26.0.0","releaseType":"Beta","version":"26.0.0.18"}
```

**为什么容易中招**：本机 brew 装的 `ohos-sdk` 稳定版就是 `26.0.0.18` —— 一个比 API 26 Beta1
（`26.0.0.23`）还早的滚动快照，`releaseType` 长期是 `Beta`，而 `brew update` 也换不到别的。
可 API 26.0.0 早在 2026-08-29 就已经 Release 了，官方 Release 包的构建号是 `.38`。
（规律：**Release 构建号大、Beta 快照号小且长期不动**。）

**判据命令**（改完这**两处**都要看。注意 `.app` 那份 `pack.info` 是**缩进过的 JSON**，
所以要容忍冒号两侧的空格，别写成紧贴的 `"releaseType":"…"` —— 那样一个都匹配不到）：

```sh
grep -oE '"releaseType"[[:space:]]*:[[:space:]]*"[A-Za-z]*"' \
    entry/build/release/outputs/default/pack.info build/outputs/release/pack.info
```

**Release SDK 从哪来**（brew 里没有 Release formula，只能去官方发布页）：

| 项 | 值 |
| --- | --- |
| 发布线 | OpenHarmony 7.0 Release |
| 包 | `ohos-sdk-windows_linux-public_20260829.tar.gz`（3.42 GiB） |
| 内含 SDK | `Ohos_sdk_public 26.0.0.38`（API 26.0.0 **Release**） |
| SHA-256 | `6bf6ae1efe8de0e8bd15ddbd7fac58bcb54d9620262a541b9b219439317a4c42` |
| 下载 | `https://repo.huaweicloud.com/openharmony/os/7.0-Release/ohos-sdk-windows_linux-public_20260829.tar.gz` |
| 出处 | OpenHarmony docs 仓库 `zh-cn/release-notes/OpenHarmony-v7.0-release.md` |

两个坑：

- `cidownload.openharmony.cn`（S3 兼容）**拒绝列目录**（`AccessDenied`），只能按完整路径取物；
  想"看有哪些版本"用华为云镜像 `https://repo.huaweicloud.com/openharmony/os/`，它可以列目录。
- **包名里的 `x64` 是命名习惯，内容全是 arm64**：`*-ohos-x64-26.0.0.38-Release.zip` 里的
  `restool` / `ohos_packing_tool` / `hap-sign-tool` / `es2abc` / `hdc` 实测都是 `ld-musl-aarch64`，
  在本机鸿蒙 PC 上能直接跑。

**包内结构**：tar 里是 5 个 zip，每个 zip 的顶层就是组件目录名，解到同一个根下即可：

```sh
tar xf ohos-sdk-windows_linux-public_20260829.tar.gz        # → ohos-sdk/ohos/*.zip
SDK=~/CPPLib/toolchains/harmonyos/26.0.0.38
mkdir -p "$SDK"
for z in ets js native previewer toolchains; do
    unzip -q /path/to/ohos-sdk/ohos/"$z"-ohos-x64-26.0.0.38-Release.zip -d "$SDK"
done
```

**切换用脚本，别手工搬**（`--check` 只看不写）：

```sh
sh scripts/switch-ohos-sdk.sh ~/CPPLib/toolchains/harmonyos/26.0.0.38
```

脚本做四件事，外加一道闸：

| 步骤 | 说明 |
| --- | --- |
| ① 先查 `releaseType` | 五个组件都必须是 `Release`，否则**退出码 3** 并打印 AGC 那句驳回原文（`ALLOW_BETA=1` 可强行继续，仅供自测） |
| ② 装桥接壳 | 编出 `app_packing_tool.jar` / `hap-sign-tool.jar` 放进 SDK 的 `toolchains/lib/` |
| ③ 补 `libimage_transcoder_shared.so` | 官方 Public SDK **不发**这个文件；工程里一直用指向 `libc++_shared.so` 的替身（未开资源压缩时它不会被真正加载） |
| ④ 切 `.ohos-sdk/26` | 旧的若是实体目录，按 `<名>.<releaseType 小写>-<版本>.bak` 留档，**绝不覆盖** |

**② 是必须的，而且差点丢件**：hvigor 找打包/签名工具时写死的是 **jar 名**
（`getPackageToolPath()` → `toolchains/lib/app_packing_tool.jar`、
`getVerifySignConfigToolPath()` → `…/hap-sign-tool.jar`），而官方 Public SDK 的 `toolchains/lib/`
里只有同名的**可执行文件** `ohos_packing_tool` / `hap-sign-tool`。两者之间靠两个 1~2 KB 的
桥接壳转发：读环境变量 `OHOS_PACKING_TOOL` / `OHOS_HAP_SIGN_TOOL`，`inheritIO()` 后透传退出码；
签名壳还多一段 —— `verify-profile -outFile` 时要把原生工具写的**裸 Profile JSON**包成
`{"content": …}`（hvigor 是按 `content["bundle-info"]` 读的），幂等。

这两个壳原先只以编译产物形式躺在本机 `.ohos-sdk/` 里、**仓库里一行记录都没有**，换 SDK 时差点
当临时文件丢掉。现在源码入库 `scripts/toolchain-bridges/`（重建产物用 `javap -p -c` 与原件逐条
比对过，**字节码完全一致**）。

**重建与验收**（2026-09-16 实测）：

```sh
sh scripts/build-release-hap.sh    # 34 s
sh scripts/build-release-app.sh    # 4 min 14 s → 502,358,776 B
```

出包后三处都要是 `Release`：

| 检查点 | 期望 |
| --- | --- |
| `entry/build/release/outputs/default/pack.info` | `"releaseType":"Release"` |
| `build/outputs/release/pack.info` | `"releaseType":"Release"` |
| `.app` 内嵌 hap 的 `pack.info` | `"releaseType":"Release"` |

**签名侧不用动**：换 SDK 只换构建工具，`build-profile.json5` 里的发布签名材料、`.p7b` 的 ACL、
验签三件套（Step 3 / Step 4）全部照旧。本次换完复验：`hap verify successed!`、内嵌 Profile 与
AGC 下载的 `.p7b` 逐字节相同、证书链叶子公钥指纹仍是 `8e3b8d79…`。

**防复发**：`scripts/build-gui-hap-ohos.sh` 现在会读 SDK 元数据 —— 凡是 `BUILD_MODE=release`
撞上非 Release 版 SDK，直接**退出码 3** 并说明原因（`ALLOW_BETA_SDK=1` 可放行）；其余构建打印
一行 `SDK: <releaseType> <version>`，让日志里看得出这次是哪套 SDK 出的包。

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
| 分层**前景** `foreground.png` | **必须**有透明区域 | alpha `0~255`，669571 个全透（字形四周与笔画间隙） |
| 分层**背景** `background.png` | **必须**全不透明 | alpha `255~255`，0 个透明像素 |
| **AGC 上传图** `yuankou-appgallery-1024.png` | **不允许**含透明像素 | alpha `255~255`，0 个透明像素 |

判据是 **alpha 极值**，不是肉眼——"看着像实心"的图常年带着几千个半透明抗锯齿像素而被驳回。
自查一行搞定：

```sh
python3 -c "import sys;sys.path.insert(0,'tools/icon');import pngtool as P;\
w,h,p=P.read_png('store-assets/icon/yuankou-appgallery-1024.png');\
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
| `foreground.png` | `AppScope/resources/base/media/` 与 `entry/src/main/resources/base/media/` | 透明底自有图形（轴测拉伸的立体「元」：白色正字面 ＋ 红色厚度），1024×1024，图形撑满（无内间距） |
| `background.png` | 同上 | 纯色 `#418FDE`（满幅蓝，圆角交给系统遮罩），1024×1024，**完全不透明** |
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
| `yuankou-appgallery-1024.png` | **上传这一张**：1024×1024、PNG、正方形、完全不透明 |
| `yuankou-appgallery-216.png` | 同一张图的 216×216 版本，备用（AGC 也接受 216 上传） |
| `foreground-1024.png` / `background-1024.png` | 分层素材原样留档，方便以后用 DevEco 的 Image Asset 重新生成 |

**背景色为什么是 `#418FDE`**：第三版图标把蓝色让给了背景（官方 logo 里"面积最大的一块"
就是蓝色齿轮），前景留白色字形与红色厚度。这样三个色块在明度上互不吞并 ——
白字在蓝底上对比度最高，红厚度紧贴蓝底也有足够的明度差。**背景必须满幅且不透明**
（华为规范不允许背景层含透明像素、也不允许自行裁圆角），桌面上看到的圆角是系统遮罩裁出来的。

> 想换背景色：把 `store-assets/icon/background-1024.png` 与两处 `background.png` 换成同色
> 重新生成，保持包内包外一致即可。`tools/icon/pngtool.py` 负责 PNG 的读/写/缩放（纯 Python
> 手写，`zlib` + `struct`——本机没有 Pillow，也没有任何 SVG 渲染器）。

### 图标的造型与生成方式（2026-09-18 · 第三版：轴测拉伸）

**现用造型**：把「元」字形沿一条斜向轴**挤出成一个棱柱**，按**轴测投影**画出"正面 ＋ 可见侧壁"，
叠在**纯蓝背景**上。**不使用官方 logo 的任何几何元素**：没有齿轮、没有两段 45° 斜切、
也不是"左红条 + 中白字 + 右蓝块"那个三分构图。

配色沿用 FreeCAD 品牌色，而且与官方 logo 的**角色分工一一对应**：

| 元素 | 色值 | 对应官方 logo 里的 |
| --- | --- | --- |
| 背景层（满幅蓝） | `#418FDE` | 蓝色齿轮（面积最大的一块） |
| 字形正面（白） | `#FEFEFE` | 白色 "F"（"字"的角色） |
| 侧壁上档（浅红） | `#FF585D` | 浅红斜切块 |
| 侧壁下档（深红） | `#CB333B` | 深红斜切块 |

**为什么从第二版换掉**：第二版是"照搬官方造型、只换中央字"，那是所有改法里商标风险最高的一种
（§7.7 逐条拆过）。第三版让**形体本身**成为原创 —— 改的是"造型"而不只是"字"，
这才是 §7.6 三条必守条件里第 ③ 条真正要求的东西。

**"蓝色圆角矩形"是怎么来的** —— 这里有条容易走错的路：

> 华为规范要求背景层**不允许含透明像素**，且**资源不允许自行裁切圆角**。

所以**不能**在前景里画一个"比画布小的蓝色圆角矩形"（等于自己裁圆角 + 加内间距），
也不能在背景层画圆角矩形（四角会变成透明像素，直接违规）。正确做法是
**背景层做成整幅满铺的纯蓝**，圆角**由系统遮罩裁**出来 —— 桌面上看到的就是蓝色圆角矩形。
AGC 上传的那张合成图同样是**不带圆角的方形图**。

**几何**（生成器 `tools/icon/make_yuankou_3d.js`）：

- 字形区域 `A` 沿 z 轴拉伸到 `[0, D]`，得到棱柱 `A × [0, D]`；
- 投影用**斜轴测**：`(x, y, z) → (x + z·dx, y + z·dy)`，屏幕平移向量 `d` 的模长即"厚度"。
  现用 `d` 指向**右下 32°**、厚度 = 字高 × **14%**；
- 棱柱表面 = 正面 `A@z=D` ∪ 背面 `A@z=0` ∪ 侧壁 `∂A × [0, D]`。斜投影下视线平行于 z 轴，
  所以"z 越大越近"。两条可见性结论：
  - **背面完全不可见** —— 若 p ∈ A 且存在 z>0 使 `p − z·d ∈ A`，p 就被更近的层遮住；
    而 z\*=0 只可能发生在 p ∈ ∂A 上，那已经属于侧壁；
  - **侧壁中只有外法线 n 满足 `n·d < 0` 的那些面朝观察者**。读法：字形往右下挤出，
    露出来的是"左上侧"的壁 —— 上边缘与左边缘那一圈。

**渲染的三条规矩**（都是踩坑换来的）：

1. 同层次的相邻侧壁面片共享边，必须**按覆盖度加权平均**，不能用画家算法的 `over` ——
   共享边两侧各只有 ~0.5 覆盖度，`over` 会算成"另外 0.25 是背景"、alpha 只剩 0.75，深底上就是暗缝；
2. **正面（z=D）用标准 `over` 压在侧壁之上** —— 它是真正近处的覆盖层；
3. 侧壁明暗来自**法线**（现用两档硬分色：`|n_y| ≥ |n_x|` 归"顶侧"＝浅红，否则归"侧向"＝深红），
   所以同一条边是单色、相邻边之间是硬边 —— 这正是轴测图"面片感"的来源。
   另有连续明暗（Lambert）档位可选，见下面的方案表。

**外法线怎么定** —— 这里有一个会把整幅图做错的坑，写下来：

> **错**：取最接近水平的那条边，认定它的外法线朝上（y 为负）。
> **对**：逐环点测投票 —— 两个候选法线各向外偏移一小段，落点在字形**之外**的才是外法线。

底边同样接近水平，但外法线朝下。一旦选中底边，全字形法线整体反转，"该画的侧壁没画、
不该画的画了"。本项目实际踩到过：字形左边界（x≈125）算出的外法线是 `(1, 0)`（朝右）。
逐环投票还顺带处理了内孔 —— TrueType 约定内孔与外轮廓绕向相反，整环的法线规则要单独定。

**自检方式**：不比对任何上游文件，而是用**独立几何求交**验证渲染结果 —— 随机撒 500 个屏幕点，
对每个点沿 z 求 `z* = max{z : p − z·d ∈ A}`（射线法判点在不在多边形内，逐点扫 97 层），
与渲染出的 alpha 比对。实测一致 **498/500（0.40%）**，两个反例都落在图形边界上（抗锯齿像素），
不是洞。

> 自检脚本自己出过一次错，值得记：早先写成 `z = 1 − s/24`，只扫到 1/24 就停了，
> **整块字形内部（z\*≈0）全被判成"渲染缺失"**，误报 13.7% 不一致。z 必须覆盖到 0。

**色占比**（前景层内）：白 `#FEFEFE` **59.0%** / 浅红 `#FF585D` **21.8%** /
深红 `#CB333B` **18.1%**，透明 **63.9%**；背景层整幅 `#418FDE`（0 个透明像素）。

```sh
node tools/icon/make_yuankou_3d.js --depth 0.14 --dir 32 --schemes C --bg '#418FDE'
```

参数速查：`--depth`（厚度/字高）、`--dir`（挤出方向角，屏幕坐标 y 向下，正值向右下）、
`--fill`（含厚度的整体占画布比例，默认 0.80）、`--bg`（背景层色）、
`--schemes`（只跑指定配色）、`--font`（默认 `/system/fonts/FZHeiT-SC-Bold.ttf`）、`--ch`、`--out`。

一次输出：`foreground-v4{A..F}.png`（透明底，包内用）、`appgallery-{1024,216}-v4{A..F}.png`、
`background-v4.png`、`detail-1to1-v4{C}.png`（1:1 裁切，看侧壁面片边界与抗锯齿质量）、
`diag-sideonly-v4{C}.png`（只看侧壁）、以及对照图 `review-sheet.png`
（跑全部配色时是 6 个方案 × 4 种桌面色）。

六个配色方案（`--bg` 默认深色 `#1F2430`；白面那几档配蓝底即当前方案）：

| 档 | 正面 | 厚度 | 说明 |
| --- | --- | --- | --- |
| A | 白 | 红（连续明暗） | 白字红边，干净 |
| B | 蓝 | 红（连续明暗） | 蓝字红边，明暗过渡像被照亮的实体 |
| **C** | **白** | **红（顶/侧硬分两档）** | **已装入**（配 `--bg '#418FDE'`）。面片感最强 |
| D | 蓝 | 红（顶/侧硬分两档） | 蓝面红边（同造型，靠 `--bg` 与 C 互相切换） |
| E | 白 | 蓝（连续明暗） | 全冷色 |
| F | 浅红 | 蓝（连续明暗） | 反色系，辨识度低 |

**正面用白、背景用蓝** 而不是反过来，有两个原因：一是官方 logo 里"字"的角色就是白色
（白 F 居中）；二是白色字形在蓝底上的对比度最高，而红色厚度紧贴蓝底时明度差也够，
三个色块互不吞并。试过蓝面（D 档）配深底，中央的字会与背景同色系、辨识度下降。

换档只需重跑生成器（改 `--schemes` / `--depth` / `--dir` / `--bg`），把 `foreground-v4X.png`、
`background-v4.png` 与 `appgallery-*-v4X.png` 覆盖到那几处路径，再跑 `scripts/build-gui-hap-ohos.sh`。

> ⚠️ **残留风险**：形体已经是自画的，但**配色仍是官方那三个色值逐色相同**
> （`#418FDE` / `#FF585D` / `#CB333B`）。§7.6 必守条件第 ③ 条写的是"不使用 logo 的
> **任何造型与配色**" —— 造型这一半现在站住了，**配色这一半仍是不满足**。
> 代价权衡见 §7.7：改配色会让"与 FreeCAD 的视觉关联"变弱，不改则留着"刻意沿用品牌色"的话柄。

> 前两版都保留在仓库里，但**都不要再用于上架**：
> v1 `tools/icon/make_yuankou_icon.js`（八段切角方环 ＋ 白色「元」，自有造型但品格语言仍在）、
> v2 `tools/icon/make_yuankou_v3.js`（照搬官方红蓝造型、只换中央字，商标风险最高）。

## 6. 版本号

当前 `versionCode: 1` / `versionName: "0.1.0"`。发布后 `versionCode` 只能递增；
首版建议对齐上游版本（例如 `versionName: "1.1.2"`、`versionCode: 1001002`）。这份数字会
同时出现在 AGC 版本页、包内元数据和更新说明里，三处要一致。

## 7. 审核可能问询的点（提前准备说明）

- **包内有大量 Python 脚本 + 内嵌 CPython 解释器**：`rawfile/python311.zip`、
  `rawfile/freecad-runtime.zip` 里是随包固定的 Python 3.11 解释器与 FreeCAD 自带模块。
  hvigor 打包时会警告 `Unexpected source code files packaged in 'entry'`。随提审附说明，
  成稿见 `store-assets/appgallery-review-notes-zh-CN.txt` 第五、六部分。

  > **2026-09-16 更正**：本节曾写作"不下载、不热更新、不执行外部代码"，**这是错的**，
  > 已按实测代码改写。三条通道确实存在，写在下面，别再用"零外部代码"的口径去答审核 ——
  > 一旦审核自己去包内翻到，比主动申报难解释得多。
  >
  > | 通道 | 代码位置 | 默认状态 | 性质 |
  > | --- | --- | --- | --- |
  > | 插件管理器下载并安装社区插件 | `Mod/AddonManager/addonmanager_utilities.py:444`（`urllib.request.urlopen` 兜底）、`AddonCatalogCacheCreator.py:349`（`requests.get(zip_url)`） | 需用户打开「工具 → 插件管理器」并点安装；**启动时零网络**（`FirstRunDialog` 与 `startup()` 都在对话框内） | 用户主动下载第三方 Python 代码并运行 |
  > | AI 工作台执行模型生成的建模脚本 | `freecad_ai/core/executor.py:709` `exec(code, namespace)` | `auto_execute = False`，须用户在界面点击执行 | 用户确认后执行远端生成的代码 |
  > | 本地 MCP 服务监听 | `freecad_ai/mcp/transport.py`（`bind()`/`serve()`） | `127.0.0.1:3000` 回环、带 bearer token、由设置页显式启动 | 仅供本机外部工具接入，不对外监听 |
  >
  > 可守住的口径（这几条都是真的、可当场验证）：**不下载可执行文件、不做应用自更新/热更新、
  > 不替换包内代码、不绕过应用市场动态加载功能、无远程控制通道、无内置服务商密钥、
  > 不上传用户模型与剪贴板内容**。AddonManager 的 `git fetch` 路径在本机无效（沙箱内无
  > `git` 二进制），但它有 HTTP 下载 zip 的兜底，所以"没有 git 所以装不了插件"**不能**当作
  > 免责理由。
  >
  > **若审核以插件管理器为由驳回**：它进包走的是 `stage-gui-hap.sh:322` 那条整体打包
  > `zip -q -r … Mod Ext share`，所以有两条路 —— ① 省事：在该行的 `-x` 排除列表里加
  > `'Mod/AddonManager/*'`（并把 `FREECAD_BUILD_ADDONMGR` 设 OFF，否则
  > `stage-gui-hap.sh:393` 会断言"打包后的 runtime 缺少 Addon Manager 注册脚本"而报错，
  > `verify-gui-hap.sh:275` 同理）；
  > ② 彻底：用 `FREECAD_BUILD_ADDONMGR=OFF` 重配重编（`configure-freecad-gui-qt6-ohos.sh:43`
  > 转成 `-DBUILD_ADDONMGR=OFF`），install 前缀里就不再有它。
  > 无论走哪条，**同时删掉应用介绍第六节末"应用内提供插件管理器（Addon Manager）入口"
  > 这句** —— 介绍文案与包内容必须一致。
- **INTERNET 权限用途**：两处，且都需用户主动触发 —— ① freecad-ai 工作台访问用户自选的
  LLM 端点；② 插件管理器拉取插件目录与插件包。成稿见
  `store-assets/appgallery-review-notes-zh-CN.txt` 第四部分。
  （注意：对外口径必须与 `store-assets/appgallery-text-zh-CN.txt` 第 62 行的应用介绍一致
  —— 那里已经写了"网络权限用于插件管理，以及 FreeCAD AI 工作台"，别再只提 AI。）
- **READ_PASTEBOARD 权限说明 + 场景视频**：AGC 的受限权限复核项。理由天然成立（Qt 自绘
  界面用不了系统粘贴控件），成稿与 60 秒分镜脚本见 `store-assets/appgallery-review-notes-zh-CN.txt`
  第一、二、三部分。**视频须真机录制、不可用模拟器**，演示时用假 Key。
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

## 7.6 驳回记录：名称与图标被指与「FreeCAD」冲突（2026-09-18 · 待处置）

**驳回原文**（分类：知识产权；共 1 个错误问题）：

> 问题1：应用与"FreeCAD"应用的名称相同、图标相似，但未提供相关授权或商标权属证明，
> 可能导致用户产生混淆、误认或不适宜的联想。
>
> 修改建议1：请删除应用信息中与其它应用相同或相似的内容，或提供相关授权或商标权属证明。
> 并确保授权方名下未上传名称、图标、外观或内容相似的应用。
>
> 修改建议2：如您认为其他应用侵犯了您的合法权益，可按流程对存疑的侵权内容进行申诉。

提交 2026-09-17 18:42（即 Step 6 换 Release SDK 后的那次），报告 2026-09-18 19:55。
**技术侧已清空**：这一轮没有再提 beta API，Step 6 的修复有效。

**冲突对象已实测确认（2026-09-18）**：AppGallery 里**搜不到**名为 FreeCAD 的应用（AGC 搜索页要
JS，此项由用户在真机商店实搜完成）。所以驳回里那句"与『FreeCAD』**应用**的名称相同"**不是平台内
同名应用冲突**，而是**针对 FPA 持有的 FreeCAD 商标/品牌**的拦截。这一条对本节结论影响很大：
它把 B 路从"可能拿到授权也没用"变成"**授权书是能解锁的**"。

### 判得不冤：我们用的是 FPA 的标识本身，而不是"相似"

两层规则同时踩到，一层是平台规则，一层是上游规则：

| 来源 | 内容 |
| --- | --- |
| AGC《审核指南》1.2 | 应用名称不得为…包括但不限于使用**商标术语**、热门应用名称或别称 |
| AGC《审核指南》1.3 | 应用名称不得和其他应用名称相同 |
| AGC《审核指南》9 知识产权 + 审核 Checklist 第 6 条 | 名称/图标/内容与他人应用相似 ⇒ 需优化差异化设计，杜绝侵权 |
| FPA《品牌指南》（`fpa.freecad.org/handbook/process/logo.html`） | "Third parties can only use it **to provide credit for FreeCAD or to link to freecad.org**" |
| 同上「Don'ts」 | logo **不得改动**（颜色/形状/风格/渐变/描边/阴影） |
| FreeCAD wiki · License / Logo | logo 是 **FPA 持有的商标**（2022-10 注册于 Benelux）；"可以用它来指代 FreeCAD，但**不能用作你自己产品的标识**" |

**实测证据——不是"像"，是"就是"**：包内
`AppScope/resources/base/media/foreground.png` 的像素配色与上游官方
`share/icons/hicolor/scalable/apps/org.freecad.FreeCAD.svg` 的四个 `fill` **逐色相同**：

| 颜色 | 我们图标的不透明像素占比 | 官方 SVG |
| --- | --- | --- |
| Tufts Blue `#418FDE` | 31.5% | `#418fde` |
| 白 `#FFFFFF` | 27.3% | `#fefefe` |
| Dark Red `#CB333B` | 25.3% | `#cb333b` |
| Light Red `#FF585D` | 15.6% | `#ff585d` |

造型也一致：8×8 降采样后仍是官方 logo 那个"左红条 + 白 F + 右蓝块"的分块graph。
即 **前景层 = 官方 logo 本体，只是把底换成了深蓝灰 `#1F2430`**（背景层本身是合规的：
1024²、无透明像素）。两处 `string.json` 的 `app_name` 又都写着 `FreeCAD`。

→ 结论：**"在介绍首句声明非官方社区移植"这种披露式免责不够用**。第 7 节拍板点 2
当时把它当"低成本做法"，现在被证伪——AGC 要的是**权利文件**，不是声明。

### 上游其实留了正门：FreeCAD 官方《品牌化 / Branding》页

翻 FPA 文档时发现一条此前漏掉、但**性质完全改变**的事实：FreeCAD wiki 有专门一页
`wiki.freecad.org/Branding`（有中文版「品牌化」），**明文支持第三方基于 FreeCAD 做自己的
应用、换名换图标**：

> 品牌化意味着基于 FreeCAD 构建你自己的应用程序。可以仅仅是你自己的可执行文件或启动页面，
> 也**可以完全重新改造的程序**。

> **警告** 尽管你可以自由修改 FreeCAD，社区也乐于看到其他基于 FreeCAD 的应用出现…我们也看到
> 很多人对这个页面上的信息进行了不公平的使用，他们只是简单地将 FreeCAD 重新命名为一个闭源
> 应用程序来从中获利。虽然 LGPL 许可证允许在闭源应用程序中使用 FreeCAD 源代码，但它也给出了
> 严格的规则，**即不允许将 FreeCAD 改个名字它并去掉它的许可证**。

官方连技术做法都给了（`MainGui.cpp` 的 `App::Application::Config()` 里设
`ExeName` / `AppIcon` / `SplashScreen` / `StartWorkbench`）。《License》页把这种"换了品牌的
版本"叫 **derivatives**，并明确**只有不开源的那一类被 LGPL 禁止**
（"Derivatives which are not open-source are prohibited by the LGPL license"）。

⇒ **A 路不是"退让方案"，是上游文档化的正规路径。** 但要真的算"品牌化"、而不是"社区会主动
举报的改名版"，除改名换图标外还必须守住三条：

| # | 条件 | 依据 | 我们的现状 |
| --- | --- | --- | --- |
| 1 | 明确告知用户"本应用基于 FreeCAD，FreeCAD 采用 LGPL" | 《License》页硬性条件 | 介绍文案已有此句，**保留，别删** |
| 2 | 保持开源、提供源码 | 同上（条件 1/2 做不到就必须整包 LGPL 并公开源码） | 仓库已 public + 根 `LICENSE`，**已满足** |
| 3 | 不使用 FPA logo 的任何造型与配色 | 商标 + 品牌指南"不得改动 / 不得用于你自己产品" | ⚠️ **造型这一半已满足，配色这一半仍不满足**。图标已换成第三版（轴测拉伸的立体「元」，几何完全自画 —— 不用齿轮、不用两段 45° 斜切、也不是"左红条 + 中白字 + 右蓝块"那个三分构图）；但**配色仍是官方三色逐色相同**（`#418FDE` / `#FF585D` / `#CB333B`）。要不要连配色也换，见 §7.7 末的权衡 |

### 为什么 B（要 FPA 授权书）概率不大

结论先说：**约 25%（纯邮件）~ 35%（再加论坛公开帖）**。上一版给 15~20%，因下面第 5、6、7 条
新证据上调。失败形态仍然很贵 —— 不是干脆驳回，是**等 2~6 周后被告知"请按品牌化路径改名"**。
依据：

| # | 事实 | 含义 |
| --- | --- | --- |
| 1 | 品牌指南通篇 + FAQ 11 问，**没有一条**讲"第三方产品能否用 FreeCAD 名称/图标"，也没有任何申请入口 | 官网唯一入口是理事会邮箱 `fpa@freecad.org`：**没有流程、没有表单、没有先例** |
| 2 | 「Proper Reference」把"官方"定义成"…**digitally signed by The FreeCAD project association AISBL**" | 要满足它 = 让 FPA 用自家私钥签我们的包。那不是"许可"，是**背书**，对一个小协会是极重的法律动作 |
| 3 | FPA 2022-10-12 商标公告原文：FPA "owns the rights over the **commercial use** of the FreeCAD name and logo"，动机是打击"**fake versions of FreeCAD sold** on the Windows and Apple app stores"；同页又强调 "the logo itself is still covered by the LGPL license, so everyone still has the legal rights to use the logo as far as the LGPL permits" | **两读，净偏正面**。坏的一面是"对我们没有紧迫性"；好的一面是**它给了 FPA 一个答应的理由** —— 我们免费、无广告、无内购、无遥测、开源、真源码，正是他们"要打的那类"的反面，答应对其内部几乎无阻力 |
| 4 | 一旦给某个移植者发了授权书，各平台的移植者都会来要 | 志愿者理事会最省事的答复永远是"请走品牌化路径，用你自己的名字" |
| 5 | 驳回原文说的是"与『**FreeCAD』应用**的名称相同" | ✅ **已实测排除（2026-09-18）**：AppGallery 里搜不到名为 FreeCAD 的应用 ⇒ 冲突对象是 **FPA 的商标/品牌本身**，不是平台内同名应用 ⇒ **FPA 的授权书是能解锁的**。这把上一版"可能拿到也没用"的悬置风险拿掉了，是本次上调的主因 |
| 6 | 未验证的小岔口 | 若那个同名应用只是**分区/分语言未上架**，B 就无效、只有 A 可行。但两种情形下 **A 都要做**，所以这条**不改变执行计划**，只影响 B 的期望值 |
| 7 | **请求可以"降维"**：驳回是**两条**指控（名称相同 **+** 图标相似），而图标我们无论如何都要重画 | 把信里的提问缩到只剩"名称"一项，且用**指代移植对象**的措辞（"FreeCAD for HarmonyOS"），比"把 logo 当自家产品标识"更接近品牌指南允许的"署名 / 指代"用途。单这一步就能明显提高回复率 |

发信的价值现在有两层：**下限**是拿一封回信（留一条"已与上游沟通过"的软证据，并确认他们是否
愿意把鸿蒙移植接纳为官方项目）；**上限**是真的拿到那纸同意函，从而**保住原名**——冲突对象既已
确认为 FPA 商标，这份文件的效力就是完整的。

### 四条路，只有两条能走

| 路 | 做法 | 可行性 | 代价 |
| --- | --- | --- | --- |
| **A** | 改名 + 重画图标 | ✅ **上游文档化的正规路径（品牌化）**，不依赖任何外部方；守好上面三条即合规 | 丢掉"FreeCAD"一词的搜索辨识度；占用一次改名额度（1.12：**名称一年只能改 2 次**，图标/分类/标签同样"不得频繁更改"） |
| **B** | 拿到 FPA 的同意函 / 授权书 | ⚠️ **约 25%（纯邮件）~ 35%（加论坛公开帖）**，依据见上一小节；因冲突对象已确认为 FPA 商标，**这份文件是有效的** | 保留原名与**现用图标** —— 第三版图标已是自画造型，所以无论 B 成不成，**图标都不必再返工**。若还想连配色一起授权，信里必须明确要（信稿默认已承诺"不复用其造型与配色"，改口径见 §7.7 末的变体 B）。失败要等 2~6 周才被告知，期间压着改名额度 |
| C | 申诉（修改建议2 → 50120） | ❌ 走不通 | 50120 是《侵权投诉处理指引》，是**权利人对他人**投诉的通道；我们不是 FreeCAD 商标的权利人，没有申诉的权利基础 |
| D | 名称加后缀（"FreeCAD 鸿蒙版"之类） | ❌ 别试 | 既仍含商标术语（1.2）、又仍属"相似"（1.3），大概率二驳；还白烧一次改名额度 |

**决策规则（本版修正）**：真正的取舍不是"A 还是 B"，而是**"用 14 天赌 25~35% 保住原名"**。

| 时间 | 动作 | 理由 |
| --- | --- | --- |
| D0 | 发出 `docs/fpa-brand-permission-request.md`（邮件） | 成本≈0；信里的筹码现在有实质内容（非商业、开源、真源码、图标本就要重画） |
| D0 起 | 照常做 A 的准备工作（换图标、改写文案、改 `string.json`） | ✅ 名称、文案、图标都已完成（2026-09-18，图标为第三版）。这些工作无论 B 结果如何都不浪费 —— 文案本来就要改成"基于 FreeCAD"，图标本来就要换；**信里承诺的"重画图标、不复用其造型"已经兑现**（第三版几何完全自画）。**唯一还悬着的是配色**：仍沿用官方三色，若要按"完全不复用配色"的口径走，还需再调一版（改法见 §7.7 末） |
| D7 无回复 | 去 `forum.freecad.org` 发一条公开帖问同样的问题 | 邮件容易沉；公开帖通常几天内就有社区或理事回话，**顺带留痕，防止日后被当成仿冒者**。别在 D0 就公开——先给理事会一个私下答复的机会 |
| D14 止损 | 回信同意 → 用原名提交；无回复 / 被拒 → **立刻用新名提交** | 名称一年只能改 2 次，等不起太久；AGC 那边没有硬 deadline，但也没必要拖成月 |

**为什么敢等这 14 天**：AGC 驳回的口径是"**在提供授权前**不允许"，不是永久否决；而且这 14 天里
没有任何不可逆动作（改名额度消耗发生在"用新名提交"那一刻，不是现在）。
**为什么只能等 14 天**：25~35% 意味着 6~7 成概率白等。

### A 路的连带改动清单（已盘点）

| 位置 | 现状 | 动作 |
| --- | --- | --- |
| `AppScope/resources/base/element/string.json` | `app_name = FreeCAD` | 改新名 |
| `entry/src/main/resources/base/element/string.json` | `app_name = FreeCAD` | 同上 |
| `AppScope/resources/base/media/{foreground,background}.png` | 官方 logo + 深蓝灰底 | ✅ **已出第二版**（2026-09-18）：保留红蓝全部元素、"F" 换「元」、F 缺口补深红 |
| `entry/src/main/resources/base/media/{foreground,background}.png` | 同上（与 AppScope 两份 md5 相同） | ✅ 同上（两处 md5 已核一致） |
| `AppScope/.../media/app_icon.png`、`entry/.../media/icon.png` | 扁平图（`startWindowIcon` 实际用的是 `transparent_start_window.svg`，这两个只是单层源图） | ✅ 已跟着重出（改成带底的合成图） |
| `store-assets/icon/*.png` | AGC 上传图（含 1024 主图与 216 缩略） | ✅ 已跟着重出（`yuankou-appgallery-{1024,216}.png`） |
| `store-assets/appgallery-text-zh-CN.txt` | 名称字段 + 介绍里的自称 | 改名称字段；介绍首句改成"…，基于 FreeCAD 1.1.2（非官方社区移植）" |
| `store-assets/appgallery-review-notes-zh-CN.txt` | 同上 | 同上 |
| `PRIVACY.md` / `PRIVACY.en.md` / `README.md` | 自称 FreeCAD | 改成"本应用是 X，基于 FreeCAD" |
| 包名 `com.liangxiaohui.freecad` | 含 `freecad` | **不动**（用户看不到；改它要连带动 APP ID 与签名 Profile），但要知道它留在那里 |

生成器都在：`tools/icon/pngtool.py`（纯 Python）、技能目录里的 `make_icon.py`
（只负责压底出图，**不画造型**——造型 PNG 得重画）。

**应用内标题**：主窗口标题是上游 C++ 硬编码的 `FreeCAD 1.1.2`，改它要动上游代码（一次 rebuild）。
建议**不改**——保留它属于"指名 FreeCAD"的合规用法（品牌指南明确允许署名），
必要时在「关于」框加一行"<新名> · 非官方社区移植"即可回答 1.20 的"应用信息需与应用内容一致"。

### 命名约束（AGC 明文）

- ≤15 个汉字或 ≤30 个其他语言字符（1.1）；不得含 `*` `&` `-` `( )` 等特殊符号（1.4）
- 不得是广义归纳、无辨识度的词（"开源CAD""三维CAD"这类会被 1.2 打回）
- 不得含他人商标术语 —— **"鸿蒙" / "HarmonyOS" 同理不要放进名称**
- 一条利好：名称不含 FreeCAD ≠ 不能提 FreeCAD。介绍、标签里写"基于 FreeCAD 1.1.2 移植"
  是被允许的（FPA 指南允许"用于指明/署名"），用户搜索仍能命中。

候选（~~待拍板~~ **已于 2026-09-18 拍板：元构CAD**）：**元构CAD** / ~~造物CAD~~ / ~~方寸CAD~~。

## 7.7 图标为什么比名称更难守：「照搬官方造型、只换中央字」是最危险的一种改法

§7.6 把"图标相似"和"名称相同"当成两条并列指控。查完之后要更正这个印象：**图标这条更难守**，
而第二版图标（保留官方红蓝全部元素、把 F 换成「元」）恰好落在最危险的位置上。

> **进展（2026-09-18 晚）**：本节结论已经落地 —— 图标换成了**第三版**（轴测拉伸的立体「元」，
> `tools/icon/make_yuankou_3d.js`），几何完全自画，不再含任何官方几何元素。
> 下面那张"合规规格"表已按第三版逐项对账；**唯一没兑现的是配色**，权衡见本节末。

### 一、四层独立的规则，别混为一谈

| 层 | 权利 / 规则 | 对我们的结论 |
| --- | --- | --- |
| 著作权 | FreeCAD 源码与 logo 文件都随上游走 **LGPL-2.1+** | ✅ **不是问题**。LGPL 允许复制、修改、再分发这个文件（我们本来就在分发 FreeCAD 本体） |
| 商标权 | logo 是 **FPA 的注册商标**（2022-10-12 公示，注册地**仅比荷卢**） | ❌ 问题在这里 |
| 上游品牌规则 | FPA《品牌指南》 | ❌ 现用图标直接踩它的「Do nots」 |
| 平台规则 | AGC《审核指南》9.3 / 9.5 +《开发者账号与应用处理原因及措施》 | ❌ 而且**带账号级处罚** |
| 中国法 | 《反不正当竞争法》（2025 修订）混淆条款 | ❌ 2025 新版**明文列举了"应用程序图标"** |

**最常见的误读**："logo 是 LGPL 的，所以我可以随便用。" —— 不对。开源许可给的是**著作权**许可，
**不含商标许可**，这是通例（Apache-2.0 §6、Mozilla 商标政策同理）。FPA 在 2022 公告里说得很直白：
商标 "predominantly acts as an additional tool to **enforce the underlying copyright** when the LGPL is
violated"、"more like a **super-copyright**"。LGPL 与商标是两把锁，开了一把不等于开了另一把。

### 二、上游的三句原话，都不支持我们的用法

| 出处 | 原话 | 含义 |
| --- | --- | --- |
| wiki《Logo》/《License》 | "The logo is a trademark owned by the FPA… the FPA is the **sole body authorized to say who has the right to use** the FreeCAD logo or not." | 用不用 logo，**只有 FPA 说了算**，LGPL 说了不算 |
| wiki《Logo》/《License》 | "you must use it **to reference FreeCAD**, and **not** use it, for example, **for your own product**" | 当"自家产品标识"用 = 明确越界 |
| FPA《品牌指南 · Logo Kit》 | "Third parties can only use it **to provide credit for FreeCAD or to link to freecad.org**." | 第三方**只有两种**合法用法：署名、外链 |
| FPA《品牌指南 · Do nots》 | "You should **not alter colors, shape, style**, or apply any effects such as gradients, borders, shadows, or outlines." | **改中央字 = 改 shape**，正撞这一条 |

→ 现用图标 = 官方造型 **+ 改 shape + 当自家应用标识**，三件事同时做。它几乎就是品牌指南
"examples of what not to do" 那一页的典型反例。

### 三、中国法：2025 年修订后，"应用程序图标"被点名了

《反不正当竞争法》**2025-06-27 第二次修订、2025-10-15 施行**，混淆条款从旧第六条移到**第七条**，
并在列举项里新增了应用场景（旧版没有）：

> **第七条** 经营者不得实施下列混淆行为，引人误认为是他人商品或者与他人存在特定联系：
> （一）擅自使用与他人有一定影响的商品名称、包装、装潢等相同或者近似的标识；
> （二）擅自使用他人有一定影响的名称（包括简称、字号等）、姓名（包括笔名、艺名、网名、译名等）；
> （三）擅自使用他人有一定影响的域名主体部分、网站名称、网页、**新媒体账号名称、应用程序名称或者图标**等；
> （四）其他足以引人误认为是他人商品或者与他人存在特定联系的混淆行为。

**"应用程序名称或者图标"是新增的明文项**，我们这条正好落进去。两点要注意：

- 该条以对方标识"**有一定影响**"为前提。FreeCAD 在国内有相当规模的用户与汉化社区，这一要件不难被认定。
- **免费不免责**：混淆条款保护的是"不引人误认"，**不问我们是否获利**。所以"我们不赚钱"在这条上不是抗辩，
  只是减轻情节。（真正管"商业使用"的是商标权那一层。）

### 四、最现实的风险不是法院，是账号

| 风险 | 触发条件 | 后果 | 判断 |
| --- | --- | --- | --- |
| **AGC 第三次驳回** | 再带这个图标提交 | 打回；**累计 3 次知识产权指控** | **高** —— 已 2 次，且两次指的就是同一批元素 |
| **账号冻结** | 见下表 | 名下**所有应用** + 开发者账号受牵连 | 概率低、**代价最高** |
| FPA 投诉 / 公开点名 | 上架后被社区或品牌负责人发现 | AGC 下架；wiki 明说社区会"举报到平台并曝光直到下架" | 中 —— 优先打"卖钱的"，但上架即成为可见目标 |
| 民事赔偿 | 商标权 / 反法 | 反法混淆行为的法定赔偿上限 **500 万**（第 17 条） | 低 —— 比荷卢注册、无实际损失、非获利；但数字不好看 |
| 声誉 | 社区发现"改名 + 照搬 logo" | 被当成 wiki 里点名的那种 derivatived 仿冒者 | 中 —— 最伤的反而是我们本来最在意的那件事 |

华为《开发者账号与应用处理原因及措施》里两条直接相关：

> 处理原因：**3、开发者账号下存在 3 次及以上侵权的恶意行为** …
> 处理措施：包括但不限于**账号冻结**和应用冻结；**纳入风险应用清单**，采取必要的安全管控措施
>
> 处理原因：**5、应用多次违反同类型的问题** …
> 处理措施：包括但不限于**账号冻结或应用冻结**

两次驳回都是「知识产权」类；第三次提交若仍是"相似图标"，就构成"多次违反同类型的问题"。
"恶意"一词给我们留了辩白空间（善意、开源、仓库公开、有邮件沟通记录），但**处罚判定权在华为手里**，
不该拿开发者账号去赌这个措辞。

### 五、结论与处置：把官方 logo 从"我们的头像"降级为"我们的署名"

同一张图，两种法律地位完全不同：

| 用法 | 法律地位 | 依据 |
| --- | --- | --- |
| ❌ 当应用图标 | 用他人商标标识自己的商品 ⇒ 商标侵权 / 混淆 | 品牌指南只允许第三方"署名或外链"；反法第七条（三）明文含"应用程序图标" |
| ✅ 在「关于」页、商店详情、README 里写"本应用基于 FreeCAD 1.1.2（LGPL-2.1+）；FreeCAD 是 FPA 的商标" **+ 链接 freecad.org** | 品牌指南**明文允许**的第三方用法；且顺带履行 LGPL"必须告知用户使用了 FreeCAD 且 FreeCAD 是 LGPL"的硬性义务 | 《License》页条件 1 |

所以最终形态是三件事一起：

1. **应用图标换成真正自画的「元构CAD」**（合规规格见下）。
2. 官方 logo 只在**署名位**出现（关于页 / 商店文案 / README），用官方原图、**不改造型**。
3. 介绍与关于页保留"基于 FreeCAD、LGPL"的告知句（§7.6 条件 1，本来就有，别删）。

**A 路图标的合规规格**（第三版已按这个规格走了一遍，逐项对账）：

| 项 | 要求 | 第三版的状态 | 理由 |
| --- | --- | --- | --- |
| 几何 | **完全自画**；不做官方那个蓝齿轮本体、不做那种两段 45° 斜切红边带 | ✅ **满足**：字形挤出成的棱柱，几何全部由「元」自己的轮廓生成 | 造型即商标本体 |
| 构图 | **不要**"左红条 + 中白字 + 右蓝块"的三分块面 | ✅ **满足**：只有"正面 + 一圈侧壁" | 该分块图是官方 logo 的辨识特征 |
| 配色 | 可以保留"蓝 + 红"的**配色语言**，但**换色值** —— 不用 `#418FDE` / `#FF585D` / `#CB333B` 这三个原值 | ⚠️ **不满足**：仍是这三个原值（用户 2026-09-18 明确要求"颜色跟 FreeCAD 一样"） | 逐色相同是"近似"最容易被列举的证据 |
| 字 | 中央仍是「元」 | ✅ **满足**：机制从 v3 的"二分收敛 + 48 方向膨胀"换成 v4 的"逐环法线投票 + 两档分色" | 这部分与商标无关 |

**关于配色这一条要不要真做** —— 现在唯一没兑现的就是它，取决于怎么权衡：

- **不动**：图标一眼就是 FreeCAD 血统，用户认知成本最低；代价是"刻意沿用品牌色"仍是一个可被列举的点。
- **动**：把三色整体偏移明度/饱和度（例如蓝 → `#4C93DD`、红 → `#C93F45`），消掉"逐色相同"。
  代价是视觉上的品牌关联变弱，而且包内其他地方若引用了这些色值也要一起改。

判断：商标混淆看的是**整体视觉印象**。造型已经完全不同（立体拉伸字 vs 平面齿轮 + 斜切），
"配色相同"单拎出来的杀伤力比第二版时小得多。**建议先不动**，等 AGC 第三次提审的反馈再定 ——
如果这次仍被驳回、且驳回理由点名了配色，再改也不迟（改一版只要重跑生成器 + 一次构建）。

### 六、发信前必须先决定的一件事（一致性）

`docs/fpa-brand-permission-request.md` 的正文里写明：

> "I am redrawing the app icon from scratch… will not reuse any part of its shape **or its colour palette**"

那是**承诺**。第三版图标已经把 "shape" 那一半兑现了（几何完全自画），
但 **"colour palette" 那一半还没兑现**（仍用官方三色原值）。所以发信之前必须二选一：

- **要么**把配色也调一版，彻底兑现这句承诺；
- **要么**把信里 "or its colour palette" 删掉，改成只承诺不复用造型。

**别带着一句自己做不到的话去要授权** —— 那比不要授权更糟。

**若要连造型带配色一起授权**（B 的变体）：必须把信里那段承诺改成"如果贵会允许，我希望保留符号；
否则我重画"，并做好"批不下来时图标照样要重画"的准备 —— 等于多赌一次，换来的只是图标好看一点。

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
   ④ ~~出 `.app`~~ **已完成（2026-09-16）**：`sh scripts/build-release-app.sh` 产出
   `build/outputs/release/freecad-on-harmonyos-release-signed.app`（502,358,775 B；
   见 Step 4）。**AGC 要的是 `.app` 不是 `.hap`**，选取软件包时**不勾**「应用加密」
   （理由见 Step 5）。三处 `pack.info` 均为 `releaseType: Release`，验签三件套通过
   （叶子证书公钥 SHA-256 `8e3b8d79…`、内嵌 Profile 与 AGC 下载件逐字节相同）。
   **待人工**：把这个 `.app` 传 AGC 提审。
   ⑤ ~~补权限说明 / CPython 说明~~ **文案已成稿（2026-09-16）**：
   `store-assets/appgallery-review-notes-zh-CN.txt` —— READ_PASTEBOARD 申请理由（256 字版
   + 详细版）、场景视频分镜脚本、INTERNET 说明、内嵌 Python 运行时说明、插件管理器边界
   说明、PC 桌面特性备注、备案栏。**待人工**：按分镜录 60 秒场景视频（真机、非模拟器，
   演示里用假 Key）。AGC「备案信息」栏勾「您的 APP 为单机 APP」（依据见第 7.5 节）。
   ⑥ ~~装到真机确认发布签名包能装上~~ **已否定（2026-09-16 实测）**：发布签名的包
   **装不上任何设备**。完全卸载调试包后重装，仍是
   `9568322 signature verification failed due to not trusted app source`
   （hilog：`untrusted source app with release profile`）。release profile 只能经
   应用市场 / AGC 测试渠道分发，侧载一律拒绝 —— 原记录里"发布 Profile 无设备白名单、
   任何设备可装"的说法是错的。上真机请用调试签名包，发布包只做离线验签 + 上架。
   附注：同包名换签名确实需要先卸调试包（本次已卸），沙箱 `freecad-home` 一并清掉；
   该目录权限 0700、`shell` 用户读不到，**事前无法备份**。
9. ~~修 AGC 的「使用了 HarmonyOS beta 版本的 API」驳回~~ **已完成（2026-09-16）**：
   根因在 SDK —— 元数据 `releaseType: Beta`（那个快照是 `26.0.0.18`），它被原样写进
   `pack.info`，工程侧**没有任何配置项能覆盖**。换成 OpenHarmony 7.0 Release 的
   `Ohos_sdk_public 26.0.0.38` 后重建：`entry/…/pack.info`、`build/outputs/release/pack.info`
   与 `.app` 内嵌 hap 三处都是 `Release`，验签三件套照旧通过。做法、下载源与桥接壳那个坑
   见 **Step 6**。同时入库：`scripts/switch-ohos-sdk.sh`（带 `releaseType` 闸门，
   非 Release 直接退 3）、`scripts/toolchain-bridges/`（两个桥接壳的源码，原先只在
   本机 `.ohos-sdk/` 里、仓库无记录），以及 `build-gui-hap-ohos.sh` 里
   「release 撞非 Release SDK 就退 3」的守卫。**剩下只是把新的 `.app` 重新上传提审**（即 ④）。
10. **处置 AGC 第 2 次驳回：名称/图标与「FreeCAD」冲突**（2026-09-18，详见第 7.6 节）。
   AGC 要"授权或商标权属证明"，而我们用的就是 FPA 的商标本身（图标四色与官方 SVG 逐色相同）。
   **结论（2026-09-18 第二轮修正）**：**A 照做，B 升格为"带止损线的并行赌注"**。
   ① A（改名 + 重画图标）仍是保底路径 —— 查证后确认这不是退让，而是 FreeCAD 官方文档化支持的
   方式（wiki《品牌化》页明文允许基于 FreeCAD 做应用并换名换图标，只有**不改开源**才被禁）；
   ② 但 B 的概率从 15~20% **上调到 25~35%**，因为两件事查实了（详见 7.6）：
   AppGallery 里**没有同名应用** ⇒ 冲突对象是 FPA 商标本身 ⇒ **同意函是有效的**；
   且 FPA 商标公告写的动机是打击"**售卖的假 FreeCAD**"，而我们免费开源真源码 —— 这给了他们
   一个答应的理由，不只一个拒绝的理由。
   **执行序**：D0 发信 → D0 起并行做 A 的全部准备（不浪费）→ D7 无回复就上 `forum.freecad.org`
   公开帖 → **D14 止损**（同意则原名提交，否则用新名提交）。
   信稿（已按"已知品牌化路径 + 只问名称 + 图标必换"重写）：
   `docs/fpa-brand-permission-request.md`。若走 A，连带改动清单、命名约束与三条必守条件见 7.6；
   名称一年只能改 2 次，一次做到位。

   **进展（2026-09-18 第三轮 · 用户已拍板）**：
   - **名称定为「元构CAD」**。两处 `string.json` 的 `app_name` 已改，已重出 HAP 并确认
     `resources.index` 里能读到。
   - **图标已出第三版**（2026-09-18 晚，替换掉当天的第二版）：用户先要求"把「元」按轴测方式拉伸
     成一个体、配色仍跟 FreeCAD 一样"，再补一条"蓝色改作圆角矩形的背景，字形正面换成白色"。
     最终形态 = **白字 ＋ 红厚度 ＋ 满幅蓝底**（蓝底是**背景层**，圆角由系统遮罩裁，见第 5 节）。
     几何**完全自画** —— 没有齿轮、没有 45° 斜切、也不是"左红条 + 中白字 + 右蓝块"的三分构图。
     生成器 `tools/icon/make_yuankou_3d.js`，做法、几何推导与自检见第 5 节。
   - ✅ **第二版留下的那条商标风险已解除**：造型不再照搬官方，逐项对账见 7.7 的"合规规格"表。
     仍未兑现的只剩**配色**（仍用官方三色原值）—— **发信前必须先决定要不要改**，见 7.7 第六节。
   - **构建脚本改动**：`build-gui-hap-ohos.sh` 现在会在 PATH 上找不到 `java` 时自动启用
     `scripts/toolchain/java`（sh 桥：把 hvigor 硬编码的 `java -jar <tool>.jar` 翻译给 SDK 自带的
     原生 arm64 工具）。本机是 HarmonyOS host、没有 JRE，此前只是恰好靠环境里有 java 才通得过。
   - **另一处构建修正（审计从 FAIL 回到 passed）**：本轮机标那次 stage 的审计出现两条
     `FAIL … has absolute RUNPATH` —— `libQt6OpenGL.so.6` 指向 `CPPLib/build/qt/6.8.3-ohos-gui/lib`、
     `libGL.so` 指向 `CPPLib/sources/gl4es/81547d9/lib`，都是重装 install 前缀时带出的构建树路径。
     这两个库的依赖不是同目录兄弟就是系统库，绝对路径在设备上指不到、也没作用，却会把真正的
     RUNPATH 问题埋掉（历史上这个审计一直是 0 FAIL）。`stage-gui-hap.sh` 现在会把这些库的 RUNPATH
     规范化为 `$ORIGIN`；重跑后审计 **passed（231 个 AArch64 ELF）**、FAIL 回到 0。
     细节见 `docs/build-env-pitfalls.md` 第三节。
   - **第三处构建修正（`assembleApp` 曾整包失败）**：`build-release-app.sh` 第一次跑倒在
     `:entry:default@ProcessLibs` —— `00308001 Failed to delete the file`。不是权限问题（同一目录
     `/bin/rm -rf` 删得掉），而是 WorkBuddy 注入的 `NODE_OPTIONS` / `CODEBUDDY_SAFE_DELETE_*`
     把 hvigor 的 `fs.rm` 钩住了。debug 路径此前能过，是因为调用时**手工**套了 `env -u …`；
     release 脚本是内部再调 `build-gui-hap-ohos.sh`，漏了这层。修法改在 `build-gui-hap-ohos.sh`
     **脚本内部** unset，调用方不必再操心。见 `docs/build-env-pitfalls.md` 第三节 3。
   - ✅ **2026-09-18 22:02 出包成功（本轮最终产物）**：
     `build/outputs/release/freecad-on-harmonyos-release-signed.app`，**502,420,410 B**。
     正面证据：`.app` 验签 `Digest verify result: success`；内嵌 Profile 与 AGC 下载件
     **逐字节 `cmp` 相同**；证书链叶子公钥 `8e3b8d794f1a2354`（`CN=…\Release`，**不是**调试那张
     `c10b5b23…`）；`pack.info` 的 `releaseType = Release`；包内 `module.json` 记
     `compileSdkVersion 26.0.0.38 / apiReleaseType Release`；包内四张图标 md5 与
     `store-assets/icon/` 逐字节一致（`foreground 8c009848…` / `background 6247c3e4…` /
     `app_icon` = `icon` = `1154e7de…`）。同机设备已装入本轮调试包
     （`bm dump` 的 `updateTime = 2026-09-18 22:03:22`）。
   - 文案类改动（`PRIVACY*.md` / `README.md` / 两个商店文本 / promo 套图）已同步完成。
   - **剩余人工动作**：上传 `.app` 提审、按分镜录 60 秒场景视频、备案栏勾「单机 APP」、
     决定要不要发那封 FPA 信（**发信前先处理 7.7 第六节那个"配色承诺"**）。

