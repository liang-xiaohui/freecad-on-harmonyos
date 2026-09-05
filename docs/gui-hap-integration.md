# FreeCAD v1.1.2 GUI HAP 集成（Qt6 + OHOS QPA）

更新时间：2026-09-05（单 Ability 无框 splash、主窗口、基础 3D 与 Preferences 真机通过）

## 集成模型

采用 tqtc Qt5.12 fork 的官方 HAP 模板（`CPPLib/sources/qt/5.12.12-ohos/template/`）：

```
ArkTS (QAbilityStage/QAbility)  ──import libqohos.so──►  QPA NAPI（handleAbilityOnCreate 等）
        │                                                    │
        ▼                                                    ▼
XComponent(libraryname='qohos')  ──OH_NativeXComponent──►  QPA qarkui/XComponent 注册
                                                             │
                                                             ▼
                                        setupQtApplication(appName=libfreecadqtapp.so)
                                                             │
                                            dlopen + 调用 libfreecadqtapp.so 的 main()
                                                             │
                                                        FreeCAD GUI main()
```

- **libqohos.so**（Qt6 OHOS QPA 插件）：既是 XComponent 原生库（`libraryname: 'qohos'`），又是 NAPI 模块（`nm_modname="qohos"`，constructor 注册）。
- **libfreecadqtapp.so**：Qt 应用库，导出 `main(argc, argv)`；由 FreeCAD `src/Main/MainGui.cpp` 编译为共享库（`CPPLib/build/freecad-qtapp/`，独立 CMake 工程）。
- QPA 启动前设置 `QT_QPA_PLATFORM=ohos`、`QT_PLUGIN_PATH=HAP libs 目录`，FreeCAD 的 `QApplication` 自动走 ohos 平台。

## 本工程改动（entry/ 模块）

- `entry/src/main/ets/`：新增 qability/、qabilitystage/、process/、common/、pages/MainWindowNativeNode 等（自 tqtc 模板拷贝）；`QtAppConstants.ets` 的 `APP_LIBRARY_NAME='libfreecadqtapp.so'`。
- `module.json5`：AbilityStage=`QAbilityStage.ets`；abilities = EntryAbility（headless 验收）+ QAbility（GUI、当前 mainElement、file uri skills）。
- `entry/src/main/qt/libqohos.d.ts` + `oh-package.json5`：libqohos.so 的 ArkTS 类型声明。
- 资源：string.json 新增 QAbility_desc / 悬浮窗 / 后台权限；main_pages 含 Index、原生节点页和 `StartupSplash`；启动子窗使用 FreeCAD 1.1.2 `src/Gui/Icons/freecadsplash.png` 的原始官方图片，应用图标仍使用方形 `icon.png`。

### 单 Ability 启动 splash

OHOS QPA 会把新的 Qt 顶层窗口映射为新的 Ability，因此不能直接把桌面端独立
`QSplashScreen` 作为第一个 Qt 窗口。系统 `startWindowIcon` 又只适合应用图标，曾表现为小 logo、
空白大窗和系统切换动画。最终方案通过 `startWindowType=REQUIRED_HIDE` 隐藏系统 starting
window，并由 `QAbility` 在同一 Ability 内管理一个 ArkUI splash 子窗。

启动时序如下：

1. `onWindowStageCreate()` 记录原主窗几何，将主窗临时调整为官方图片的 `568x368 vp`
   居中矩形，加载透明 `MainWindowNativeNode` 宿主页并显式 `showWindow()`。
2. 父主窗可见后，以同一矩形创建 `decorEnabled: false` 的 `StartupSplash` 子窗，加载并显示
   `freecadsplash.png`；子窗显示后才设置透明背景。父窗未显示或过早设置子窗背景都会收到
   WindowManager `1300002`。
3. runtime 和 splash 就绪后才把同一个 `WindowStage` 交给 QPA。QPA patch 16 将 `createInfo`
   注入已经加载的宿主页，避免二次 `loadContent()` 引起位置跳变；同时暂存 Qt 请求的主窗几何，
   并在 splash 活跃时忽略 decor/background 修改。
4. XComponent 保持 attached 但移到屏幕外，避免隐藏组件导致 native surface 销毁。FreeCAD 在
   启动工作台激活后延迟 100 ms 写入 `.gui-ready`；ArkUI 恢复 Qt 主窗几何、移回 XComponent，
   等待 50 ms 后抬起主窗，最后销毁 splash 子窗。

FreeCAD patch 禁用桌面端 `QSplashScreen`、OHOS 状态栏启动 logo 和样式调色板临时 QLabel；
QPA patch 15 还会把启动阶段的孤立 `QLabelClassWindow` 兜底映射到现有主窗。它们共同阻止
第二个 Ability、最小化动画和主窗退到 splash 后面。主窗宿主与子窗必须完全同尺寸同位置；
否则官方 PNG 透明投影附近会露出另一层窗口边界。

2026-09-05 在 `192.168.3.16:39405`、`3296x2472` 显示上真机验证：host 与 splash 均为
`1137,905,1022x662`。连续取帧只出现一张无标题栏官方 splash，随后直接过渡到完整主窗；
日志最终顺序为 `main window raised behind startup splash`、`FreeCAD GUI ready; startup transition complete`。

### 启动后提示与 Python GUI 依赖

- API 26 不提供 Qt 模板可选的 FileManagerServiceKit，文件图标查询会回退为空 `QIcon`。
  Start 页原先继续缩放空 pixmap，启动后会产生可见提示；
  `ohos-start-filecard-null-pixmap.patch` 现在为任何空 thumbnail 创建透明占位图。
- Addon Manager 启动会导入 `PySide6.QtNetwork`。PySide6 构建模块集已扩为
  `Core;Gui;Widgets;Network;Svg;SvgWidgets;OpenGL;OpenGLWidgets`；staging 和 HAP 验证脚本
  都会拒绝缺少 `QtCore`、`QtGui`、`QtWidgets` 或 `QtNetwork` 绑定的产物，避免问题延迟到真机启动。

## Staging（scripts/stage-gui-hap.sh）

- `entry/libs/arm64-v8a/`（完整 GUI native 依赖闭包，当前 155 个 AArch64 ELF；签名 HAP 含 229 个 `.so*`）：
  - Qt6 运行库（libQt6*.so.6，14 个）+ plugins/platforms/libqohos.so、qoffscreen、qminimal + imageformats（qsvg/qjpeg/qico/qgif）
  - FreeCAD GUI 基础线：FreeCAD.so、FreeCADGui.so、libFreeCADApp/Base/Gui.so、Part/PartGui、Mesh/MeshGui、Material/MatGui
  - headless 验收模块：Sketcher.so、_PartDesign.so、Import.so；这些不是 GUI 工作台，不能替代 `SketcherGui.so`、`PartDesignGui.so`、`ImportGui.so`
  - libfreecadqtapp.so、Coin（libCoin.so.80）、gl4es（libGL.so）、OCCT（libTK*）、CPython（libpython3.11 + lib-dynload）、xerces、libffi
- `rawfile/`：python311.zip、freecad-runtime.zip（GUI Mod/Ext/share + headless Mod/Sketcher|PartDesign|Import|Start|Draft）、freecad_headless_acceptance.py

## 运行时物化（materializeFreecadRuntimeAsync）

FreeCAD GUI 需要 `Mod/Ext/share` 与 Python stdlib；HAP rawfile 里的 `freecad-runtime.zip`/`python311.zip`
由 `libfreecadacceptance.so` 新增的 NAPI `materializeFreecadRuntimeAsync(filesDir)` 物化：

1. rawfile → `filesDir/runtime/`（zip 原样拷贝，复用 copyRawFile）
2. native async work 中的纯 C++/zlib 解压 `freecad-runtime.zip` → `filesDir/freecad-home/`
3. 设置环境（与 headless 验收同布局）：`FREECAD_APP_HOME/FREECAD_APP_LIBRARY_DIR`=HAP libs 根、
   `FREECAD_APP_RESOURCE_DIR`=freecad-home/share、`FREECAD_USER_*`=filesDir 子目录、`LD_LIBRARY_PATH` 前置 libs 根

`QAbility.ets::onCreate` 先同步复制 rawfile 并设置环境，再提交纯 C++ 解压任务。任务完成前暂存
`WindowStage` 和前台状态，不把它们交给 QPA，因此 XComponent/FreeCAD main 不会抢跑。
`freecad-home/.runtime-ready` 以 ZIP 大小和 CRC32 标识完整版本，只有解压成功才写入。

## 构建与运行

1. gl4es 变更后运行 `/storage/Users/currentUser/CPPLib/scripts/build-gl4es-ohos.sh`。
2. Qt/QPA 变更后运行 `./scripts/build-qt6-gui-ohos.sh`；FreeCAD 变更后运行 `./scripts/rebuild-freecad-all-workbenches.sh`。
3. `sh scripts/stage-gui-hap.sh`。
4. 本地验收需要先执行 `./scripts/sign-staged-native-ohos.sh`，再执行 `./scripts/run-staged-freecad-acceptance.sh`。
5. `./scripts/build-gui-hap-ohos.sh`（或 DevEco Studio：Sync → Build Hap）。
6. `./scripts/verify-gui-hap.sh`。
7. 运行：
   - 验收（headless 门禁）：显式启动 EntryAbility，页面显示验收 JSON，hilog 见 `FreeCADProbe` 的 `Python acceptance result` 行
   - GUI：启动 QAbility（DevEco run config 选 QAbility，或 `aa start -b <bundle> -a QAbility`），主窗口经 XComponent 呈现 FreeCAD GUI

## 真机结论与后续回归

- 2026-08-25 真机已显示主窗口、New Document、Part/Cube 与复杂多色示例。3D 根因不是 FEM/Assembly 缺模块，也不是要把所有 RasterSurface 强制改成 GL backing store，而是 Qt 与 gl4es 共用 GLES context 时的缓存失配。`patches/gl4es-81547d9/ohos-external-context-state.patch` 与 QPA patch 02/11 完成 context 映射、proc address 解析和 program/VBO/EBO/vertex-attrib 缓存失效。
- Edit → Preferences 已打开成功。`patches/freecad-1.1.2/ohos-native-uitools.patch` 恢复原生 QUiLoader、链接 `libQt6UiTools.so.6`，并为失败页面增加空值防线。
- QPA patch 12 在输入法 controller detached 时延后 cursor rectangle 更新，避免数万条非侵入通知淹没界面。
- 当前包 SHA-256 见 `docs/handoff-device-steps.md`。后续重点是长时间相机交互、更多工作台、文件对话框和前后台切换。
- 如果下拉菜单仍只有 Part、Material、Mesh，先运行 `./scripts/verify-gui-hap.sh`；它会拒绝缺少三个 GUI native 库或使用旧 rawfile 的 HAP。
- MeshPart/BIM 需要额外的 Salome SMESH、MEDFile 和 HDF5；依赖未安装时保持关闭，不影响 PartDesign/Sketcher/Import 等核心工作台。
- Assembly 默认启用。FreeCAD 1.1.2 发布源码不包含 `OndselSolver` 子模块，重建脚本会固定准备标签记录的提交（`30e9b64e8bf881d438d4b88834f9ba3674865418`）。Reverse Engineering 同样默认启用；MeshPart、BIM、FEM 因 SMESH/MEDFile/HDF5 依赖未移植而保持关闭。
- Addon Manager 默认开启；发布源码不包含该子模块时，重建脚本会固定准备提交 `937b6877239dc78ef59eeefe8099e5f14243eda1`。无网络或不需要附加组件管理器时可设置 `FREECAD_BUILD_ADDONMGR=OFF`。
- Start 默认开启；它使用 Microsoft.GSL 的 `gsl::owner` 头文件，重建脚本会固定准备 FreeCAD 1.1.2 记录的提交 `543d0dd3fe966ddf20e884b44e5fdbf12cb43784`。无网络时可设置 `FREECAD_BUILD_START=OFF`，但会失去 Start/StartGui 工作台。
- 2026-08-24 本地端到端复验：**GUI HAP 运行时（Qt6 staged 集合）跑通全部 6 项验收**（OK: True）——OCCT、FreeCAD 1.1.2、Part/Import/Materials/Mesh/PartDesign/Sketcher 导入、Box/Cylinder/Boolean、FCStd、STEP、STL。可直接运行 `scripts/run-staged-freecad-acceptance.sh`。
- **源码真源提醒**：`probes/freecad-headless/acceptance.py` 是验收脚本的唯一真源，staging 会把它拷为 rawfile；改 env/布局必须改 probes/（曾因只改 rawfile 副本被 staging 覆盖导致真机验收会失败——2026-08-22 已修正真源）。
- 2026-08-22：PySide6/shiboken6/pivy 已 staged 进 HAP runtime（Ext/ 下 + libpyside6/libshiboken6 运行库；NAPI LD_LIBRARY_PATH 增加 Ext/PySide6、Ext/shiboken6），本地从 HAP runtime 解压目录验证 PySide6.QtWidgets 与 pivy 均可用。
- **本地探针提示**：stage-gui-hap.sh 不签名（HAP 构建时签名）；本地 target-runtime 探针在 staging 后运行 `scripts/sign-staged-native-ohos.sh`。
- 当前 API 26 SDK 不含 Qt 模板中的 FileManagerServiceKit。Qt 文件图标引擎会捕获该可选查询异常并返回空系统图标；Start 页在 `QIcon::pixmap()` 仍为空时改用透明占位，不再调用 `QPixmap::scaled()` 触发通知。`OhosExportModules.ts` 不伪造当前 SDK 无法解析的 Kit 导入。CoreSpeechKit、Penkit、ShareKit、StatusBarExtensionKit 同样未启用。
- 2026-08-22：**Sketcher/PartDesign/Import 改用 Qt6 重建**（`scripts/configure-freecad-headless-qt6-ohos.sh` + `build-freecad-headless-qt6-ohos.sh`，BUILD_GUI=OFF 免 SWIG）。原因：headless（Qt5）产物混入 Qt6 HAP 会导致 Qt5/Qt6 ABI 冲突；现 staged 集合全部 Qt6 链接、依赖闭包审计通过（无 Qt5 残留），GUI HAP 内的 headless 验收（EntryAbility）可用。
- 5.12 fork 有 qohos 样式插件与 platform theme 深度定制（dialog embedded remap 等），Qt6 移植先走默认样式，后续按需补。
- Pivy/Shiboken-PySide 已构建并随 GUI runtime staged 到 `Ext/`；本地导入验证通过。
- headless 验收相关：`scripts/configure-freecad-headless-qt6-ohos.sh` / `build-freecad-headless-qt6-ohos.sh`（Qt6 headless 模块构建，供 GUI HAP 内验收）。
- Qt6 的 qohos 插件默认不开 accessibility（QT_NO_ACCESSIBILITY）。
