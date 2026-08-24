#!/bin/sh
# 一键重新配置并编译 FreeCAD 核心 GUI 工作台模块。
# MeshPart/BIM 依赖 Salome SMESH + MEDFile/HDF5，默认不启用；补齐依赖后
# 可通过 FREECAD_BUILD_MESH_PART=ON FREECAD_BUILD_BIM=ON 显式开启。
# Addon Manager 和 Start 默认启用，脚本会准备其发布源码中的 git 子模块。
set -e

PROJECT_DIR=/storage/Users/currentUser/github/freecad-on-harmonyos
CPP_LIB_ROOT=/storage/Users/currentUser/CPPLib
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"
BUILD="${FREECAD_GUI_BUILD:-$CPP_LIB_ROOT/build/freecad/1.1.2/ohos-arm64-v8a-gui-qt6-full}"
PREFIX="${FREECAD_GUI_PREFIX:-$CPP_LIB_ROOT/install/freecad/1.1.2/ohos/arm64-v8a-gui-qt6}"
PYBIND11_ROOT="${PYBIND11_ROOT:-$CPP_LIB_ROOT/sources/pybind11/pybind11-2.13.6}"
BUILD_ASSEMBLY="${FREECAD_BUILD_ASSEMBLY:-OFF}"
BUILD_ADDONMGR="${FREECAD_BUILD_ADDONMGR:-ON}"
BUILD_START="${FREECAD_BUILD_START:-ON}"

echo "==> Step 1/5: 准备 pybind11 头文件（CAM/flat-mesh）"
PYBIND11_ROOT="$PYBIND11_ROOT" sh "$PROJECT_DIR/scripts/prepare-pybind11-ohos.sh"

if [ "$BUILD_ASSEMBLY" = ON ]; then
  echo "==> 准备 Assembly 的 OndselSolver（固定 FreeCAD 1.1.2 对应提交）"
  FREECAD_VERSION=1.1.2 sh "$PROJECT_DIR/scripts/prepare-ondsel-solver.sh"
else
  echo "==> Assembly 默认关闭（设置 FREECAD_BUILD_ASSEMBLY=ON 并准备 OndselSolver 可启用）"
fi

if [ "$BUILD_ADDONMGR" = ON ]; then
  echo "==> 准备 GUI Addon Manager（固定 FreeCAD 1.1.2 对应提交）"
  FREECAD_VERSION=1.1.2 sh "$PROJECT_DIR/scripts/prepare-addon-manager.sh"
else
  echo "==> Addon Manager 已关闭（设置 FREECAD_BUILD_ADDONMGR=ON 可启用）"
fi

if [ "$BUILD_START" = ON ]; then
  echo "==> 准备 Start 工作台的 Microsoft.GSL（固定 FreeCAD 1.1.2 对应提交）"
  FREECAD_VERSION=1.1.2 sh "$PROJECT_DIR/scripts/prepare-freecad-gsl.sh"
else
  echo "==> Start 工作台已关闭（设置 FREECAD_BUILD_START=ON 可启用）"
fi

echo "==> Step 2/5: 重新配置 FreeCAD（生成含完整 GUI 模块的 build.ninja）"
FREECAD_GUI_BUILD="$BUILD" FREECAD_GUI_PREFIX="$PREFIX" \
  PYBIND11_ROOT="$PYBIND11_ROOT" \
  FREECAD_BUILD_ASSEMBLY="$BUILD_ASSEMBLY" \
  FREECAD_BUILD_ADDONMGR="$BUILD_ADDONMGR" \
  FREECAD_BUILD_START="$BUILD_START" \
  sh "$PROJECT_DIR/scripts/configure-freecad-gui-qt6-ohos.sh"
echo "==> configure 完成"

echo "==> Step 3/5: 编译 FreeCAD（耗时较长）"
FREECAD_GUI_BUILD="$BUILD" sh "$PROJECT_DIR/scripts/build-freecad-gui-qt6-ohos.sh"
echo "==> build 完成"

echo "==> Step 4/5: 安装到 prefix"
[ -f "$BUILD/bin/FreeCAD" ] || {
  echo "FreeCAD GUI executable was not produced; refusing to install a partial build." >&2
  exit 1
}
"$CMAKE_BIN" --install "$BUILD"
echo "==> install 完成"

echo "==> Step 5/5: 打包到 HAP"
FREECAD_PREFIX="$PREFIX" FREECAD_BUILD_ADDONMGR="$BUILD_ADDONMGR" FREECAD_BUILD_START="$BUILD_START" \
  sh "$PROJECT_DIR/scripts/stage-gui-hap.sh"
echo "==> stage 完成"

echo ""
echo "==> 全部完成！已构建的工作台模块："
ls "$BUILD/Mod/" 2>/dev/null
