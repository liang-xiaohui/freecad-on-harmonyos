#!/bin/sh
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
FREECAD_SHA256="${FREECAD_SHA256:-e964520db9da2c67bf2a81223015e33d359178b1c461a16a802ad67f900c62b7}"
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCHIVE="$CPP_LIB_ROOT/downloads/freecad/FreeCAD-$FREECAD_VERSION.tar.gz"
SOURCE_DIR="$CPP_LIB_ROOT/sources/freecad/$FREECAD_VERSION"
URL="https://codeload.github.com/FreeCAD/FreeCAD/tar.gz/refs/tags/$FREECAD_VERSION"
VERSION_HEADER="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/Version.h"
OHOS_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos.patch"
PYTHON_COMPAT_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/python-ohos-compat.patch"
BOOST_COMPAT_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/boost-1.86.patch"
RPATH_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-rpath.patch"
HEADLESS_SWIG_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/headless-swig.patch"
HEADLESS_TRANSLATIONS_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/headless-translations.patch"
HEADLESS_TRANSLATION_TOOLS_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/headless-translation-tools.patch"
SOURCE_LOCATION_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-source-location.patch"
LIBCXX_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-libcxx.patch"
ICU_C_API_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-icu-c-api.patch"
QT512_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/headless-qt5.12.patch"
CLANG15_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-clang15.patch"
LIBCXX15_VIEWS_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-libcxx15-views.patch"
RUNTIME_LAYOUT_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-runtime-layout.patch"
TECHDRAW_CLOCALE_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-techdraw-clocale.patch"
TECHDRAW_QGVPAGE_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-techdraw-qgvpage.patch"
CAM_GLES_CONSTANTS_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-cam-gles-constants.patch"
STYLEPARAMETERS_NUMERIC_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-styleparameters-numeric.patch"
GL_ATTRIB_STACK_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-gl-attrib-stack.patch"
GUI_SPLASH_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-disable-gui-splash.patch"
GLES_SURFACE_FORMAT_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-gles-surface-format.patch"
GUI_STARTUP_LOGO_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-parent-startup-logo.patch"
GUI_STYLESHEET_PROBES_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-parent-stylesheet-probes.patch"
QUARTER_DEFER_PAINT_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-defer-quarter-paint.patch"
LCS_RESTORE_NULL_GUARD_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-lcs-restore-null-guard.patch"
QUARTER_STACK_ON_TOP_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-quarter-stack-on-top.patch"
QUARTER_PAINT_ORDER_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-quarter-paint-order.patch"
NATIVE_UITOOLS_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-native-uitools.patch"
LEGACY_EMBEDDED_DIALOG_TITLEBAR_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-embedded-dialog-titlebar.patch"
DEFAULT_LANGUAGE_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-default-language.patch"
QSS_WIDGET_INDICATOR_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-qss-widget-indicator-images.patch"
QSS_TASK_INDICATOR_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-qss-task-indicator-images.patch"
QSS_TASK_MENU_ARROW_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-qss-task-menu-arrow-images.patch"
QSS_DOCK_SEPARATOR_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-qss-dock-separator-hit-area.patch"
QT_PLUGIN_PATH_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-qt-plugin-path.patch"
SERVICE_PROVIDER_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-serviceprovider-cross-dso.patch"
SKETCH_MAKE_INTERNALS_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-sketch-make-internals.patch"
AXIS_CROSS_ASCII_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-axis-cross-ascii-labels.patch"
GUI_FATAL_HILOG_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-gui-fatal-hilog.patch"
NAVICUBE_AXISCROSS_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-enable-navicube-axiscross.patch"
NAVICUBE_RAW_GL_LABELS_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-navicube-raw-gl-labels.patch"
VIEW_ALL_CLIPPING_SYNC_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-view-all-clipping-sync.patch"
SAVE_DOCS_DIRECT_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-save-docs-path-direct.patch"
SKETCHER_SETTINGS_DEFAULT_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-sketcher-settings-internal-faces-default.patch"
PICK_RADIUS_DEFAULT_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-pick-radius-default.patch"
SELECTION_CONTEXT_RENDER_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-selection-context-render.patch"
START_FILECARD_NULL_PIXMAP_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-start-filecard-null-pixmap.patch"
GUI_READY_MARKER_PATCH="$PROJECT_DIR/patches/freecad-$FREECAD_VERSION/ohos-gui-ready-marker.patch"

if [ "$FREECAD_VERSION" != "1.1.2" ] && [ -z "${FREECAD_SHA256:-}" ]; then
    echo "FREECAD_SHA256 is required for version $FREECAD_VERSION" >&2
    exit 1
fi

mkdir -p "$(dirname "$ARCHIVE")" "$(dirname "$SOURCE_DIR")"

if [ ! -f "$ARCHIVE" ]; then
    echo "Downloading FreeCAD $FREECAD_VERSION"
    curl -fL --retry 2 --connect-timeout 15 -o "$ARCHIVE.part" "$URL"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi

actual_sha256=$(sha256sum "$ARCHIVE" | awk '{print $1}')
if [ "$actual_sha256" != "$FREECAD_SHA256" ]; then
    echo "Checksum mismatch for $ARCHIVE" >&2
    echo "expected: $FREECAD_SHA256" >&2
    echo "actual:   $actual_sha256" >&2
    exit 1
fi

if [ -f "$SOURCE_DIR/CMakeLists.txt" ]; then
    echo "FreeCAD source already prepared: $SOURCE_DIR"
elif [ -d "$SOURCE_DIR" ]; then
    echo "Refusing to extract into incomplete directory: $SOURCE_DIR" >&2
    exit 1
else
    mkdir -p "$SOURCE_DIR"
    tar --no-same-owner --strip-components=1 -xzf "$ARCHIVE" -C "$SOURCE_DIR"
    echo "Prepared FreeCAD source: $SOURCE_DIR"
fi

if [ -f "$VERSION_HEADER" ]; then
    if ! cmp -s "$VERSION_HEADER" "$SOURCE_DIR/src/Build/Version.h"; then
        cp "$VERSION_HEADER" "$SOURCE_DIR/src/Build/Version.h"
        echo "Installed release version header: $SOURCE_DIR/src/Build/Version.h"
    else
        echo "Release version header is up to date"
    fi
fi

# The upstream 1.1.2 archive stores this source file with CRLF line endings;
# normalize it so the minimal OHOS include patch also works with Toybox patch.
TECHDRAW_SOURCE="$SOURCE_DIR/src/Mod/TechDraw/App/DrawTemplate.cpp"
if [ -f "$TECHDRAW_SOURCE" ]; then
    sed -i 's/\r$//' "$TECHDRAW_SOURCE"
fi
CAM_OPENGL_WRAPPER="$SOURCE_DIR/src/Mod/CAM/PathSimulator/AppGL/OpenGlWrapper.h"
if [ -f "$CAM_OPENGL_WRAPPER" ]; then
    sed -i 's/\r$//' "$CAM_OPENGL_WRAPPER"
fi
DOCUMENT_SOURCE="$SOURCE_DIR/src/App/Document.cpp"
if [ -f "$DOCUMENT_SOURCE" ]; then
    sed -i 's/\r$//' "$DOCUMENT_SOURCE"
fi
for selection_source in \
    "$SOURCE_DIR/src/Gui/Selection/SoFCUnifiedSelection.h" \
    "$SOURCE_DIR/src/Gui/Selection/SoFCUnifiedSelection.cpp"; do
    if [ -f "$selection_source" ]; then
        sed -i 's/\r$//' "$selection_source"
    fi
done
START_FILECARD_SOURCE="$SOURCE_DIR/src/Mod/Start/Gui/FileCardDelegate.cpp"
if [ -f "$START_FILECARD_SOURCE" ]; then
    sed -i 's/\r$//' "$START_FILECARD_SOURCE"
fi

# Older local OHOS preparations disabled native QUiLoader because the Qt 5
# port lacked UiTools.  Qt 6 ships the target UiTools library; restore the
# upstream guard before applying the Qt 6-specific configuration patch.
UI_LOADER_HEADER="$SOURCE_DIR/src/Gui/UiLoader.h"
if grep -q '#if !defined(__MINGW32__) && !defined(FREECAD_OHOS)' "$UI_LOADER_HEADER" 2>/dev/null; then
    sed -i 's/#if !defined(__MINGW32__) && !defined(FREECAD_OHOS)/#if !defined(__MINGW32__)/' "$UI_LOADER_HEADER"
fi

# Native OHOS SubWindows now provide the frame and title bar for top-level
# dialogs. Remove the earlier in-content title bar when updating an already
# prepared source tree; keep the old patch only as reversible migration data.
if grep -q '_freecad_ohos_dialog_titlebar' \
       "$SOURCE_DIR/src/Gui/GuiApplication.cpp" 2>/dev/null; then
    git -C "$SOURCE_DIR" apply --ignore-space-change --ignore-whitespace \
        --reverse "$LEGACY_EMBEDDED_DIALOG_TITLEBAR_PATCH"
    echo "Removed legacy embedded dialog title bar"
fi

for patch_file in "$OHOS_PATCH" "$PYTHON_COMPAT_PATCH" "$BOOST_COMPAT_PATCH" "$RPATH_PATCH" "$HEADLESS_SWIG_PATCH" "$HEADLESS_TRANSLATIONS_PATCH" "$HEADLESS_TRANSLATION_TOOLS_PATCH" "$SOURCE_LOCATION_PATCH" "$LIBCXX_PATCH" "$ICU_C_API_PATCH" "$QT512_PATCH" "$CLANG15_PATCH" "$LIBCXX15_VIEWS_PATCH" "$RUNTIME_LAYOUT_PATCH" "$TECHDRAW_CLOCALE_PATCH" "$TECHDRAW_QGVPAGE_PATCH" "$CAM_GLES_CONSTANTS_PATCH" "$STYLEPARAMETERS_NUMERIC_PATCH" "$GL_ATTRIB_STACK_PATCH" "$GUI_SPLASH_PATCH" "$GLES_SURFACE_FORMAT_PATCH" "$GUI_STARTUP_LOGO_PATCH" "$GUI_STYLESHEET_PROBES_PATCH" "$QUARTER_DEFER_PAINT_PATCH" "$LCS_RESTORE_NULL_GUARD_PATCH" "$QUARTER_STACK_ON_TOP_PATCH" "$QUARTER_PAINT_ORDER_PATCH" "$NATIVE_UITOOLS_PATCH" "$DEFAULT_LANGUAGE_PATCH" "$QSS_WIDGET_INDICATOR_PATCH" "$QSS_TASK_INDICATOR_PATCH" "$QSS_TASK_MENU_ARROW_PATCH" "$QSS_DOCK_SEPARATOR_PATCH" "$QT_PLUGIN_PATH_PATCH" "$SERVICE_PROVIDER_PATCH" "$SKETCH_MAKE_INTERNALS_PATCH" "$AXIS_CROSS_ASCII_PATCH" "$GUI_FATAL_HILOG_PATCH" "$NAVICUBE_AXISCROSS_PATCH" "$NAVICUBE_RAW_GL_LABELS_PATCH" "$VIEW_ALL_CLIPPING_SYNC_PATCH" "$SAVE_DOCS_DIRECT_PATCH" "$SKETCHER_SETTINGS_DEFAULT_PATCH" "$PICK_RADIUS_DEFAULT_PATCH" "$SELECTION_CONTEXT_RENDER_PATCH" "$START_FILECARD_NULL_PIXMAP_PATCH" "$GUI_READY_MARKER_PATCH"; do
    [ -f "$patch_file" ] || continue
    if [ "$patch_file" = "$HEADLESS_TRANSLATION_TOOLS_PATCH" ] &&
       grep -q 'Keep the mobile package focused while shipping complete Simplified' \
           "$SOURCE_DIR/cMake/FreeCAD_Helpers/SetupQt.cmake" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$LIBCXX_PATCH" ] &&
       grep -q '_LIBCPP_ENABLE_EXPERIMENTAL' "$SOURCE_DIR/CMakeLists.txt" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$QT512_PATCH" ] &&
       grep -q 'QT_VERSION < QT_VERSION_CHECK(5, 14, 0)' \
           "$SOURCE_DIR/src/Mod/Material/App/MaterialValue.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    # Later NaviCube patches intentionally re-enable two overlays disabled by
    # this patch, so recognize its GL state-save replacement semantically.
    if [ "$patch_file" = "$GL_ATTRIB_STACK_PATCH" ] &&
       grep -q "gl4es' emulated attribute stack is unstable" \
           "$SOURCE_DIR/src/Gui/View3DInventorViewer.cpp" 2>/dev/null &&
       grep -q "gl4es' emulated attribute stack is unstable" \
           "$SOURCE_DIR/src/Gui/Inventor/SoFCBackgroundGradient.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$SKETCH_MAKE_INTERNALS_PATCH" ] &&
       grep -q 'GetBool("MakeInternals", true)' \
           "$SOURCE_DIR/src/Mod/Sketcher/App/SketchObject.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$AXIS_CROSS_ASCII_PATCH" ] &&
       grep -q 'draw Axis Cross labels as Coin geometry' \
           "$SOURCE_DIR/src/Gui/Inventor/SoFCPlacementIndicatorKit.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$VIEW_ALL_CLIPPING_SYNC_PATCH" ] &&
       grep -q 'Coin updates the automatic clipping planes through a delay sensor' \
           "$SOURCE_DIR/src/Gui/View3DInventorViewer.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    # These Quarter patches intentionally touch adjacent lines. Once a later
    # patch is present, git's whole-hunk reverse check can no longer recognize
    # an earlier patch even though its semantic change is still in the source.
    if [ "$patch_file" = "$GLES_SURFACE_FORMAT_PATCH" ] &&
       grep -q 'surfaceFormat.setRenderableType(QSurfaceFormat::OpenGLES)' \
           "$SOURCE_DIR/src/Gui/Quarter/QuarterWidget.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$QUARTER_DEFER_PAINT_PATCH" ] &&
       grep -q '_freecad_ohos_surface_ready' \
           "$SOURCE_DIR/src/Gui/Quarter/QuarterWidget.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$QUARTER_STACK_ON_TOP_PATCH" ] &&
       grep -q 'WA_AlwaysStackOnTop was tried here' \
           "$SOURCE_DIR/src/Gui/Quarter/QuarterWidget.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$QUARTER_PAINT_ORDER_PATCH" ] &&
       grep -q 'Draw the Coin scene after that pass' \
           "$SOURCE_DIR/src/Gui/Quarter/QuarterWidget.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$DEFAULT_LANGUAGE_PATCH" ] &&
       grep -q 'Default new profiles' \
           "$SOURCE_DIR/src/Gui/Application.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$QSS_WIDGET_INDICATOR_PATCH" ] &&
       grep -q 'QAbstractSpinBox::up-button' \
           "$SOURCE_DIR/src/Gui/Stylesheets/FreeCAD.qss" 2>/dev/null &&
       grep -q 'check-mark-@StylesheetIconsColor.png' \
           "$SOURCE_DIR/src/Gui/Stylesheets/FreeCAD.qss" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$QSS_TASK_INDICATOR_PATCH" ] &&
       grep -q 'OHOS: use raster assets for item-view indicators' \
           "$SOURCE_DIR/src/Gui/Stylesheets/FreeCAD.qss" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$QSS_DOCK_SEPARATOR_PATCH" ] &&
       grep -q 'OHOS: the stock 4px extent is unreachable' \
           "$SOURCE_DIR/src/Gui/Stylesheets/FreeCAD.qss" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$QSS_TASK_MENU_ARROW_PATCH" ] &&
       sed -n '/^QToolButton::menu-arrow {/,/^}/p' \
           "$SOURCE_DIR/src/Gui/Stylesheets/FreeCAD.qss" 2>/dev/null |
           grep -q 'arrow-down-lightgray.png'; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if [ "$patch_file" = "$QT_PLUGIN_PATH_PATCH" ] &&
       grep -q 'FREECAD_APP_LIBRARY_DIR' "$SOURCE_DIR/src/Gui/StartupProcess.cpp" 2>/dev/null &&
       grep -q 'native plugins are signed' "$SOURCE_DIR/src/Gui/StartupProcess.cpp" 2>/dev/null; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
        continue
    fi
    if git -C "$SOURCE_DIR" apply --ignore-space-change --ignore-whitespace --reverse --check "$patch_file" >/dev/null 2>&1; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
    elif git -C "$SOURCE_DIR" apply --ignore-space-change --ignore-whitespace --check "$patch_file"; then
        git -C "$SOURCE_DIR" apply --ignore-space-change --ignore-whitespace "$patch_file"
        echo "Applied FreeCAD patch: $(basename "$patch_file")"
    elif patch -d "$SOURCE_DIR" -p1 -l --dry-run -R < "$patch_file" >/dev/null 2>&1; then
        echo "FreeCAD patch already applied: $(basename "$patch_file")"
    elif patch -d "$SOURCE_DIR" -p1 -l --dry-run < "$patch_file" >/dev/null 2>&1; then
        patch -d "$SOURCE_DIR" -p1 -l < "$patch_file"
        echo "Applied FreeCAD patch: $(basename "$patch_file")"
    else
        echo "FreeCAD patch does not apply cleanly: $patch_file" >&2
        exit 1
    fi
done
