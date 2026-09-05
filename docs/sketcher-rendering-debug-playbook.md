# Sketcher/3D 可视化问题调试手册（2026-09）

本文沉淀 2026-08 底至 2026-09-05 期间在 OHOS（arm64，Qt6 QPA + gl4es + Coin）
上修复 FreeCAD GUI 一系列可视化问题的根因链、补丁位置与调试方法论。
涉及提交（origin/main，时间序）：

| 提交 | 问题 |
| --- | --- |
| `5a2378a` | Sketcher 线型/端点/约束图标渲染异常（9 个 gl4es 补丁） |
| `b8ffab3` | 画线时跟随光标的尺寸/角度输入框（OVP）不显示 |
| `6c96c8d` | 在实体上草绘时端点/约束图标被实体遮挡 |
| `6f268af` | Pad 等 PartDesign 对话框弹出 `Exception(bad any cast)` |
| 半透明回归修复 | Pad 预览/草绘填充等一切半透明绘制失效（诊断补丁自伤） |
| MakeInternals 默认开启 | 草绘闭合轮廓无半透明蓝色填充 |

---

## 1. Sketcher 线型/端点/约束图标（5a2378a）

症状：草绘编辑态线条细灰、无端点标记、约束图标黑块且位置错误。
全部修复在 `patches/gl4es-81547d9/`，根因四条：

1. **纹理命名空间混用**（`ohos-raster-texture-name-restore.patch`、
   `ohos-raster-blit-native-texture.patch`）：`raster_to_texture()` 保存的是原生
   `glname`，恢复时却走公开名的 `gl4es_glBindTexture()`；`gl4es_blitTexture()`
   直接走 GLES 绑定，也需要原生名。共享 Qt/GL4ES 上下文里两个命名空间会发散。
2. **光栅位置被错误裁剪**（`ohos-rasterpos-clip-fix.patch`）：上游
   `gl4es_glRasterPos3f()` 对 NDC `z<0` 一律丢弃且不做 `w` 除法；Coin 传的就是负 z，
   约半数标记/图标位置被拒，`rPos` 残留旧值，画到错误位置。修复为 GL 裁剪体
   `|ndc|<=1` + 正确的 `w` 除法。
3. **黑块约束图标**（`ohos-blit-color-alpha.patch` +
   `ohos-blit-force-texture-params.patch`，后者是决定性的）：GLES2 blit 路径强制关混合、
   着色器无 `discard`，且 gl4es 在 sampler 仿真里记录的纹理参数只在 FPE 绘制路径的
   `realize_1texture()` 里应用——blit 路径直接绑原生纹理，从不触发，导致图标纹理保持
   mipmap MIN_FILTER 但只有 level 0，GLES2 下不完整纹理采样为 `(0,0,0,1)` 即黑块。
   修复：blit 后用原生调用强制 `NEAREST`/`CLAMP_TO_EDGE`，BLIT_COLOR 走 alpha 着色器。
4. **active texture unit 失同步**（`ohos-blit-force-texture-unit0.patch`）：
   `gleshard->active` 只是缓存，Qt 会在共享上下文里绕过 gl4es 切换原生单元。

附带：`ohos-getter-line-width-range.patch`（`GL_LINE_WIDTH_RANGE` 是 GL1 枚举，
GLES2 下触发 `GL_INVALID_ENUM` 并污染 Coin 的线宽钳制）映射到
`GL_ALIASED_LINE_WIDTH_RANGE`；`ohos-linewidth-zero-clamp.patch` 把 `<1` 的线宽钳到 1。

## 2. OVP 输入框不显示（b8ffab3）

画线时跟随光标的长度/角度输入框是真正的 `QuantitySpinBox` widget，合成在 raster
控件层；旁边的尺寸线/箭头才是 GL 部分（`SoDatumLabel`）。
`patches/freecad-1.1.2/ohos-quarter-stack-on-top.patch` 曾给 QuarterWidget 的
QOpenGLWidget 设置 `Qt::WA_AlwaysStackOnTop`，导致 OHOS QPA 合成器把 3D 视口纹理
压在所有 raster 控件之上，OVP 框被盖住。当初加它是为修白视口，而白视口真正原因是
graphics-view 背景通道画进 FBO 的顺序问题，已由 `ohos-quarter-paint-order.patch` 修复。
**不要重新加回该属性**（补丁里有 `WA_AlwaysStackOnTop was tried here` 标记，
`prepare-freecad-source.sh` 会检测）。

## 3. 端点/图标被后绘制的实体遮挡（6c96c8d）

`ohos-raster-blit-depth.patch`：光栅 blit 原来强制关深度测试、关深度写入、着色器
硬编码 NDC `z=0`。场景顺序中实体在草绘之后绘制时，其面片会覆盖先画的标记
（标记不测深度也不写深度；线条幸存是因为线条在真实 z 写深度，polygon-offset 面片
在 `LEQUAL` 测试下输给线条）。修复：光栅路径把光栅位置的 NDC z 传给 blit
（`glstate->raster.blit_*`，blit 着色器 `uZ` uniform），并遵循调用者的深度测试/
深度掩码状态；内部 blit（FBO 拷贝、纹素回读）保持原有无深度行为。
被实体挡住的几何保持遮挡，与桌面版一致。

## 3.5. 鼠标坐标文字产生大块纹理（2026-09-05）

症状：在草绘编辑态画完矩形后移动鼠标，视口出现随鼠标变化的大块黑白字形纹理。
触发链为 `EditModeCoinManager::setPositionText()` → `SoText2` → `glBitmap` →
GL4ES bitmap batching；坐标轴交点的原点标记本身尺寸和绘制行为正常。

根因：GL4ES 会把不同 raster depth 的位图合入同一批次，却在
`bitmap_flush()` 时用当时的 `rPos.z` 绘制整批。静态原点标记、动态鼠标坐标文字和
后续 raster position 因而组成一个跨越视口的大纹理，并使用无关深度绘制。
`ohos-bitmap-batch-depth.patch` 为批次保存创建时的 z；新位图深度变化时先刷新，
刷新时使用保存的批次深度。同一深度的文字 glyph 仍会正常合批。该补丁应在
`ohos-raster-blit-depth.patch` 之后应用。

修复前依次排除了 blit 纹理重绑、shader/VBO/vertex attribute 恢复和上传前强制
texture unit 0 三个假设。2026-09-05 在真机上确认大块纹理消失，原点标记和鼠标
坐标文字均正常。

## 4. Pad 对话框 bad any cast（6f268af）

`patches/freecad-1.1.2/ohos-serviceprovider-cross-dso.patch`：
libc++ 的 `std::any` 跨共享库比较 typeinfo 只按地址；OHOS 上各模块以 `RTLD_LOCAL`
加载，同名类型的 typeinfo 在不同 DSO 里地址不同，`any_cast` 必炸。
修复：ServiceProvider 的负载从 `std::any` 改为 `void*`。

## 5. 半透明全失效：诊断插桩自伤（教训最深的一条）

症状：Pad 预览不透明、草绘填充不出现等一切半透明失效；普通不透明绘制正常。

根因：诊断补丁 `ohos-sketch-render-diagnostics.patch` 曾在 `drawing.c` 顶部加宏：

```c
#define gles_glDrawElements(...) freecad_sketch_diag_draw_elements(...)
```

`drawing.c` 里的 `gles_glDrawElements` 原本经 `LOAD_GLES_FPE` 绑定到 **FPE 入口**，
被宏换成诊断包装后直接调了**原生 GLES** 函数，完全绕过 `fpe_glDrawElements` 里的
`realize_glenv()`——混合/材质/逐绘制状态应用全部丢失。矩阵 uniform 恰好新鲜，
所以静态画面看起来正常，排查时极具迷惑性。

**守则：诊断插桩不得改变被测行为。** 在 gl4es 里尤其要注意同名符号经
`LOAD_GLES` / `LOAD_GLES_FPE` 绑定后的真实指向。当前补丁已删除该宏劫持，
`drawing.c` 留有 NOTE 注释说明原因；FPE 三角形级探针改为直接加在
`fpe.c` 内部（`fpe-tris`，仍受 `FREECAD_OHOS_SKETCH_DIAG` 保护）。

## 6. 草绘闭合轮廓填充（MakeInternals）

闭合轮廓的半透明蓝色填充（`SoSketchFaces`，仅非编辑态显示）链路：

```
SketchObject::execute → buildInternals(闭合线框→内部面) → InternalShape 属性
  → ViewProviderSketch::updateData(InternalShape) → setupCoinGeometry → pcSketchFaces
  → 颜色/透明度来自 SketchFaceColor 参数（默认 0x54abff40，经 ShapeAppearance）
```

前提：首选项 `BaseApp/Preferences/Mod/Sketcher/MakeInternals` 为真
（上游默认 **false**，对应首选项对话框"Generate internal faces"复选框）。
填充显示还需 `pcSketchFacesToggle->on == Visibility`。

**OHOS 上的实际根因（2026-09-04 探针确认）**：设备参数库里
`MakeInternals` 被显式存成了 `false`（探针：`paramExists=1 valDef0=0`），
上游默认值本来就是 `false`，且当时 Preferences 对话框会闪退（见第 7 节），
用户无法通过 UI 打开它。在 `harmonyos_startup.py` 启动脚本里 `SetBool`
种子也未生效（该脚本以位置参数传给 FreeCAD main，执行时机/执行与否不可靠，
已撤回该尝试）。

最终修复（可改，不是硬编码）：

1. `patches/freecad-1.1.2/ohos-sketch-make-internals.patch`：
   `SketchObject::setupObject()` 的默认值从 `GetBool("MakeInternals", false)`
   改为 `GetBool("MakeInternals", true)`——新建草绘默认生成内部面，
   用户仍可通过首选项关闭。
2. `entry/src/main/cpp/acceptance.cpp` 的 `dropStaleBoolPreferences()`：
   启动时（FreeCAD 初始化前）检查 `freecad-home/user.cfg`，若存在历史遗留的
   显式 `MakeInternals=false` 条目则删除该行——否则存量的 false 会盖过新默认值。
   删除后该参数重新回落到默认值，之后用户的显式选择会被正常保留。
3. `patches/freecad-1.1.2/ohos-sketcher-settings-internal-faces-default.patch`
   （2026-09-04 晚补上）：**首选项对话框的复选框默认值也必须同步**。
   PrefCheckBox 在参数缺失时回落到 .ui 里的 `checked` 默认值（原为未勾选），
   用户只要在 Preferences 点一次 OK，就会把 false 重新写回参数库，
   盖过运行期默认值——表现为"默认开启莫名失效，要手动开"。.ui 默认值
   改为勾选后，UI 与运行期默认值一致。

注意 `setupObject()` 只在新建对象时调用；已保存文档里的旧草绘仍带着
存档的 `MakeInternals=false`，需要在属性面板手动打开（或重新创建）。

同批改动：3D 视图的坐标轴十字默认开启
（`patches/freecad-1.1.2/ohos-axis-cross-default.patch`，
`View3DSettings`/`CommandDoc` 两处 `GetBool("ShowAxisCross", ...)` 默认值
false→true，仍可在首选项关闭）；历史存量的显式 false 由同一个
user.cfg 迁移（`dropStaleBoolPreferences`，带一次性标记
`freecad-home/.prefs-migrated-*`，不会覆盖用户之后的选择）。

**通用教训**：OHOS 上任何"默认值从关改开"的参数，要三处一起改——
代码里的 GetBool 默认值、首选项 .ui 的控件默认值、以及存量 user.cfg 的
一次性迁移，缺一个都会被参数系统"顶回去"。

## 6.5 保存文档报 "Failed to open file"（2026-09-04 晚）

症状：保存/另存文档时弹 "Failed to open file"。

根因：OHOS 系统文件选择器（DocumentViewPicker）返回的是按 URI 授权的
`/docs/...` 路径；授权是**按文件**的，目录不可写。FreeCAD 的
`App::Document::saveToFile()` 默认开启 BackupPolicy：先写 `<name>.<uuid>`
临时文件再 rename——在 /docs 目录里创建这个临时兄弟文件直接失败。

修复（`patches/freecad-1.1.2/ohos-save-docs-path-direct.patch`）：
目标路径以 `/docs/` 开头时跳过临时文件策略，直接写目标文件
（选择器在 save 时已创建该文件并授权）。代价：此类保存不产生 .FCBak 备份。

## 7. Preferences 对话框崩溃（2026-09-04 定位修复）

症状：打开"编辑→首选项"后操作一会儿（悬停出 tooltip、点 Number format
下拉框可 100% 复现）必崩，SIGABRT 且无任何有效日志。

定位链条：

1. DFX 的崩溃报告写在 `/data/log/faultlog`，hdc shell 无权限读取。
2. 在 `acceptance.cpp` 加了两个常驻诊断探针：`std::set_terminate`（打印未捕获
   异常类型和 what()）和 SIGABRT/SIGSEGV/SIGBUS/SIGILL 的
   `_Unwind_Backtrace` + `dladdr` 回溯（直接打 hilog，帧带库名+符号+偏移）。
3. 回溯显示调用栈为 `QMessageLogger::fatal ← libqohos
   QOhosView::tryCreateWindowProxyIfNeeded ← QOhosView::showImmediate`，随后
   FreeCAD 的 `messageHandler` 对 QtFatalMsg 主动 `abort()`（上游行为，
   "deliberately core dump"）。qFatal 的消息文本被 messageHandler 吃掉，
   又在 `Application.cpp` 给 fatal 消息加了 hilog 镜像（永久保留，见
   `patches/freecad-1.1.2/ohos-gui-fatal-hilog.patch`），拿到原文
   "Failed to determine valid parent for this window."。
4. 用 llvm-objdump 反汇编崩溃点确认：qFatal 后的下一条指令是
   `__stack_chk_fail`（编译器认为 fatal 可能返回），曾误导方向。

根因：QPA `qohosview.cpp` 的 SubWindow 创建路径里，当逻辑父窗口是
**嵌入式对话框**（EmbeddedWindow，本移植里 FreeCAD 对话框都嵌入主窗口）时，
宿主窗口沿**弹窗自身**的视图祖先链解析（`ancestorViewWithWindowOrNull()`），
而下拉框/tooltip 这类弹窗的视图父链是空的 → 解析失败 → qFatal。
修复（`patches/qt-6.8-ohos/14-popup-parent-of-embedded-dialog.patch`）：
改为沿**目标父视图**（对话框）的祖先链解析宿主窗口。

## 8. 通知洪泛（"打开 Preferences 弹一堆提示"）

现象：进 Preferences 后通知区被几十条 "Numeric mode unsupported in the
posix collation implementation" / "Case insensitive sorting unsupported..."
刷屏，最后一条 "Too many opened non-intrusive notifications. Notifications
are being omitted!"。

根因：OHOS 的 Qt 构建没有 ICU，QCollator 退化为 POSIX 实现；该实现不支持
numeric/case-insensitive 排序，**每次排序都 qWarning**。FreeCAD 的
`messageHandler` 把 Qt warning 转成 `Base::Console().warning`，GUI 再把
warning 弹成用户可见通知 → 洪泛。修复
（`patches/qt-6.8-ohos/13-collator-warn-once.patch`）：每条告警每进程只发一次。

## 8.5 NaviCube 与角落坐标轴缺失/面片深灰（2026-09-04 晚）

症状：3D 视图右上角的导航立方体和右下角的坐标系指示器（feedback axis cross）
完全不显示；启用后立方体六个面是深灰色、无 "Front/Top/..." 文字。

两个叠加原因：

1. **移植期被整体禁用**：
   `View3DInventorViewer` 里 `drawAxisCross()` 和 `naviCube->drawNaviCube()`
   的四处调用点被 `#if !defined(FREECAD_OHOS)` 关掉（早期怕 legacy
   immediate-mode GL 出问题）。gl4es 的 FPE 已覆盖这些调用
   （glPushAttrib/矩阵栈/glBegin/glEnd），直接恢复
   （`patches/freecad-1.1.2/ohos-enable-navicube-axiscross.patch`）。
2. **QOpenGLTexture 与 gl4es 纹理命名空间不兼容**（面片深灰的根因）：
   NaviCube 的面标签纹理用 Qt 的 `QOpenGLTexture` 创建——Qt 用自己的函数表
   直接调原生 GLES，纹理不在 gl4es 的纹理表里。绘制时
   `glBindTexture(GL_TEXTURE_2D, textureId)` 走 gl4es 的
   `gl4es_getTexture()`：查不到该名字就**新建一个空的同名记录**，draw 时绑定
   的是这个新空纹理 → 采样 `(0,0,0,1)` → 标签 quad 整面盖成深色、文字不可见。
   修复（`patches/freecad-1.1.2/ohos-navicube-raw-gl-labels.patch`）：
   标签纹理改用裸 GL 调用创建（glGenTextures/glTexImage2D，全程走 gl4es），
   且不用 mipmap（GLES2 不完整纹理即黑的坑见第 1 节）。

注意：NaviCube 的拾取用 Qt 的 `QOpenGLFramebufferObject`（同属 Qt 原生
路径，未验证），如果点击立方体切换视角不正常，先查这条 FBO 混用路径。

## 9. 调试方法论

- **单一变量迭代**：每次构建只改一处，HAP/libGL 的 sha256 逐轮记录到
  `/storage/Users/currentUser/codex-freecad-artifacts/sketch-fix-20260903/`。
- **SKETCH_DIAG 探针**（gl4es，hilog tag `gl4es`）：逐绘制状态转储、光栅位置
  接受/拒绝日志、图标位图上传校验和（证明 RGBA 内容完好到达 GL4ES）、blit 时
  原生绑定/单元/混合查询、scratch-FBO 回读 blit 纹理内容（证明上传成功）、
  blit 后帧缓冲回读（证明输出是黑的）。每个假设靠一次单值改动证实或证伪。
- **FreeCAD/Coin 侧探针**：`Base::Console` 输出在 hilog 不可见；探针用
  `dlopen("libhilog_ndk.z.so")` + `dlsym("OH_LOG_Print")`（签名
  `int(int,int,unsigned,const char*,const char*,...)`，LOG_APP=0 / LOG_INFO=4 /
  domain 0xFC00 / tag `FreeCADProbe`）。
- **渲染路径分离判定**：光标自动约束提示（Qt cursor pixmap）、持久约束图标
  （`SoImage`→glDrawPixels）、端点（`SoMarkerSet`→glBitmap）、几何线（FPE 颜色数组）、
  面填充（`SoBrepFaceSet`/`SoSketchFaces`→FPE triangles）是**五条独立路径**，
  必须分别做 pass/fail 判定，不能互相推断。
- **大日志处理**：采集器输出超千万行时按 PID 过滤 + tail；操作前先问清用户
  屏幕上的文档/视图状态，否则日志无法对号入座。
- **补丁序列机器验证**：任何源码树改动后重新生成补丁，验证
  `pristine tarball + 补丁序列 == 工作源码树` 逐字节一致（gl4es 排除 `lib/` 构建目录）。

## 10. 环境坑（本轮新遇到）

- ~~Preferences 对话框在 OHOS 上闪退~~（2026-09-04 已修复，见第 7 节）。
  教训：在修复前，"让用户去首选项里勾一下"的解法不可行，涉及首选项的功能
  必须用代码默认值保证；且早期版本经 Preferences 的 OK 按钮把一批
  "默认关"的值显式写进了 user.cfg，后续改默认值时必须配套一次性迁移
  （`dropStaleBoolPreferences`）。
- **`harmonyos_startup.py` 启动脚本机制不可靠**：脚本由
  `QAbilityStage.ets` 作为位置参数传给 FreeCAD main 执行；本轮在其中
  `SetBool('MakeInternals', True)` 未生效（脚本是否执行、何时执行不可见），
  已撤回。后续若要依赖该脚本，需先验证它真的被运行。
- HDC 私钥若被换成加密格式（`BEGIN ENCRYPTED PRIVATE KEY`），`tconn` 会在 RSA
  握手阶段失败：`read prikey from ~/.harmony/hdckey failed` / `Auth failed`。
  处置见 AGENTS.md：核对候选明文密钥派生公钥与 `hdckey.pub` 的 sha256 一致后才替换，
  旧密钥备份到产物目录，绝不把私钥内容打进日志。（2026-09-04 再次复发，
  按此流程用 `hdckey_new` 恢复。）
- 本机 `/tmp` 可能变只读：构建脚本日志一律重定向到
  `/storage/Users/currentUser/codex-freecad-artifacts/` 下。
