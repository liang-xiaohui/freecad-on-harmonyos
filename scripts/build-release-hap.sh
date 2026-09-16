#!/bin/sh
# 出**发布包**：product=release + buildMode=release，用 AGC 签发的发布证书与发布 Profile。
#
# 与默认构建的三处差别，都是必须的：
#   1. product 选 release —— 签名是按 product 绑定的（buildModeSet 的 schema 里根本没有
#      signingConfig 字段），所以 -p buildMode=release 单独用**不会**换证书。
#   2. 产物落在 entry/build/release/outputs/default/，与调试包不同目录，不会互相覆盖。
#   3. 固定 PACKAGE_FLEXIMIND=OFF —— 带私有载荷的包只用于开发机调试，绝不上架。
#
# 顺序固定为 stage → build → verify，且 **stage 非 0 就不继续 build**：
# 失败的 stage 会让 staging 停在半成品，而紧接着的 build 仍会"成功"产出一个残缺 HAP，
# 只有 verify 会报出来。
#
# 前置条件：发布材料已就位（见 docs/appgallery-release.md「发布材料」一节）
#   ~/Documents/ohos/config/release-signing/{ohos-release.p12, FreeCAD_Release_2026.cer,
#                                          FreeCAD_Release_2026Release.p7b, material/}
# 以及 build-profile.json5 里有绑定发布材料的 release signingConfig + release product。
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"

[ -z "${PACKAGE_FLEXIMIND:-}" ] || [ "$PACKAGE_FLEXIMIND" = "OFF" ] || {
    echo "错误：发布包必须 PACKAGE_FLEXIMIND=OFF，当前为 $PACKAGE_FLEXIMIND。" >&2
    echo "      内部包（ON）会把私有载荷打进 rawfile，不能上架。" >&2
    exit 2
}
export PACKAGE_FLEXIMIND=OFF

RELEASE_HAP="$PROJECT_DIR/entry/build/release/outputs/default/entry-default-signed.hap"

echo "==> 1/3 stage（准备 rawfile 与 native 库）"
./scripts/stage-gui-hap.sh

echo
echo "==> 2/3 build（PRODUCT=release BUILD_MODE=release）"
PRODUCT=release BUILD_MODE=release ./scripts/build-gui-hap-ohos.sh

[ -f "$RELEASE_HAP" ] || {
    echo "错误：构建结束但找不到发布包：$RELEASE_HAP" >&2
    echo "      检查 build-profile.json5 里是否已有 release product 且 signingConfig 指向发布签名。" >&2
    exit 1
}

echo
echo "==> 3/3 verify（HAP 指向发布包）"
HAP="$RELEASE_HAP" ./scripts/verify-gui-hap.sh

echo
echo "发布包就绪："
echo "  $RELEASE_HAP"
echo "  $(stat -c '%s' "$RELEASE_HAP") 字节"
echo
echo "上架前建议再核对签名与 Profile（改自 AGC 下载的文件时尤其要做）："
echo "  OUT=\${TMPDIR:-/tmp}   # 有些环境 /tmp 只读"
echo "  .sdk-overlay/26/toolchains/lib/hap-sign-tool verify-app \\"
echo "      -inFile '$RELEASE_HAP' -outCertChain \"\$OUT/chain.cer\" -outProfile \"\$OUT/hap.p7b\""
echo "  cmp \"\$OUT/hap.p7b\" ~/Documents/ohos/config/release-signing/*.p7b   # 应逐字节相同"
echo "  另需确认证书链叶子是**发布**证书（公钥 SHA-256 前 16 位 8e3b8d794f1a2354），"
echo "  不是调试那张（c10b5b2372e06496）。"
