#!/bin/sh
# 把 BIM（Arch）工作台安装进 FreeCAD GUI 安装前缀。
#
# 为什么不能只用 -DBUILD_BIM=ON：
#   cMake/FreeCAD_Helpers/CheckInterModuleDependencies.cmake 声明
#     REQUIRES_MODS(BUILD_BIM BUILD_PART BUILD_MESH BUILD_MESH_PART BUILD_DRAFT)
#   于是 BUILD_BIM 被拒绝，除非 BUILD_MESH_PART=ON —— 那会连带拖进 C++
#   的 MeshPart 模块（SMESH + VTK + MEDFile）。
#   这个依赖是保守声明：BIM 只在两条惰性路径上碰 MeshPart
#     * ArchCommands.py:554   Mesh->Wire 辅助函数里的 import MeshPart
#     * importers/importDAE.py、importers/importOBJ.py、importSH3DHelper.py
#       （由 FreeCAD.addImportType 按需加载）
#   文档恢复路径（ArchComponent / ArchWall / ArchStructure / ArchSite /
#   ArchAxis / ArchBuildingPart …）完全不 import 它。
#
# 本脚本逐条镜像 src/Mod/BIM/CMakeLists.txt 的 Install Manifest，效果等同于
# `cmake --install`。BIM 是纯 Python，没有任何 .so，所以不经过 C++ 构建。
#
# 不装它会怎样：PropertyPythonObject::Restore 对每个 Arch* 模块报
#   blocked import of module 'ArchWall' / 'ArchStructure' / 'ArchAxis' …
# 每个 Arch 对象丢掉 Proxy，execute() 不再运行，文档静默退化成存盘几何的
# 只读副本，Message 面板被刷屏。
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
QT_VERSION="${QT_VERSION:-6.8.3}"
SRC="${FREECAD_SRC:-$CPP_LIB_ROOT/sources/freecad/$FREECAD_VERSION}/src/Mod/BIM"
PREFIX="${FREECAD_GUI_PREFIX:-$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-gui-qt6}"
RCC="$CPP_LIB_ROOT/install/qt/$QT_VERSION/ohos/$ABI/libexec/rcc"
ARTIFACT_DIR="${ARTIFACT_DIR:-/storage/Users/currentUser/codex-freecad-artifacts}"

[ -d "$SRC" ] || {
    echo "缺少 BIM 源码：$SRC" >&2
    exit 1
}
[ -x "$RCC" ] || {
    echo "缺少 Qt rcc：$RCC（Arch_rc.py 由 rcc --generator=python 生成）" >&2
    exit 1
}

mkdir -p "$ARTIFACT_DIR"

# ---- Mod/BIM：顶层 .py + 生成的 Arch_rc.py -------------------------------
echo "==> Mod/BIM（顶层 .py）"
mkdir -p "$PREFIX/Mod/BIM"
# CMakeLists 的 Arch_SRCS 就是顶层全部 .py，这里用通配等价实现，避免清单漂移。
cp "$SRC"/*.py "$PREFIX/Mod/BIM/"

# Arch_rc.py 是构建期产物（PYSIDE_WRAP_RC -> rcc --generator=python）。
# Qt 自带的 rcc 就能产出 Python 模块，且它是 target 二进制、本机可直接执行。
echo "==> 生成 Mod/BIM/Arch_rc.py（rcc --generator=python）"
"$RCC" --generator=python --compress-algo=zlib --compress=1 \
    "$SRC/Resources/Arch.qrc" -o "$PREFIX/Mod/BIM/Arch_rc.py"

# ---- Mod/BIM 子包 --------------------------------------------------------
# 保留相对路径：importers/samples/Sample.sh3d 与
# bimtests/fixtures/FC_site_simple-102.FCStd 在 Manifest 里位于嵌套目录下。
for sub in Dice3DS importers bimcommands bimtests nativeifc; do
    [ -d "$SRC/$sub" ] || continue
    echo "==> Mod/BIM/$sub"
    find "$SRC/$sub" -type f \
        \( -name '*.py' -o -name '*.brep' -o -name '*.FCStd' -o -name '*.sh3d' \) | \
    while IFS= read -r f; do
        rel="${f#"$SRC"/}"
        mkdir -p "$PREFIX/Mod/BIM/$(dirname "$rel")"
        cp "$f" "$PREFIX/Mod/BIM/$rel"
    done
done

# ---- Presets 与资源 ------------------------------------------------------
# Manifest 只装 Resources/icons/BIMWorkbench.svg 与
# Resources/templates/webgl_export_template.html；这里额外整体复制 Resources/，
# 因为上游自身在 InitGui.py:41 与 bimcommands/BimLibrary.py:677 用
# `__file__` 相对路径找图标，仅按 Manifest 安装会漏。
echo "==> share/Mod/BIM（Presets + Resources）"
mkdir -p "$PREFIX/share/Mod/BIM"
if [ -d "$SRC/Presets" ]; then
    mkdir -p "$PREFIX/share/Mod/BIM/Presets"
    cp "$SRC"/Presets/* "$PREFIX/share/Mod/BIM/Presets/"
fi
mkdir -p "$PREFIX/share/Mod/BIM/Resources"
cp -r "$SRC/Resources/." "$PREFIX/share/Mod/BIM/Resources/"
mkdir -p "$PREFIX/Mod/BIM/Resources"
cp -r "$SRC/Resources/." "$PREFIX/Mod/BIM/Resources/"

# ---- 自检 ----------------------------------------------------------------
echo "==> 结果"
for required in \
    Mod/BIM/Init.py \
    Mod/BIM/InitGui.py \
    Mod/BIM/ArchWall.py \
    Mod/BIM/ArchStructure.py \
    Mod/BIM/ArchComponent.py \
    Mod/BIM/Arch_rc.py \
    share/Mod/BIM/Presets/profiles.csv \
    share/Mod/BIM/Resources/icons/BIMWorkbench.svg; do
    [ -f "$PREFIX/$required" ] || {
        echo "错误：BIM 安装不完整，缺少 $required" >&2
        exit 1
    }
done
echo "Mod/BIM 文件数：$(find "$PREFIX/Mod/BIM" -type f | wc -l)"
ls -la "$PREFIX/Mod/BIM/Arch_rc.py"
