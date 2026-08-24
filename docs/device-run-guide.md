# DevEco 真机执行指引（验收 + GUI）

更新时间：2026-08-25。本工程当前为 **GUI HAP（Qt6）** 布局，同时保留 headless 验收能力。

## 构建

1. 在可执行 OHOS SDK 环境运行 `./scripts/rebuild-freecad-all-workbenches.sh`；不要只运行 hvigor，旧 staging 会保留三个工作台。脚本会准备 Addon Manager 和 Microsoft.GSL；Assembly 默认关闭，要启用它需确保 DevEco shell 可下载 OndselSolver，再设置 `FREECAD_BUILD_ASSEMBLY=ON`。
2. 运行 `./scripts/stage-gui-hap.sh`，再运行 `./scripts/build-gui-hap-ohos.sh`；也可在 DevEco Studio 对 `default` product 执行 Sync → Build Hap。
3. Build Hap 完成后运行 `./scripts/verify-gui-hap.sh`，确认 HAP 内含 `ImportGui.so`、`PartDesignGui.so`、`SketcherGui.so` 以及 AddonManager/核心工作台注册脚本。
4. 若改动过 C++/ArkTS，DevEco 会自动重编 `libfreecadacceptance.so` 与 ArkTS。

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
  如果 `bm`/`aa` 不在 PATH，说明当前终端不是应用管理 shell；请在 DevEco 中配置本机运行目标，或使用系统的 HAP 安装器。

- **DevEco/主机终端**：先确认设备已连接，再指定连接 key：
  ```sh
  hdc list targets
  # 用上一步实际输出的 key 替换 CONNECT_KEY；不要输入尖括号。
  hdc -t CONNECT_KEY install -r /绝对路径/entry-default-signed.hap
  hdc -t CONNECT_KEY shell aa start -b com.freecad.headless.acceptance -a QAbility
  ```
  如果 `hdc list targets` 输出 `[Empty]`，说明主机还没有连接设备；请先连接 USB/网络设备并在设备上确认调试授权，或在主机执行 `hdc tconn IP:PORT` 后再查询 targets。
- **已经进入设备 shell（`uname` 显示 HongMeng/Toybox）**：不要再次调用 `hdc`，直接执行：
  ```sh
  aa start -b com.freecad.headless.acceptance -a QAbility
  ```
  `need connect-key` 表示在设备 shell 中调用了需要主机目标的 `hdc`，不是 HAP 或 FreeCAD 错误。

- **`module.json5` 的 `mainElement` 已改为 `QAbility`**：DevEco Run / 桌面图标直接进 FreeCAD 全量 GUI。
- 运行配置（`.bitfun/configs.json`）已同步为 `launch=Ability, abilityName=QAbility`。
- 启动链：QAbility.onCreate → `setupFreecadEnv`（同步复制 rawfile 并设置环境）→
  `materializeFreecadRuntimeAsync`（native async work 用纯 C++/zlib 解压约 48MB）→ Promise 成功后才把
  `WindowStage`/前台状态转交 QPA → QPA dlopen 并调用 `libfreecadqtapp.so` 的 `main()` →
  FreeCAD 主窗口渲染进 XComponent。解压期间不会创建 XComponent 或启动 Qt main。
- `freecad-home/.runtime-ready` 保存 runtime ZIP 的大小和 CRC32。标记缺失或不匹配时会先清理
  `Mod/Ext/share` 再解压，成功后才原子写入标记，避免复用崩溃留下的半成品。
- hilog 标签：`FreeCADGui`（ArkTS）、`QtForOhos`（QPA）、`FreeCADProbe`（验收）。

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
- 真机已显示 FreeCAD 1.1.2 主窗口、菜单、工具栏、New Document、Part/Cube 与复杂多色示例；Edit → Preferences 可打开。当前验证包 SHA-256 为 `6a6849b82e2122685c377246dcdf034493611a69852278049d83b6ece9368bd5`。

## 当前 GUI 回归重点

- 长时间覆盖旋转、缩放、平移、拾取、选择高亮、输入映射和弹窗 remap。
- 反复打开 Preferences、文件选择器并切换前后台，确认窗口和输入法生命周期稳定。
- 若崩溃或白屏，保留 `QtForOhos`、`gl4es` 日志，并用 `hidumper -e --print com.freecad.headless.acceptance -n 3` 读取持久化 cppcrash。
