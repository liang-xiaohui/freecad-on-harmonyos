# Headless HAP 验收

更新时间：2026-08-20

这个 HAP 只验证 FreeCAD v1.1.2 的 headless 闭环，不包含 FreeCAD GUI，也不代表完整移植完成。ArkUI 页面调用 NAPI 异步任务；NAPI 先直接运行 OCCT smoke，再初始化 staged CPython 并执行 FreeCAD Python 验收脚本。

## 本地准备

```sh
./scripts/build-python-runtime-ohos.sh
./scripts/build-freecad-headless-ohos.sh
./scripts/build-headless-hap-native-ohos.sh
./scripts/stage-headless-hap.sh
./scripts/run-staged-python-runtime-probe.sh
```

最后一个命令会生成：

- `entry/libs/arm64-v8a/`：FreeCAD、Python 动态扩展、OCCT、Qt Core/Xml、Xerces 及递归非系统依赖。
- `entry/src/main/resources/rawfile/python311.zip`：Python 纯 Python 标准库。
- `entry/src/main/resources/rawfile/freecad-runtime.zip`：FreeCAD `Mod/Ext/share`。
- `entry/src/main/resources/rawfile/freecad_headless_acceptance.py`：端侧验收脚本。

普通文件不能直接放在 `entry/libs`：Hvigor 只收集该目录中的 native `.so`。NAPI 使用 `librawfile.z.so` 将三个 rawfile 复制到应用 `filesDir/runtime`，再将 zip 和 `lib-dynload` 加入嵌入式 Python 的模块路径。

## 签名与构建

在 DevEco Studio 打开仓库根目录，给 `default` product 配置本工程自己的自动签名，然后执行 Sync 和 Build Hap。不要复制 MeshLab 工程的签名配置；profile 与 bundle name 绑定，而且配置文件包含本机私密材料。

本工程只提交 `build-profile.example.json5`。本机由 DevEco/签名流程生成的
`build-profile.json5` 已被忽略；不得提交 `storePassword`、`keyPassword`、证书、
profile 或 keystore 路径。

构建完成后运行：

```sh
./scripts/verify-headless-hap.sh
```

脚本会检查 staged native 文件、三个 rawfile、`libfreecadacceptance.so`、`libc++_shared.so`，以及 FreeCAD v1.1.2 的 `Materials`、`Sketcher`、`PartDesign` 模块是否都进入当前 HAP，并拒绝早于验收源码或 runtime staging 的陈旧 HAP。旧的 `libentry.so` 也会被标记为陈旧产物。

DevEco Studio 中修改 native 包名后请执行一次 `Sync Project`，再执行 `Build > Clean Project` 和 `Build > Build Hap`。旧 HAP 即使重新签名也不会改变其中的 ArkTS/native 模块映射；验收脚本应针对刚生成的 signed HAP 运行。

## 验收项

应用启动后会自动执行，并在页面显示 JSON 结果：

1. 直接 OCCT Box/Cut、体积、STEP 写出和读回。
2. 断言 `App.Version()[:3]` 为 `1.1.2`，并导入 `FreeCAD`、`Part`、`Mesh`、`Import`、`Materials`、`Sketcher`、`PartDesign`。
3. Box、Cylinder、Boolean 和精确体积断言。
4. FCStd 保存、关闭、重新打开和几何体积断言。
5. STEP 写出、读回和非空 shape/volume 断言。
6. STL 导出、读回和点/面片数量断言。

输出文件位于页面 JSON 的 `outputDir`：

```text
freecad-acceptance.json
acceptance.FCStd
acceptance.step
acceptance.stl
occt-smoke.step
```

在 DevEco Terminal 抓取原生错误日志：

```sh
./scripts/watch-headless-hap-log.sh
```
