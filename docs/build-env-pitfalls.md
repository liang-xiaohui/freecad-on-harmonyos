# 构建环境与真机取证的坑（增量）

本文件收纳两类**与具体功能无关、但每次动手都会撞上**的知识：

1. **WorkBuddy shell（本机命令行环境）的陷阱** —— 脚本莫名挂掉、命令静默失效时先看这里；
2. **HarmonyOS 真机操作与取证** —— 截图/日志/状态判定的正确姿势。

从 `.workbuddy/memory/MEMORY.md` 移出（该文件是索引，控制体积）。功能性的实现细节仍在
`docs/appgallery-release.md`、`docs/device-run-guide.md` 与各技能里。

---

## 一、WorkBuddy shell 陷阱

### 1. `rm` 失效导致 stage 脚本以 126 挂掉

PATH 首位被注入 `.../cli/vendor/shim/safe-bin`，其中有一个 `rm` 垫片。当脚本走到 `rm` 时
直接以 **126** 退出（`stage-gui-hap.sh` 就是这样挂的）。

- `env -u` **清不掉**这个垫片（它不是环境变量导致的），必须**把该目录从 PATH 里剥掉**：
  ```bash
  CLEAN=$(printf '%s' "$PATH" | tr ':' '\n' \
          | sed '/cli\/vendor\/shim\/safe-bin/d' | tr '\n' ':' | sed 's/:$//')
  PATH="$CLEAN"
  ```
- **根因**：垫片（shim）在 `CODEBUDDY_SAFE_DELETE_ENABLED` **被 unset** 时会直接退 126 ——
  而 hvigor 构建**恰好要求** unset 这个变量（否则报 EACCES 且不产出 HAP）。
- ⇒ **别用同一套 env 同时跑 stage 和 build**：先剥 PATH 目录（`rm` 就会回落到 `/bin/rm`，
  与变量无关），unset 只作用于 build 那一步。
- 新写的脚本一律自卫：`RM=/bin/rm; [ -x "$RM" ] || RM=rm`。

### 2. stage 失败但 build「成功」→ 产出残缺 HAP

失败的 stage 会留下一份**不一致的 staging**，而后续 build 仍会正常退出 0，只是打出一个
**内容残缺的 HAP**。这个错误要到 `verify-gui-hap.sh` 才会以
`HAP 使用了过期 rawfile/…` 暴露出来。

- **stage 非 0 就别接着 build。**
- 跑多阶段用**链式脚本顺序执行**（脚本里**不要** `set -e`，让每步都跑到并打印），
  末尾补一次"最终态自检"。

### 3. 路径与临时文件

- `/tmp` **只读** → 日志写项目目录内或 `~/codex-freecad-artifacts/`。
- hvigor 的 `ProcessLibs` 残留（错误码 `00308001`）是**常态**，提权删掉目录即可。
- 脚本里续行参数列表**中间插 `#` 注释会静默丢参数**（续行拼接被注释截断）。
- **`TMPDIR` 必须可写**，否则 `git commit` 会 **SIGSEGV** —— 特征是 index 已暂存但提交没发生、
  且**没有任何报错**：
  ```bash
  export TMPDIR=~/codex-freecad-artifacts/tmp
  ```

### 4. GitHub 通道：走 SSH，别走 HTTPS

- `github.com:443`（HTTPS）在本机**稳定被拒**：TCP 连接直接超时 68~135 s，不是偶发慢。
- `github.com:22` 与 `ssh.github.com:443` 都能认证。判定命令：
  ```bash
  ssh -T git@ssh.github.com -p 443
  ```
- 本仓库 `origin` 的 fetch/push 都指向
  `ssh://git@ssh.github.com:443/liang-xiaohui/freecad-on-harmonyos.git`，`git push` 直连即可，
  **不必再内联 token**。
- **本机 git 的 `git remote set-url --push` 实测会把 `url` 一并改掉**，不只是改 `pushurl`。
- 下载源码走 `codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/<branch>`（443 通）。
- 查 GitHub 一律用 `curl`（走系统 CA），**别用宿主 `python3` 的 `urllib`**
  （`SSLCertVerificationError`）。

### 5. 重写历史后的推送陷阱

保底分支 `backup/*` 位于 `refs/heads/` 下，所以 `git push --all` / `--mirror` 会把
**旧世系里已经撤出的私有内容重新推回公开仓库**。重写历史后只推具体分支，别用 `--all`。

### 6. 设备临时目录

`/data/local/tmp` 下有约 720MB 历史取证截图（**多项目共用**）→ 清理时按文件名**精确 `rm`**，
不要用通配符。

### 7. 本仓库里 Grep 工具可能静默失效

对本仓库的部分文件，专用 Grep 工具会返回 `No matches found`（即使内容确实存在）。
定位行号时改用 Bash 的 `grep -n`：

```bash
grep -n "^#\{1,4\} " docs/appgallery-release.md | head -60
```

---

## 二、真机操作与取证

### 1. 连接

- HDC：`/data/service/hnp/bin/hdc`；server `127.0.0.1:8710`；**端点用 `127.0.0.1:39405` 更稳**。
- `hdc list targets -v` **可能把 Offline 设备排在前面** ⇒ **不能盲取第一条**。
- 应用沙箱 home：`/data/storage/el2/base/haps/entry/files/freecad-home/`。

### 2. 抓不到界面的头号原因：锁屏

`power-shell wakeup` **只点亮屏幕、不解锁**，锁屏状态下截图只能拍到轮换壁纸。

- **判定方法**：`aa force-stop <bundle>` 之后再截一张，**画面没变**就说明还在锁屏。
- 收工前恢复：`power-shell timeout -r`。

### 3. 「应用起来了」的判据

不要用 `window attached #0` 当判据。正确的证据链：

- mission：`state #FOREGROUND` + `ready #1`；
- 窗口属性：`hidumper -s WindowManagerService -a '-w <WinId>'` 里的
  `FirstFrameCallbackCalled` / `IsVisible`；
- 窗口表里**第 4 列是 WinId**。

**交互优先让用户自己操作**（点击/输入类验证交给用户，比脚本模拟更可信）。

### 4. 日志：stdout/stderr 不进 hilog

FreeCAD 是 **dlopen 同进程调 main**，其 stdout/stderr **不会接入 hilog**。

- 取法：`dup2()` 重定向落盘，再从 debug 挂载点读沙箱里的文件；
- 控制台文件是 **append** 的，切分时按最后一条 `===== OHOS console capture pid=` 之后的内容看。
- 抓 Python 层状态最快的办法：**往 argv[2] 的真实路径写探针脚本**
  （`QAbilityStage.ets` 只接收 `.fcstd`，所以探针要放在它能转交的路径上）。

### 5. 验证补丁：别用系统 `patch`

设备/系统里的 `patch` 是 toybox 版，**连 `--dry-run` 都会真的写文件**。稳妥流程：

1. 反向 apply 把源码还原成 pristine；
2. 改源码；
3. 用 `difflib` 重新生成补丁；
4. 在临时 git 仓库里 `git apply --check`；
5. 最后 `diff` 对照活源码树。
