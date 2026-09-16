# 真机交接：需要用户执行的剩余步骤

更新时间：2026-09-09。**FEM 的编译、安装、签名 HAP 打包与本机数据验收已完成；Axis Cross 黑块、标签和箭头当前已恢复。针对 BIM 材质与帧率回归，已移除 Coin 材质诊断循环，并将 GL4ES BGRA 客户端颜色数组改为临时 GLES VBO，重新生成待真机复验的 HAP。**

## 当前就绪状态（已验证）

| 产物 | 验证 |
|---|---|
| Qt 6.8.3 全 GUI 模块 + OHOS QPA（libqohos.so） | 构建/加载/注册 ✓ |
| FreeCAD v1.1.2 GUI（Qt6）已启用工作台 | bin/FreeCAD + libFreeCADGui + CAM/Draft/FEM/Import/Inspection/Measure/PartDesign/Points/Robot/Sketcher/Spreadsheet/Start/Surface/TechDraw GUI 编译安装 ✓ |
| Pivy / Shiboken6 / PySide6（Core/Gui/Widgets/Network/Svg/SvgWidgets/OpenGL/OpenGLWidgets） | 全部构建+导入验证 ✓；已 staged 进 HAP runtime（Ext/） |
| GUI HAP staging | 226 个 AArch64 ELF + rawfile；签名 HAP 内 243 个 `.so*`，内容/新鲜度验证通过 |
| headless 验收（本地） | **8/8 PASS**（2026-09-06，原有六项 + FEM 示例恢复及 UNV/MED 往返） |
| GUI 真机 | FEM 包曾安装并启动，用户确认模型基本加载；当前候选包的 BIM 帧时间、材质/透明度和 FEM 结果仍待复验。Axis Cross 的 label/箭头/黑块现象已在候选包中恢复正常。此前版本的主窗口、New Document、Part/Cube、Cube ViewFit 动画、复杂多色示例、Preferences、Recovery ✓ |
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

## 2026-09-06 FEM 接入：数据验收通过，真机初步加载通过

- 原先包里有 `FEMExample.FCStd`，但配置为 `BUILD_FEM=OFF`，没有 `Fem.so`、`FemGui.so` 或 `Mod/Fem`，因此每个 FEM 对象恢复失败；缺失 Python 包也会进入恢复检查的 `blocked import` 分支。本次没有放宽安全导入规则。
- HDF5 1.14.6、MEDFile 6.0.1 与 FreeCAD 内置 SMESH 7.7.1 已编译安装，FEM 默认启用。staging 递归收集 `libmedC.so.14`、`libhdf5.so.310`、SDK `libomp.so`，并验证 FEM Python 材料代理与许可文件。
- 当前包对应的本机原生八项验收全部通过：示例完整恢复 43 个对象、17 个 FEM Python 代理、6 份网格（1,956 个节点）和 3 组结果；四面体 UNV/MED 写入读回正确。结果在 `/storage/Users/currentUser/codex-freecad-artifacts/fem-port-20260906/acceptance-packaged/freecad-acceptance.json`。
- 独立 offscreen GUI 探针未完成：复制自签名的 `bin/FreeCAD` 在启动时收到 SIGSEGV，回溯位于 `/lib/ld-musl-aarch64.so.1`，没有执行 FEM 验收宏。该结果不能代替 `QAbility` 真机回归，也不能据此归因于 FEM。记录为同目录下的 `gui-native-probe.log`；继续工作时不要把旧 `gui-probe.json` 当作成功结果。
- 用户要求安装后，22:04 通过 HDC server `127.0.0.1:8710` 向 `192.168.3.16:39405` 执行 `install -r`，返回 `install bundle successfully`；重启 `QAbility` 返回成功，进程 PID 为 `24844`。随后默认值回退包再次以同一目标安装并启动，最新进程 PID 为 `32618`。最新记录位于 `/storage/Users/currentUser/codex-freecad-artifacts/fem-warp-render-20260906/axis-default-off/`。材料 ViewProvider、结果颜色/变形及编辑仍需逐项核对；外部 Gmsh/CalculiX/Elmer/Netgen 尚未接入，MeshPart/BIM 也仍默认关闭。
- 用户截图仍显示 PartDesign 的 `Cannot find icon: .../freecad-homeMod/PartDesign/WizardShaft/WizardShaft.svg`。已确认 runtime 包内存在该 SVG；`WizardShaft.py` 第 221、247 行直接把 `AppHomePath` 与 `Mod/...` 拼接，当前路径缺少目录分隔符。这是独立的图标路径问题，不是 FEM 模块缺失；本轮仅记录，未修改代码或为此重建。
- 可复现构建与验收命令见 `docs/fem-ohos.md`。原签名 HAP 已备份到 `/storage/Users/currentUser/codex-freecad-artifacts/fem-port-20260906/entry-before-fem-signed.hap`；当前候选 HAP 的 SHA-256 为 `83a0bd9aa38dd965b8f70343368f7d26ec2477b5e854e66f48b1183d210d744a`。Coin/GL4ES 材质诊断已从生产构建移除，正式补丁记录见 `patches/coin-4.0.0/ohos-remove-material-diagnostics.patch` 与 `patches/gl4es-81547d9/ohos-fpe-client-array-vbo.patch`。

## 2026-09-06 历史记录：BIM 材质与透明度异常（2026-09-13 更正根因归属）

- **2026-09-13 二次更正（推翻 09-12 的修复层）**：09-12 那条"gl4es 广告缺失 → Qt 退回 16 位深度"的因果链在 **Qt 侧不成立**。OHOS QPA 在 `makeCurrent` 时把 gl4es 的 GLES 入口解析器指向原生 EGL（`src/plugins/platforms/ohos/qohoseglplatformcontext.cpp:22-49`，`setGetProcAddress(resolveCurrentGlesProcAddress)` 且 `resolveCurrentGlesProcAddress = eglGetProcAddress`），而 Qt 的扩展判定走 `QOpenGLExtensionMatcher`（`src/gui/opengl/qopengl.cpp:41` → `funcs->glGetString(GL_EXTENSIONS)`，判别逻辑在 `src/gui/opengl/qopenglfunctions.cpp:314-370`），读到的是**原生驱动**的扩展串。gl4es 通过链接替换提供的 `glGetString` 不在 Qt 的解析路径上，因此 `ohos-advertise-depth24-extensions.patch` 广告什么 Qt 都看不到；本机 `hardext.depth24` / `hardext.depthstencil` 实测（`EXT_DIAG` 探针）也恒为 0 —— 原生 ES2 上下文普遍不声明 `GL_OES_depth24`（该扩展已被 ES3 吸收为核心功能），所以 `if(hardext.depth24)` 永远为假。该补丁因此是**双重不生效的死代码**，其注释已在 2026-09-13 改写以记录这一点，保留它只为 gl4es 自身扩展串的语义诚实。
- **真实根因与正确修复层（2026-09-13）**：根因仍是 **Qt 拿到的是 16 位深度缓冲**，但决策点在 Qt 自己：原生 ES2 不声明 `GL_OES_depth24` → `QOpenGLExtensions::Depth24` 未置位 → `src/opengl/qopenglframebufferobject.cpp:744` 静默回落 `GL_DEPTH_COMPONENT16` → 16 位分辨不了 BIM 的亚毫米近共面几何 → 逐像素抢深度。修复落在 `patches/qt-6.8-ohos/19-prefer-24bit-depth-attachment.patch`：新增 `reserveRenderbufferStorage()` 先尝试 `GL_DEPTH_COMPONENT24`、以 `glGetError()` 判定驱动是否接受、失败才降级 16 位并打印一次性告警；`PackedDepthStencil` 门控同时放宽到 ES3。该方案**不依赖任何扩展声明**，所以不受上面那条"Qt 读原生串"的限制。由 `scripts/build-qt6-gui-ohos.sh` 应用。
- **几何侧铁证（2026-09-13）**：红色 `Wall014` 是零厚度 `Part::Part2DObjectPython`（diffuse `(255,99,85)`，全模型仅 2 条 red 材质条目，`Transparency=0`）。解析全部 201 个 `.Shape.brp` 的 `Surfaces` 段确认：它**全部 10 个平面**与 `BuildingPart003`（313 曲面）、`BuildingPart005`（3014 曲面）逐位共面 —— 即用户观察到的"红色灰色两个重叠的集合"。量化验收指标 `Metric.java`（矩形 x=2060 y=1380 200×140 的中性灰占比）修复前基线为 **40.207%**。
- **2026-09-12 首次定位（结论部分成立，修复层已由上文更正）**：本节此前记录的"外部 context blend/depth 恢复"方向当天已被真机证伪（包括恢复激活态、延迟恢复、`glFinish` A/B、VBO 逐面材质补丁）。2026-09-12 用对照实验重新定位：手工构造的 `TranspTest.FCStd`（前盒绿色 70% 透明 + 后盒不透明）在设备上混合完全正确，证明基础透明管线无问题；BIM 玻璃上的细密斜纹只出现在透明面上，是近共面几何的深度冲突 —— **这一观察成立**。当时认为修复点是 gl4es 的扩展广告，现已确认该层对 Qt 无效，实际修复见上面两条。
- **2026-09-12 附带修复（启动参数顺序）**：`QAbilityStage.onAcceptWant()` 先于 `QAbility.onCreate()` 初始化 Qt，导致 `--ps fcstdPath <文件>` 从未进入 FreeCAD 的 argv（此前"用 fcstdPath 打开文件"其实都靠 FreeCAD 崩溃恢复在还原上次的文档）。现已在 `onAcceptWant`/`onNewProcessRequest` 中先调 `setAppArgsFromWant` 再初始化。另注意：应用沙箱读不到 `/data/local/tmp`，真机传测试文件需走 HAP rawfile（`freecad-home/share/examples/`）内路径。
- **现象**：打开 `BIMExample.FCStd` 后，部分红色/浅色表面出现不属于模型的白色重叠条纹；玻璃仍按不透明表面显示。旋转期间 FreeCAD 的 `paintEvent()` 约为 25–30 ms，但 RenderService 实际只有约 10–18 FPS。当前先解决材质正确性，不再继续性能调优。
- **与 Python 恢复警告的关系**：报告视图中的 `PropertyPythonObject::Restore: blocked import of module 'Arch...'` 表示 Arch/BIM Python Proxy 被安全导入规则阻止，可能影响对象重算、编辑或代理行为，需要作为独立兼容性问题处理。现有证据表明几何、视图材质及透明度数组已经进入 Coin/GL4ES，因此该警告不是当前白色条纹和玻璃不透明的直接原因。
- **已确认的透明 draw 状态**：颜色 attribute 是 normalized `GL_UNSIGNED_BYTE`，原生颜色和法线 attribute 均已启用且指针有效；混合为 `GL_SRC_ALPHA / GL_ONE_MINUS_SRC_ALPHA`，深度测试开启且 `depthmask=0`。Coin cache 同时具有对应的 diffuse/transparency 数组，并能看到 `alpha=38..255`、`alpha=77..255` 等范围。由此已排除 attribute 未归一化、原生 attribute 未启用、指针/VBO 绑定错误、混合关闭、混合因子错误和透明 draw 写深度。
- **已证伪的修改**：给 `SoBrepFaceSet` VBO 顶点颜色补写 packed transparency 后，真机画面没有任何变化。`ohos-brep-vbo-materials.patch` 及其 `prepare-freecad-source.sh` 接入已删除，CPPLib 的 FreeCAD 源码也已恢复到试验前版本，不要恢复该实验。现有 build/install、staged HAP 和设备安装包仍可能包含最后一次试验生成的旧二进制；建立干净验证基线时必须重新编译、install、stage、构建并安装 HAP。
- **材质线索**：从示例文件提取的 `GuiDocument.xml` 中，序列化 `ShapeMaterial` 的 `specularColor="255"`，即 RGB 为黑色；白色条纹不是文件设计的正常镜面高光。更可能的方向是 GL4ES FPE 材质/灯光状态陈旧、多余 light 状态，或透明/不透明面合并绘制时后部三角形的材质索引处理。
- **下一步**：先用 `/data/local/tmp/MaterialControl.FCStd` 对照普通整体透明对象是否正常；再让 Coin 日志记录每个 cache 中第一个 `alpha < 255` 三角形的索引和 RGBA，并记录 GL4ES 的 lighting、normalize/rescale、前表面 material 以及每个启用 light 的参数。根据结果做单变量材质/灯光实验，确认根因后再形成正式补丁。
- **诊断资料**：原生 attribute/state 日志位于 `/storage/Users/currentUser/codex-freecad-artifacts/material-debug-20260906/native-attrs/current-native-attrs.log`，示例的材质 XML 位于同目录下的 `GuiDocument.xml`。临时诊断仍在 `/storage/Users/currentUser/CPPLib/sources/gl4es/81547d9/src/gl/fpe.c` 和 `/storage/Users/currentUser/CPPLib/sources/coin/4.0.0/src/caches/SoPrimitiveVertexCache.cpp`；相应备份位于该 artifact 目录的 `fpe.before-indexed-material-diag.c` 与 `coin-before-diag/SoPrimitiveVertexCache.cpp`。这些诊断不属于正式仓库补丁，继续构建或清理前要明确是否保留。

## 2026-09-09 当前候选：先验证性能与材质

- 已移除 Coin `SoPrimitiveVertexCache` 中每次 cache/triangle 的 OHOS 材质日志和 `dlopen` 路径，避免复杂 BIM 在渲染线程中反复格式化和输出。
- GL4ES 的 `GL_BGRA` 客户端颜色数组仍会做 RGBA 转换，但转换结果现在上传到短生命周期 GLES VBO；删除 VBO 名称由驱动延迟回收，不再对每个 scratch draw 调用 `glFinish()`。普通 FPE draw 仍每 4 条调用非阻塞 `glFlush()`。
- 该候选 HAP 已完成 stage/build/verify，SHA-256 为 `83a0bd9aa38dd965b8f70343368f7d26ec2477b5e854e66f48b1183d210d744a`。HDC 当前未确认在线，因此还没有把候选包的 BIM 帧时间、材质透明度和 FEM 结果视觉结论写成“真机已通过”。

## 构建后核对

DevEco 构建完成后先跑 GUI HAP 验证（native/rawfile/新鲜度一键核对）：

```sh
./scripts/build-gui-hap-ohos.sh
./scripts/verify-gui-hap.sh
```

当前待复验包：`entry/build/default/outputs/default/entry-default-signed.hap`，SHA-256
`83a0bd9aa38dd965b8f70343368f7d26ec2477b5e854e66f48b1183d210d744a`。
该包新增 FEM/SMESH、MED/HDF5/OpenMP runtime，并包含移除 Coin 材质诊断、BGRA 临时
VBO 及 Axis Cross 修复后的 GL4ES/FreeCAD 路径；已通过 rawfile 一致性、新鲜度、243 个 native `.so*`、GUI 工作台、RUNPATH、
Python 绑定和 splash 生成资源检查，以及本机八项数据验收。它尚未在设备上完成
BIM 帧时间、材质/透明度、FEM 结果显示和 Axis Cross 复验；此前中文默认值、独立
对话框及 splash 的真机通过结论不应自动升级为本包已验证。

GL4ES 增量构建后还必须对对应 build tree 执行 `cmake --install`，再运行
`stage-gui-hap.sh`；只运行 Ninja 会让新库停留在源码/构建树，最终 HAP 仍可能
打入 install prefix 中的旧 `libGL.so`。

## 步骤 A：headless 验收真机复跑（关闭 headless 门禁）

> ⚠️ 2026-09-15 起，对外包的默认形态里**没有 `EntryAbility`**（`PACKAGE_FLEXIMIND=OFF`，
> `entry/hvigorfile.ts` 在构建期把它从 `module.json5` 裁掉，因为它是 `exported: true` 的
> 无头桥）。本步骤要在**内部包**上做：从终端带着开关跑 `PACKAGE_FLEXIMIND=ON` 的
> `stage-gui-hap.sh` → `build-gui-hap-ohos.sh` → `install-gui-hap.sh`；用 DevEco 的话也要
> 从带开关的终端启动它，否则 Sync/Build 读不到开关会按 OFF 处理。见
> `docs/appgallery-release.md` 的「FlexiMind 面的清除」。

1. DevEco Studio 打开仓库根目录 → Sync → Build Hap（自动签名），再显式启动 EntryAbility；默认 Run 入口是 GUI `QAbility`。
2. 页面显示验收 JSON（ok）；hilog 核对：
   ```sh
   ./scripts/watch-headless-hap-log.sh
   ```
   找 `FreeCADProbe` 的 `Python acceptance result status=0 json={... ok:true ...}`。
3. 通过后告诉我，我来更新文档关闭 headless 门禁。

## 步骤 B：FreeCAD GUI（QAbility）真机运行与调试

1. 同一工程 Sync → Build Hap → Run config 选 **QAbility**。命令行从 DevEco 主机先执行 `hdc list targets -v`，只选择状态为 `Connected` 的完整 key，再执行 `hdc -t <connect-key> shell aa start -b com.liangxiaohui.freecad -a QAbility`。只有 `bm`/`aa` 实际具有执行权限的特权 HiShell 才直接调用设备命令；`uname` 显示 HarmonyOS/Toybox 不能单独作为判断依据。
2. 启动链：QAbility.onCreate → 并行准备 runtime 与同一 Ability 内的无框 ArkUI splash 子窗 → `setupQtApplication('libfreecadqtapp.so')` → QPA 复用主窗宿主页并启动 XComponent → `.gui-ready` 后抬起主窗、销毁 splash。
3. hilog 标签：`FreeCADGui`（ArkTS）、`QtForOhos`（QPA）、`FreeCADProbe`（验收）。
4. 当前回归重点：启动 QAbility → 新建文档/打开复杂文件 → 长时间旋转/缩放/选择 → 反复打开 Preferences/文件对话框 → 前后台切换。
5. 若仍崩溃，请保留 `QtForOhos`、`gl4es` 日志，并运行 `hidumper -e --print com.liangxiaohui.freecad -n 3` 保存 cppcrash 完整栈。

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
- **HAP 构建用的 SDK 必须是 Release 版**（当前 `Ohos_sdk_public 26.0.0.38`）。hvigor 找打包/签名
  工具时写死的是 **jar 名**，而 OpenHarmony 官方 Public SDK 里只有同名可执行文件 —— 中间靠
  `scripts/toolchain-bridges/` 里两个 1~2 KB 的桥接壳转发，所以**换 SDK 要连壳一起装**，
  别手工搬目录：用 `sh scripts/switch-ohos-sdk.sh <SDK 根目录>`（它会装壳、补
  `libimage_transcoder_shared.so`、切 `.ohos-sdk/26`，并在 SDK 非 Release 时直接拒绝）。
  缘由与排查见 `docs/appgallery-release.md` 的「Step 6」。
- `probes/freecad-headless/acceptance.py` 是验收脚本唯一真源（staging 覆盖 rawfile 副本），改 env/布局必须改这里。
- GUI 会话的 FreeCAD 运行布局：FREECAD_APP_HOME=filesDir/freecad-home（含 Mod/ python 目录）、FREECAD_APP_LIBRARY_DIR=HAP libs 根、FREECAD_USER_*=filesDir 子目录。
- 构建/验证入口脚本：`scripts/build-qt6-gui-ohos.sh`、`build-qt6-modules-ohos.sh`、`configure-freecad-gui-qt6-ohos.sh`、`build-freecad-gui-qt6-ohos.sh`、`stage-gui-hap.sh`；绑定栈：`CPPLib/scripts/build-swig-ohos.sh`、`build-pivy-ohos.sh`、`build-shiboken6-ohos.sh`、`build-pyside6-ohos.sh`。
