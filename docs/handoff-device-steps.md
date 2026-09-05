# 真机交接：需要用户执行的剩余步骤

更新时间：2026-09-05。**全工作台 GUI 构建、staging、签名 HAP、基础 3D、Preferences、Recovery、Cube ViewFit 动画与单 Ability 无框 splash 均已在真机通过**。

## 当前就绪状态（已验证）

| 产物 | 验证 |
|---|---|
| Qt 6.8.3 全 GUI 模块 + OHOS QPA（libqohos.so） | 构建/加载/注册 ✓ |
| FreeCAD v1.1.2 GUI（Qt6）全工作台 | bin/FreeCAD + libFreeCADGui + CAM/Draft/Import/Inspection/Measure/PartDesign/Points/Robot/Sketcher/Spreadsheet/Start/Surface/TechDraw GUI ✓ |
| Pivy / Shiboken6 / PySide6（Core/Gui/Widgets/Network/Svg/SvgWidgets/OpenGL/OpenGLWidgets） | 全部构建+导入验证 ✓；已 staged 进 HAP runtime（Ext/） |
| GUI HAP staging | 155 个 AArch64 ELF + rawfile；签名 HAP 内 229 个 `.so*`，内容/新鲜度验证通过 |
| headless 6 项验收（本地） | **6/6 PASS**（2026-08-24 当前 staging 复验） |
| GUI 真机 | FreeCAD 1.1.2 主窗口、New Document、Part/Cube、Cube ViewFit 动画、复杂多色示例、Preferences、Recovery ✓ |
| 单 Ability splash | 13 张官方高清图随机显示、异形玻璃外扩、无系统圆角/矩形阴影、ArkUI/XComponent 交接和完整主窗恢复均已真机验证 |

## 2026-09-05 真机问题结论

### 随机官方 splash 与异形玻璃轮廓

- **目标**：与 macOS 版一致，启动时随机显示 FreeCAD 官方 splash，并在原图整体 alpha 轮廓外增加一圈半透明异形玻璃；不能变成矩形背景、圆角矩形阴影或模糊外发光。
- **素材与尺寸**：`freecadsplash0_2x.png` 到 `freecadsplash12_2x.png` 共 13 张官方高清素材。`QAbility` 每次启动随机选择一张，按各自画布比例和逻辑尺寸显示，小屏最多占显示区域 80%，ArkUI 使用 `ImageFit.Contain`。
- **生成方式**：`scripts/generate-startup-splashes.mjs` 直接读取官方 8-bit RGBA PNG，以 alpha `>=128` 的内容为轮廓，使用欧氏距离变换生成 `40 px` 等距玻璃外扩和 `4 px` 玻璃边缘。官方图片原位叠回；四周仅增加 `16 px` 安全画布，利用素材已有透明边距，避免为玻璃效果明显放大矩形宿主窗。
- **矩形残影根因**：HarmonyOS 子窗即使内容和窗口背景均透明，仍默认带矩形边框阴影与系统圆角。隐藏标题栏不会清除这两项；尝试启用系统阴影还会返回 WindowManager `1300004`。
- **修复**：子窗显示并设置透明背景后，显式调用 `setWindowShadowRadius(0)` 和 `setWindowCornerRadius(0)`。玻璃外观完全来自 PNG alpha，不依赖窗口合成器绘制形状。
- **复现与校验**：staging 会重新生成全部 13 张资源；HAP 校验使用同一算法做逐字节检查，并确认打包资源与 staging 哈希一致。真机日志确认关闭阴影和圆角均成功，用户于 2026-09-05 确认最终视觉效果正确。

### Cube 放大动画被裁切

- **现象**：在新文档的 Part 工作台创建 Cube 后，10 帧 `ViewFit` 放大动画的中间帧像几何体被异常切掉；动画结束后的静态 Cube 正常。
- **根因**：几何和相机插值都连续，实际滞后的是 Coin 的自动裁剪面。相机位置每帧立即更新，但 near/far 由 delay sensor 更新；OHOS 的 queued QOpenGLWidget paint 偶尔先于该 sensor 执行，导致当前相机帧沿用上一帧裁剪范围。例如 Cube 深度已经从 `63.177-80.103` 移到 `54.180-71.106`，裁剪面仍为上一帧的 `72.102-89.189`。
- **修复**：`patches/freecad-1.1.2/ohos-view-all-clipping-sync.patch` 在 `animatedViewAll()` 每次写入相机位置后，仅针对 `FREECAD_OHOS` 调用 `SoDB::getSensorManager()->processDelayQueue(false)`，使当前帧的自动裁剪面在绘制前完成更新，不移除动画也不改变其他平台行为。
- **验证**：修复后同一段 10 帧动画的每一帧 near/far 都覆盖当前 Cube 深度；例如第 4 帧裁剪范围变为 `54.126-71.177`。临时 `FreeCADViewFit` 深度与 GL 探针已从正式源码和补丁中移除，真机视觉回归通过。

### 启动期 Recovery 弹窗偏到左上角

- **现象**：存在恢复数据时，`Document Recovery` 出现在左上角且内容被裁切，`Cleanup` 按钮无法操作。
- **根因**：splash 显示期间，Qt 已使用延后的完整主窗几何计算 modal dialog 的屏幕坐标，ArkUI 物理父节点却仍是 splash 的临时小矩形。QPA 用这两个不同坐标系相减，曾得到 `(-284,-135)` 一类错误的父相对位置。
- **修复**：`patches/qt-6.8-ohos/16-reuse-startup-content.patch` 检测 Qt 主窗原点与 ArkUI 节点原点是否不一致；启动过渡期若不一致，嵌入式对话框统一使用 Qt 主窗原点换算。主窗装饰调用也改为首次 `showWindow()` 后执行并独立捕获异常，避免 WindowManager `1300002` 连带跳过 splash 创建。
- **验证**：Recovery 弹窗居中、内容完整，`Cleanup` 真机点击成功。`aa force-stop` 会走正常销毁并清理恢复状态；复测恢复流程应等待 autosave 后用 `SIGKILL` 模拟异常退出。

## 构建后核对

DevEco 构建完成后先跑 GUI HAP 验证（native/rawfile/新鲜度一键核对）：

```sh
./scripts/build-gui-hap-ohos.sh
./scripts/verify-gui-hap.sh
```

当前包：`entry/build/default/outputs/default/entry-default-signed.hap`，SHA-256
`9a0c3325cdde9d4c7c160a852953bdf6819c34d9b147a5480f8740461c57cda3`。该包包含 13 张
随机官方高清 splash、异形玻璃轮廓、19 个简体中文 `.qm` 的编译嵌入及原生对话框
SubWindow 路径，并通过 rawfile 一致性、新鲜度、229 个 native `.so`、GUI 工作台、
RUNPATH、Python 绑定和 splash 生成资源检查。中文默认值、独立对话框及最终 splash
视觉效果均已完成真机交互验证。

GL4ES 增量构建后还必须对对应 build tree 执行 `cmake --install`，再运行
`stage-gui-hap.sh`；只运行 Ninja 会让新库停留在源码/构建树，最终 HAP 仍可能
打入 install prefix 中的旧 `libGL.so`。

## 步骤 A：headless 验收真机复跑（关闭 headless 门禁）

1. DevEco Studio 打开仓库根目录 → Sync → Build Hap（自动签名），再显式启动 EntryAbility；默认 Run 入口是 GUI `QAbility`。
2. 页面显示验收 JSON（ok）；hilog 核对：
   ```sh
   ./scripts/watch-headless-hap-log.sh
   ```
   找 `FreeCADProbe` 的 `Python acceptance result status=0 json={... ok:true ...}`。
3. 通过后告诉我，我来更新文档关闭 headless 门禁。

## 步骤 B：FreeCAD GUI（QAbility）真机运行与调试

1. 同一工程 Sync → Build Hap → Run config 选 **QAbility**。命令行从 DevEco 主机先执行 `hdc list targets -v`，只选择状态为 `Connected` 的完整 key，再执行 `hdc -t <connect-key> shell aa start -b com.freecad.headless.acceptance -a QAbility`。只有 `bm`/`aa` 实际具有执行权限的特权 HiShell 才直接调用设备命令；`uname` 显示 HarmonyOS/Toybox 不能单独作为判断依据。
2. 启动链：QAbility.onCreate → 并行准备 runtime 与同一 Ability 内的无框 ArkUI splash 子窗 → `setupQtApplication('libfreecadqtapp.so')` → QPA 复用主窗宿主页并启动 XComponent → `.gui-ready` 后抬起主窗、销毁 splash。
3. hilog 标签：`FreeCADGui`（ArkTS）、`QtForOhos`（QPA）、`FreeCADProbe`（验收）。
4. 当前回归重点：启动 QAbility → 新建文档/打开复杂文件 → 长时间旋转/缩放/选择 → 反复打开 Preferences/文件对话框 → 前后台切换。
5. 若仍崩溃，请保留 `QtForOhos`、`gl4es` 日志，并运行 `hidumper -e --print com.freecad.headless.acceptance -n 3` 保存 cppcrash 完整栈。

## PySide6 / Shiboken6 集成状态（2026-09-05 修正）

- PySide6、Shiboken6 Python 模块和原生库从 2026-08-22 起已经随 HAP runtime staged，Python 侧导入验证通过。
- 旧的独立 `configure-freecad-gui-qt6-pyside-ohos.sh` 构建树虽然缓存显示 `FREECAD_USE_PYSIDE=ON` / `FREECAD_USE_SHIBOKEN=ON`，但没有找到两个 CMake package，最终 `libFreeCADGui.so` 也未链接其运行库。旧文档把 runtime 可导入误判成 FreeCAD C++ converter 已启用，此结论已废弃。
- 当前唯一正式入口是 `configure-freecad-gui-qt6-ohos.sh` 的 full 构建。它显式指定目标端 package 目录、启用两项集成，并检查 `HAVE_PYSIDE6` / `HAVE_SHIBOKEN6` 生成定义。
- Addon Manager 会同时导入 `PySide6.QtNetwork`。PySide6 必须以 `Core;Gui;Widgets;Network;Svg;SvgWidgets;OpenGL;OpenGLWidgets` 模块集构建；staging 和 HAP 验证会拒绝缺少 `QtNetwork.abi3.so` 的产物。
- 2026-09-05 的全工作台 Release 构建确认 `PythonWrapper.cpp` 编译了 `Base::Quantity` converter，`libFreeCADGui.so` 直接依赖 `libpyside6.abi3.so.6.8` 和 `libshiboken6.abi3.so`。这修复了 Draft 画线时 `slot(Base::Quantity)` 参数无法转换的问题。

## 排障：hvigor 构建退出码 1（2026-08-22 实测）

现象：`hvigorw.js ... assembleHap --info --analyze=normal --parallel --incremental --daemon` 退出码 1；
hvigor 日志（`.hvigor/outputs/build-logs/build.log`）显示 `:entry:default@ConfigureCmake` 执行后出现
`session manager: cannot find corresponding worker process for process id 36`（并行 worker 崩溃）。

结论：
- 同一命令曾有 `BUILD SUCCESSFUL in 2 s 341 ms`（`.hvigor/report/report-202608220817454850.json`）——
  **工程配置本身全部有效**（native/ArkTS/metadata 校验通过）。
- 失败来自 hvigor `--daemon/--parallel` 的 worker 进程崩溃（staging 含完整 GUI native 依赖闭包与 ~250MB rawfile，
  并行打包压力大）。

处理（按顺序）：
1. 当前 Hvigor 版本不支持 `hvigorw --stop`；关闭 DevEco 中打开的工程，必要时清理残留进程：`pkill -f hvigor`。
2. 去掉并行/daemon 重试：`hvigorw.js -p module=entry@default -p product=default -p buildMode=debug assembleHap --info`
3. 仍失败则 Clean：删除 `entry/.cxx` 与 `entry/build`（或 DevEco Build > Clean Project）后重建。
4. 若在 strip/打包阶段再挂：可临时把 `scripts/stage-gui-hap.sh` 的 rawfile 压缩级别调低或分批。

## 排障：`ENOSPC: System limit for number of file watchers reached`（2026-08-22 08:24/08:25 实测）

现象：`hvigor worker: Exit with error: Error: ENOSPC: System limit for number of file watchers reached,
watch '.../hvigor/hvigor-config.json5'` → `:entry:default@ConfigureCmake` worker exit 1。
（注意：这是 **inotify 文件监视器上限耗尽**，不是磁盘空间。）

根因：
- 本机 `fs.inotify.max_user_watches=8192`（默认值偏低）、`max_user_instances=128`。
- 该限额**按用户跨所有进程共享**：DevEco IDE 编辑器、hvigor（chokidar 递归 watch 项目树，988 个目录 +
  大量 native `.so`）、ohpm、Node LSP 同时监视同一棵项目树，合计超限。
- hvigor 的 watch 一旦 ENOSPC，worker 直接 exit 1 → ConfigureCmake 失败；此前 `session manager:
  cannot find corresponding worker process` 的崩溃大概率同为该限额在并行模式下引爆。

修复（设备 shell，需 sudo/root）：
```bash
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=1024
cat /proc/sys/fs/inotify/max_user_watches   # 验证 → 524288
```
若 `sudo sysctl` 被拒：`echo 524288 | sudo tee /proc/sys/fs/inotify/max_user_watches`（root shell 直接 echo）。
> 重启后失效；频繁重启则写入开机脚本。

然后重跑（保持 `hvigor-config.json5` 的 daemon/parallel=false，且**不要**加 `--incremental` 减少监视压力）：
```bash
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```
仍失败则兜底：关闭 DevEco 中打开的工程并清理残留 `hvigor` worker 的 watch，再跑命令行构建
（DevEco 自身也在 watch 同一棵树）。

## 已知注意事项

- 无线调试开关已开启但 `tconn` 仍失败时，先看 HDC server 日志。2026-09-02
  实测曾因 active `~/.harmony/hdckey` 是当前 HDC 无法解开的 encrypted PEM 而在
  RSA 握手阶段失败。已有备用私钥只有在其派生公钥哈希与 active `.pub` 完全
  一致时才可替换，并先把旧文件备份到
  `/storage/Users/currentUser/codex-freecad-artifacts`；否则重新生成密钥并重新授权。
- `list targets -v` 可能把历史 `Offline` 项列在当前 `Connected` 项之前。不要让
  安装逻辑直接取第一条非空记录；多目标时显式指定完整连接 key。
- `bm install` 在受限终端可能打印 `error: failed to execute your command` 却返回
  退出码 0，必须检查标准输出/错误文本。安装命令被中断后，重新确认连接并重复
  执行 `install -r`，不要根据退出码或中断时机猜测设备状态。

- `stage-gui-hap.sh` 不签名（HAP 构建时签名）；本地探针运行 `scripts/sign-staged-native-ohos.sh` 自签名 entry/libs，再运行 `scripts/run-staged-freecad-acceptance.sh`。
- Qt6 的 `moc/uic/rcc` 自签名必须在能访问 DevEco 主机工具链的终端完成。`/data/service/hnp/bin` 是设备运行环境路径，不代表存在 `binary-sign-tool`；如果 `uname -a` 显示 `HarmonyOS`/`Toybox`，当前是设备 shell，应切换到 DevEco Studio 的主机终端，或显式提供主机 SDK 中的真实路径：
  ```bash
  command -v binary-sign-tool
  find "${DEVECO_SDK_HOME:-${OHOS_SDK_HOME:-}}" -type f -name binary-sign-tool 2>/dev/null
  BINARY_SIGN_TOOL=/实际找到的路径/binary-sign-tool \
  QT_PREFIX=/storage/Users/currentUser/CPPLib/install/qt/6.8.3/ohos/arm64-v8a \
  ./scripts/sign-qt6-host-tools-ohos.sh
  ```
  若 `command -v` 和 `find` 都没有结果，说明该 DevEco SDK 未安装签名工具，不能用 `/data/service/hnp/bin/binary-sign-tool` 这个猜测路径代替。
- `probes/freecad-headless/acceptance.py` 是验收脚本唯一真源（staging 覆盖 rawfile 副本），改 env/布局必须改这里。
- GUI 会话的 FreeCAD 运行布局：FREECAD_APP_HOME=filesDir/freecad-home（含 Mod/ python 目录）、FREECAD_APP_LIBRARY_DIR=HAP libs 根、FREECAD_USER_*=filesDir 子目录。
- 构建/验证入口脚本：`scripts/build-qt6-gui-ohos.sh`、`build-qt6-modules-ohos.sh`、`configure-freecad-gui-qt6-ohos.sh`、`build-freecad-gui-qt6-ohos.sh`、`stage-gui-hap.sh`；绑定栈：`CPPLib/scripts/build-swig-ohos.sh`、`build-pivy-ohos.sh`、`build-shiboken6-ohos.sh`、`build-pyside6-ohos.sh`。
