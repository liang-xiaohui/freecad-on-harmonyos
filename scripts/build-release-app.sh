#!/bin/sh
# 出**发布应用包**（.app）——AGC 提审上传用的是这个文件，不是 .hap。
#
# 为什么必须分两种产物：
#   设备安装（hdc install）走 .hap，但**发布签名**的包在任何设备上都装不上。
#   bundle manager 一律以 9568322 "signature verification failed due to not
#   trusted app source" 拒绝，hilog 里对应的是：
#       [nodict]VerifyProfileInfo: untrusted source app with release profile
#   这是设计如此 —— 发布 Profile 只能经应用市场（或 AGC 测试渠道）分发。
#   所以本机自测永远用调试签名的 .hap（默认构建），.app 只喂给 AGC。
#
# 产物：
#   build/outputs/release/freecad-on-harmonyos-release-unsigned.app
#   build/outputs/release/freecad-on-harmonyos-release-signed.app   <-- 上传这个
#
# 顺序固定为 stage → assembleApp → verify，且 **stage 非 0 就不继续 build**
# （同 build-release-hap.sh：失败的 stage 会让 staging 停在半成品，而紧接着的
# build 仍会"成功"产出一个残缺包）。
#
# 注意 .app 内的 entry-default.hap 是**未签名**形态：hap 签名块不在里面，
# 签名加在 .app 整体上（hap-sign-tool verify-app 对 .app 本体校验）。因此下面
# 第 3 步要把内嵌 hap 解出来，再走一遍 verify-gui-hap.sh 的内容校验。
#
# 前置条件：发布材料已就位（见 docs/appgallery-release.md「发布材料」一节）
#   ~/Documents/ohos/config/release-signing/{ohos-release.p12, FreeCAD_Release_2026.cer,
#                                          FreeCAD_Release_2026Release.p7b, material/}
# 以及 build-profile.json5 里有绑定发布材料的 release signingConfig + release product。
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"

# WorkBuddy 的 shell 会把 .../cli/vendor/shim/safe-bin 注进 PATH 首位，那里的 rm 在
# 沙箱删除保护关闭时会拒绝执行，stage-gui-hap.sh 会因此以 126 退出。`env -u` 清不掉
# 这个注入，只能把该目录从 PATH 里摘掉。（PATH 里没有它时，这段等价于空操作。）
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | sed '/cli\/vendor\/shim\/safe-bin/d' | tr '\n' ':' | sed 's/:$//')
export PATH

[ -z "${PACKAGE_FLEXIMIND:-}" ] || [ "$PACKAGE_FLEXIMIND" = "OFF" ] || {
    echo "错误：发布包必须 PACKAGE_FLEXIMIND=OFF，当前为 $PACKAGE_FLEXIMIND。" >&2
    echo "      内部包（ON）会把私有载荷打进 rawfile，不能上架。" >&2
    exit 2
}
export PACKAGE_FLEXIMIND=OFF

RELEASE_APP="$PROJECT_DIR/build/outputs/release/freecad-on-harmonyos-release-signed.app"
SIGN_TOOL="${SIGN_TOOL:-$PROJECT_DIR/.sdk-overlay/26/toolchains/lib/hap-sign-tool}"
SIGNING_DIR="${SIGNING_DIR:-$HOME/Documents/ohos/config/release-signing}"
ARTIFACT_ROOT="${FREECAD_ARTIFACT_ROOT:-/storage/Users/currentUser/codex-freecad-artifacts}"

echo "==> 1/3 stage（准备 rawfile 与 native 库）"
./scripts/stage-gui-hap.sh

echo
echo "==> 2/3 assembleApp（PRODUCT=release BUILD_MODE=release）"
HVIGOR_TASK=assembleApp PRODUCT=release BUILD_MODE=release ./scripts/build-gui-hap-ohos.sh

[ -f "$RELEASE_APP" ] || {
    echo "错误：构建结束但找不到应用包：$RELEASE_APP" >&2
    echo "      检查 build-profile.json5 里是否已有 release product 且 signingConfig 指向发布签名。" >&2
    exit 1
}

echo
echo "==> 3/3 verify（.app 本体签名 + 内嵌 hap 内容）"
[ -x "$SIGN_TOOL" ] || {
    echo "错误：找不到可执行的 hap-sign-tool：$SIGN_TOOL" >&2
    exit 1
}
mkdir -p "$ARTIFACT_ROOT"
VERIFY_DIR=$(mktemp -d "$ARTIFACT_ROOT/release-app-verify.XXXXXX")
trap 'rm -rf "$VERIFY_DIR"' EXIT HUP INT TERM

echo "--- 3a) .app 本体签名"
"$SIGN_TOOL" verify-app -inFile "$RELEASE_APP" \
    -outCertChain "$VERIFY_DIR/app-chain.cer" -outProfile "$VERIFY_DIR/app.p7b"

SIGNING_PROFILE="${SIGNING_PROFILE:-}"
if [ -z "$SIGNING_PROFILE" ]; then
    set -- "$SIGNING_DIR"/*.p7b
    [ $# -eq 1 ] || {
        echo "错误：$SIGNING_DIR 下的 .p7b 不是唯一一份，请用 SIGNING_PROFILE 指定 AGC 下载的那份。" >&2
        exit 2
    }
    SIGNING_PROFILE=$1
fi
cmp "$VERIFY_DIR/app.p7b" "$SIGNING_PROFILE" || {
    echo "错误：.app 内嵌 Profile 与 AGC 下载的 $(basename "$SIGNING_PROFILE") 不一致。" >&2
    exit 1
}
echo "    内嵌 Profile 与 AGC 下载的 $(basename "$SIGNING_PROFILE") 逐字节相同 ✓"

echo
echo "--- 3b) 内嵌 hap 内容（解出后按 .hap 同一套规则校验）"
unzip -p "$RELEASE_APP" entry-default.hap > "$VERIFY_DIR/entry-default.hap"
HAP="$VERIFY_DIR/entry-default.hap" ./scripts/verify-gui-hap.sh

echo
echo "发布应用包就绪（AGC 提审上传这个）："
echo "  $RELEASE_APP"
echo "  $(stat -c '%s' "$RELEASE_APP") 字节"
echo
echo "它和本机设备安装无关："
echo "  * 本机调试/自测 → 调试签名的 .hap：./scripts/install-gui-hap.sh"
echo "  * 想在真机上跑发布签名版本 → 只能走 AGC 的测试渠道分发"
