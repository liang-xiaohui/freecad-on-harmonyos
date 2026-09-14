# FEM：HarmonyOS 构建与验收

更新日期：2026-09-09。

## 范围

GUI Qt6 构建默认启用 `FREECAD_BUILD_FEM=ON`，使用 FreeCAD 1.1.2 自带的
Salome SMESH 7.7.1。`Fem.so`、`FemGui.so`、FEM Python 包及其原生依赖必须一起
安装和打包。仅复制 `FEMExample.FCStd` 或 Python 包不能恢复 FEM 对象。

本次接入不默认启用 MeshPart，也不提供 Gmsh、CalculiX、Elmer 或 Netgen
可执行程序。BIM（Arch）已于 2026-09-14 单独接入——它是纯 Python，不经过
CMake 的 `BUILD_BIM` 开关，见 `docs/bim-ohos.md`。已有模型、网格及计算结果
的恢复，与重新生成网格、运行外部求解器是不同的验收项；不能把前者通过写成
完整求解流程已经通过。

## 固定依赖

| 组件 | 版本 | 安装位置（`CPP_LIB_ROOT` 下） |
| --- | --- | --- |
| HDF5 | 1.14.6，serial，zlib，C API | `install/hdf5/1.14.6/ohos/arm64-v8a` |
| MEDFile | 6.0.1，C/C++，无 Fortran/MPI/Python 包装 | `install/medfile/6.0.1/ohos/arm64-v8a` |
| SMESH | 7.7.1，FreeCAD 内置修改版 | 随 FreeCAD 安装到 GUI prefix 的 `lib` |

HDF5 使用 HDFGroup 发布源码；MEDFile 使用 `chennes/med` 的 `v6.0.1` 固定标签
源码。两个下载归档的 SHA-256 固定在构建脚本中，下载后必须验证；临时下载与日志
放入 `/storage/Users/currentUser/codex-freecad-artifacts`。

MEDFile 6.0.1 的 CMake 检查要求 HDF5 1.14.x，不能把 MEDFile 4.1.1 对
HDF5 1.10.x 的检查直接删除后当作兼容。HDF5/MEDFile 构建脚本保留动态库，
staging 按 ELF `NEEDED` 递归收集 `libmedC.so.14`、`libhdf5.so.310` 等依赖。

## 构建

在具备 OHOS SDK 的主机终端执行：

```sh
ARTIFACTS=/storage/Users/currentUser/codex-freecad-artifacts/fem-port-20260906
mkdir -p "$ARTIFACTS"
export TMPDIR="$ARTIFACTS"

sh scripts/build-hdf5-ohos.sh > "$ARTIFACTS/hdf5-build.log" 2>&1
sh scripts/build-medfile-ohos.sh > "$ARTIFACTS/medfile-build.log" 2>&1
sh scripts/configure-freecad-gui-qt6-ohos.sh > "$ARTIFACTS/freecad-configure.log" 2>&1
sh scripts/build-freecad-gui-qt6-ohos.sh > "$ARTIFACTS/freecad-build.log" 2>&1
cmake --install /storage/Users/currentUser/CPPLib/build/freecad/1.1.2/ohos-arm64-v8a-gui-qt6-full \
  > "$ARTIFACTS/freecad-install.log" 2>&1
sh scripts/stage-gui-hap.sh > "$ARTIFACTS/stage.log" 2>&1
sh scripts/build-gui-hap-ohos.sh > "$ARTIFACTS/hap-build.log" 2>&1
sh scripts/verify-gui-hap.sh > "$ARTIFACTS/hap-verify.log" 2>&1
```

`rebuild-freecad-all-workbenches.sh` 也会在 FEM 或 MeshPart 启用时准备这两个
依赖，然后配置、构建、安装并 stage。设置 `FREECAD_BUILD_FEM=OFF` 可恢复裁剪
构建；configure、stage、verify 各阶段必须使用相同开关。

## 验收

staging 和 HAP 验证脚本均检查 `Fem.so`、`FemGui.so`、`Mod/Fem/InitGui.py`、
`ObjectsFem.py` 及截图报错的两个材料代理脚本，防止再次出现“示例存在但模块缺失”。

OHOS PC 可直接对 staging 自签名后运行原生验收，不需要更改设备上的文档：

```sh
sh scripts/sign-staged-native-ohos.sh
FREECAD_PROBE_FEM=ON \
FREECAD_PROBE_OUTPUT_DIR=/storage/Users/currentUser/codex-freecad-artifacts/fem-port-20260906/acceptance \
  sh scripts/run-staged-freecad-acceptance.sh
```

FEM 开关在原有六项 FreeCAD/OCCT 检查之外增加：

- 导入 `Fem`、`ObjectsFem` 与材料代理；构造四面体，验证 UNV/MED 网格写入和读取。
- 对照示例 `Document.xml` 核对完整对象名、类型、Python 代理、网格节点及结果数组。

这两项是无界面的数据验收；`FemGui` 的交互、网格着色、结果变形显示及工作台切换
仍需要 GUI/真机单独验收。测试不会覆盖保存内置示例。

GL4ES/Coin 的诊断源码与 FEM 接入独立；诊断文件仍保留在 CPPLib 及 artifact 备份中，
但本次回归基线明确关闭 GL4ES 诊断宏，未将诊断读回或日志路径打进生产 HAP。

## 2026-09-06 本机验收记录

- HDF5/MEDFile、FreeCAD 内置 SMESH、`Fem.so` 和 `FemGui.so` 编译安装成功。
- staging 的 AArch64/RUNPATH/递归依赖审计通过，共 226 个 ELF；包含
  `libmedC.so.14`、`libhdf5.so.310` 和 SDK `libomp.so`。
- 原有六项检查及两项 FEM 检查全部通过。FEM 示例恢复 43 个对象、17 个 FEM
  Python 代理、6 份网格（合计 1,956 个节点）和 3 组结果；日志未出现
  `No module named 'Fem'`、`Cannot create object` 或 `blocked import`。
- 四面体的 UNV 与 MED 往返均保持 4 个节点、1 个体单元及节点坐标。
- 结果文件为
  `/storage/Users/currentUser/codex-freecad-artifacts/fem-port-20260906/acceptance-packaged/freecad-acceptance.json`。
- 签名 HAP 已通过完整内容/新鲜度校验，包含 243 个 `.so*`。独立 offscreen GUI
  探针在执行 FEM 宏之前于系统加载器收到 SIGSEGV；没有据此宣称 GUI 验收通过，
  此后已通过 HDC 安装并启动 `QAbility`，用户确认 FEM 模型基本加载；结果着色、
  变形和编辑等完整真机回归仍待进行。用户截图中的 PartDesign `WizardShaft.svg`
  警告已定位为 `AppHomePath` 拼接缺少 `/`，图标文件本身已打包，尚未修复。
- 这些结果不等于真机 GUI 渲染/交互或外部求解器已经通过；签名 HAP 信息及真机
  回归状态见 `docs/handoff-device-steps.md`。

## WarpVector/Axis Cross 显示问题（仍未闭环）

用户反馈：显示 FEM 示例的 `WarpVector` 时出现大块黑色多边形，隐藏它后黑块和
彩色模型一起消失。`ViewProviderFemPostObject::hide()` 同时隐藏结果几何和前景
色标，因此这个操作只能把问题缩小到结果显示相关路径，不能单独证明网格损坏，
也不能单独证明是色标问题。它不是保留模型的解决办法。

已对当前 staging 对应的示例做隔离数据检查，不打开或保存用户正在编辑的文档：

- 三个 WarpVector 分别含 569/408/200 个点和 242/70/16 个单元。
- 每个对象分别导出恢复数据、Factor=0 的重算数据、恢复原 Factor=10 的重算数据；
  九份 VTK 数据的坐标和节点结果均为有限数值，连接索引均在节点范围内，单元
  offsets 严格递增且末值与连接数组长度一致。
- 主 WarpVector 零倍率边界为 `[0,8000] × [0,1000] × [0,1000]` mm；倍率 10
  的恢复和重算边界一致，没有发现异常放大的输入坐标。
- 此检查不覆盖 `vtkGeometryFilter` 的表面输出、Coin 场景状态或 GL4ES/GPU 绘制，
  不能作为黑块已修复或渲染驱动已确定有误的证据。

诊断脚本、九份导出、JSON 和用户截图保存在
`/storage/Users/currentUser/codex-freecad-artifacts/fem-warp-render-20260906/`。
默认值回退构建记录、设备安装记录和新 HAP 校验记录保存在
`/storage/Users/currentUser/codex-freecad-artifacts/fem-warp-render-20260906/axis-default-off/`。

用户已完成线框对照：模型变为彩色线框，黑块仍然实心。用户进一步观察到黑块像
“气泡式引线框”，连接原点坐标系，旋转视角时会从不同 XYZ 轴延伸。该现象使
坐标轴标签及其与色标共享的 GL 状态成为优先排查对象，但目前仍不能把它当作
已修复的渲染驱动问题。

原点坐标系由 `View3DInventorViewer::setAxisCross()` 创建的
`SoFCPlacementIndicatorKit` 绘制；XYZ 标签是 `SoFrameLabel`（继承 `SoImage`），
并明确设置 `frame=false`、`border=false`，正常不应有气泡背景框。不要与
右下角角落坐标系的 `drawAxisCross()` 路径混淆。

真机曾完成可逆对照：关闭原点坐标系后黑块消失，`WarpVector` 模型仍然显示；但
后续切换轴交叉时又出现过黑块、标签或箭头缺失，现象并不稳定。因此只能确认
Axis Cross 叠加路径与问题相关，不能宣称 FEM 结果或 GL4ES 根因已经解决。为避免
新文档启动即触发该问题，已撤回 OHOS 下把 `ShowAxisCross` 默认改为开启的补丁；
用户仍可手动执行 `Gui.ActiveDocument.ActiveView.setAxisCross(True)` 做对照，当前
不把这项操作列为 FEM 通过条件。

## Axis Cross 标签绘制实验记录（2026-09-08）

调试截图显示，替换 XYZ 标签或移除箭头都会改变黑色形状，但不能作为修复；
完整 Axis Cross 必须保留。`patches/gl4es-81547d9/ohos-raster-unbind-single-buffer.patch`
曾作为单变量实验加入，用来清理 client-array blit 前残留的数组/索引缓冲区；它已
完成编译和 HAP 静态验证，但尚未通过当前设备上的 FEMExample 复验，也不能解释
之后出现的标签/箭头消失。该补丁和 Axis Cross ASCII 标签补丁暂不应被描述为已
解决黑块。

## 2026-09-09 性能/材质回滚基线

最近一次回归排查发现，CPPLib 外部源码里残留了若干未验证实验：每次 FPE draw
执行 `glFinish()`、禁用 GL4ES batching/VBO、QPA 换帧前同步，以及 FEM 颜色/透明度
状态改写。这些路径会把复杂 BIM 的渲染串行化，并可能覆盖原有材质行为；已在
`/storage/Users/currentUser/codex-freecad-artifacts/regression-before-rollback-20260909/`
保存回滚前副本后全部撤回。当前 GL4ES 恢复为批处理/VBO 默认路径，普通 draw 仅按
正式补丁每 4 次 `glFlush()`；BGRA 客户端颜色数组先转换并上传到临时 GLES VBO，
释放 scratch 不再逐绘制调用 `glFinish()`。Coin 的材质诊断循环也已移除，诊断宏关闭。
FreeCAD FEM 颜色渐变和 `ViewProviderFemPostObject` 也已恢复到实验前的材质/透明度
路径。新的候选 HAP 已重新编译、staging、签名和静态验证，SHA-256 为
`83a0bd9aa38dd965b8f70343368f7d26ec2477b5e854e66f48b1183d210d744a`；设备在线后仍
需要用户用 BIMExample 对照帧时间、材质和透明度，不能把本机 HAP 验证当作真机
性能结论。对应的 Coin 清理记录为 `patches/coin-4.0.0/ohos-remove-material-diagnostics.patch`，
GL4ES VBO 记录为 `patches/gl4es-81547d9/ohos-fpe-client-array-vbo.patch`。
