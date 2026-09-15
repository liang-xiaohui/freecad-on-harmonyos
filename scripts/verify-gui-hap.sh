#!/bin/sh
# 验证 FreeCAD v1.1.2 GUI HAP（Qt6）内容：native 文件、rawfile、能力清单、新鲜度。
# 用法：DevEco 构建完成后运行：
#   ./scripts/verify-gui-hap.sh
# 通过条件：
#   - HAP 内含当前 staging 的全部 native 文件（Qt6/QPA/FreeCAD GUI/OCCT/Coin/gl4es/Python/绑定栈）
#   - rawfile 含 python311.zip / freecad-runtime.zip（PACKAGE_FLEXIMIND=ON 时另含验收脚本）
#   - module.json 的能力清单与 PACKAGE_FLEXIMIND 一致：OFF 时不得声明 EntryAbility（对外包），
#     ON 时必须有（内部包）；两种情况都必须有 QAbility
#   - HAP 时间不早于 staging 与验收源码
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# 与 stage-gui-hap.sh / build-gui-hap-ohos.sh / entry/hvigorfile.ts 同一个开关：
# OFF（默认）＝对外包，要求包里**没有** FlexiMind/、没有验收脚本、不声明 EntryAbility；
# ON ＝内部包，三者必须都在。构建时三处取值必须一致，本脚本负责把不一致拦下来。
# ON 时的私有输入清单与条目断言由外部钩子提供，见 scripts/fleximind-hook.sh。
PACKAGE_FLEXIMIND="${PACKAGE_FLEXIMIND:-OFF}"
case "$PACKAGE_FLEXIMIND" in
    ON | on | 1 | true | yes) PACKAGE_FLEXIMIND=ON ;;
    *) PACKAGE_FLEXIMIND=OFF ;;
esac
if [ "$PACKAGE_FLEXIMIND" = "ON" ]; then
    RAWFILE_REQUIRED="python311.zip freecad-runtime.zip freecad_headless_acceptance.py"
    . "$PROJECT_DIR/scripts/fleximind-hook.sh"
    fleximind_load_hook
else
    RAWFILE_REQUIRED="python311.zip freecad-runtime.zip"
fi
# 载荷顶层目录名：钩子可覆盖，这里给同一个默认值，供 OFF 侧的"不得包含"断言使用。
FLEXIMIND_PAYLOAD_DIR="${FLEXIMIND_PAYLOAD_DIR:-FlexiMind}"
PY_YAML_ROOT="$PROJECT_DIR/runtime/pyyaml"
PACKAGING_ROOT="$PROJECT_DIR/runtime/packaging"
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"
NUMPY_SP="${NUMPY_SP:-$CPP_LIB_ROOT/install/numpy/2.2.6/ohos/$ABI/site-packages}"
NUMPY_LICENSE="$NUMPY_SP/numpy-2.2.6.dist-info/LICENSE.txt"
ARTIFACT_ROOT="${FREECAD_ARTIFACT_ROOT:-/storage/Users/currentUser/codex-freecad-artifacts}"

HAP="${HAP:-$PROJECT_DIR/entry/build/default/outputs/default/entry-default-signed.hap}"
STAGED_DIR="$PROJECT_DIR/entry/libs/$ABI"
RAWFILE_DIR="$PROJECT_DIR/entry/src/main/resources/rawfile"
SPLASH_MEDIA_DIR="$PROJECT_DIR/entry/src/main/resources/base/media"
FREECAD_SPLASH_SOURCE="$CPP_LIB_ROOT/sources/freecad/1.1.2/src/Gui/Icons"
BUILD_ADDONMGR="${FREECAD_BUILD_ADDONMGR:-ON}"
BUILD_START="${FREECAD_BUILD_START:-ON}"
BUILD_ASSEMBLY="${FREECAD_BUILD_ASSEMBLY:-ON}"
BUILD_REVERSEENGINEERING="${FREECAD_BUILD_REVERSEENGINEERING:-ON}"
BUILD_FEM="${FREECAD_BUILD_FEM:-ON}"

[ -f "$HAP" ] || { echo "错误：找不到 HAP：$HAP" >&2; exit 1; }
for c in node unzip stat sha256sum; do
    command -v "$c" >/dev/null 2>&1 || { echo "错误：需要 $c" >&2; exit 2; }
done
READELF=$(command -v readelf 2>/dev/null || command -v llvm-readelf 2>/dev/null || true)
[ -n "$READELF" ] || { echo "错误：需要 readelf 或 llvm-readelf" >&2; exit 2; }

echo "==> 检查 HAP 与 rawfile staging 内容一致"
for rf in $RAWFILE_REQUIRED; do
    staged_hash=$(sha256sum "$RAWFILE_DIR/$rf" | awk '{print $1}')
    hap_hash=$(unzip -p "$HAP" "resources/rawfile/$rf" | sha256sum | awk '{print $1}')
    [ "$staged_hash" = "$hap_hash" ] || {
        echo "错误：HAP 使用了过期 rawfile/$rf，请重新运行 stage-gui-hap.sh 后再 Build Hap" >&2
        exit 1
    }
    echo "    ✓ rawfile/$rf 与 HAP 一致"
done

echo "==> 检查 13 张官方随机 splash 及异形玻璃外扩"
node "$PROJECT_DIR/scripts/generate-startup-splashes.mjs" --check \
    "$FREECAD_SPLASH_SOURCE" "$SPLASH_MEDIA_DIR"
splash_count=0
for splash_index in 0 1 2 3 4 5 6 7 8 9 10 11 12; do
    splash_name="freecadsplash${splash_index}.png"
    source_splash="$FREECAD_SPLASH_SOURCE/freecadsplash${splash_index}_2x.png"
    staged_splash="$SPLASH_MEDIA_DIR/$splash_name"
    [ -f "$source_splash" ] && [ -f "$staged_splash" ] || {
        echo "错误：缺少 splash 资源：$splash_name" >&2
        exit 1
    }
    staged_hash=$(sha256sum "$staged_splash" | awk '{print $1}')
    hap_hash=$(unzip -p "$HAP" "resources/base/media/$splash_name" | sha256sum | awk '{print $1}')
    [ "$staged_hash" = "$hap_hash" ] || {
        echo "错误：HAP 中的 $splash_name 与异形玻璃 staging 资源不一致" >&2
        exit 1
    }
    splash_count=$((splash_count + 1))
done
[ "$splash_count" -eq 13 ] || { echo "错误：随机 splash 数量不是 13" >&2; exit 1; }
echo "    ✓ 13 张高清官方素材已生成异形玻璃外扩并进入 HAP"
mkdir -p "$ARTIFACT_ROOT"
RUNTIME_ZIP=$(mktemp "$ARTIFACT_ROOT/verify-gui-hap-runtime.XXXXXX")
RUNTIME_DIR=$(mktemp -d "$ARTIFACT_ROOT/verify-gui-hap.XXXXXX")
HAP_MANIFEST=$(mktemp "$ARTIFACT_ROOT/verify-gui-hap-module.XXXXXX")
trap 'rm -f "$RUNTIME_ZIP" "$HAP_MANIFEST"; rm -rf "$RUNTIME_DIR"' EXIT HUP INT TERM

echo "==> 检查 HAP 新鲜度"
hap_mtime=$(stat -c '%Y' "$HAP")
newest_input=0
for f in "$STAGED_DIR"/plugins/platforms/libqohos.so "$STAGED_DIR"/libqohos.so "$STAGED_DIR"/libfreecadqtapp.so "$STAGED_DIR"/FreeCADGui.so \
         "$RAWFILE_DIR/freecad-runtime.zip" \
         "$PROJECT_DIR/entry/hvigorfile.ts" \
         "$PROJECT_DIR/entry/src/main/cpp/acceptance.cpp" \
         "$PROJECT_DIR/entry/src/main/ets/qability/QAbility.ets" \
         "$PROJECT_DIR/entry/src/main/ets/pages/StartupSplash.ets" \
         "$PROJECT_DIR/entry/src/main/ets/qabilitystage/QAbilityStage.ets" \
         "$PROJECT_DIR/entry/src/main/module.json5" \
         "$PROJECT_DIR/scripts/generate-startup-splashes.mjs" \
         "$PROJECT_DIR"/entry/src/main/resources/base/media/freecadsplash*.png \
         "$PROJECT_DIR/entry/src/main/resources/base/media/transparent_start_window.svg" \
         "$PY_YAML_ROOT/LICENSE" \
         "$PY_YAML_ROOT/yaml/__init__.py" \
         "$PACKAGING_ROOT/LICENSE" \
         "$PACKAGING_ROOT/LICENSE.APACHE" \
         "$PACKAGING_ROOT/LICENSE.BSD" \
         "$PACKAGING_ROOT/packaging/__init__.py" \
         "$NUMPY_LICENSE" \
         "$NUMPY_SP/numpy/__init__.py"; do
    [ -f "$f" ] || { echo "错误：staging 输入缺失：$f" >&2; exit 1; }
    m=$(stat -c '%Y' "$f")
    [ "$m" -gt "$newest_input" ] && newest_input=$m
done
if [ "$PACKAGE_FLEXIMIND" = ON ]; then
    for f in "$RAWFILE_DIR/freecad_headless_acceptance.py" $(fleximind_input_files); do
        [ -f "$f" ] || { echo "错误：staging 输入缺失：$f" >&2; exit 1; }
        m=$(stat -c '%Y' "$f")
        [ "$m" -gt "$newest_input" ] && newest_input=$m
    done
fi
newer_numpy=$(find "$NUMPY_SP/numpy" -type f -newer "$HAP" -print -quit)
if [ -n "$newer_numpy" ]; then
    m=$(stat -c '%Y' "$newer_numpy")
    [ "$m" -gt "$newest_input" ] && newest_input=$m
fi
for source in "$PY_YAML_ROOT"/yaml/*.py; do
    [ -f "$source" ] || continue
    m=$(stat -c '%Y' "$source")
    [ "$m" -gt "$newest_input" ] && newest_input=$m
done
newer_packaging=$(find "$PACKAGING_ROOT" -type f -newer "$HAP" -print -quit)
if [ -n "$newer_packaging" ]; then
    m=$(stat -c '%Y' "$newer_packaging")
    [ "$m" -gt "$newest_input" ] && newest_input=$m
fi

if [ "$PACKAGE_FLEXIMIND" = ON ]; then
    unzip -p "$HAP" resources/rawfile/freecad-runtime.zip > "$RUNTIME_ZIP"
    for entry in $(fleximind_payload_entries); do
        unzip -Z1 "$RUNTIME_ZIP" | grep -Fqx "$entry" || {
            echo "错误：freecad-runtime.zip 缺少 $entry" >&2
            exit 1
        }
    done
    echo "    FlexiMind 载荷在位（PACKAGE_FLEXIMIND=ON）✓"
    if unzip -Z1 "$RUNTIME_ZIP" | grep -Eq "$(fleximind_forbidden_pattern)"; then
        echo "错误：已禁用的 FlexiMindGripDesign GUI 工作台仍存在于 freecad-runtime.zip" >&2
        exit 1
    fi
else
    unzip -p "$HAP" resources/rawfile/freecad-runtime.zip > "$RUNTIME_ZIP"
    if unzip -Z1 "$RUNTIME_ZIP" | grep -q "^$FLEXIMIND_PAYLOAD_DIR/"; then
        echo "错误：对外包不得包含 $FLEXIMIND_PAYLOAD_DIR/ 载荷，请用（默认的）PACKAGE_FLEXIMIND=OFF 重新 stage 并重打包" >&2
        exit 1
    fi
    echo "    HAP 不含 $FLEXIMIND_PAYLOAD_DIR/ 载荷（PACKAGE_FLEXIMIND=OFF）✓"
    # 对外包只做工作台顶层路径这一级防护；源码结构级的断言由私有钩子在 ON 时负责。
    if unzip -Z1 "$RUNTIME_ZIP" | grep -q '^Mod/FlexiMindGripDesign/'; then
        echo "错误：已禁用的 FlexiMindGripDesign GUI 工作台仍存在于 freecad-runtime.zip" >&2
        exit 1
    fi
fi
if [ "$hap_mtime" -lt "$newest_input" ]; then
    echo "错误：HAP 早于 staging/验收源码，请重新 Build Hap" >&2
    exit 1
fi
echo "    HAP $(stat -c '%y' "$HAP") 新于所有输入 ✓"

echo "==> 检查 native 文件（关键样本 + 数量）"
# 注意：多数库带版本化后缀（libQt6Core.so.6 / libTKernel.so.7.8 / libCoin.so.80 /
# libpython3.11.so.1.0），不能只匹配 \.so$；用 .*\.so 匹配全部 native 库。
total=$(unzip -l "$HAP" | grep -cE 'libs/arm64-v8a/.*\.so' || true)
staged_total=$(find "$STAGED_DIR" -type f -name '*.so' | wc -l | tr -d ' ')
[ "$staged_total" -gt 0 ] || { echo "错误：staging 中没有 native .so" >&2; exit 1; }
[ "$total" -ge "$staged_total" ] || {
    echo "错误：HAP native .so 少于当前 staging（$total < $staged_total）" >&2
    exit 1
}
echo "    native .so 总数：$total（当前 staging：$staged_total）"
for lib in libfreecadqtapp.so FreeCAD.so FreeCADGui.so Part.so PartGui.so \
           Sketcher.so SketcherGui.so _PartDesign.so PartDesignGui.so Import.so ImportGui.so libQt6Core.so.6 libQt6Gui.so.6 \
           libCoin.so.80 libGL.so libpython3.11.so.1.0 libTKernel.so.7.8 \
           Shiboken.abi3.so libshiboken6.abi3.so QtCore.abi3.so QtGui.abi3.so \
           QtWidgets.abi3.so libpyside6.abi3.so.6.8 _coin.so \
           _multiarray_umath.cpython-311-aarch64-linux-ohos.so \
           _pocketfft_umath.cpython-311-aarch64-linux-ohos.so \
           _umath_linalg.cpython-311-aarch64-linux-ohos.so; do
    if unzip -l "$HAP" | grep -qE "libs/arm64-v8a/(plugins/platforms/)?$lib$"; then
        echo "    ✓ $lib"
    else
        echo "    缺失 native 库：$lib" >&2
        exit 1
    fi
done
if [ "$BUILD_FEM" = ON ]; then
    for lib in Fem.so FemGui.so; do
        unzip -l "$HAP" | grep -qE "libs/arm64-v8a/$lib$" || {
            echo "错误：FEM native 库缺失：$lib" >&2
            exit 1
        }
        echo "    ✓ $lib"
    done
    for entry in Mod/Fem/Init.py Mod/Fem/InitGui.py Mod/Fem/ObjectsFem.py \
                 Mod/Fem/femobjects/material_common.py \
                 Mod/Fem/femviewprovider/view_material_common.py \
                 share/licenses/fem-dependencies/HDF5-COPYING \
                 share/licenses/fem-dependencies/MEDFile-COPYING \
                 share/licenses/fem-dependencies/MEDFile-COPYING.LESSER \
                 share/licenses/fem-dependencies/OHOS-native-NOTICE.txt; do
        unzip -p "$RUNTIME_ZIP" "$entry" >/dev/null 2>&1 || {
            echo "错误：freecad-runtime.zip 缺少 FEM 脚本：$entry" >&2
            exit 1
        }
        echo "    ✓ $entry"
    done
fi
if [ "$BUILD_ASSEMBLY" = ON ]; then
    for lib in AssemblyApp.so AssemblyGui.so; do
        unzip -l "$HAP" | grep -qE "libs/arm64-v8a/$lib$" || {
            echo "错误：Assembly native 库缺失：$lib" >&2
            exit 1
        }
        echo "    ✓ $lib"
    done
fi
if [ "$BUILD_REVERSEENGINEERING" = ON ]; then
    for lib in ReverseEngineering.so ReverseEngineeringGui.so; do
        unzip -l "$HAP" | grep -qE "libs/arm64-v8a/$lib$" || {
            echo "错误：Reverse Engineering native 库缺失：$lib" >&2
            exit 1
        }
        echo "    ✓ $lib"
    done
fi

echo "==> 检查 GUI 工作台注册脚本"
# These are the workbenches enabled by the default full GUI configuration.
# Keep this list in sync with rebuild-freecad-all-workbenches.sh so an old,
# three-workbench staging cannot pass validation unnoticed.
workbench_entries="
Mod/CAM/InitGui.py
Mod/Draft/InitGui.py
Mod/Help/InitGui.py
Mod/Import/InitGui.py
Mod/Inspection/InitGui.py
Mod/Material/InitGui.py
Mod/Measure/InitGui.py
Mod/Mesh/InitGui.py
Mod/Part/InitGui.py
Mod/PartDesign/InitGui.py
Mod/Points/InitGui.py
Mod/Robot/InitGui.py
Mod/Sketcher/InitGui.py
Mod/Spreadsheet/InitGui.py
Mod/Surface/InitGui.py
Mod/TechDraw/InitGui.py
Mod/Test/InitGui.py
Mod/Tux/InitGui.py"
for entry in $workbench_entries; do
    unzip -p "$RUNTIME_ZIP" "$entry" >/dev/null 2>&1 || {
        echo "错误：freecad-runtime.zip 缺少 GUI 工作台脚本：$entry" >&2
        exit 1
    }
    echo "    ✓ $entry"
done
if [ "$BUILD_ADDONMGR" = ON ]; then
    for entry in Mod/AddonManager/Init.py Mod/AddonManager/InitGui.py; do
        unzip -p "$RUNTIME_ZIP" "$entry" >/dev/null 2>&1 || {
            echo "错误：freecad-runtime.zip 缺少 Addon Manager 脚本：$entry" >&2
            exit 1
        }
        echo "    ✓ $entry"
    done
fi
if [ "$BUILD_START" = ON ]; then
    for entry in Mod/Start/Init.py Mod/Start/InitGui.py; do
        unzip -p "$RUNTIME_ZIP" "$entry" >/dev/null 2>&1 || {
            echo "错误：freecad-runtime.zip 缺少 Start 脚本：$entry" >&2
            exit 1
        }
        echo "    ✓ $entry"
    done
fi
if [ "$BUILD_ASSEMBLY" = ON ]; then
    for entry in Mod/Assembly/Init.py Mod/Assembly/InitGui.py; do
        unzip -p "$RUNTIME_ZIP" "$entry" >/dev/null 2>&1 || {
            echo "错误：freecad-runtime.zip 缺少 Assembly 脚本：$entry" >&2
            exit 1
        }
        echo "    ✓ $entry"
    done
fi
if [ "$BUILD_REVERSEENGINEERING" = ON ]; then
    for entry in Mod/ReverseEngineering/Init.py Mod/ReverseEngineering/InitGui.py; do
        unzip -p "$RUNTIME_ZIP" "$entry" >/dev/null 2>&1 || {
            echo "错误：freecad-runtime.zip 缺少 Reverse Engineering 脚本：$entry" >&2
            exit 1
        }
        echo "    ✓ $entry"
    done
fi
for entry in Ext/yaml/__init__.py Ext/yaml/loader.py Ext/yaml/dumper.py Ext/yaml/LICENSE; do
    unzip -p "$RUNTIME_ZIP" "$entry" >/dev/null 2>&1 || {
        echo "错误：freecad-runtime.zip 缺少 PyYAML 文件：$entry" >&2
        exit 1
    }
    echo "    ✓ $entry"
done
for entry in Ext/packaging/__init__.py Ext/packaging/version.py Ext/packaging/utils.py \
             Ext/packaging/LICENSE Ext/packaging/LICENSE.APACHE Ext/packaging/LICENSE.BSD; do
    unzip -p "$RUNTIME_ZIP" "$entry" >/dev/null 2>&1 || {
        echo "错误：freecad-runtime.zip 缺少 packaging 文件：$entry" >&2
        exit 1
    }
    echo "    ✓ $entry"
done
for entry in Ext/numpy/__init__.py Ext/numpy/_core/__init__.py Ext/numpy/fft/__init__.py \
             Ext/numpy/linalg/__init__.py Ext/numpy/random/__init__.py Ext/numpy/LICENSE.txt; do
    unzip -p "$RUNTIME_ZIP" "$entry" >/dev/null 2>&1 || {
        echo "错误：freecad-runtime.zip 缺少 NumPy 文件：$entry" >&2
        exit 1
    }
    echo "    ✓ $entry"
done

echo "==> 检查 rawfile native ELF 与 Python 绑定 RUNPATH"
# Every ELF must be a native HAP file so HarmonyOS signs it. Also reject
# build-host paths in the Python bindings' RUNPATH.
if unzip -Z1 "$RUNTIME_ZIP" |
   grep -Eq '\.so([.]|$)'; then
    echo "错误：freecad-runtime.zip 含未签名的 native ELF" >&2
    exit 1
fi
for package in PySide6 shiboken6 pivy; do
    unzip -p "$RUNTIME_ZIP" "Ext/$package/__init__.py" |
        grep -q 'FREECAD_APP_LIBRARY_DIR' || {
            echo "错误：$package 未配置从 HAP native 目录加载扩展模块" >&2
            exit 1
        }
done
for package in numpy/_core numpy/fft numpy/linalg numpy/random; do
    unzip -p "$RUNTIME_ZIP" "Ext/$package/__init__.py" |
        grep -q 'FREECAD_APP_LIBRARY_DIR' || {
            echo "错误：$package 未配置从 HAP native 目录加载扩展模块" >&2
            exit 1
        }
done
unzip -q "$HAP" 'libs/arm64-v8a/*.abi3.so*' 'libs/arm64-v8a/_coin.so' \
    'libs/arm64-v8a/*cpython-311-*.so*' -d "$RUNTIME_DIR"
for binding in QtCore QtGui QtWidgets QtNetwork; do
    [ -f "$RUNTIME_DIR/libs/arm64-v8a/$binding.abi3.so" ] || {
        echo "错误：HAP 缺少 PySide6 $binding 绑定" >&2
        exit 1
    }
done
for binding in "$RUNTIME_DIR"/libs/arm64-v8a/*.so*; do
    [ -f "$binding" ] || continue
    runpath=$("$READELF" -d "$binding" 2>/dev/null |
        awk '/\(RPATH\)|\(RUNPATH\)/ {sub(/^.*\[/, ""); sub(/\].*$/, ""); print}')
    echo "$runpath" | grep -Eq '(^|:)/' && {
        echo "错误：native 绑定模块含绝对 RUNPATH：${binding#$RUNTIME_DIR/}: $runpath" >&2
        exit 1
    } || true
done
echo "    ✓ 绑定 ELF 位于 HAP native 区域且 RUNPATH 可移植"

echo "==> 检查 rawfile"
for rf in $RAWFILE_REQUIRED; do
    if unzip -l "$HAP" | grep -q "resources/rawfile/$rf"; then
        echo "    ✓ rawfile/$rf"
    else
        echo "    缺失 rawfile：$rf" >&2
        exit 1
    fi
done
if [ "$PACKAGE_FLEXIMIND" != "ON" ] &&
   unzip -l "$HAP" | grep -q "resources/rawfile/freecad_headless_acceptance.py"; then
    echo "    对外包不应含 rawfile/freecad_headless_acceptance.py（只有 EntryAbility 会读它）" >&2
    exit 1
fi

echo "==> 检查 module.json 的能力清单（PACKAGE_FLEXIMIND=$PACKAGE_FLEXIMIND）"
unzip -p "$HAP" module.json > "$HAP_MANIFEST"
HAP_MANIFEST="$HAP_MANIFEST" PACKAGE_FLEXIMIND="$PACKAGE_FLEXIMIND" node -e '
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.env.HAP_MANIFEST, "utf8"));
const names = (manifest.module.abilities || []).map((ability) => ability.name);
const internal = process.env.PACKAGE_FLEXIMIND === "ON";
if (!names.includes("QAbility")) {
    console.error(`    错误：module.json 缺 QAbility（abilities=${names.join(", ")}）`);
    process.exit(1);
}
if (internal && !names.includes("EntryAbility")) {
    console.error("    错误：内部包（PACKAGE_FLEXIMIND=ON）里没有 EntryAbility，设备侧验收跑不起来");
    process.exit(1);
}
if (!internal && names.includes("EntryAbility")) {
    console.error(`    错误：对外包里仍声明了导出的无头桥 EntryAbility（abilities=${names.join(", ")}）`);
    process.exit(1);
}
console.log(`    ✓ 能力清单与开关一致：abilities=[${names.join(", ")}]`);
'
# 无头桥一旦被剥掉，acceptance.cpp 导出的 runJob/runAcceptance 就没有调用方了；
# 但 .so 本身必须还在 —— QAbilityStage.prepareOpenGL() 与 QAbility 的
# setupFreecadEnv()/materializeFreecadRuntimeAsync() 都 import 它。
unzip -l "$HAP" | grep -q "libs/arm64-v8a/libfreecadacceptance.so" || {
    echo "    缺失：libs/arm64-v8a/libfreecadacceptance.so（GUI 依赖它的 NAPI 导出）" >&2
    exit 1
}
echo "    ✓ libs/arm64-v8a/libfreecadacceptance.so 保留（GUI 的 NAPI 模块）"

echo "==> 检查 Qt 插件"
for plug in libs/arm64-v8a/libqohos.so libs/arm64-v8a/plugins/platforms/libqohos.so libs/arm64-v8a/plugins/imageformats/libqsvg.so libs/arm64-v8a/plugins/iconengines/libqsvgicon.so; do
    unzip -l "$HAP" | grep -q "$plug" && echo "    ✓ $plug" || { echo "    缺失：$plug" >&2; exit 1; }
done

echo
echo "GUI HAP 验证通过：$HAP"
if [ "$PACKAGE_FLEXIMIND" = "ON" ]; then
    echo "运行：Run EntryAbility（验收）或 QAbility（GUI）；GUI 日志 scripts/watch-gui-hap-log.sh"
else
    echo "运行：Run QAbility（GUI）；GUI 日志 scripts/watch-gui-hap-log.sh"
    echo "（对外包不含 EntryAbility；要做设备侧验收请用 PACKAGE_FLEXIMIND=ON 重新 stage + 构建）"
fi
