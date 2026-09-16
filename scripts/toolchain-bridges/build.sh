#!/bin/sh
# 把两个桥接壳（见 README.md）编译成 app_packing_tool.jar / hap-sign-tool.jar。
#
# 用法：
#   sh scripts/toolchain-bridges/build.sh              # 编到本目录 .build/
#   OUT=/tmp/bridges sh scripts/toolchain-bridges/build.sh
#   JAVAC=/path/to/javac sh scripts/toolchain-bridges/build.sh
#
# 产物是两个 jar，不随仓库提交（可由源码重建），安装进 SDK 由
# scripts/switch-ohos-sdk.sh 负责。
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="${OUT:-$HERE/.build}"
CLASSES="$OUT/classes"

# /bin/rm 优先：本机 PATH 首位被注入了 safe-bin 目录，其 rm 在特定环境下会以 126 退出。
RM=/bin/rm
[ -x "$RM" ] || RM=rm

find_tool() {
    name="$1"
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/$name" ]; then
        printf '%s\n' "$JAVA_HOME/bin/$name"
        return 0
    fi
    if [ -x "$HOME/.harmonybrew/bin/$name" ]; then
        printf '%s\n' "$HOME/.harmonybrew/bin/$name"
        return 0
    fi
    if found=$(command -v "$name" 2>/dev/null) && [ -n "$found" ]; then
        printf '%s\n' "$found"
        return 0
    fi
    # harmonybrew 的 Cellar 里按版本号排；取最高版本
    if [ -d "$HOME/.harmonybrew/Cellar/openjdk" ]; then
        found=$(ls -d "$HOME/.harmonybrew/Cellar/openjdk"/*/bin/"$name" 2>/dev/null | sort -V | tail -n 1)
        if [ -n "$found" ] && [ -x "$found" ]; then
            printf '%s\n' "$found"
            return 0
        fi
    fi
    return 1
}

JAVAC="${JAVAC:-$(find_tool javac || true)}"
JAR_BIN="${JAR_BIN:-$(find_tool jar || true)}"
[ -n "$JAVAC" ] && [ -x "$JAVAC" ] || {
    echo "错误：找不到 javac（试过 JAVA_HOME、~/.harmonybrew/bin、PATH、Cellar）。" >&2
    exit 2
}
[ -n "$JAR_BIN" ] && [ -x "$JAR_BIN" ] || {
    echo "错误：找不到 jar（试过 JAVA_HOME、~/.harmonybrew/bin、PATH、Cellar）。" >&2
    exit 2
}

"$RM" -rf "$OUT"
mkdir -p "$CLASSES"

# --release 17：hvigor 可能用自带 JBR 跑这个 jar，别把字节码版本绑死在本机 JDK 26 上。
# 用到的 API（System.getenv / ProcessBuilder / Files.readString）Java 11 就有。
"$JAVAC" --release 17 -d "$CLASSES" \
    "$HERE/OhosPackingToolBridge.java" \
    "$HERE/OhosHapSignToolBridge.java"

# jar 名必须与 hvigor 期望的一致：getPackageToolPath() → app_packing_tool.jar，
# getVerifySignConfigToolPath() → hap-sign-tool.jar（依据见 README.md）。
build_jar() {
    jar_name="$1"
    main_class="$2"
    manifest="$OUT/$jar_name.manifest"
    printf 'Manifest-Version: 1.0\nMain-Class: %s\n\n' "$main_class" > "$manifest"
    "$JAR_BIN" cfm "$OUT/$jar_name" "$manifest" -C "$CLASSES" "$main_class.class"
}

build_jar app_packing_tool.jar OhosPackingToolBridge
build_jar hap-sign-tool.jar OhosHapSignToolBridge

"$RM" -f "$OUT"/*.manifest

echo "已生成："
for f in "$OUT/app_packing_tool.jar" "$OUT/hap-sign-tool.jar"; do
    echo "  $f"
done
echo "用 javac: $JAVAC"
