#!/bin/sh
# Self-sign staged OHOS ELF shared libraries so local target-runtime probes can
# load them. HAP signing is handled separately by Hvigor.
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

STAGED_DIR="${STAGED_DIR:-$PROJECT_DIR/entry/libs/$ABI}"
READELF_BIN="${READELF_BIN:-$NATIVE_SDK/llvm/bin/llvm-readelf}"

find_readelf_tool() {
    for candidate in \
        "$READELF_BIN" \
        "$(command -v llvm-readelf 2>/dev/null || true)" \
        "$NATIVE_SDK/llvm/bin/llvm-readobj" \
        "/data/service/hnp/bin/llvm-readelf"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

find_sign_tool() {
    for candidate in \
        "${BINARY_SIGN_TOOL:-}" \
        "$(command -v binary-sign-tool 2>/dev/null || true)" \
        "/data/service/hnp/bin/binary-sign-tool" \
        "$OHOS_SDK/toolchains/lib/binary-sign-tool" \
        "$NATIVE_SDK/../toolchains/lib/binary-sign-tool" \
        "/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/toolchains/lib/binary-sign-tool"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

[ -d "$STAGED_DIR" ] || {
    echo "错误：staged native 目录不存在：$STAGED_DIR" >&2
    exit 2
}
READELF_BIN=$(find_readelf_tool || true)
[ -n "$READELF_BIN" ] || {
    echo "错误：llvm-readelf 不可执行：$READELF_BIN" >&2
    exit 2
}

BINARY_SIGN_TOOL=$(find_sign_tool || true)
[ -n "$BINARY_SIGN_TOOL" ] || {
    echo "错误：找不到 binary-sign-tool；可用 BINARY_SIGN_TOOL 指定。" >&2
    exit 2
}

elf_count=0
find "$STAGED_DIR" -type f -name '*.so*' -print | while IFS= read -r library; do
    [ -n "$library" ] || continue
    "$READELF_BIN" -h "$library" >/dev/null 2>&1 || continue
    signed="$library.bst-signed.$$"
    if [ -e "$signed" ]; then
        echo "错误：临时签名文件已存在：$signed" >&2
        exit 1
    fi
    "$BINARY_SIGN_TOOL" sign -inFile "$library" -outFile "$signed" -selfSign 1 >/dev/null
    [ -s "$signed" ] || {
        echo "错误：签名工具未生成输出：$library" >&2
        exit 1
    }
    mv "$signed" "$library"
    chmod +x "$library" 2>/dev/null || true
    elf_count=$((elf_count + 1))
    if [ $((elf_count % 25)) -eq 0 ]; then
        echo "已签名 $elf_count 个 staged ELF"
    fi
done

total=$(find "$STAGED_DIR" -type f -name '*.so*' -print | wc -l | tr -d ' ')
echo "staged native 自签名完成：$total 个 .so* 文件（$STAGED_DIR）"
