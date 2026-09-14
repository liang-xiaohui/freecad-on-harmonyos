# FreeCAD AI 工作台（freecad-ai）on OHOS

上游：<https://github.com/ghbalf/freecad-ai>（LGPL-2.1-or-later，图标 CC0-1.0）
归档版本：`0.27.0-alpha`（2026-09-14 快照）

## 为什么没有"编译"这一步

freecad-ai 是**纯 Python**，零外部依赖 —— 只用标准库（`urllib` / `json` /
`threading` / `ssl`）。它 `package.xml` 里声明的是：

```xml
<freecadmin>1.0</freecadmin>
<pythonmin>3.10</pythonmin>
```

与本项目的 FreeCAD 1.1.2 / CPython 3.11.4 兼容。因为它不含任何 C 扩展：

- 不参与 CMake 构建，没有 `BUILD_*` 开关（和 BIM 的区别是：BIM 在 FreeCAD
  源码树里有 `src/Mod/BIM` 可以镜像安装清单，freecad-ai 是第三方仓库，
  源码单独归档在 CPPLib）。
- 可以安全进入 rawfile —— `stage-gui-hap.sh` 禁止 native ELF 进
  `freecad-runtime.zip`（rawfile 里的 ELF 会丢失 HAP 代码签名），纯 Python
  天然合规。

所以集成工作实质只有三件：放进前缀、声明网络权限、重新打包。

## 集成链路

```
CPPLib/downloads/freecad-ai/freecad-ai-master-20260914.tar.gz   （下载归档）
        │  解压
        ▼
CPPLib/sources/freecad-ai/0.27.0-alpha/                          （源码归档）
        │  scripts/install-freecad-ai-module-ohos.sh
        ▼
CPPLib/install/freecad/1.1.2/ohos/arm64-v8a-gui-qt6/Mod/freecad-ai/
        │  scripts/stage-gui-hap.sh   →  zip Mod/ … → freecad-runtime.zip
        ▼
entry/src/main/resources/rawfile/freecad-runtime.zip
        │  scripts/build-gui-hap-ohos.sh
        ▼
entry-default-signed.hap  →  hdc install
        │  首次启动解压 rawfile
        ▼
设备的 freecad-home/Mod/freecad-ai/
```

一键入口：`scripts/rebuild-freecad-all-workbenches.sh` 的 **Step 4c/5**
（在 `cmake --install` 之后、`stage` 之前，和 BIM 的 Step 4b 并列）。
用 `FREECAD_BUILD_FREECAD_AI=OFF` 可跳过。

### 三个硬约束

| 约束 | 原因 | 违反后果 |
|---|---|---|
| 目录名必须精确为 `freecad-ai` | `Init.py` 里 `os.path.join(FreeCAD.getUserAppDataDir(), "Mod", "freecad-ai")` 是硬编码的，工作台靠它把自己挂进 `sys.path` | 工作台不出现，且无显式报错 |
| 目录内不得出现任何 `.so` | rawfile 里的 ELF 会丢失 HAP 代码签名 | `stage-gui-hap.sh` 主动报错退出；装到设备上会加载失败 |
| 必须声明 `ohos.permission.INTERNET` | 应用原本没有任何 `requestPermissions`，socket 层会在 connect 时被拒 | 每个请求都失败在一个裸 EPERM 上，很难和"端点不可达"区分 |

`INTERNET` 是 `system_grant` 权限，声明即生效，没有运行时弹窗。
`entry/src/main/module.json5` 里的 `usedScene.abilities` 必须写 `QAbility`
（GUI 入口），`reason` 指向 `entry/src/main/resources/base/element/string.json`
的 `reason_internet`。

## 已知限制：OHOS Python runtime 没有 `_ssl`

这是当前**唯一阻断"真正可用"**的问题，与 freecad-ai 本身无关。

实测证据（CPPLib Python 3.11.4 OHOS 产物）：

```sh
# lib-dynload 里有 _socket，没有 _ssl
$ ls install/python/3.11.4/ohos/arm64-v8a/lib/python3.11/lib-dynload/ | grep -E '^(ssl|_ssl|_socket)'
_socket.cpython-311-aarch64-linux-ohos.so
# libpython3.11.so 的 NEEDED 只有 libc.so，没有 libssl/libcrypto
$ readelf -dW install/python/3.11.4/ohos/arm64-v8a/lib/libpython3.11.so.1.0 | grep NEEDED
  Shared library: [libc.so]
```

`_socket.so` 只依赖 `libpython3.11.so.1.0` + `libc.so`（自包含），所以
**TCP/明文 HTTP 可用**；`ssl.py` 虽然存在于 stdlib，但它 `import _ssl`，
拿不到扩展就会 `ImportError`。

freecad-ai 对此**有防御** —— `freecad_ai/llm/client.py`：

```python
try:
    import ssl
    _HAS_SSL = True
except ImportError:
    _HAS_SSL = False
```

因此：工作台能加载、能打开聊天面板、能配置 provider，但 `https://` 端点
会在 `urlopen` 阶段失败。**可用路径是明文 `http://` 端点**（自建反向代理、
内网网关等）。

要接云端 HTTPS provider，需要给 OHOS Python 补 `_ssl`。基础条件已具备：
`CPPLib/install/openssl/3.5.7/ohos/arm64-v8a/` 已有 OpenSSL 的 OHOS 构建。
两条路线：

1. **重配 Python runtime**（正统）：`configure --with-openssl=$OPENSSL_PREFIX`
   后重建 runtime，`_ssl` / `_hashopenssl` 一起出来。代价是重编整个 Python。
2. **单独编 `_ssl.c`**（轻量）：手工编译 `Modules/_ssl.c` 为
   `_ssl.cpython-311-aarch64-linux-ohos.so`，链 `libssl`/`libcrypto`。
   需要 Python 头 + OpenSSL 头，`_hashopenssl`（`hashlib` 的 OpenSSL 后端，
   可选）同理。

补完后 `_ssl*.so` 必须走 **HAP `libs/`**（native 扩展不能从可写的
`freecad-home` 树加载，见 `stage-gui-hap.sh` 的相关注释），不能进 rawfile。

## 其它需要注意的点

- **Qt 绑定**：`freecad_ai/ui/compat.py` 优先 `PySide6`，回退 `PySide2`。
  本项目是 PySide6，直接命中。
- **无平台特定代码**：全仓库没有 `sys.platform` / `winreg` / `darwin` 分支。
- **MCP 是可选路径**：`freecad_ai/mcp/client.py` 顶层 `import ssl`（无
  try/except），但它只被 `InitGui.py` 和 `chat_widget.py` 里的**函数内
  延迟导入**触达，所以无 `ssl` 时不会阻塞工作台注册和聊天面板。
  但真要用 MCP / 视觉回退会踩到它。
- **`subprocess` 用量很小**：`llm/client.py` 只有一处（约 line 222），
  与 provider 探测相关。OHOS 的 fork 限制可能影响该路径，但不影响主流程。
- **首次启动会慢**：rawfile 变了就要重新解压（`freecad-runtime.zip` 本次
  约 61.8 MB），加 `Mod/freecad-ai` 后签名 HAP 从 494,484,645 B 增至
  495,332,517 B。

## 复现步骤

```sh
# 1. 取源码（codeload 通道；github.com:443 在本网络下不稳定）
curl -sSL -o fai.tar.gz \
  https://codeload.github.com/ghbalf/freecad-ai/tar.gz/refs/heads/master
mkdir -p "$CPP_LIB_ROOT/sources/freecad-ai/0.27.0-alpha"
tar -xzf fai.tar.gz -C "$CPP_LIB_ROOT/sources/freecad-ai/0.27.0-alpha" --strip-components=1

# 2. 装进安装前缀
sh scripts/install-freecad-ai-module-ohos.sh

# 3. 重新打包（stage 会把 Mod/ 带进 rawfile）
sh scripts/stage-gui-hap.sh
sh scripts/build-gui-hap-ohos.sh

# 4. 装到设备
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

## 设备侧验证

`freecad-home/` 是应用沙箱内的可写树，权威路径：

```
/data/storage/el2/base/haps/entry/files/freecad-home/Mod/freecad-ai/
```

验收判据：

1. 应用启动后 Report 面板 **无** `blocked import of module 'freecad_ai…'`
   一类的报错（这是纯 Python 模块缺失时的典型症状）。
2. 工作台下拉列表里出现 **FreeCAD AI**。
3. 能打开聊天面板（Settings 齿轮可见）。

注意：设备锁屏时 `aa start` 会返回成功但窗口不附着
（`aa dump -l` 里 `window attached #0`），截图只会拿到锁屏壁纸轮播 ——
这时**不要**把"看不到工作台"当成集成失败。
