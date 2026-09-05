# FreeCAD v1.1.2 HarmonyOS 移植执行计划

更新时间：2026-09-05

## 目标基线

- 目标设备：HarmonyOS PC，`arm64-v8a`。
- 唯一上游基线：FreeCAD v1.1.2。
- 最终交付：完整原生 FreeCAD GUI HAP，不重写为 ArkUI CAD 界面。
- GUI 目标依赖：Qt 6.8、OpenCASCADE 7.8、Coin3D、Pivy、Shiboken/PySide 和 CPython 3.11。
- 当前 Qt 5.12.12 + OpenCASCADE 7.8.1 用于 headless 兼容门禁；Qt6 仍是最终 GUI 基线。
- 旧 FreeCAD 0.21.2 产物仅保留为历史记录，不继续维护或验收。

## 当前进度

- FreeCAD v1.1.2 官方源码已固定并接入可重复补丁流程。
- v1.1.2 headless 已完成交叉编译、安装和 ELF 审计。安装前缀为 `CPPLib/install/freecad/1.1.2/ohos/arm64-v8a-headless`。
- 已产出 `FreeCADCmd`、`FreeCAD.so`、`libFreeCADBase.so`、`libFreeCADApp.so`、`Part.so`、`Mesh.so`、`Import.so`、`Materials.so`、`Sketcher.so` 和 `_PartDesign.so`。
- CPython 3.11.4 runtime 的 staged probe 已通过 `_socket`、`ctypes`、`binascii`、`zlib` 和标准库功能检查。
- GUI HAP runtime 已 staging 155 个 AArch64 ELF（最终 HAP 229 个 `.so*`）；AArch64、相对 RUNPATH 和递归 `DT_NEEDED` 审计通过。
- Python 验收强制检查 `App.Version()[:3] == (1, 1, 2)`，并导入 FreeCAD、Part、Mesh、Import、Materials、Sketcher 和 PartDesign。
- OpenCASCADE 7.8.1 已完成 OHOS `arm64-v8a` 构建、安装、ELF 审计，并已切换 FreeCAD v1.1.2 headless 与 native HAP entry 的链接配置。
- 完整原生 GUI 已完成构建、安装、staging 和签名 HAP 校验；真机主窗口、New Document、Part/Cube、Cube ViewFit 动画、复杂多色示例、Preferences、Recovery、子元素选择高亮和单 Ability 无框官方 splash 已通过。当前主要缺口是长时间 3D 交互、文件对话框与更多工作台回归。

## 执行阶段

### M0：冻结 v1.1.2 headless 基线

产物：

- 固定校验值的 v1.1.2 源码归档。
- `patches/freecad-1.1.2/` 可重复补丁集。
- 固定版本的 Python、Boost、Eigen、fmt、yaml-cpp、Xerces-C 和 OCCT 输入。
- FreeCAD headless 构建、安装、ELF 审计和 staging 脚本。

状态：已完成。

### M1：签名 HAP headless 功能门禁

HAP 内必须完成：

1. OCCT Box/Cut、体积检查、STEP 写出和读回。
2. FreeCAD v1.1.2 版本断言及核心模块导入。
3. Part Box、Cylinder 和 Boolean。
4. FCStd 保存、关闭、重开和几何断言。
5. STEP、STL 导出与读回。

这一步只证明 native loader、Python 嵌入、CAD 核心和应用沙箱可用，不代表 GUI 完成。

### M2：Qt 6.8 / OCCT 7.8 基线

- 为 HarmonyOS 构建 Qt 6.8 Core、Gui、Widgets、OpenGL、Svg、UiTools 和 LinguistTools。
- 移植或更新 QPA 平台插件，验证 EGL surface、输入、窗口生命周期、对话框和文件选择。
- [x] 构建 OpenCASCADE 7.8.1 并通过 OHOS ELF 审计；OCCT smoke probe 已验证 Box/Cut 与 STEP 接口。
- [x] 将 FreeCAD v1.1.2 headless 与 HAP native entry 从 OCCT 7.6 线切换到 7.8.1，并完成本地重新编译和审计。
- [x] 构建 Qt 6.8、更新 QPA，并生成签名 GUI HAP；主窗口、基础 3D 与 Preferences 真机通过。

### M3：FreeCAD GUI 与 3D 场景

- [x] 构建 Coin3D、Pivy、Shiboken/PySide。
- [x] 启用 FreeCADGui、SketcherGui、PartDesignGui 等 GUI 模块。
- [x] 真机验证主窗口、菜单、工具栏、New Document、Part/Cube、复杂多色示例和 Preferences。
- [x] 验证 OpenGL 到 HarmonyOS EGL/GLES/gl4es 的基础实体显示路径。
- [x] 真机验证面子元素的 hover 与 click 选择高亮。
- [x] 真机验证 Cube `ViewFit` 动画逐帧裁剪面同步。
- 真机压力验证相机交互、边/点拾取和大模型稳定性。

### M4：完整 GUI HAP

- [x] 将 Qt 平台插件、FreeCAD GUI、Python runtime、Coin/Pivy/PySide 和工作台资源纳入 HAP。
- 处理应用沙箱中的用户配置、`Mod/`、字体、翻译、插件和文档目录。
- 验证文件选择器、文档导入导出、崩溃日志、前后台切换及窗口恢复。
- 不假设其他应用可以直接执行 HAP 内的 `FreeCADCmd`；headless 能力通过明确的受控接口暴露。

### M5：FlexiMind 与产品验收

- 安装并激活 `FlexiMindGripDesign` 工作台。
- 验证 `Init.py`、`InitGui.py`、多视角渲染、完整设计流程和 FCStd 文件交换。
- 按业务脚本实际调用决定是否启用 MeshPart/SMESH 及 VTK、MEDFile、HDF5 链。
- 对每个受支持工作流保存输入、操作、输出、日志和可复跑步骤。

## 完成定义

只有以下条件全部满足才称为“FreeCAD v1.1.2 移植完成”：

- FreeCAD v1.1.2 完整原生 GUI 在 HarmonyOS PC 签名 HAP 内启动。
- 核心工作台、3D 渲染和交互、Python GUI API、文件 I/O 均通过真机验收。
- FlexiMind 工作台能够注入、激活并完成目标设计流程。
- staged 目录与最终 HAP 的所有 native ELF 均通过架构、RUNPATH 和递归依赖审计。

单独通过编译、链接、打包、ArkUI 启动页或 headless 测试，均不满足完成定义。
