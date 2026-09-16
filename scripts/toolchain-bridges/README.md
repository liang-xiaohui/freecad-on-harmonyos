# 工具链桥接壳（app_packing_tool / hap-sign-tool）

这两个 jar **不是**华为的打包/签名工具本体，而是 1~2 KB 的薄壳，作用是把 hvigor 的
「`java -jar` 某个 jar」调用**转发**到 OpenHarmony 官方 Public SDK 里同名的**本机可执行文件**。

## 为什么需要它

hvigor 找打包与签名工具时，写死的是 jar 文件名（`@ohos/hvigor-ohos-plugin/src/const/sdk-const.js`
与 `src/sdk/impl/sdk-toolchains-component.js`）：

| hvigor 取用点 | 期望的路径 |
| --- | --- |
| `getPackageToolPath()` | `<DEVECO_SDK_HOME>/toolchains/lib/app_packing_tool.jar` |
| `getVerifySignConfigToolPath()` | `<DEVECO_SDK_HOME>/toolchains/lib/hap-sign-tool.jar` |

而从 OpenHarmony 官方发布渠道下载的 **Public SDK**（`ohos-sdk-windows_linux-public_*.tar.gz`）
`toolchains/lib/` 里**没有这两个 jar**，只有等价的、本机可直接执行的文件
`ohos_packing_tool` 与 `hap-sign-tool`（实测都是 `aarch64` musl 原生 ELF；zip 名里的
`x64` 只是华为的命名习惯，别被它骗了）。

用 DevEco 自带的 HarmonyOS SDK 时不会遇到这问题（那里 jar 是真的）。用官方 Public SDK
或 CI 里拼装的 SDK，就必须自己补这层壳，否则 hvigor 直接报找不到打包工具、构建走不到签名。

## 语义（源码即真相，见同目录两个 `.java`）

两者结构一致：

1. 从环境变量取目标可执行文件：`OHOS_PACKING_TOOL` / `OHOS_HAP_SIGN_TOOL`，
   **缺失或为空即抛 `IllegalStateException`**，不做路径猜测；
2. 拼命令再执行，`inheritIO()`（否则工具的输出全被吞掉），`waitFor()` 后**把退出码原样透传**。

只有签名壳多一件事：`verify-profile -inFile <p7b> -outFile <json>` 需要**改写输出**。

- 原生可执行文件往 `-outFile` 写的是**裸 Profile JSON**（顶层就是 `bundle-info` 等键）；
- hvigor 读这个文件时取的是 `json5Obj.content["bundle-info"]`
  （`src/utils/validate/validate-util.js` 的 `getBundleNameFromP7b`），它期待
  `{"content": <裸 JSON>}` —— 华为官方 jar 正是这么写的，原生可执行文件不是；
- 于是壳里补一层包裹，且**幂等**：内容已经是 `{"content"` 开头就不再动。

环境变量由调用方导出，本工程是 `scripts/build-gui-hap-ohos.sh`：

```sh
DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$PROJECT_DIR/.ohos-sdk/26}"
OHOS_PACKING_TOOL="${OHOS_PACKING_TOOL:-$DEVECO_SDK_HOME/toolchains/lib/ohos_packing_tool}"
OHOS_HAP_SIGN_TOOL="${OHOS_HAP_SIGN_TOOL:-$DEVECO_SDK_HOME/toolchains/lib/hap-sign-tool}"
export DEVECO_SDK_HOME OHOS_PACKING_TOOL OHOS_HAP_SIGN_TOOL
```

## 安装

jar 由源码生成，不随仓库提交：

```sh
sh scripts/toolchain-bridges/build.sh          # 编到本目录 .build/
sh scripts/switch-ohos-sdk.sh <SDK 根目录>      # 装进 SDK 并把工程切过去（推荐）
```

`build.sh` 用 `--release 17` 编译，避免把字节码版本绑死在本机那个 JDK 26 上
（hvigor 端可能是自带 JBR 在跑）。

## 历史

2026-08-24 首次以反编译最小壳的形式落地在本机的 `.ohos-sdk/26/toolchains/lib/` 里，
**没有进仓库、也没有任何文字记录**；2026-09-16 换 Release SDK 时差点因此丢件。
本轮把行为逐条反编译确认后重写成源码入库，并加了 `scripts/switch-ohos-sdk.sh` 让它可复现。
重建产物用 `javap -p -c` 与原件逐条比对过，**字节码完全一致**。
