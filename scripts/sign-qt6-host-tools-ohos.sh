#!/bin/sh
# Sign the arm64 OHOS Qt host tools executed by downstream CMake projects.
# Qt's moc/uic/rcc are target-arch binaries in this toolchain; after install
# they must be self-signed before they can execute from CPPLib/shared paths.
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
QT_PREFIX="${QT_PREFIX:-$CPP_LIB_ROOT/install/qt/6.8.3/ohos/arm64-v8a}"

find_sign_tool() {
    # DevEco uses different variable names across SDK/IDE releases. Keep the
    # lookup rooted in those variables instead of scanning the whole device.
    for sdk_root in \
        "${DEVECO_SDK_HOME:-}" \
        "${OHOS_SDK_HOME:-}" \
        "${OHOS_SDK_ROOT:-}" \
        "${HOS_SDK_HOME:-}" \
        "${OHOS_SDK:-}" \
        "${NATIVE_OHOS_SDK:-}" \
        "${NATIVE_SDK:-}"; do
        [ -n "$sdk_root" ] || continue
        for candidate in \
            "$sdk_root/toolchains/lib/binary-sign-tool" \
            "$sdk_root/openharmony/toolchains/lib/binary-sign-tool" \
            "$sdk_root/default/openharmony/toolchains/lib/binary-sign-tool" \
            "$sdk_root/native/toolchains/lib/binary-sign-tool"; do
            if [ -x "$candidate" ]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
        # Some DevEco shells expose only the SDK parent, not the exact API
        # version. Search that explicitly supplied root as a final fallback.
        candidate="$(find "$sdk_root" -type f -name binary-sign-tool -perm -111 -print -quit 2>/dev/null || true)"
        if [ -n "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

if [ -z "${BINARY_SIGN_TOOL:-}" ]; then
    BINARY_SIGN_TOOL=""
    for candidate in \
        "$(command -v binary-sign-tool 2>/dev/null || true)" \
        "/data/service/hnp/bin/binary-sign-tool" \
        "/data/app/sdk.org/sdk_1.0.0/default/openharmony/toolchains/lib/binary-sign-tool" \
        "/data/app/sdk.org/sdk_1.0.0/default/openharmony/native/toolchains/lib/binary-sign-tool" \
        "/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/toolchains/lib/binary-sign-tool" \
        "$CPP_LIB_ROOT/toolchains/harmonyos/6.1.0.105/toolchains/lib/binary-sign-tool"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            BINARY_SIGN_TOOL="$candidate"
            break
        fi
    done
    if [ -z "$BINARY_SIGN_TOOL" ]; then
        BINARY_SIGN_TOOL="$(find_sign_tool || true)"
    fi
fi

[ -d "$QT_PREFIX" ] || {
    echo "Qt prefix does not exist: $QT_PREFIX" >&2
    exit 1
}

QT_LD_LIBRARY_PATH="$QT_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

run_qt_tool() {
    tool_path=$1
    LD_LIBRARY_PATH="$QT_LD_LIBRARY_PATH" "$tool_path" -h
}

needs_sign=0
for tool in moc uic rcc; do
    path="$QT_PREFIX/libexec/$tool"
    [ -f "$path" ] || {
        echo "Qt host tool is missing: $path" >&2
        exit 1
    }
    chmod +x "$path" 2>/dev/null || true
    if run_qt_tool "$path" >/dev/null 2>&1; then
        echo "Qt host tool already executable: $path"
    else
        needs_sign=1
    fi
done

if [ "$needs_sign" -eq 0 ]; then
    exit 0
fi

if [ ! -x "$BINARY_SIGN_TOOL" ]; then
    host_description="$(uname -a 2>/dev/null || true)"
    case "$host_description" in
        *HarmonyOS*|*Toybox*)
            echo "This shell looks like a HarmonyOS device shell, not a DevEco host shell:" >&2
            echo "  $host_description" >&2
            echo "Run the signing step in DevEco Studio's host terminal, or expose the host SDK tool here." >&2
            ;;
    esac
    if [ -n "${BINARY_SIGN_TOOL:-}" ]; then
        echo "BINARY_SIGN_TOOL is not executable: $BINARY_SIGN_TOOL" >&2
        if [ -e "$BINARY_SIGN_TOOL" ]; then
            ls -l "$BINARY_SIGN_TOOL" >&2 || true
        else
            echo "The path does not exist." >&2
        fi
    else
        echo "binary-sign-tool was not found in PATH or the configured DevEco/OHOS SDK roots." >&2
    fi
    echo "In DevEco, run: command -v binary-sign-tool" >&2
    echo "Then set BINARY_SIGN_TOOL to that exact path, or unset it to use automatic discovery." >&2
    exit 1
fi

sign_one() {
    path=$1
    signed="$path.bst-signed.$$"
    rm -f "$signed"
    "$BINARY_SIGN_TOOL" sign -inFile "$path" -outFile "$signed" -selfSign 1 >/dev/null
    [ -f "$signed" ] || {
        echo "binary-sign-tool produced no output for: $path" >&2
        exit 1
    }
    mv "$signed" "$path"
    chmod +x "$path" 2>/dev/null || true
}

# uic/rcc dynamically load Qt6Core. Install/copy steps can drop the OHOS
# signature from versioned shared libraries even when the executable itself is
# signed, so sign the Qt6 runtime libraries before validating the tools.
find "$QT_PREFIX/lib" -maxdepth 1 -type f -name 'libQt6*.so*' -print 2>/dev/null |
while IFS= read -r library; do
    [ -n "$library" ] || continue
    sign_one "$library"
    echo "signed Qt6 runtime library: $library"
done

for tool in moc uic rcc; do
    path="$QT_PREFIX/libexec/$tool"
    sign_one "$path"
    run_qt_tool "$path" >/dev/null 2>&1 || {
        echo "Qt host tool is still not executable after signing: $path" >&2
        echo "Check LD_LIBRARY_PATH and the Qt6 libraries under $QT_PREFIX/lib." >&2
        run_qt_tool "$path" 2>&1 | head -12 >&2 || true
        exit 1
    }
    echo "signed Qt host tool: $path"
done
