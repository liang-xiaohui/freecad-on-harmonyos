# 给 FPA 的品牌授权询问信（草稿 · 2026-09-18）

背景见 `docs/appgallery-release.md` 第 7.6 节：AGC 以"应用与「FreeCAD」应用的名称相同、
图标相似，但未提供相关授权或商标权属证明"驳回，要求**要么删掉相似内容，要么提供授权/权属证明**。

## 怎么用

| 项 | 说明 |
| --- | --- |
| 收件人 | `fpa@freecad.org`（FPA 理事会，见 `fpa.freecad.org` 的 Contact 一节） |
| 备选渠道 | FreeCAD 论坛给理事会成员发私信（`forum.freecad.org`，成员名单在 `fpa.freecad.org/handbook/people/roster.html`） |
| 期望周期 | **按周算，别按天算**。理事会志愿者开会投票，没有 SLA。发出后同步走 A 路（改名+换图标），不要等 |
| 期望结果 | 拿到能给 AGC 用的**同意函**的概率约 **25%（纯邮件）~ 35%（加论坛公开帖）**，依据见 `appgallery-release.md` 7.6。**注意冲突对象已确认为 FPA 商标本身**（AppGallery 无同名应用），所以这份文件一旦到手，效力是完整的。即便不批，一封信的真实价值也是拿到回信：① 确认"改名 + 保留'基于 FreeCAD'的署名"就是我们该走的路；② 确认这类衍生版是否需要在某处登记，以免被社区当成仿冒 |
| 为什么要发 | wiki 明确说社区会主动发现并举报 "rebranded versions"。我们把名字改成不含 FreeCAD 的样子继续分发，**更容易被误判成仿冒**。主动写信留痕是保护自己；同时这是唯一能探明"FPA 是否愿意把鸿蒙移植接纳为官方项目"的方式 |
| 升级阶梯 | **D0 邮件 → D7 若无回复，去 `forum.freecad.org` 发一条公开帖问同样的问题 → D14 止损**。邮件容易沉；公开帖通常几天内就有社区或理事回话，而且公开留痕能防止日后被当成仿冒者。**别在 D0 就公开发帖**——先给理事会一个私下答复的机会 |
| 时机 | 与 A 路**并行**：D0 发出，同时按 A 动工（重画图标、改文案）。给到 **D14** 止损线 —— 期间若回信同意就用原名提交，否则用新名提交。名称一年只能改 2 次，等不起太久 |

正文在下面代码块里，**整块复制**即可。

---

```text
Subject: Permission to distribute a community port of FreeCAD for HarmonyOS PC (name and logo use)

Dear FPA board,

I am an individual developer (Xiaohui Liang, Shanghai, China) and I have built an
unofficial community port of FreeCAD 1.1.2 for HarmonyOS / OpenHarmony PC
(arm64-v8a, Qt 6.8 GUI, native OpenGL ES). It is a genuine build of upstream
FreeCAD 1.1.2 plus HarmonyOS-specific patches (Qt platform plugin, GLES rendering,
app sandbox paths); no third-party fork of the CAD core and no proprietary
components.

Full source, including every patch, is public here:
https://github.com/liang-xiaohui/freecad-on-harmonyos
The project is distributed under LGPL-2.1, with the license texts of all
components shipped in the package.

Distribution terms: completely free, no ads, no in-app purchases, no telemetry,
no self-hosted service. Inside the app and in the store listing, users are told
explicitly that this is an unofficial community port, that it is not affiliated
with, sponsored by, or authorized by the FreeCAD project or the FPA, that it uses
FreeCAD, and that FreeCAD itself is LGPL and freely available from freecad.org.

Where I need your help. I am trying to publish it on Huawei AppGallery (the
HarmonyOS PC store). The submission was rejected with this finding:

  "The app has the same name as the 'FreeCAD' application and a similar icon,
   but no authorization or proof of trademark ownership was provided."

The store asks me to either remove the similar content, or provide a written
authorization or proof that I hold the rights. I searched AppGallery myself, and
there is no application named "FreeCAD" published there, so I take the objection
to be about the FreeCAD name and logo themselves - the trademark held by the FPA -
rather than about a conflict with another publisher. That is exactly why I am
asking you rather than assuming.

I have also read two documents that seem to already answer most of this, and I
would rather follow them than argue with the store. Your wiki "Branding" page says
third parties may build their own applications on top of FreeCAD - including a
completely redesigned one - and its warning is aimed specifically at renaming
FreeCAD into a closed-source product. The "License" page says derivatives that are
not open-source are prohibited by the LGPL, which implies an open-source renamed
port is acceptable. This port is open-source, and it already tells users that it
is based on FreeCAD.

One thing I will do regardless, and I do not need an answer for: I am redrawing the
app icon from scratch. The current icon reuses the official symbol from the
upstream source tree; having read the brand guidelines I accept that the symbol
must not be used as a product identity, so the new icon will not reuse any part of
its shape or its colour palette. That half of the store's finding is already being
fixed on my side.

That leaves only the name, which is the actual question:

1. Would the FPA be willing for this port to keep the word "FreeCAD" in its name,
   in a form that clearly references the upstream project - for example
   "FreeCAD for HarmonyOS"? If yes, a short store-facing statement confirming the
   authorization would be enough (I am not asking for a trademark licence
   agreement), or please tell me the wording you would accept. Whatever you allow,
   I will follow the brand guidelines exactly: clear attribution in the app and in
   the store listing, no altered logo anywhere, and a link to freecad.org.

2. If not - which I fully understand, and will comply with immediately - I will
   drop the name as well and use an entirely original one. Could you then confirm
   the form of words you prefer for a port like this (for example
   "<Name>, based on FreeCAD <version>"), and tell me whether ports like this
   should be registered or listed somewhere? My goal is that the result is
   recognisable as a legitimate port rather than a rebranded derivative.

Two pieces of context that may help you decide. First, your 2022 trademark
announcement described the purpose of the trademark as stopping versions of
FreeCAD being sold in app stores; that is not what this is - the app is free, with
no ads, no in-app purchases and no telemetry, and the source is public under
LGPL-2.1. Second, the store has also objected to the icon, so the only thing I am
actually asking you about is a name.

Either way, an explicit answer from the FPA would be very helpful to me: it settles
the question, and I will proceed that way the same day.

I am happy to provide anything that helps you decide: the complete patch list
against 1.1.2, build instructions, screenshots, a walkthrough of the app, or the
package itself. If the answer is no, that is a perfectly fine answer and I will
comply immediately — I would simply rather ask first.

Thank you for the work you and the community do on FreeCAD.

Best regards,
梁晓辉 (Xiaohui Liang)
GitHub: https://github.com/liang-xiaohui
```

---

## 附：被问到时的口径

| 可能的追问 | 回答 |
| --- | --- |
| 是不是"改名的衍生版"？ | 不是。现在的名称与图标都直接取自上游，没有替换成自有品牌；改名的动因是应用商店的平台规则，不是想把 FreeCAD 变成自己的产品。若 FPA 不便授权，我们走官方《品牌化》页那条路，并保留"基于 FreeCAD"的署名与源码公开 |
| 图标为什么要换？ | 驳回原文同时指"图标相似"。官方 logo 是 FPA 商标，品牌指南明确不许当作自家产品标识 —— 这一点我们接受并已认领，会重画造型与配色（只换色不算） |
| 你们不是已经有开源仓库了吗？ | 有：`github.com/liang-xiaohui/freecad-on-harmonyos`，全部补丁公开。信里已把地址、许可与分发条款写明，便于对方核实 |
| 有没有改动上游？ | 有，但都在 HarmonyOS 集成层（Qt QPA、GLES 渲染、沙箱路径、部分 UI 适配），补丁全公开在仓库 `patches/` 下 |
| 是否收费 / 有没有商业动机？ | 完全免费、无广告、无内购、无遥测；也不自建服务端 |
| LGPL 的源码义务？ | 已履行：仓库 public，修改过的 LGPL 组件源码可公开获取 |
| 打包了哪些附加组件？ | `Mod/` 下随上游发行版一并分发的组件，另外装了纯 Python 的 `freecad-ai` 插件；各组件按其原始许可分发，许可文本随包提供 |
