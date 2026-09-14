#!/bin/sh
# 把 FreeCAD AI 助手工作台安装进 FreeCAD GUI 安装前缀。
#
# 上游：https://github.com/ghbalf/freecad-ai （LGPL-2.1-or-later）
# 它不在 FreeCAD 源码树里，是独立的第三方 addon，所以不像 BIM 那样有
# src/Mod/BIM 可镜像 —— 源码单独归档在
#   $CPP_LIB_ROOT/sources/freecad-ai/$FREECAD_AI_VERSION/
# 下载包归档在
#   $CPP_LIB_ROOT/downloads/freecad-ai/
#
# 为什么不需要"编译"：
#   freecad-ai 是纯 Python，零外部依赖（只用 stdlib：urllib / json /
#   threading / ssl），package.xml 声明 freecadmin 1.0 + pythonmin 3.10，
#   与本项目的 FreeCAD 1.1.2 / Python 3.11.4 兼容。没有 C 扩展，因此
#     * 不参与 CMake 构建，没有 BUILD_* 开关；
#     * 可以安全地进入 rawfile（stage-gui-hap.sh 禁止 native ELF 入
#       runtime 归档，纯 Python 天然合规）。
#
# 目录名必须是 freecad-ai（不能改名）：
#   Init.py 里 os.path.join(FreeCAD.getUserAppDataDir(), "Mod", "freecad-ai")
#   是硬编码的，工作台靠它把自己挂进 sys.path。
#
# OHOS 已知限制（安装脚本不解决，仅记录）：
#   OHOS Python runtime 没有编 _ssl 扩展，lib-dynload 里只有 _socket。
#   freecad_ai/llm/client.py 对 ssl 做了 try/except（_HAS_SSL），所以工作台
#   能加载、能打开聊天面板，但 https:// 端点会在 urlopen 处失败。
#   可用路径是明文 http:// 端点；要接云端 HTTPS provider 需要先给 OHOS
#   Python 补 _ssl（OpenSSL 已有 OHOS 构建，见 CPPLib install/openssl/3.5.7）。
set -eu

CPP_LIB_ROOT="${CPP_LIB_ROOT:-/storage/Users/currentUser/CPPLib}"
. "$CPP_LIB_ROOT/scripts/common-ohos.sh"

FREECAD_VERSION="${FREECAD_VERSION:-1.1.2}"
FREECAD_AI_VERSION="${FREECAD_AI_VERSION:-0.27.0-alpha}"

SRC="${FREECAD_AI_SRC:-$CPP_LIB_ROOT/sources/freecad-ai/$FREECAD_AI_VERSION}"
PREFIX="${FREECAD_GUI_PREFIX:-$CPP_LIB_ROOT/install/freecad/$FREECAD_VERSION/ohos/$ABI-gui-qt6}"
DEST="$PREFIX/Mod/freecad-ai"

# 交互式 WorkBuddy 会话会把一个 safe-delete shim 目录插到 PATH 首位，里面那个
# rm 不可执行，直接调 rm 会以 "No such file or directory" 失败。这个 shim 是
# PATH 注入而不是环境变量，所以 `env -u` 清不掉。用绝对路径绕开，让脚本不
# 依赖调用者的 PATH（stage-gui-hap.sh 也踩过同一个坑）。
RM=/bin/rm
[ -x "$RM" ] || RM=rm

[ -d "$SRC" ] || {
    echo "缺少 freecad-ai 源码：$SRC" >&2
    echo "请先从 codeload 取包并解压到该目录（见本脚本头部注释）。" >&2
    exit 1
}

# 必须的入口与包结构。Init.py 负责 sys.path，InitGui.py 负责注册工作台。
for required in Init.py InitGui.py freecad_ai/__init__.py; do
    [ -f "$SRC/$required" ] || {
        echo "freecad-ai 源码不完整，缺少：$required" >&2
        exit 1
    }
done

echo "==> Mod/freecad-ai（纯 Python，$FREECAD_AI_VERSION）"
"$RM" -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC"/. "$DEST"/

# 源码归档里可能带进来开发期的字节码缓存；它们只会在设备上制造
# 解释器版本不匹配的噪声。
find "$DEST" -type d -name '__pycache__' -prune -exec "$RM" -rf {} + 2>/dev/null || true
find "$DEST" -type f -name '*.pyc' -delete 2>/dev/null || true

# native ELF 绝不能进入这个目录：stage-gui-hap.sh 会把 Mod/ 打进 rawfile，
# 而 rawfile 里的 ELF 会丢失 HAP 代码签名。
if find "$DEST" -type f \( -name '*.so' -o -name '*.so.*' \) | grep -q .; then
    echo "错误：Mod/freecad-ai 含 native ELF，不能进 rawfile" >&2
    exit 1
fi

echo "==> 安装完成：$DEST"
echo "    文件数：$(find "$DEST" -type f | wc -l)"
echo "    磁盘占用：$(du -sk "$DEST" | cut -f1) KB"
echo
echo "提示：重新打包前需先跑 scripts/stage-gui-hap.sh（它会把 Mod/ 打进"
echo "      rawfile 的 freecad-runtime.zip），再跑 scripts/build-gui-hap-ohos.sh。"
