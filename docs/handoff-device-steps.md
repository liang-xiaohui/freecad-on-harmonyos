# 真机交接：需要用户执行的剩余步骤

更新时间：2026-08-25。**全工作台 GUI 构建、staging、签名 HAP、基础 3D 与 Preferences 均已在真机通过**；当前继续扩大交互和工作台覆盖。

## 当前就绪状态（已验证）

| 产物 | 验证 |
|---|---|
| Qt 6.8.3 全 GUI 模块 + OHOS QPA（libqohos.so） | 构建/加载/注册 ✓ |
| FreeCAD v1.1.2 GUI（Qt6）全工作台 | bin/FreeCAD + libFreeCADGui + CAM/Draft/Import/Inspection/Measure/PartDesign/Points/Robot/Sketcher/Spreadsheet/Start/Surface/TechDraw GUI ✓ |
| Pivy / Shiboken6 / PySide6（Core/Gui/Widgets/OpenGL/OpenGLWidgets） | 全部构建+导入验证 ✓；已 staged 进 HAP runtime（Ext/） |
| GUI HAP staging | 183 个 AArch64 ELF + rawfile；签名 HAP 内 200 个 `.so*`，内容/新鲜度/签名摘要验证通过 |
| headless 6 项验收（本地） | **6/6 PASS**（2026-08-24 当前 staging 复验） |
| GUI 真机 | FreeCAD 1.1.2 主窗口、New Document、Part/Cube、复杂多色示例、Preferences ✓ |

## 构建后核对

DevEco 构建完成后先跑 GUI HAP 验证（native/rawfile/新鲜度一键核对）：

```sh
./scripts/build-gui-hap-ohos.sh
./scripts/verify-gui-hap.sh
```

当前包：`entry/build/default/outputs/default/entry-default-signed.hap`。

## 步骤 A：headless 验收真机复跑（关闭 headless 门禁）

1. DevEco Studio 打开仓库根目录 → Sync → Build Hap（自动签名）→ Run（默认 EntryAbility）。
2. 页面显示验收 JSON（ok）；hilog 核对：
   ```sh
   ./scripts/watch-headless-hap-log.sh
   ```
   找 `FreeCADProbe` 的 `Python acceptance result status=0 json={... ok:true ...}`。
3. 通过后告诉我，我来更新文档关闭 headless 门禁。

## 步骤 B：FreeCAD GUI（QAbility）真机运行与调试

1. 同一工程 Sync → Build Hap → Run config 选 **QAbility**。命令行从 DevEco 主机执行 `hdc -t <connect-key> shell aa start -b com.freecad.headless.acceptance -a QAbility`；如果已经在设备 shell，则直接执行 `aa start -b com.freecad.headless.acceptance -a QAbility`，不要再调用 `hdc`。
2. 启动链：QAbility.onCreate → `materializeFreecadRuntimeAsync`（解压 runtime + 设 env）→ `setupQtApplication('libfreecadqtapp.so')` → QPA dlopen main() → FreeCAD 主窗口渲染进 XComponent。
3. hilog 标签：`FreeCADGui`（ArkTS）、`QtForOhos`（QPA）、`FreeCADProbe`（验收）。
4. 当前回归重点：启动 QAbility → 新建文档/打开复杂文件 → 长时间旋转/缩放/选择 → 反复打开 Preferences/文件对话框 → 前后台切换。
5. 若仍崩溃，请保留 `QtForOhos`、`gl4es` 日志，并运行 `hidumper -e --print com.freecad.headless.acceptance -n 3` 保存 cppcrash 完整栈。

## 2026-08-22 追加：PySide6 已启用进 FreeCAD

- 构建了 **FREECAD_USE_PYSIDE=ON / FREECAD_USE_SHIBOKEN=ON** 的 FreeCAD v1.1.2 GUI（`scripts/configure-freecad-gui-qt6-pyside-ohos.sh`，独立构建目录，完成后安装覆盖 gui-qt6 前缀——PySide 超集）。
- 配置期识别到 "PySide 6.8.3 Python module found"；FreeCADGui 经运行时导入使用 PySide（Python 控制台等）。
- 重新 staging + 本地全量验证：**验收 6/6 PASS（PySide 超集 runtime）**、PySide6.QtWidgets + pivy 从 HAP runtime 导入正常。
- 已知伪影：`bin/FreeCAD` 独立可执行的本机冒烟在 pyside 变体下报 `Base::Exception` typeinfo 重定位错误（musl 加载器对可执行文件的 RTTI UNIQUE 符号处理）；**共享库路径（FreeCAD.so 经嵌入 Python、libfreecadqtapp.so 经 QPA）均正常**，HAP 走共享库路径，不受影响。

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
