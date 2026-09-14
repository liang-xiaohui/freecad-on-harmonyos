# DevEco 真机执行指引（验收 + GUI）

更新时间：2026-09-05。本工程当前为 **GUI HAP（Qt6）** 布局，同时保留 headless 验收能力。

## 构建

1. 在可执行 OHOS SDK 环境运行 `./scripts/rebuild-freecad-all-workbenches.sh`；不要只运行 hvigor，旧 staging 会保留不完整的工作台集合。脚本会准备 Addon Manager、Microsoft.GSL 和 Assembly 所需的固定版本 OndselSolver，以及 FEM 所需的 HDF5/MEDFile；FEM、Assembly 与 Reverse Engineering 默认启用，SMESH 使用 FreeCAD 内置源码。MeshPart 仍保持关闭。BIM（Arch）默认接入：它是纯 Python，脚本在 install 之后调用 `install-bim-module-ohos.sh` 按安装清单写入前缀，`FREECAD_BUILD_BIM=OFF` 可关闭，见 `docs/bim-ohos.md`。FEM 数据验收及外部求解器限制见 `docs/fem-ohos.md`。
2. 运行 `./scripts/stage-gui-hap.sh`，再运行 `./scripts/build-gui-hap-ohos.sh`；也可在 DevEco Studio 对 `default` product 执行 Sync → Build Hap。
3. Build Hap 完成后运行 `./scripts/verify-gui-hap.sh`，确认 HAP 内含 `ImportGui.so`、`PartDesignGui.so`、`SketcherGui.so` 以及 AddonManager/核心工作台注册脚本。FreeCAD 配置阶段还会检查 Qt6 `LinguistTools/lrelease`；构建日志应出现 `FreeCAD_zh-CN.qm` 及各已启用工作台的 `_zh-CN.qm`，而不是 `RCC: Warning: No resources`。
4. 若改动过 C++/ArkTS，DevEco 会自动重编 `libfreecadacceptance.so` 与 ArkTS。

如果只增量修改 GL4ES，不能只运行 Ninja。Ninja 链接出的库仍在 GL4ES
源码/构建树，而 `stage-gui-hap.sh` 从 install prefix 取库，必须继续安装：

```sh
/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/build-tools/cmake/bin/ninja \
  -C /storage/Users/currentUser/CPPLib/build/gl4es/81547d9/ohos-arm64-v8a-ninja \
  libGL.so
/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/build-tools/cmake/bin/cmake \
  --install /storage/Users/currentUser/CPPLib/build/gl4es/81547d9/ohos-arm64-v8a-ninja
./scripts/stage-gui-hap.sh
./scripts/build-gui-hap-ohos.sh
./scripts/verify-gui-hap.sh
```

## 0) 默认启动 = FreeCAD GUI（QAbility，mainElement）

### 从哪里执行启动命令

“编译机和目标机是同一台 HarmonyOS PC”只影响编译器的 host/target，不会让
DevEco 的 Run 自动获得一个 HDC target。`assembleHap` 只生成 HAP；Run 还必须通过
DevEco 的本地运行目标、系统的 `bm`/`aa` 工具，或 HDC 完成安装和启动。

- **同机本地运行**：如果系统 shell 提供 `bm` 和 `aa`，可以直接安装并启动：
  ```sh
  bm install -p /storage/Users/currentUser/github/freecad-on-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
  aa start -b com.freecad.headless.acceptance -a QAbility
  ```
  如果 `bm`/`aa` 不在 PATH、没有执行权限，或 `bm install` 只打印
  `error: failed to execute your command`，说明当前终端不是特权应用管理
  shell；请走已认证的 HDC target。注意部分 `bm` 失败时仍返回退出码 0，
  必须检查命令输出，不能只看 `$?`。

- **DevEco/主机终端**：先确认设备已连接，再指定连接 key：
  ```sh
  hdc list targets
  # 用上一步实际输出的 key 替换 CONNECT_KEY；不要输入尖括号。
  hdc -t CONNECT_KEY install -r /绝对路径/entry-default-signed.hap
  hdc -t CONNECT_KEY shell aa start -b com.freecad.headless.acceptance -a QAbility
  ```
  使用 `hdc list targets -v`；输出中可能同时保留 `Offline` 与 `Connected`
  项，安装时必须显式选择 `Connected` 的完整 key，不能取第一行。如果
  输出 `[Empty]`，先执行 `hdc tconn IP:PORT` 并确认设备授权。
- **真正的特权设备 shell**：只有 `bm` 和 `aa` 实际可执行时才直接运行：
  ```sh
  bm install -p /storage/Users/currentUser/github/freecad-on-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
  aa start -b com.freecad.headless.acceptance -a QAbility
  ```
  `uname` 显示 HarmonyOS/HongMeng/Toybox 并不足以证明当前是特权 HiShell；
  这台 HarmonyOS PC 的普通 DevEco host 终端也有相同内核标识，但仍需通过
  HDC 完成安装和启动。

- **`module.json5` 的 `mainElement` 已改为 `QAbility`**：DevEco Run / 桌面图标直接进 FreeCAD 全量 GUI。
- 运行配置（`.bitfun/configs.json`）已同步为 `launch=Ability, abilityName=QAbility`。
- 启动链：QAbility.onCreate → `setupFreecadEnv`（同步复制 rawfile 并设置环境）→
  `materializeFreecadRuntimeAsync`（native async work 用纯 C++/zlib 解压约 48MB）。与此同时，
  `onWindowStageCreate` 把主窗临时改为 splash 几何并加载透明的 `MainWindowNativeNode` 宿主页，
  显示主窗后在同一 Ability 内创建 `decorEnabled: false` 的 `StartupSplash` 子窗。runtime 与
  splash 都就绪后才把 `WindowStage` 交给 QPA，QPA 复用宿主页创建 XComponent 并启动
  `libfreecadqtapp.so`。
- 启动期间 XComponent 不能设为隐藏，否则 native surface 会被销毁；当前将它移出屏幕，
  并暂存 Qt 对主窗 size/position/decor/background 的修改。FreeCAD 激活启动工作台并完成一次
  事件循环后写入 `.gui-ready`，ArkUI 随即恢复 Qt 请求的主窗几何、移回 XComponent、抬起
  主窗，再销毁 splash 子窗。
- `startWindowType=REQUIRED_HIDE` 隐藏系统 starting window，FreeCAD 侧也跳过桌面端
  `QSplashScreen`。不要恢复启动 status-bar logo 或样式探针的临时顶层 QLabel；OHOS QPA
  会把它们识别为额外顶层窗口，表现为第二个 splash、最小化动画或主窗退到后台。
- HarmonyOS 要求父主窗先 `showWindow()`，否则创建 splash 子窗会失败并返回 `1300002`。
  `setWindowDecorVisible(false)` 同样只能在首次 `showWindow()` 后调用，并且装饰切换必须单独
  捕获异常；否则一次 `1300002` 会跳过后续整个 splash 子窗创建流程。splash 的透明背景也必须
  在 `setUIContent()` 和 `showWindow()` 之后设置。主窗宿主与 splash 必须使用完全相同的矩形，
  避免官方 PNG 的透明阴影区域露出第二层合成边界。
- 启动时从 FreeCAD 1.1.2 自带的 `freecadsplash0_2x.png` 到 `freecadsplash12_2x.png`
  随机选择一张。`generate-startup-splashes.mjs` 以高 alpha 内容为轮廓，生成比原轮廓大一圈的
  半透明异形玻璃底板，再把官方像素无损叠回中心。不同素材画布比例不同，窗口按生成素材的
  逻辑尺寸居中并保持比例；透明背景和 `Contain` 保留齿轮、圆角及原有投影。不要改成矩形
  ArkUI box-shadow。子窗默认的矩形边框阴影和圆角必须通过 `setWindowShadowRadius(0)`、
  `setWindowCornerRadius(0)` 显式清除；启用系统窗体阴影的接口返回 `1300004`，没有采用。
- `freecad-home/.runtime-ready` 保存 runtime ZIP 的大小和 CRC32。标记缺失或不匹配时会先清理
  `Mod/Ext/share` 再解压，成功后才原子写入标记，避免复用崩溃留下的半成品。
- hilog 标签：`FreeCADGui`（ArkTS）、`QtForOhos`（QPA）、`FreeCADProbe`（验收）。

### 启动画面真机判据（2026-09-05）

在 `3296x2472` 显示上，日志应记录主窗宿主与 splash 完全相同：

```text
startup geometry display=3296x2472 ... host=1137,905,1022x662 splash=1137,905,1022x662
startup host window shown
decor-free startup splash loaded
main window raised behind startup splash
FreeCAD GUI ready; startup transition complete
```

`192.168.3.16:39405` 上的冷启动连续取帧确认：启动阶段只有一张无标题栏官方 splash，
没有大空白主窗、错位的第二层或最小化切换；GUI-ready 后直接显示完整主窗。PNG 自带的
透明投影属于官方素材，不是第二个窗口。

### 启动期 Recovery 弹窗（2026-09-05）

Qt 在 splash 期间已经按延后的完整主窗几何计算 `Document Recovery` 的屏幕位置，但 ArkUI
父节点仍处在 splash 的临时小矩形。QPA 原先从目标屏幕坐标减去 ArkUI 物理父节点原点，得到
类似 `(-284,-135)` 的嵌入坐标，导致弹窗被放到左上角并裁掉按钮区域。QPA patch 16 现在检测
主窗的 Qt 几何与 ArkUI 节点几何是否不一致；不一致时使用 Qt 主窗原点完成父相对坐标换算。
真机已验证 Recovery 弹窗居中、内容完整且 `Cleanup` 按钮可点击。

`aa force-stop` 会执行 Ability 的正常销毁流程，FreeCAD 会移除当前 lock 和 transient recovery
目录，不能用来制造 Recovery 测试数据。模拟崩溃时应先等待自动恢复文件写入（默认 15 分钟，
可临时改为 1 分钟），再对应用进程发送 `SIGKILL`。

### 简体中文与独立对话框验收

新配置第一次启动时应直接显示简体中文；如果已有 `BaseApp/Preferences/General/Language`
设置，则继续尊重该显式值。首选项的语言列表选择“简体中文”后重新启动，核心菜单以及
Part、Part Design、Sketcher、Assembly 等已启用工作台应保持中文，Qt 标准按钮也应正确翻译。

Preferences、About 以及同类顶层 `QDialog` 应表现为独立的 OHOS 子窗：具有单个系统窗框，
内容不被主窗口客户区裁切，可以移动和关闭，modal 对话框打开时主窗口不可误操作。重点回归
对话框内的下拉框和 tooltip；它们仍依赖 QPA 的 popup parent 解析。若看到双标题栏，说明旧的
`ohos-embedded-dialog-titlebar.patch` 仍残留在 FreeCAD 外部源码树，应重新运行
`scripts/prepare-freecad-source.sh` 完成迁移后再构建。

### HDC 无线调试已开启但仍然 `Connect failed`

先区分两个端口：`127.0.0.1:8710` 是本机 HDC server，设备界面显示的
`192.168.3.16:39405` 一类地址才是设备 daemon endpoint。无线调试开关已开
只说明 daemon 应当可用，不代表主机 RSA 认证成功。

2026-09-02 的实测失败已连到 daemon 并开始握手，最终原因是：

```text
read prikey from /storage/Users/currentUser/.harmony/hdckey failed
Auth failed
```

当日志出现这个错误时，不要继续扫描端口。检查 active private key 是否为当前
HDC 能读取的 PEM，并检查已有备用私钥派生出的公钥是否与 active public key
一致。校验只输出哈希，不要输出私钥内容：

```sh
openssl pkey -in /storage/Users/currentUser/.harmony/hdckey_new \
  -pubout -outform DER 2>/dev/null | sha256sum
openssl pkey -pubin -in /storage/Users/currentUser/.harmony/hdckey.pub \
  -outform DER 2>/dev/null | sha256sum
```

本机两个哈希一致，因此把原 `hdckey` 备份到
`/storage/Users/currentUser/codex-freecad-artifacts/hdc-key-repair-*` 后，使用
`hdckey_new` 替换 active private key，重连立即得到 `Connect OK`。若哈希不同，
严禁替换；应重新生成 HDC key 并在设备上重新授权。

连接恢复后的预期列表可能包含历史离线项：

```text
127.0.0.1:39405       TCP  Offline
192.168.3.16:39405    TCP  Connected
```

此时必须显式指定后者：

```sh
HDC_BIN=/data/service/hnp/bin/hdc
HDC_SERVER=127.0.0.1:8710
TARGET=192.168.3.16:39405
"$HDC_BIN" -s "$HDC_SERVER" -t "$TARGET" install -r \
  entry/build/default/outputs/default/entry-default-signed.hap
"$HDC_BIN" -s "$HDC_SERVER" -t "$TARGET" shell aa start \
  -b com.freecad.headless.acceptance -a QAbility
```

安装过程若被中断，不能假设“已安装”或“未安装”；重新确认 target 为
`Connected`，再重复执行可幂等覆盖的 `install -r`，然后启动 QAbility。

## 1) headless 验收（EntryAbility，不再默认启动）

- 验收入口改为**显式命令行触发**（应用安装后）：
  ```
  aa start -b com.freecad.headless.acceptance -a EntryAbility
  ```
- 或临时把 `module.json5` 的 `mainElement` 改回 `EntryAbility` 后 Run。
- 启动 EntryAbility → 自动执行 6 项验收（OCCT / 版本断言 / 模块导入 / 布尔 / FCStd / STEP / STL）。
- 结果：页面 JSON（ok 布尔）+ hilog：
  ```
  ./scripts/watch-headless-hap-log.sh
  ```
  查找 `FreeCADProbe` 的 `Python acceptance result status=0 json={...}`（本地已验证全绿）。
- 说明：本 GUI HAP 的验收在**同一 Qt6 运行时**上跑（Sketcher/PartDesign/Import 已 Qt6 重建），
  与 16:40 的 headless 签名包等价甚至更新。

## 本地已验证（沙箱内，无需设备）

- GUI HAP 运行时（Qt6 staged native 依赖闭包）跑通 6/6 验收（`logs/gui-acceptance-out/freecad-acceptance.json` ok=true）。
- FreeCAD GUI 二进制（Qt6 + offscreen 平台）可启动至 Qt 事件循环：Python 初始化 → QApplication →
  offscreen 平台窗口创建（`propagateSizeHints`），无崩溃（渲染需真机 OHOS QPA）。
- 真机已显示 FreeCAD 1.1.2 主窗口、菜单、工具栏、New Document、Part/Cube 与复杂多色示例；Edit → Preferences、Recovery 弹窗和单 Ability 无框官方 splash 均已验证。当前包摘要见 `docs/handoff-device-steps.md`。

## Part Cube 的 View All 动画裁剪（2026-09-05 已解决）

原故障只出现在新建 Cube 后的 10 帧自动 `ViewFit` 放大过程：模型会像被不规则切掉一样变形，
动画结束后的静态画面正常。逐帧探针同时记录相机、Cube 在相机坐标中的深度范围以及
`nearDistance/farDistance`，确认模型几何和相机插值本身连续，异常来自 Coin 自动裁剪面滞后。

Coin 用延迟传感器更新相机裁剪面。`animatedViewAll()` 每帧修改相机后只进入一个 20 ms 的
Qt 事件循环，默认假定传感器和 QOpenGLWidget 重绘会在下一帧前完成。OHOS 的异步绘制有时先
消费唯一一次 queued paint，却未处理裁剪传感器。例如故障帧 Cube 深度已移动到 `54.180–71.106`，
near/far 仍是上一帧的 `72.102–89.189`，因此模型在深度测试前已被裁掉。

`ohos-view-all-clipping-sync.patch` 在 OHOS 相机更新后立即调用
`SoDB::getSensorManager()->processDelayQueue(false)`，让该帧的自动裁剪面在呈现前同步完成，
而不取消原有动画。修复后 10 帧逐帧验证 near/far 均完整覆盖当帧 Cube 深度，真机观察不再
出现裁切变形。诊断用 `FreeCADViewFit` hilog 探针未纳入正式补丁。

## 子元素选择高亮（2026-09-04 已解决）

原故障表现为新建立方体后，鼠标悬停面的预选高亮和第一次点击面的
绿色选择高亮都不显示；再次点击后整个立方体的绿色高亮正常。拾取本身没有
失效，状态栏仍能显示 `Preselected: Unnamed.Box.Face3`，因此问题位于选择上下文
到渲染节点的传递过程，而不是触摸坐标或拾取半径。

（预选/选中颜色取自 `View3DSettings.cpp:262-283`：预选 `SbColor(0.8, 0.1, 0.1)`
为**红**色，选中 `SbColor(0.1, 0.8, 0.1)` 为绿色。早期笔记写"黄色预选"有误。）

排查发现两个相互叠加的 HarmonyOS 差异：

1. `SoBrepFaceSet::GLRender()` 执行时，`SoFCSelectionRoot::SelStack` 可能为空，
   action 阶段已经写入的 face selection context 因而无法在 render 阶段查回。
   OHOS 路径现在从 `SoGLRenderAction::getCurPath()` 重建 selection-root stack，
   face、edge、point 三类 BRep 渲染节点统一传入当前 render action。
2. 工作台经 `RTLD_LOCAL` 动态加载后，跨 `libFreeCADGui.so` 与 `PartGui.so` 的
   `dynamic_pointer_cast<SoFCSelectionContextEx>` 在设备上不可靠。即使 context-map
   key 已命中，转换仍可能返回空。OHOS 路径根据“查询 node 决定该 map entry 类型”
   的不变量使用 `static_pointer_cast`，并为 `SoFCSelectionContextEx` 提供由
   `libFreeCADGui.so` 导出的 out-of-line 析构函数，以统一其 RTTI/typeinfo 所属 DSO。

将 highlight pass 的 depth function 强制为 `GL_LESS` 没有改变故障，证明它不是
深度测试遮挡 —— 注意这个结论**仅对本次故障成立**：当时 highlight pass 根本没画
出来（context 查不回），深度函数自然无从影响结果。2026-09-14 出现的同类外观
（面级高亮消失）根因完全不同，详见下节；当时那轮试验和所有 `FreeCADSel` 临时
日志均未保留。真机验证确认立方体
面的 hover 黄色高亮、首次点击绿色面高亮、再次点击整体绿色高亮均已恢复；构建
仍保持 `BUILD_ASSEMBLY=ON`。移除诊断后重新构建并通过 `verify-gui-hap.sh` 的
签名包 SHA-256 为 `dfbdeec8ee9f9e2da690a2d70cc2d1920c9f5f5e8a3a390e05b9dbe50c123afe`。

## 子元素高亮回归：Native 渲染路径缺少 `glDepthFunc(GL_LESS)`（2026-09-14 已解决）

`91a337c`（"Enable FEM and BIM workbenches; fix BIM coplanar stripe artifact"）
推送后面级高亮再次消失：整对象选中高亮正常，但**鼠标悬停单个面**的红色预选和
**单击单个面**的绿色选中都不显示。状态栏仍正确显示 `Preselected: BIMExample.Wall007.Face3`，
所以拾取、选择上下文和颜色下发都是好的，问题只在最终光栅化。

根因链（每一步都有设备实证）：

1. gl4es 默认 `glstate->depth.func = GL_LESS`（`src/gl/glstate.c:296`）。
2. Coin3D 在一次性的 `needglinit` 里**主动把深度函数改成 `GL_LEQUAL`**
   （`SoGLRenderAction.cpp:1081-1095`），注释明说"SoGLDepthBufferElement 假定初始值是
   `GL_LEQUAL`"。
3. FreeCAD 只在 `View3DInventorViewer::renderToFramebuffer()`（约 line 2403）用
   `glDepthFunc(GL_LESS)` 抵消它 —— 但 `renderType` 默认是 `Native`
   （`View3DInventorViewer.cpp:409/433`），`actualRedraw()` 走的是 `renderScene()`，
   **那里没有这句**。
4. `SoBrepFaceSet::GLRender()` 先画高亮 pass、再画**同深度**的基准面 pass。`GL_LEQUAL`
   下 `z <= z` 成立，灰色基准面完整覆盖刚画好的红/绿高亮。只影响与基准面共面的
   面级高亮，边高亮和整对象高亮不受影响 —— 与现象完全一致。

为什么 `91a337c` 才暴露：该提交给 Qt 引入 `19-prefer-24bit-depth-attachment.patch`，
深度附件从 16-bit 回退变成真正的 24-bit。

| 深度精度 | 共面高亮面 vs 基准面的深度值 | `GL_LEQUAL` 下的结果 |
|---|---|---|
| 16-bit（91a337c 之前） | 量化误差使两者略有差异 | 高亮可见（偶然正确） |
| 24-bit（91a337c 之后） | 精确相等 | 基准面覆盖高亮 |

同一提交修好 BIM 红柱条纹也正是靠 24-bit 抑制 z-fighting，所以不能回退它。

定位手段（探针已全部撤销，仅在此存档）：在 gl4es 的 `gl4es_glDepthFunc()` 打点输出
`DEPTHFUNC func=...`，并在 FPE draw 入口追踪 `glstate->color`。实测高亮 pass：

```text
HL2 REDC glcolor=0.800,0.200,0.200 count=228 depthmask=1 depthtest=1
         depthfunc=0x0203 colarray=0 colmat=1 lighting=0 program=9
```

`0x0203` 即 `GL_LEQUAL`；全程 `0x0201`(`GL_LESS`) 出现 **0 次**，证明 FreeCAD 的
`glDepthFunc(GL_LESS)` 从未到达 gl4es。把 `func == GL_LEQUAL` 临时强制成 `GL_LESS`
做 5 分钟实验，真机上高亮立即恢复，根因随即确认。

正式修复取 FreeCAD 侧最小侵入方案，与 `renderToFramebuffer()` 对称，补丁为
`patches/freecad-1.1.2/ohos-native-render-depthfunc.patch`：

```cpp
// renderScene()，backgroundroot apply 之后
glDepthFunc(GL_LESS);
```

不改 gl4es、不改 Coin、不影响 BIM 修复。真机复验通过，签名 HAP 尺寸回到
494,480,552 B（实验版为 494,512,664 B）。

### 顺带修复：configure 脚本续行被注释截断

排查中 `scripts/configure-freecad-gui-qt6-ohos.sh` 的重新配置失败，`BUILD_BIM` 回到
默认 `ON` 又与 `BUILD_MESH_PART=OFF` 冲突。原因是 `91a337c` 把一段 BIM 说明注释
插进了 `cmake_configure` 的续行参数列表**中间**：

```sh
    -DBUILD_ASSEMBLY="$BUILD_ASSEMBLY" \
    # BUILD_BIM stays OFF for CMake on purpose. ...
    -DBUILD_BIM=OFF \
```

shell 里 `\` 续行后紧跟注释行会**终止整条命令**，于是 `-DBUILD_BIM=OFF` 及其后
**整批 `-D` 参数被静默丢弃**。旧缓存恰好是关掉 BIM 之前的快照，ninja 一直没触发
重配置因此长期未暴露。修复是把注释移到参数列表之外，并加了防回归说明。全仓库
已扫描确认无同类残留。

## Draft `Base::Quantity` 信号转换（2026-09-05 构建修复）

Draft 画线任务面板曾在数值变化时报告：

```text
Cannot call meta function "slot(Base::Quantity)" because parameter 0 of type
"Base::Quantity" cannot be converted.
```

`Gui::InputField::valueChanged(const Base::Quantity&)` 需要 FreeCADGui 在启动时
向 Shiboken 注册 `Base::Quantity` converter。旧的 full 构建脚本显式关闭了
`FREECAD_USE_SHIBOKEN` 和 `FREECAD_USE_PYSIDE`；PySide Python 模块虽然已经随
HAP 打包，`libFreeCADGui.so` 却没有链接两个 C++ 运行库，converter 因此从未注册。

正式的 `configure-freecad-gui-qt6-ohos.sh` 现在显式传入目标端
`Shiboken6_DIR`/`PySide6_DIR` 并启用两项集成。配置结束还会检查生成的
`build.ninja` 是否同时包含 `HAVE_SHIBOKEN6` 和 `HAVE_PYSIDE6`，避免 CMake
缺少依赖时静默退回 OFF。2026-09-05 已完成全工作台 Release 构建、安装、staging
和 `verify-gui-hap.sh`；`libFreeCADGui.so` 的 `DT_NEEDED` 已包含
`libpyside6.abi3.so.6.8` 与 `libshiboken6.abi3.so`。签名 HAP SHA-256 为
`c1587ac4c5a139a9d929904f2be7e68c40466aca4b6399fe1fb65d83b72e93cc`，已覆盖安装
到 `192.168.3.16:39405`；安装后的 Draft 交互复验需在设备解锁后完成。

## 当前 GUI 回归重点

- **面级高亮（红色预选 / 绿色选中）是最敏感的光栅化探针**：它依赖"高亮面与基准面
  深度值恰好相等"这一边界条件，深度精度、深度函数、渲染路径类型任一变化都可能
  让它消失而其他功能看起来完全正常。凡是改动深度附件格式、`glDepthFunc`、
  `renderType` 或 gl4es 深度状态，都必须复验 hover/单击单个面的高亮。
- 长时间覆盖旋转、缩放、平移、拾取、选择高亮、输入映射和弹窗 remap。
- 反复打开 Preferences、文件选择器并切换前后台，确认窗口和输入法生命周期稳定。
- 若崩溃或白屏，保留 `QtForOhos`、`gl4es` 日志，并用 `hidumper -e --print com.freecad.headless.acceptance -n 3` 读取持久化 cppcrash。
