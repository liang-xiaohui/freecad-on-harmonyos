# FreeCAD v1.1.2 on HarmonyOS PC

将 **FreeCAD v1.1.2** 原生移植到 HarmonyOS PC（`arm64-v8a`）的工程记录。

> 唯一上游基线是 FreeCAD v1.1.2。旧的 0.21.2 构建只属于历史验证，不再作为移植产物或回退路线。

> 本仓库公开可访问：分发修改过的 LGPL 组件（FreeCAD 主体、Qt 补丁、Coin3D 等）时，
> 由此满足 LGPL-2.1 的**源码提供义务**。应用隐私政策见 [简体中文](PRIVACY.md) /
> [English](PRIVACY.en.md)；上架合规材料与提审清单见 [AppGallery 发布](docs/appgallery-release.md)。

## 当前状态

截至 2026-09-05：

- FreeCAD v1.1.2 headless 已完成交叉编译、安装和 ELF 审计。
- OpenCASCADE 7.8.1 已完成 OHOS `arm64-v8a` 构建、安装、48 个共享库 ELF 审计，并已用于重新构建 FreeCAD headless 与 OCCT smoke probe。
- 已构建 `FreeCADCmd`、`FreeCAD.so`、`Part`、`Mesh`、`Import`、`Materials`、`Sketcher` 和 `PartDesign` 等模块。
- CPython 3.11 runtime 已补齐 `_socket`、`binascii`、`zlib` 和 `_ctypes`，staged Python probe 已通过。
- GUI HAP staging 包含完整 native 依赖闭包（当前 155 个 AArch64 ELF）；签名 HAP 内含 229 个 `.so*`，全部通过 AArch64、RUNPATH、递归依赖、内容和新鲜度审计。
- **完整原生 GUI 的基础闭环已在真机通过。** FreeCAD 1.1.2 主窗口、菜单、工具栏、New Document、Part/Cube 与复杂多色示例均可显示；Edit → Preferences 也可以打开，不再闪退。
- 3D 白屏/创建 Cube 闪退的根因是 Qt 原生 GLES 状态与 gl4es 内部缓存不同步。最终修复在 EGL context 交接时映射 gl4es state，并使 program、VBO/EBO 与 vertex-attrib enable 缓存失效；不启用会破坏普通窗口的全局 RasterSurface GL backing-store 实验。
- Preferences 崩溃的根因是 OHOS 路径禁用了原生 `QUiLoader`，而精简 PySide6 又没有 QtUiTools Python 扩展。当前恢复目标端 Qt6 UiTools，并对加载失败的 form 增加空值防线。
- GUI 冷启动现使用同一 QAbility 内的无框 ArkUI 子窗显示 FreeCAD 官方 splash。系统 starting window 和桌面端 `QSplashScreen` 均被禁用；主窗宿主与 splash 使用相同几何，FreeCAD 发布 GUI-ready 标记后才抬起主窗并移除 splash，已在真机连续取帧验证。
- 启动期 `Document Recovery` 已按完整主窗几何居中且 `Cleanup` 可点击；Part 新建 Cube 的 `ViewFit` 放大动画也已同步 Coin 自动裁剪面，不再出现中间帧被旧 near/far 裁切的变形。
- GUI HAP 的 Qt6 runtime 已通过本地 6/6 headless 验收（OCCT/模块/布尔/FCStd/STEP/STL）；FreeCAD GUI（Qt6）二进制可启动至 Qt 事件循环（offscreen）。真机执行见 [DevEco 执行指引](docs/device-run-guide.md)。
- GUI 进展（Qt6 目标线，重大推进）：
  - **Qt 6.8.3 qtbase 全 GUI 构建+安装完成**（`scripts/build-qt6-gui-ohos.sh`）：Gui/Widgets/OpenGL(GLES2)/EGL/PrintSupport/Network/Xml/Concurrent + offscreen/minimal/linuxfb 平台插件；本机冒烟测试 qVersion=6.8.3、QWidget 正常运行。
  - **Qt6 OHOS QPA 移植完成编译**：tqtc Qt5.12 `qohos` 平台插件（331 文件）整体移植进 qtbase 源码树并 CMake 化；裁剪 accessibility（QT_NO_ACCESSIBILITY）、字体库改 QFreeTypeFontDatabase 扫 /system/fonts、NAPI 桥适配 SDK 26（node-addon-api + node_api.h 兼容头）；`libqohos.so` 编译链接通过、插件可加载注册。
  - **qtsvg + qttools 构建安装完成**（Svg/SvgWidgets + UiTools/Designer/Linguist；qttools 跳过 libclang/qdoc）。
  - **FreeCAD v1.1.2 GUI 核心及已启用工作台完成编译安装**：默认启用 Part/PartDesign、Mesh、Material、Sketcher、Import、TechDraw、Spreadsheet、Start、Addon Manager、CAM、Draft、Inspection、Measure、Points、Robot、Surface、Assembly、Reverse Engineering 和 FEM 等。FEM 使用 HDF5 1.14.6、MEDFile 6.0.1 与内置 SMESH 7.7.1；示例对象恢复和 UNV/MED 数据往返已通过本机 OHOS 原生验收，外部网格生成器/求解器尚未接入，详见 `docs/fem-ohos.md`。MeshPart 仍默认关闭；BIM（Arch）已于 2026-09-14 接入——它是纯 Python，由 `scripts/install-bim-module-ohos.sh` 在 `cmake --install` 之后按安装清单写入前缀，不走 CMake 的 `BUILD_BIM`，详见 `docs/bim-ohos.md`。Assembly 使用 FreeCAD 1.1.2 固定版本的 OndselSolver 子模块。**FreeCAD AI** 助手工作台（第三方 `ghbalf/freecad-ai`）已于 2026-09-14 接入——同样是纯 Python，由 `scripts/install-freecad-ai-module-ohos.sh` 装进前缀 `Mod/freecad-ai`，不走 CMake，详见 `docs/freecad-ai-ohos.md`；HAP 为此补上了此前完全缺失的 `ohos.permission.INTERNET`，注意 OHOS Python 没有 `_ssl` 扩展，当前只支持明文 `http://` 端点。桌面 GL API 由 gl4es 提供。
  - **GUI HAP staging 已完成**（见 [GUI HAP 集成](docs/gui-hap-integration.md)）：Qt 应用库 `libfreecadqtapp.so`（导出 main）已构建；entry/ 已按 tqtc 官方模板改造（QAbilityStage/QAbility + XComponent 页）；`scripts/stage-gui-hap.sh` 已 staged 完整 GUI native 依赖闭包（数量由验证脚本动态校验）+ rawfile（python311.zip + freecad-runtime.zip + 验收脚本），headless 验收能力保留在 EntryAbility。
  - 首次 GUI 构建尝试（Qt 5.12.12 + Coin 4.0.0）卡在 `FreeCADGui/MainWindow.cpp`：Qt5.12 头缺 `QTime` 定义、`QSignalMapper::mappedWidget` 需 Qt ≥ 5.15；Qt 5.15 源码获取失败（tqtc 分支不存在），故按计划转向 Qt6。
- Pivy、Shiboken6、**PySide6 全绑定栈（Core/Gui/Widgets/Network/Svg/SvgWidgets/OpenGL/OpenGLWidgets）均已构建并验证**（v6.8.3，QWidget 可创建）。
  - FlexiMind headless runtime 已接入：`EntryAbility` 提供参数化夹指、参数化模型和人工 FCStd job bridge。普通 GUI HAP 不打包或自动激活 `FlexiMindGripDesign`；该工作台由 FlexiMind 设计交付包的 launcher 按需注入。接口与设备调用见外部私有材料。**私有侧的输入清单、作业运行器与作业契约文档不进本仓库**（本仓库公开）：`PACKAGE_FLEXIMIND=ON` 时由外部钩子 `scripts/private/fleximind-stage.sh` 提供，加载器见 [`scripts/fleximind-hook.sh`](scripts/fleximind-hook.sh)。

当前 FreeCAD 安装前缀：

```text
/storage/Users/currentUser/CPPLib/install/freecad/1.1.2/ohos/arm64-v8a-headless
```

执行文档：

- [移植执行计划](docs/porting-plan.md)
- [依赖与技术闸门矩阵](docs/dependency-matrix.md)
- [Headless HAP 验收](docs/headless-hap-acceptance.md)
- [上架发布清单（AppGallery）](docs/appgallery-release.md)
- 隐私政策：[在线版](https://liang-xiaohui.github.io/freecad-on-harmonyos/privacy/)（GitHub Pages，AGC 里填的就是它）· [简体中文](PRIVACY.md) · [English](PRIVACY.en.md) · [网页版源目录](docs/privacy/)（自足双语小站，可整目录搬到任何静态托管）

## 可复跑入口

```sh
./scripts/build-freecad-headless-ohos.sh
./scripts/audit-freecad-headless-ohos.sh
./scripts/build-occt-7.8-ohos.sh
./scripts/audit-occt-7.8-ohos.sh
./scripts/build-occt-smoke-ohos.sh
./scripts/build-headless-hap-native-ohos.sh
./scripts/stage-headless-hap.sh
./scripts/run-staged-python-runtime-probe.sh
# PACKAGE_FLEXIMIND 默认 OFF：这个 HAP 是对外分发的产物，默认不带 FlexiMind/ 载荷、
# 不带验收脚本 rawfile/freecad_headless_acceptance.py，并且 entry/hvigorfile.ts 会在构建期
# 把导出的 EntryAbility（无头桥）从 module.json5 里剥掉。三个脚本要同一次构建里取值一致：
#   PACKAGE_FLEXIMIND=ON ./scripts/stage-gui-hap.sh       # 载荷 + 验收脚本
#   PACKAGE_FLEXIMIND=ON ./scripts/build-gui-hap-ohos.sh  # 保留 EntryAbility 声明
#   PACKAGE_FLEXIMIND=ON ./scripts/verify-gui-hap.sh      # 按内部包断言
# ON 时的私有输入清单与打包/断言逻辑由外部钩子提供：scripts/private/fleximind-stage.sh
# （在 .gitignore 里，不进公开仓库），加载器是 scripts/fleximind-hook.sh；缺钩子会明确报错退出。
./scripts/stage-gui-hap.sh
./scripts/sign-staged-native-ohos.sh  # 仅供本地 target-runtime 探针
./scripts/run-staged-freecad-acceptance.sh
./scripts/build-gui-hap-ohos.sh
./scripts/verify-gui-hap.sh
HDC_BIN=/data/service/hnp/bin/hdc HDC_SERVER=127.0.0.1:8710 \
  HDC_TARGET=<IP:PORT> ./scripts/install-gui-hap.sh
```

DevEco/Hvigor 完成签名构建后，核对最终包：

```sh
./scripts/verify-headless-hap.sh
```

`verify-headless-hap.sh` 会拒绝缺少 v1.1.2 必需模块、rawfile runtime，或早于当前源码/staging 的陈旧 HAP。

当前可安装 GUI 包为 `entry/build/default/outputs/default/entry-default-signed.hap`。

签名配置仅保存在本机。首次检出后以 `build-profile.example.json5` 为结构创建
`build-profile.json5`，再由 DevEco/本机签名流程填入证书、profile、keystore 和口令；
真实 `build-profile.json5` 已被忽略，禁止提交签名材料。

hvigor 只接受 **DevEco 加密后的口令密文**（明文会被直接拒绝），且解密材料必须位于 `.p12`
同目录的 `material/` 下。为免在 GUI 里做这些事，本仓库提供两个工具：

```sh
./scripts/init-release-signing.sh              # 生成发布 .p12 + .csr + 加密口令（上架用）
./scripts/build-release-app.sh                 # 出 .app（AGC 上传用；stage → assembleApp → verify）
./scripts/build-release-hap.sh                 # 出 release 签名的 .hap（模块产物，供 .app 使用）
./scripts/sign-staged-native-ohos.sh           # 仅本地 target-runtime 探针自签名
```

- [`scripts/signing-password.js`](scripts/signing-password.js)：读写那种口令密文，
  `decrypt` 找回明文、`encrypt` 为任意口令生成可粘贴的密文。
- [`scripts/init-release-signing.sh`](scripts/init-release-signing.sh)：一键生成发布密钥库与
  CSR，并把 `build-profile.json5` 需要的片段直接打印出来。
- [`scripts/build-release-app.sh`](scripts/build-release-app.sh)：**出 AGC 提审上传的应用包**
  `build/outputs/release/freecad-on-harmonyos-release-signed.app`。AGC 只收 `.app`（App Pack），
  不收 `.hap`。
- [`scripts/build-release-hap.sh`](scripts/build-release-hap.sh)：出 release 签名的模块 `.hap`。
  签名按 **product** 绑定（不是 buildMode），所以这里把 `PRODUCT` 与 `BUILD_MODE` 一起切到
  release；产物在 `entry/build/release/outputs/default/`。**stage 非 0 就中止**，不接着 build。
- [`scripts/check-signing-profile.py`](scripts/check-signing-profile.py)：**装包前必跑**，
  核对 Profile 的 bundleName 与受限权限 ACL（不匹配会 9568289）。

> ⚠️ AGC 上传用 `.app`，设备安装用调试签名的 `.hap`。**发布签名的包装不到任何设备上**：
> 设备侧对 release profile 一律返回 `9568322 signature verification failed due to not
> trusted app source`，只能经应用市场 / AGC 测试渠道分发。所以本机自测一律用默认构建的
> 调试包（[`scripts/install-gui-hap.sh`](scripts/install-gui-hap.sh)），发布包只做离线验签 + 上架。
> 详见 [上架与发布](docs/appgallery-release.md) 第 4 节 Step 4。

发布签名与上架的完整步骤（AGC 申请发布证书/发布 Profile、受限权限申请、两个 product
如何绑签名、APP 备案口径）见 [上架与发布](docs/appgallery-release.md) 第 4 节与第 7.5 节。

## 最终 GUI 路线

当前 Qt 5.12.12 + OpenCASCADE 7.8.1 组合服务于 headless 兼容验证；Qt6 仍是完整 GUI 的目标依赖线。FreeCAD v1.1.2 完整 GUI 采用以下目标依赖线：

- Qt 6.8（Widgets、OpenGL、Svg、UiTools、LinguistTools 和 HarmonyOS QPA）
- pybind11 2.13.6 headers（CAM/flat-mesh 的构建依赖，由 `scripts/prepare-pybind11-ohos.sh` 准备）
- OpenCASCADE 7.8
- Coin3D、Pivy
- Shiboken/PySide
- CPython 3.11

GUI 完成标准包括主窗口与工作台、3D 场景渲染、相机交互、拾取与选择高亮、对话框、文件访问，以及真机 HAP 内的完整功能验收。

## FlexiMind 消费模式

| 模式 | 形态 | 说明 |
|---|---|---|
| 参数化夹指 | headless FreeCAD 脚本 | 需要 Part、Mesh、Import、Sketcher、PartDesign 等模块 |
| Web 工作台 | WebAssembly runtime | 与本原生移植相互独立 |
| 本地设计包 | 完整原生 FreeCAD GUI | 交付包通过 `-M` 和专用 startup 脚本临时加载包内工作台 |

`FlexiMindGripDesign` 是 FlexiMind 设计交付包的一部分，不安装到普通 FreeCAD 的 `Mod/`。FlexiMind launcher 将包内 `workbench/` 临时加入模块路径，再执行随包 startup 脚本完成注册和激活；普通 FreeCAD 启动不感知该工作台。

## 环境约束

- 目标系统：HarmonyOS PC，`arm64-v8a`
- OHOS SDK：26.0.0.18
- Python：3.11.4 OHOS runtime
- 未签名 ELF 不能直接在设备 shell 中执行，端侧验收必须进入签名 HAP
- HAP 沙箱中的 `Mod/`、用户文件授权、loopback 接口和应用生命周期仍需随 GUI 集成验证

## 许可

本仓库是对 [FreeCAD](https://www.freecad.org/) 1.1.2 的移植工程，包含对其源码的补丁、移植脚本
与配套文档。这些衍生部分按上游同样的 **GNU 宽通用公共许可证第 2.1 版（LGPL-2.1）** 分发，
许可全文见 [`LICENSE`](LICENSE)；分发修改过的 LGPL 组件时，**对应源码由此仓库公开提供**，
以此履行 LGPL-2.1 的源码提供义务。

随包分发的其他开源组件（Qt 6、Open CASCADE Technology、Coin3D、Python、OpenSSL、NumPy、
PyYAML 等）各自遵循其原始许可，相应许可文本随应用提供。

本工程是**非官方社区移植版本**，与 FreeCAD 官方项目及其名称持有人不存在隶属、赞助或授权关系；
应用隐私政策见 [`PRIVACY.md`](PRIVACY.md)。
