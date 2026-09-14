# BIM：HarmonyOS 安装与验收

更新日期：2026-09-14。

## 范围

GUI Qt6 构建默认启用 `FREECAD_BUILD_BIM=ON`。BIM（Arch）工作台是**纯
Python**，没有任何 `.so`，因此不参与 CMake 的 C++ 构建，而是在
`cmake --install` 之后由 `scripts/install-bim-module-ohos.sh` 按
`src/Mod/BIM/CMakeLists.txt` 的 Install Manifest 镜像写入安装前缀。

不装它的后果不是"少一个工作台"，而是打开 BIM 文档时静默降级：

```
PropertyPythonObject::Restore: blocked import of module 'ArchWall' during
document restore. Only modules from FreeCAD or installed addons are permitted.
```

每个 `Arch*` 模块各报一次（`ArchAxis` ×8、`ArchBuildingPart` ×5、
`ArchCurtainWall` ×3、`ArchStairs` ×3、`ArchWall` ×2、`ArchStructure` ×2×3 …），
Message 面板被刷屏。机制见 `App/PropertyPythonObject.cpp` 的
`isAllowedModule()`：模块不在 `sys.modules` 时用 `importlib.util.find_spec()`
取 `origin`，再与 `FreeCAD.__ModDirs__` / `__MacroDirs__`（由
`App/FreeCADInit.py` 设置）做路径前缀比对；模块根本不存在时 `spec is None`，
直接返回 false 并抛 `Py::ImportError`。结果是每个 Arch 对象丢掉 Proxy、
`execute()` 不再运行，文档退化成存盘几何的只读副本。

## 为什么不走 `-DBUILD_BIM=ON`

`cMake/FreeCAD_Helpers/CheckInterModuleDependencies.cmake` 声明：

```cmake
REQUIRES_MODS(BUILD_BIM BUILD_PART BUILD_MESH BUILD_MESH_PART BUILD_DRAFT)
```

于是 CMake 直接报 `BUILD_BIM requires BUILD_MESH_PART to be ON`。但 MeshPart
对 BIM 只是**惰性依赖**——只有两处：`ArchCommands.py:554` 的 Mesh→Wire 辅助
函数，以及 `importers/importDAE.py`、`importers/importOBJ.py`、
`importSH3DHelper.py`（经 `FreeCAD.addImportType` 按需加载）。文档恢复路径
（`ArchComponent` / `ArchWall` / `ArchStructure` / `ArchSite` / `ArchAxis` /
`ArchBuildingPart` …）完全不 import 它。

`configure-freecad-gui-qt6-ohos.sh` 因此显式传 `-DBUILD_BIM=OFF`，
`FREECAD_BUILD_BIM` 改为控制安装脚本这一步。

## `Arch_rc.py` 的来源

`CMakeLists.txt` 用 `PYSIDE_WRAP_RC(Arch_QRC_SRCS Resources/Arch.qrc)` 生成
`Arch_rc.py`。**不需要 PySide 的 `pyside6-rcc`**：Qt 自带的 `rcc` 就支持
`--generator=python`，`Draft_rc.py` 同样是这么产出的，而且它是 target 二进制、
本机可直接执行：

```sh
$CPP_LIB_ROOT/install/qt/6.8.3/ohos/arm64-v8a/libexec/rcc \
  --generator=python --compress-algo=zlib --compress=1 \
  <BIM 源码>/Resources/Arch.qrc -o <prefix>/Mod/BIM/Arch_rc.py
```

该文件约 37.9 MB（未压缩），是 HAP 体积增长的主要来源。

## 安装清单

| 目标 | 内容 |
| --- | --- |
| `Mod/BIM/` | 顶层全部 `.py` + 生成的 `Arch_rc.py` |
| `Mod/BIM/Dice3DS/`、`importers/`（含 `samples/`）、`bimcommands/`、`bimtests/`（含 `fixtures/`）、`nativeifc/` | 相应 `.py` 与 `*.brep` / `*.FCStd` / `*.sh3d` 数据文件，保留相对路径 |
| `share/Mod/BIM/Presets/` | `profiles.csv`、`pset_definitions.csv`、`qto_definitions.csv`、`ifc_*_{IFC2X3,IFC4}.json` |
| `share/Mod/BIM/Resources/` | 整体复制（Manifest 只列 `icons/BIMWorkbench.svg` 与 `templates/webgl_export_template.html`；上游 `InitGui.py` 与 `bimcommands/BimLibrary.py` 用 `__file__` 相对路径找图标，只按 Manifest 会漏） |

`stage-gui-hap.sh` 在 `FREECAD_BUILD_BIM=ON` 时对上述关键文件做存在性校验，
缺失即中止打包，避免再产出"看起来正常、实际降级"的 HAP。

## 验收

`scripts/stage-gui-hap.sh` 会把整个 `Mod/` 打进 `freecad-runtime.zip`，
`entry/src/main/cpp/acceptance.cpp` 用内容指纹（`runtimeMarkerMatches` +
`runtimeArchiveIdentity`）判断是否需要重新解压，所以换包后 BIM 会自动落到
设备上 `freecad-home/Mod/BIM/`。

判定通过必须同时满足：

1. hilog 中 `blocked import` 计数为 **0**（修复前是几十条）；
2. 3D 视口里 BIM 建筑完整显示，入口红色弧形墙渲染为**实心色、无灰红交织条带**；
3. 启动参数用 `--ps fcstdPath <应用 home>/share/examples/BIMExample.FCStd`，
   应用 home 的权威路径是
   `/data/storage/el2/base/haps/entry/files/freecad-home/`。

## 已知遗留

- MeshPart 仍是 `OFF`（`FREECAD_BUILD_MESH_PART`）。依赖它的少数 BIM 导入器
  （DAE/OBJ/SH3D）与 `ArchCommands` 的 Mesh→Wire 辅助在使用时会报错，其余
  功能不受影响。
- `bimcommands/BimLibrary.py` 用 `os.path.dirname(__file__)/icons/` 找图标，
  上游 Manifest 本身不提供该目录，属于上游既有问题。
