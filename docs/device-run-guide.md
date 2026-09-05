# DevEco 真机执行指引（验收 + GUI）

更新时间：2026-09-05。本工程当前为 **GUI HAP（Qt6）** 布局，同时保留 headless 验收能力。

## 构建

1. 在可执行 OHOS SDK 环境运行 `./scripts/rebuild-freecad-all-workbenches.sh`；不要只运行 hvigor，旧 staging 会保留不完整的工作台集合。脚本会准备 Addon Manager、Microsoft.GSL 和 Assembly 所需的固定版本 OndselSolver；Assembly 与 Reverse Engineering 默认启用。MeshPart、BIM、FEM 需要尚未提供的 SMESH/MEDFile/HDF5 依赖，仍保持关闭。
2. 运行 `./scripts/stage-gui-hap.sh`，再运行 `./scripts/build-gui-hap-ohos.sh`；也可在 DevEco Studio 对 `default` product 执行 Sync → Build Hap。
3. Build Hap 完成后运行 `./scripts/verify-gui-hap.sh`，确认 HAP 内含 `ImportGui.so`、`PartDesignGui.so`、`SketcherGui.so` 以及 AddonManager/核心工作台注册脚本。
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
- HarmonyOS 要求父主窗先 `showWindow()`，否则创建 splash 子窗会失败并返回 `1300002`；
  splash 的透明背景也必须在 `setUIContent()` 和 `showWindow()` 之后设置。主窗宿主与 splash
  必须使用完全相同的矩形，避免官方 PNG 的透明阴影区域露出第二层合成边界。
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
- 真机已显示 FreeCAD 1.1.2 主窗口、菜单、工具栏、New Document、Part/Cube 与复杂多色示例；Edit → Preferences 和单 Ability 无框官方 splash 均已验证。当前包摘要见 `docs/handoff-device-steps.md`。

## 子元素选择高亮（2026-09-04 已解决）

原故障表现为新建立方体后，鼠标悬停面的黄色预选高亮和第一次点击面的
绿色选择高亮都不显示；再次点击后整个立方体的绿色高亮正常。拾取本身没有
失效，状态栏仍能显示 `Preselected: Unnamed.Box.Face3`，因此问题位于选择上下文
到渲染节点的传递过程，而不是触摸坐标或拾取半径。

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
深度测试遮挡；该试验和所有 `FreeCADSel` 临时日志均未保留。真机验证确认立方体
面的 hover 黄色高亮、首次点击绿色面高亮、再次点击整体绿色高亮均已恢复；构建
仍保持 `BUILD_ASSEMBLY=ON`。移除诊断后重新构建并通过 `verify-gui-hap.sh` 的
签名包 SHA-256 为 `dfbdeec8ee9f9e2da690a2d70cc2d1920c9f5f5e8a3a390e05b9dbe50c123afe`。

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

- 长时间覆盖旋转、缩放、平移、拾取、选择高亮、输入映射和弹窗 remap。
- 反复打开 Preferences、文件选择器并切换前后台，确认窗口和输入法生命周期稳定。
- 若崩溃或白屏，保留 `QtForOhos`、`gl4es` 日志，并用 `hidumper -e --print com.freecad.headless.acceptance -n 3` 读取持久化 cppcrash。
