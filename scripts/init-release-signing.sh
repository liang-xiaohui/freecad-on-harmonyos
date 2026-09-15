#!/bin/sh
# 准备"正式发布"签名材料：生成发布密钥库(.p12) + 证书请求文件(.csr)，
# 并算出可直接粘进 build-profile.json5 的**加密口令**。
#
# 为什么要有这个脚本：DevEco Studio「Build > Generate Key and CSR」干的就是这件事，
# 而 hvigor 又不接受明文口令（见 scripts/signing-password.js 顶部注释）。把这两件事
# 都用命令行做掉，发布签名就不必依赖 GUI，也能在只有命令行环境时重建整套材料。
#
# 产物（默认都在 $RELEASE_DIR 下）：
#   ohos-release.p12   发布密钥库。**长期资产，必须备份**：
#                      AGC 规定"更新版本要用同一个 CSR 生成的证书"，
#                      丢了私钥就意味着这个应用的后续版本只能换证书重来。
#   ohos-release.csr   上传到 AGC「新增证书」的那个文件。
#   material/          口令加解密所需的密钥材料（从现有签名目录复制，
#                      hvigor 要求它就在 .p12 同一个目录下）。
#   password.txt       本次生成的明文口令（0600）。抄进密码管理器后可删。
#
# 用法：
#   sh scripts/init-release-signing.sh
#   DNAME='CN=你的名字, OU=Individual Developer, O=你的名字, L=Shanghai, ST=Shanghai, C=CN' \
#       sh scripts/init-release-signing.sh
#
# 可覆盖的环境变量：
#   RELEASE_DIR     默认 $HOME/Documents/ohos/config/release-signing
#   KEYSTORE        默认 $RELEASE_DIR/ohos-release.p12
#   ALIAS           默认 releaseKey（build-profile.json5 的 keyAlias 要与之相同）
#   DNAME           证书主题。只在 CSR 里体现，AGC 不拿它校验账号，可随时重生成
#   VALIDITY        密钥库有效期天数，默认 9125（25 年）
#   MATERIAL_SRC    现有 material/ 的来源，默认 $HOME/Documents/ohos/config/material
#   SAVE_PASSWORD   置 0 则不写 password.txt
#   FORCE           置 1 允许覆盖已存在的密钥库（**会作废已签发的证书**）
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RELEASE_DIR="${RELEASE_DIR:-$HOME/Documents/ohos/config/release-signing}"
KEYSTORE="${KEYSTORE:-$RELEASE_DIR/ohos-release.p12}"
ALIAS="${ALIAS:-releaseKey}"
DNAME="${DNAME:-CN=liangxiaohui, OU=Individual Developer, O=liangxiaohui, L=Shanghai, ST=Shanghai, C=CN}"
VALIDITY="${VALIDITY:-9125}"
MATERIAL_SRC="${MATERIAL_SRC:-$HOME/Documents/ohos/config/material}"
SAVE_PASSWORD="${SAVE_PASSWORD:-1}"
FORCE="${FORCE:-0}"
CSR="${CSR:-$RELEASE_DIR/$(basename "$KEYSTORE" .p12).csr}"

# 这台机器上 PATH 首位被注入了失效的 rm 桩，脚本自己不做删除，只用 mv 做备份。
MV=/bin/mv; [ -x "$MV" ] || MV=mv

die() { echo "错误：$*" >&2; exit 1; }

# --- 定位 keytool（本机 java 在 harmonybrew 里）--------------------------------
find_keytool() {
    for cand in \
        "$(command -v keytool 2>/dev/null || true)" \
        "$HOME/.harmonybrew/Cellar/openjdk"/*/bin/keytool \
        /usr/bin/keytool; do
        [ -n "$cand" ] && [ -x "$cand" ] && { echo "$cand"; return; }
    done
    return 1
}
KEYTOOL=$(find_keytool) || die "找不到 keytool；先安装 JDK 或把 keytool 放进 PATH。"
JAVA_BIN_DIR=$(dirname "$KEYTOOL")
NODE_BIN="${NODE_BIN:-$(command -v node 2>/dev/null || true)}"
[ -n "$NODE_BIN" ] || die "找不到 node（加密口令要用 scripts/signing-password.js）。"
export PATH="$JAVA_BIN_DIR:$PATH"

# --- 安全检查 ----------------------------------------------------------------
if [ -e "$KEYSTORE" ] && [ "$FORCE" != "1" ]; then
    die "$KEYSTORE 已存在。
  发布密钥库是长期资产，重复生成会产生一套全新的密钥 —— 若 AGC 上已有用旧密钥
  签发的发布证书，那它就跟新密钥库配不上，等于白占一个发布证书配额。
  确认要重建，请显式设置 FORCE=1。"
fi

mkdir -p "$RELEASE_DIR"
[ -d "$RELEASE_DIR" ] || die "建不出目录 $RELEASE_DIR"

if [ ! -d "$RELEASE_DIR/material" ]; then
    [ -d "$MATERIAL_SRC" ] || die "缺少密钥材料：$MATERIAL_SRC
  （hvigor 加解密口令要用它，且必须位于 .p12 所在目录下。
    若这台机器上还没有任何可用的签名目录，请先在 DevEco 里自动签名一次以生成它。）"
    cp -R "$MATERIAL_SRC" "$RELEASE_DIR/material"
    echo "==> 已复制密钥材料：$MATERIAL_SRC -> $RELEASE_DIR/material"
fi

# --- 生成口令：>=8 位、含大小写+数字+符号（DevEco 的强度要求，方便日后在 GUI 里改）---
gen_password() {
    base=$(openssl rand -base64 60 | tr -dc 'A-Za-z0-9' | cut -c1-20) || return 1
    echo "$base" | grep -q '[A-Z]' || return 1
    echo "$base" | grep -q '[a-z]' || return 1
    echo "$base" | grep -q '[0-9]' || return 1
    printf '%s-' "$base"
}
PASSWORD=""
i=1
while [ $i -le 10 ]; do
    PASSWORD=$(gen_password 2>/dev/null || true)
    [ -n "$PASSWORD" ] && break
    i=$((i + 1))
done
[ -n "$PASSWORD" ] || die "生成随机口令失败（openssl 可用？）"

# --- 生成密钥库与 CSR（算法对齐 DevEco：EC P-256 + SHA256withECDSA）-----------
echo "==> 生成发布密钥库：$KEYSTORE"
"$KEYTOOL" -genkeypair \
    -keystore "$KEYSTORE" -storetype PKCS12 -alias "$ALIAS" \
    -keyalg EC -groupname secp256r1 -sigalg SHA256withECDSA \
    -validity "$VALIDITY" -dname "$DNAME" \
    -storepass "$PASSWORD" -keypass "$PASSWORD" >/dev/null

echo "==> 生成证书请求文件：$CSR"
"$KEYTOOL" -certreq -keystore "$KEYSTORE" -storetype PKCS12 -alias "$ALIAS" \
    -sigalg SHA256withECDSA -file "$CSR" \
    -storepass "$PASSWORD" >/dev/null

# --- 算出可粘贴的加密口令 ------------------------------------------------------
BLOB=$(cd "$PROJECT_DIR" && "$NODE_BIN" scripts/signing-password.js encrypt "$PASSWORD" \
        --material-dir "$RELEASE_DIR") || die "加密口令失败"

if [ "$SAVE_PASSWORD" = "1" ]; then
    printf '%s\n' "$PASSWORD" > "$RELEASE_DIR/password.txt"
    chmod 600 "$RELEASE_DIR/password.txt" 2>/dev/null || true
fi

cat <<EOF

================ 生成完毕 ================

发布密钥库 : $KEYSTORE
  别名      : $ALIAS
证书请求   : $CSR        <-- 传到 AGC「证书、APP ID和Profile > 证书 > 新增证书」
密钥库口令 : $( [ "$SAVE_PASSWORD" = "1" ] && echo "见 $RELEASE_DIR/password.txt（0600）" || echo '未保存（SAVE_PASSWORD=0）' )
密钥材料   : $RELEASE_DIR/material    <-- 必须和 .p12 一起备份，别单独搬走 .p12

--- AGC 侧接下来做三件事 ------------------------------------------------

1) 申请发布证书（.cer）
   AGC → 证书、APP ID和Profile → 证书 → 新增证书 → 类型选「发布证书」
   → 上传上面的 .csr → 提交 → 下载 .cer
   配额：每个账号最多 3 个发布证书，有效期 3 年（实名认证开发者）。
   **发布证书是账号级的**，一张可以给名下所有应用用；Profile 才是每个应用一份。

2) 申请发布 Profile（.p7b）
   AGC → 证书、APP ID和Profile → Profile → 添加
   → 应用名称选本应用、类型选「发布」、证书选刚签发的发布证书
   → 在「申请权限」栏勾选受限权限 ohos.permission.READ_PASTEBOARD
     （必须在这里申请，否则审核驳回；PC/2in1 应用属于明确可申请的场景）
   → 提交 → 下载 .p7b，放到 $RELEASE_DIR/ 下
   （一个应用最多 100 个 Profile；Release 类型没有设备白名单）

3) 把三件材料写进 build-profile.json5（本文件在 .gitignore 里，不会进仓库）

   "signingConfigs": [
     { "name": "default", "type": "HarmonyOS", "material": { ...现有的调试那套... } },
     {
       "name": "release",
       "type": "HarmonyOS",
       "material": {
         "storePassword": "$BLOB",
         "certpath":      "$RELEASE_DIR/default_<你下载的证书名>.cer",
         "keyAlias":      "$ALIAS",
         "keyPassword":   "$BLOB",
         "profile":       "$RELEASE_DIR/default_<你下载的 profile 名>.p7b",
         "signAlg":       "SHA256withECDSA",
         "storeFile":     "$KEYSTORE"
       }
     }
   ],

   然后**新加一个 product**（hvigor 的 signingConfig 是按 product 绑定的，
   不随 buildMode 自动切换），并把模块 target 同时挂到两个 product 上：

   "products": [
     { "name": "default", "signingConfig": "default",
       "compatibleSdkVersion": "26.0.0(26)", "targetSdkVersion": "26.0.0(26)",
       "runtimeOS": "HarmonyOS" },
     { "name": "release", "signingConfig": "release",
       "compatibleSdkVersion": "26.0.0(26)", "targetSdkVersion": "26.0.0(26)",
       "runtimeOS": "HarmonyOS" }
   ],
   "modules": [ { "name": "entry", "srcPath": "./entry",
       "targets": [ { "name": "default", "applyToProducts": ["default", "release"] } ] } ]

   出正式包：
     PRODUCT=release BUILD_MODE=release sh scripts/build-gui-hap-ohos.sh
   产物在 entry/build/release/outputs/default/（不是 default/ 那层）。

--- 提交前先自检 -------------------------------------------------------

  sh scripts/check-signing-profile.py "$RELEASE_DIR/default_<profile 名>.p7b"

EOF
