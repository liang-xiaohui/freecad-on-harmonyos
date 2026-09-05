# FreeCAD v1.1.2 依赖矩阵

更新时间：2026-09-05

| 依赖 | 当前/目标版本 | 当前状态 | 下一动作 |
|---|---:|---|---|
| OHOS SDK/CMake/Ninja/Clang | SDK 26.0.0.18 | headless 构建就绪 | 保持工具链入口可复跑 |
| FreeCAD | 1.1.2 | **GUI（Qt6 线）编译、链接、安装完成**：全量默认工作台；真机主窗口、New Document、Part/Cube、复杂多色示例和 Preferences 通过 | 长时间 3D 交互、文件对话框与更多工作台回归 |
| Qt | GUI 目标 6.8.3 | qtbase、qtsvg、qttools/UiTools 和 OHOS QPA 均已构建安装；原生 QUiLoader 已用于 Preferences，QPA 已抑制 detached cursor 告警洪泛 | 输入、窗口与前后台生命周期回归 |
| OpenCASCADE | 7.8.1（GUI 目标 7.8） | OHOS `arm64-v8a` 全量构建、安装、48 个共享库 ELF 审计通过；FreeCAD headless 和 OCCT smoke 已切换并链接 7.8.1 | 在最新签名 HAP 内完成端侧验收 |
| Python | 3.11.4 | `_socket`/`binascii`/`zlib`/`_ctypes` 与 staged probe 通过 | 在签名进程复验，供 PySide/Pivy 使用 |
| libffi | 3.4.2 | 构建、安装和 ctypes callback probe 通过 | 随 HAP staging |
| Boost | 1.86.0 | FreeCAD 所需组件已安装 | 复用并随依赖闭包审计 |
| Eigen | 3.4.1 | Part/Sketcher headless 已使用 | 复用 |
| fmt | 9.1.0 | 固定本地源并被 FreeCAD 使用 | 保持离线可复跑 |
| yaml-cpp | 0.8.0 | OHOS 构建脚本与固定校验已加入 | 随 Material 模块审计 |
| Xerces-C | 3.2.4 | 已构建并被 Import 使用 | 随 HAP staging |
| Zlib | SDK 1.3.1 | FreeCAD/Python 已链接和验证 | 复用系统库 |
| PyCXX | FreeCAD bundled | v1.1.2 bindings 已使用 | 复用 |
| SWIG | 4.2.1 | **已在本机构建**（`CPPLib/scripts/build-swig-ohos.sh`，--without-pcre，含沙箱 umask 补丁） | 供 PySide 构建复用 |
| Pivy | master（0.6.x 线） | **已构建并本地验证**：`from pivy import coin`、场景图/属性/类型系统正常（`CPPLib/scripts/build-pivy-ohos.sh`；运行时需 gl4es libGL 先加载） | 随后续 GUI 里程碑 staged 进 HAP 并启用 FREECAD_CHECK_PIVY |
| Coin3D | 4.0.0（Qt6 目标线） | 已构建、安装（含 `patches/coin-4.0.0/ohos.patch`）；当前为 Qt5.12 链接版本 | Qt6 qtbase 就绪后按 Qt6 重新构建/验证 |
| Pivy | 与 Coin/Python 匹配 | 已构建并验证 Python 场景图 API，GUI runtime 已 staged | 随真机 GUI 工作台验收继续回归 |
| Shiboken6 | 6.8.3 | **已构建并验证**：生成器（v6.8.3）+ libshiboken6 + `shiboken6` python 模块导入成功（`CPPLib/scripts/build-shiboken6-ohos.sh`；含 ClangConfig 补丁、OHOS musl 全局作用域修复——显式链接 libpython） | 用于 PySide6 绑定生成 |
| PySide6 | 6.8.3 | **Core/Gui/Widgets/Network/Svg/SvgWidgets/OpenGL/OpenGLWidgets 绑定全部构建并验证**（v6.8.3：QWidget/QPushButton/QLabel/QColor/QImage 正常，`QNetworkAccessManager` 可导入）。关键修复：绑定模块显式链接 libpython（musl 全局作用域）；libshiboken 纯文件名 NEEDED；无 SSL 的 QtNetwork 构建会同步排除 `QSslEllipticCurve` wrapper；`build-pyside6-ohos.sh`。FreeCAD full 构建已启用 `FREECAD_USE_PYSIDE` / `FREECAD_USE_SHIBOKEN`，并编译 `Base::Quantity` converter；Addon Manager 需要 QtNetwork | 供 FreeCAD Python GUI API和 C++ Qt 信号类型转换 |
| gl4es | 81547d9 | FreeCAD 1.1.2 真机 3D 已验证；外部 EGL context 映射并在 Qt/Coin 交接时失效 program/VBO/EBO/vertex-attrib 缓存 | 长时间相机/选择压力回归 |
| SMESH/VTK/MED/HDF5 | 待业务确认 | 延后，不阻塞首个 GUI | 按 MeshPart 实际需求启用 |
| Headless 验收 HAP | v1.1.2 runtime | GUI HAP 内同一 Qt6 runtime 本地 6/6 验收通过；headless 真机复跑仍独立记录 | DevEco Run EntryAbility 真机复跑 6 项验收 |
| Qt6 OHOS QPA | 移植自 tqtc Qt5.12 `qohos` 插件 | **已在真机呈现 FreeCAD 主窗口和 3D**；通过 `eglGetProcAddress` 与 gl4es external-context API 完成状态交接；启动阶段复用 ArkUI 主窗宿主页、延迟 Qt 几何，并把孤立 `QLabelClassWindow` 保留在现有 Ability | 输入、窗口和多 context 压力回归 |
| 完整 GUI HAP | v1.1.2 | 2026-09-05 包含 229 个 `.so*`，离线 6/6、主窗口、基础 3D、Preferences 和无框官方 splash 冷启动均通过 | 扩大交互与工作台覆盖 |

## 构建顺序

1. 完成 v1.1.2 headless 签名 HAP 的版本、几何、FCStd、STEP 和 STL 门禁。
2. 构建 Qt 6.8；OpenCASCADE 7.8.1 已完成并已复跑本地 headless/OCCT 构建门禁。
3. 构建 Coin3D、Pivy、Shiboken/PySide 和 FreeCAD GUI 模块。
4. 集成完整 GUI HAP并完成真机交互验收。
5. 注入 FlexiMind 工作台，再按实际需求扩展 MeshPart/SMESH。
