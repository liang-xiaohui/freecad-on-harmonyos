#!/bin/sh
# 配置 FreeCAD v1.1.2 GUI（Qt6 目标线，OHOS arm64-v8a）。
# 前置：
#   - scripts/build-qt6-gui-ohos.sh    （qtbase：Core/Gui/Widgets/OpenGL/PrintSupport/Network/Xml）
#   - scripts/build-qt6-modules-ohos.sh（qtsvg：Svg/SvgWidgets；qttools：UiTools）
#   - Coin 4.0.0（纯 GLES2 核心，无 Qt 依赖，见 install/coin/4.0.0）
#   - OCCT 7.8.1、Boost、Eigen、Xerces-C、yaml-cpp、Python 3.11.4
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
SRC="$CPP_LIB_ROOT/sources/freecad/$FREECAD_VERSION"
# Keep the old three-workbench tree intact; the default is a clean full-GUI tree.
BUILD="${FREECAD_GUI_BUILD:-$CPP_LIB_ROOT/build/freecad/$FREECAD_VERSION/ohos-$ABI-gui-qt6-full}"
PREFIX="${FREECAD_GUI_PREFIX:-$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-gui-qt6}"
QT_PREFIX="${QT_PREFIX:-$CPP_LIB_ROOT/install/qt/6.8.3/ohos/$ABI}"
COIN_PREFIX="${COIN_PREFIX:-$CPP_LIB_ROOT/install/coin/4.0.0/ohos/$ABI}"
BOOST_PREFIX="${BOOST_PREFIX:-$CPP_LIB_ROOT/install/boost/1.86.0/ohos/$ABI}"
EIGEN_PREFIX="${EIGEN_PREFIX:-$CPP_LIB_ROOT/install/eigen/3.4.1/ohos/$ABI}"
XERCES_PREFIX="${XERCES_PREFIX:-$CPP_LIB_ROOT/install/xerces-c/3.2.4/ohos/$ABI}"
OCCT_PREFIX="${OCCT_PREFIX:-$CPP_LIB_ROOT/install/occt/7.8.1/ohos/$ABI}"
YAML_CPP_PREFIX="${YAML_CPP_PREFIX:-$CPP_LIB_ROOT/install/yaml-cpp/0.8.0/ohos/$ABI}"
VTK_PREFIX="${VTK_PREFIX:-$CPP_LIB_ROOT/install/vtk/9.3.1/ohos/$ABI}"
VTK_DIR="${VTK_DIR:-$VTK_PREFIX/lib/cmake/vtk-9.3}"
FMT_SOURCE="${FMT_SOURCE:-$CPP_LIB_ROOT/sources/fmt/9.1.0}"
PYBIND11_ROOT="${PYBIND11_ROOT:-$CPP_LIB_ROOT/sources/pybind11/pybind11-2.13.6}"
PYTHON_ROOT="${PYTHON_ROOT:-$CPP_LIB_ROOT/install/python/3.11.4/ohos/$ABI}"
PYSIDE6_PREFIX="${PYSIDE6_PREFIX:-$CPP_LIB_ROOT/install/pyside6/ohos/$ABI}"
SHIBOKEN6_PREFIX="${SHIBOKEN6_PREFIX:-$CPP_LIB_ROOT/build/shiboken6/inst}"
SWIG_PREFIX="${SWIG_PREFIX:-$CPP_LIB_ROOT/install/swig/4.2.1}"
SWIG_VERSION="${SWIG_VERSION:-4.2.1}"
PIVY_SITE="${PIVY_SITE:-$CPP_LIB_ROOT/install/pivy/ohos/$ABI/site-packages}"
BUILD_MESH_PART="${FREECAD_BUILD_MESH_PART:-OFF}"
BUILD_BIM="${FREECAD_BUILD_BIM:-OFF}"
BUILD_FEM="${FREECAD_BUILD_FEM:-OFF}"
BUILD_ASSEMBLY="${FREECAD_BUILD_ASSEMBLY:-ON}"
BUILD_REVERSEENGINEERING="${FREECAD_BUILD_REVERSEENGINEERING:-ON}"
BUILD_ADDONMGR="${FREECAD_BUILD_ADDONMGR:-ON}"
BUILD_START="${FREECAD_BUILD_START:-ON}"
PYTHON_HOST_BIN="${PYTHON_HOST_BIN:-$NATIVE_SDK/llvm/python3/bin/python3}"
ICU_LIBRARY="$NATIVE_SDK/sysroot/usr/lib/aarch64-linux-ohos/libicu.so"
GL4ES_DIR="${GL4ES_DIR:-$CPP_LIB_ROOT/install/gl4es/81547d9/ohos/$ABI/usr/lib/gl4es}"
GLESV2_LIBRARY="${GLESV2_LIBRARY:-$GL4ES_DIR/libGL.so}"
OPENGL_INCLUDE_DIR="$NATIVE_SDK/sysroot/usr/include"

[ -f "$SRC/CMakeLists.txt" ] || {
    echo "FreeCAD source is missing. Run $PROJECT_DIR/scripts/prepare-freecad-source.sh" >&2
    exit 1
}
[ -d "$QT_PREFIX/lib/cmake/Qt6" ] || {
    echo "Qt6 未安装（$QT_PREFIX）。先运行 scripts/build-qt6-gui-ohos.sh 与 build-qt6-modules-ohos.sh" >&2
    exit 1
}
[ -f "$QT_PREFIX/lib/cmake/Qt6Svg/Qt6SvgConfig.cmake" ] || {
    echo "Qt6Svg 未安装。先运行 scripts/build-qt6-modules-ohos.sh" >&2
    exit 1
}
[ -f "$QT_PREFIX/lib/cmake/Qt6UiTools/Qt6UiToolsConfig.cmake" ] || {
    echo "Qt6UiTools 未安装。先运行 scripts/build-qt6-modules-ohos.sh" >&2
    exit 1
}

QT_PREFIX="$QT_PREFIX" OHOS_SDK="$OHOS_SDK" NATIVE_SDK="$NATIVE_SDK" \
    sh "$PROJECT_DIR/scripts/sign-qt6-host-tools-ohos.sh"
[ -f "$COIN_PREFIX/lib/libCoin.so.4.0.0" ] || {
    echo "Coin3D is missing under $COIN_PREFIX" >&2
    exit 1
}
[ -f "$EIGEN_PREFIX/include/eigen3/signature_of_eigen3_matrix_library" ] || {
    echo "Eigen3 headers are missing under $EIGEN_PREFIX; Sketcher and PartDesign cannot be configured" >&2
    exit 1
}
[ -f "$PYBIND11_ROOT/include/pybind11/pybind11.h" ] || {
    echo "pybind11 headers are missing under $PYBIND11_ROOT; run scripts/prepare-pybind11-ohos.sh" >&2
    exit 1
}
[ -x "$SWIG_PREFIX/bin/swig" ] || {
    echo "SWIG is missing: $SWIG_PREFIX/bin/swig" >&2
    exit 1
}
[ -f "$PIVY_SITE/pivy/_coin.so" ] || {
    echo "Pivy is missing: $PIVY_SITE/pivy/_coin.so" >&2
    exit 1
}
[ -f "$PYSIDE6_PREFIX/lib/cmake/PySide6/PySide6Config.cmake" ] || {
    echo "PySide6 target package is missing under $PYSIDE6_PREFIX" >&2
    exit 1
}
[ -f "$SHIBOKEN6_PREFIX/lib/cmake/Shiboken6/Shiboken6Config.cmake" ] || {
    echo "Shiboken6 target package is missing under $SHIBOKEN6_PREFIX" >&2
    exit 1
}

if [ "$BUILD_ASSEMBLY" = ON ] && [ ! -f "$SRC/src/3rdParty/OndselSolver/CMakeLists.txt" ]; then
    echo "Assembly 已启用，但 OndselSolver 子模块不存在。先运行 scripts/prepare-ondsel-solver.sh，或保持 FREECAD_BUILD_ASSEMBLY=OFF。" >&2
    exit 1
fi
if [ "$BUILD_ADDONMGR" = ON ] && [ ! -f "$SRC/src/Mod/AddonManager/CMakeLists.txt" ]; then
    echo "Addon Manager 已启用，但子模块不存在。先运行 scripts/prepare-addon-manager.sh，或设置 FREECAD_BUILD_ADDONMGR=OFF。" >&2
    exit 1
fi
if [ "$BUILD_START" = ON ] && [ ! -f "$SRC/src/3rdParty/GSL/include/gsl/pointers" ]; then
    echo "Start 工作台已启用，但 Microsoft.GSL 子模块不存在。先运行 scripts/prepare-freecad-gsl.sh，或设置 FREECAD_BUILD_START=OFF。" >&2
    exit 1
fi

# SetupSwig intentionally clears its cache variables and re-runs find_package.
# Make the OHOS-built SWIG discoverable through PATH/SWIG_LIB, and expose the
# target Pivy package to its configure-time Python compatibility probe.
export PATH="$SWIG_PREFIX/bin:$PATH"
export SWIG_LIB="$SWIG_PREFIX/share/swig/$SWIG_VERSION"
export PYTHONPATH="$PIVY_SITE${PYTHONPATH:+:$PYTHONPATH}"
export LD_LIBRARY_PATH="$QT_PREFIX/lib:$PIVY_SITE:$COIN_PREFIX/lib:$GL4ES_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

PREFIX_PATH="$QT_PREFIX;$COIN_PREFIX;$BOOST_PREFIX;$EIGEN_PREFIX;$XERCES_PREFIX;$OCCT_PREFIX;$YAML_CPP_PREFIX;$VTK_PREFIX;$PYTHON_ROOT;$PYSIDE6_PREFIX;$SHIBOKEN6_PREFIX"
FIND_ROOT_PATH="$NATIVE_SDK;$QT_PREFIX;$COIN_PREFIX;$BOOST_PREFIX;$EIGEN_PREFIX;$XERCES_PREFIX;$OCCT_PREFIX;$YAML_CPP_PREFIX;$VTK_PREFIX;$PYTHON_ROOT;$PYSIDE6_PREFIX;$SHIBOKEN6_PREFIX"

# FEM, BIM, and MeshPart pull in Salome SMESH, which additionally requires
# MEDFile/HDF5. Those OHOS packages are not installed in this toolchain.
# Keep the Mesh workbench itself enabled; MeshPart is an optional extension.
# OHOS libc exposes most pthread symbols but not pthread_cancel; Qt's
# -pthread probe therefore fails before FindThreads can use libpthread.
cmake_configure "$SRC" "$BUILD" "$PREFIX" \
    -DCMAKE_AUTOGEN_PARALLEL="$JOBS" \
    -DCMAKE_PREFIX_PATH="$PREFIX_PATH" \
    -DCMAKE_FIND_ROOT_PATH="$FIND_ROOT_PATH" \
    -DCMAKE_PROGRAM_PATH="$SWIG_PREFIX/bin" \
    -DCMAKE_MODULE_PATH="$PROJECT_DIR/cmake;$SRC/cMake" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
    -DCMAKE_INSTALL_RPATH='$ORIGIN' \
    -DOpenCASCADE_DIR="$OCCT_PREFIX/lib/cmake/opencascade" \
    -DVTK_DIR="$VTK_DIR" \
    -DFREECAD_QT_VERSION=6 \
    -DQt6_DIR="$QT_PREFIX/lib/cmake/Qt6" \
    -DQT_NO_THREADS_PREFER_PTHREAD_FLAG=ON \
    -DTHREADS_PREFER_PTHREAD_FLAG=OFF \
    -DTHREADS_HAVE_PTHREAD_ARG=OFF \
    -DCoin_DIR="$COIN_PREFIX/lib/cmake/Coin-4.0.0" \
    -DEIGEN3_INCLUDE_DIR="$EIGEN_PREFIX/include/eigen3" \
    -DOPENGL_gl_LIBRARY="$GLESV2_LIBRARY" \
    -DOPENGL_INCLUDE_DIR="$OPENGL_INCLUDE_DIR" \
    -DOHOS_ALLOW_UNDEFINED_SYMBOLS=ON \
    -DPython3_ROOT_DIR="$PYTHON_ROOT" \
    -DPython3_EXECUTABLE="$PYTHON_HOST_BIN" \
    -DPython3_LIBRARY="$PYTHON_ROOT/lib/libpython3.11.so" \
    -DPython3_INCLUDE_DIR="$PYTHON_ROOT/include/python3.11" \
    -DShiboken6_DIR="$SHIBOKEN6_PREFIX/lib/cmake/Shiboken6" \
    -DPySide6_DIR="$PYSIDE6_PREFIX/lib/cmake/PySide6" \
    -DSWIG_EXECUTABLE="$SWIG_PREFIX/bin/swig" \
    -DSWIG_DIR="$SWIG_PREFIX/share/swig/$SWIG_VERSION" \
    -DICU_INCLUDE_DIR="$NATIVE_SDK/sysroot/usr/include" \
    -DICU_UC_LIBRARY_RELEASE="$ICU_LIBRARY" \
    -DICU_I18N_LIBRARY_RELEASE="$ICU_LIBRARY" \
    -DPYCXX_INCLUDE_DIRS="$SRC/src/3rdParty/PyCXX" \
    -DPYCXX_SOURCE_DIR="$SRC/src/3rdParty/PyCXX/CXX" \
    -DFETCHCONTENT_SOURCE_DIR_FMT="$FMT_SOURCE" \
    -DPYBIND11_ROOT="$PYBIND11_ROOT" \
    -DINSTALL_TO_SITEPACKAGES=OFF \
    -DBUILD_GUI=ON \
    -DFREECAD_CHECK_PIVY=OFF \
    -DFREECAD_USE_SHIBOKEN=ON \
    -DFREECAD_USE_PYSIDE=ON \
    -DFREECAD_USE_3DCONNEXION_LEGACY=OFF \
    -DBUILD_FEM="$BUILD_FEM" \
    -DBUILD_SMESH=OFF \
    -DBUILD_FEM_NETGEN=OFF \
    -DBUILD_ADDONMGR="$BUILD_ADDONMGR" \
    -DBUILD_ARCH=OFF \
    -DBUILD_ASSEMBLY="$BUILD_ASSEMBLY" \
    -DBUILD_BIM="$BUILD_BIM" \
    -DBUILD_CAM=ON \
    -DBUILD_CLOUD=OFF \
    -DBUILD_DRAFT=ON \
    -DBUILD_DRAWING=OFF \
    -DBUILD_IDF=ON \
    -DBUILD_HELP=ON \
    -DBUILD_IMPORT=ON \
    -DBUILD_INSPECTION=ON \
    -DBUILD_JTREADER=OFF \
    -DBUILD_MATERIAL=ON \
    -DBUILD_MATERIAL_EXTERNAL=OFF \
    -DBUILD_MEASURE=ON \
    -DBUILD_MESH=ON \
    -DBUILD_MESH_PART="$BUILD_MESH_PART" \
    -DBUILD_FLAT_MESH=OFF \
    -DBUILD_OPENSCAD=OFF \
    -DBUILD_PART=ON \
    -DBUILD_PART_DESIGN=ON \
    -DBUILD_PATH=OFF \
    -DBUILD_PLOT=OFF \
    -DBUILD_POINTS=ON \
    -DBUILD_REVERSEENGINEERING="$BUILD_REVERSEENGINEERING" \
    -DBUILD_ROBOT=ON \
    -DBUILD_SHOW=ON \
    -DBUILD_SKETCHER=ON \
    -DBUILD_SPREADSHEET=ON \
    -DBUILD_START="$BUILD_START" \
    -DBUILD_TEST=ON \
    -DBUILD_TECHDRAW=ON \
    -DBUILD_TUX=ON \
    -DBUILD_WEB=OFF \
    -DBUILD_SURFACE=ON \
    -DENABLE_DEVELOPER_TESTS=OFF \
    -DFREECAD_USE_FREETYPE=OFF \
    -DFREECAD_USE_PCL=OFF \
    -DFREECAD_USE_EXTERNAL_FMT=OFF

# The FreeCAD cache can retain BUILD_* values even when dependency checks turn
# the corresponding normal variables off. Verify generated targets, not only
# CMakeCache.txt, before allowing an incomplete GUI runtime to be installed.
TARGETS="$BUILD/CMakeFiles/TargetDirectories.txt"
for define in HAVE_SHIBOKEN6 HAVE_PYSIDE6; do
    grep -q -- "-D$define" "$BUILD/build.ninja" || {
        echo "错误：FreeCADGui 未启用 $define；请检查 PySide6/Shiboken6 目标包" >&2
        exit 1
    }
done
for target in ImportGui PartDesignGui SketcherGui; do
    grep -q "/CMakeFiles/$target.dir" "$TARGETS" || {
        echo "错误：GUI 配置未生成 $target 目标；请检查 Eigen3/Qt6 依赖和 configure 输出" >&2
        exit 1
    }
done
if [ "$BUILD_ASSEMBLY" = ON ]; then
    for target in Assembly AssemblyGui AssemblyScripts; do
        grep -q "/CMakeFiles/$target.dir" "$TARGETS" || {
            echo "错误：Assembly 已启用但未生成 $target 目标" >&2
            exit 1
        }
    done
fi
if [ "$BUILD_REVERSEENGINEERING" = ON ]; then
    for target in ReverseEngineering ReverseEngineeringGui ReverseEngineeringScripts; do
        grep -q "/CMakeFiles/$target.dir" "$TARGETS" || {
            echo "错误：Reverse Engineering 已启用但未生成 $target 目标" >&2
            exit 1
        }
    done
fi

echo "Configured Qt6 GUI FreeCAD in $BUILD"
