# 给 FPA 的品牌授权询问信（草稿 · 2026-09-18）

背景见 `docs/appgallery-release.md` 第 7.6 节：AGC 以"应用与「FreeCAD」应用的名称相同、
图标相似，但未提供相关授权或商标权属证明"驳回，要求**要么删掉相似内容，要么提供授权/权属证明**。

## 怎么用

| 项 | 说明 |
| --- | --- |
| 收件人 | `fpa@freecad.org`（FPA 理事会，见 `fpa.freecad.org` 的 Contact 一节） |
| 备选渠道 | FreeCAD 论坛给理事会成员发私信（`forum.freecad.org`，成员名单在 `fpa.freecad.org/handbook/people/roster.html`） |
| 期望周期 | **按周算，别按天算**。理事会志愿者开会投票，没有 SLA。发出后同步走 A 路（改名+换图标），不要等 |
| 期望结果 | **别指望拿到能给 AGC 用的权利文件** —— 成功率约 15~20%，依据见 `appgallery-release.md` 7.6。一封信的真实价值是拿到回信：① 确认"改名 + 保留'基于 FreeCAD'的署名"就是我们该走的路；② 确认这类衍生版是否需要在某处登记，以免被社区当成仿冒 |
| 为什么要发 | wiki 明确说社区会主动发现并举报 "rebranded versions"。我们把名字改成不含 FreeCAD 的样子继续分发，**更容易被误判成仿冒**。主动写信留痕是保护自己；同时这是唯一能探明"FPA 是否愿意把鸿蒙移植接纳为官方项目"的方式 |
| 时机 | 与 A 路**并行**，不阻塞：发完就按 A 动工，别等回信（理事会按周计） |

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
authorization or proof that I hold the rights. I understand from your brand
guidelines that the FreeCAD name and logo are owned by the FPA and that third
parties may use the logo only to credit FreeCAD or link to freecad.org, not as
their own product identity.

I have also read two documents that seem to already answer most of this, and I
would rather follow them than argue with the store. Your wiki "Branding" page says
third parties may build their own applications on top of FreeCAD - including a
completely redesigned one - and its warning is aimed specifically at renaming
FreeCAD into a closed-source product. The "License" page says derivatives that are
not open-source are prohibited by the LGPL, which implies an open-source renamed
port is acceptable. This port is open-source, and it already tells users that it
is based on FreeCAD.

So, two questions:

1. If the FPA is willing, would it be possible for this port to keep the "FreeCAD"
   name and use the official symbol as its store icon? A short store-facing
   statement would be enough - I am not asking for a trademark license agreement -
   or please tell me the wording you would accept. I will follow the brand
   guidelines exactly: unmodified logo, official colours, no added effects,
   attribution and a link to freecad.org in the app.

2. If not - which I fully understand, and will comply with immediately - I will
   rename the application and replace the icon with an original design. Could you
   confirm the form of words you prefer for a port like this (for example
   "<Name>, based on FreeCAD <version>"), and whether ports like this should be
   registered or listed somewhere? My goal is that the result is recognisable as a
   legitimate port rather than a rebranded derivative.

Either way, an explicit "please follow the Branding path" from the FPA would be
very helpful to me: it settles the question, and I will proceed that way the same
day.

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
| 是不是"改名的衍生版"？ | 不是。应用名、图标、内嵌品牌都来自上游，没有替换成自有品牌；改名的动因是应用商店的平台规则，不是想把 FreeCAD 变成自己的产品 |
| 有没有改动上游？ | 有，但都在 HarmonyOS 集成层（Qt QPA、GLES 渲染、沙箱路径、部分 UI 适配），补丁全公开在仓库 `patches/` 下 |
| 是否收费 / 有没有商业动机？ | 完全免费、无广告、无内购、无遥测；也不自建服务端 |
| LGPL 的源码义务？ | 已履行：仓库 public，修改过的 LGPL 组件源码可公开获取 |
| 打包了哪些附加组件？ | `Mod/` 下随上游发行版一并分发的组件，另外装了纯 Python 的 `freecad-ai` 插件；各组件按其原始许可分发，许可文本随包提供 |
