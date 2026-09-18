#!/usr/bin/env node
'use strict';
/*
 * 「元构CAD」分层图标生成器 v4 —— 轴测拉伸的立体「元」
 *
 * 与 v3 的根本区别：
 *   v3 沿用官方 logo 的红蓝平面造型（齿轮 + 45° 斜切），只把中央的白 F 换成「元」；
 *   v4 **完全不使用官方造型**，把「元」字形沿一个斜向轴挤出成一个棱柱，
 *   再按轴测投影（axonometric）画出「正面 + 可见侧壁」，配色沿用 FreeCAD 品牌四色。
 *
 * ---- 数学 ----
 * 挤出：字形区域 A（xy 平面）沿 z 轴拉伸到 [0, D]，形成棱柱 A × [0, D]。
 * 投影：斜轴测（oblique axonometric），(x, y, z) → (x + z·dx, y + z·dy)，
 *       即屏幕上的平移向量 d = (dx, dy)。d 的模长 |d| 就是"厚度"。
 *
 * 棱柱表面 = 正面(A@z=D) ∪ 背面(A@z=0) ∪ 侧壁(∂A × [0, D])。
 *
 * 可见性（斜投影下视线平行于 z 轴，所以"更大的 z 更近"）：
 *   · 背面 A@z=0 完全不可见 —— 若 p ∈ A 且存在 z>0 使 p−z·d ∈ A，则 p 被更近的层遮挡；
 *     而 z*=0 只可能发生在 p ∈ ∂A 上，那已经属于侧壁。
 *   · 侧壁中只有外法线 n 满足 n·d < 0 的那些面朝观察者（外法线背着挤出方向）。
 *     读法：字形往右下挤出，露出的是"左上侧"的壁 —— 上边缘与左边缘那一圈。
 *
 * 三条渲染规矩（都是 v3 踩过坑换来的）：
 *   1. 同层次的相邻四边形（单色侧面片）共享边，必须**按覆盖度加权平均**，
 *      不能用画家算法的 over —— 否则共享边两侧各只有 ~0.5 覆盖度，
 *      over 会算成"另外 0.25 是背景"，alpha 只剩 0.75，在深色底上是暗缝。
 *   2. 正面（z=D）压在侧壁之上，用标准 over —— 它是真正近处的覆盖层。
 *   3. 侧壁的明暗来自法线（Lambert），所以同一条边是单色，
 *      相邻边之间是硬边 —— 这正是轴测图"面片"感的来源。
 *
 * ---- 自检 ----
 * 用「随机点 + 独立几何求交」验证渲染出的掩膜：
 *   对随机屏幕点 p，解析求 z* = max{z ∈ [0,D] : p − z·d ∈ A}（用射线法判点在多边形内），
 *   与图像里该点的 alpha 对比。两者应当一致。
 *
 * 依赖：opentype.js + pngjs（本机在 ~/node_modules）
 * 用法：node tools/icon/make_yuankou_3d.js [--out DIR] [--dir 32] [--depth 0.26] [--fill 0.80]
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

function loadMod(name) {
  for (const c of [name, path.join(os.homedir(), 'node_modules', name),
    path.join(os.homedir(), '.cache', 'imgtest', 'node_modules', name)]) {
    try { return require(c); } catch (e) { /* keep trying */ }
  }
  throw new Error('缺少依赖：' + name);
}
const opentype = loadMod('opentype.js');
const { PNG } = loadMod('pngjs');

const SIZE = 1024;
const SUB_FILL = 12;   /* 字形填充的垂直超采样 */
const SUB_QUAD = 8;    /* 侧壁四边形的垂直超采样 */

const PAL = { bg: [0x1F, 0x24, 0x30] };

/* FreeCAD 品牌四色（取自官方 SVG，逐色相同） */
const FC = {
  blue: [0x41, 0x8F, 0xDE],   /* #418FDE */
  lightRed: [0xFF, 0x58, 0x5D],   /* #FF585D */
  deepRed: [0xCB, 0x33, 0x3B],   /* #CB333B */
  white: [0xFE, 0xFE, 0xFE],   /* #FEFEFE */
};

/* ========================= 1. 光栅化基础 ========================= */

const _xs = [];
const _ys = [];

function addSpan(cov, y, xa, xb, weight, W) {
  const a = Math.max(xa, 0), b = Math.min(xb, W);
  if (b <= a) return;
  const ia = Math.floor(a), ib = Math.floor(b), row = y * W;
  if (ia === ib) { cov[row + ia] += (b - a) * weight; return; }
  cov[row + ia] += (ia + 1 - a) * weight;
  for (let x = ia + 1; x < ib; x++) cov[row + x] += weight;
  if (ib < W) cov[row + ib] += (b - ib) * weight;
}

/* 闭合轮廓集合 → 覆盖率图（nonzero / evenodd），x 方向解析积分、y 方向超采样 */
function coverageFor(W, H, contours, rule) {
  const cov = new Float32Array(W * H);
  const edges = [];
  let yMin = H, yMax = -1;
  for (const c of contours) {
    for (let i = 0; i < c.length; i++) {
      const ax = c[i][0], ay = c[i][1];
      const bx = c[(i + 1) % c.length][0], by = c[(i + 1) % c.length][1];
      if (ay === by) continue;
      edges.push([ax, ay, bx, by]);
      if (ay < yMin) yMin = ay; if (ay > yMax) yMax = ay;
      if (by < yMin) yMin = by; if (by > yMax) yMax = by;
    }
  }
  if (!edges.length) return cov;
  const y0 = Math.max(0, Math.floor(yMin)), y1 = Math.min(H, Math.ceil(yMax) + 1);
  const xs = _xs;
  for (let y = y0; y < y1; y++) {
    for (let s = 0; s < SUB_FILL; s++) {
      const yy = y + (s + 0.5) / SUB_FILL;
      xs.length = 0;
      for (let e = 0; e < edges.length; e++) {
        const ax = edges[e][0], ay = edges[e][1], bx = edges[e][2], by = edges[e][3];
        const lo = ay < by ? ay : by, hi = ay < by ? by : ay;
        if (yy < lo || yy >= hi) continue;
        xs.push([ax + ((yy - ay) / (by - ay)) * (bx - ax), by > ay ? 1 : -1]);
      }
      if (xs.length < 2) continue;
      xs.sort((p, q) => p[0] - q[0]);
      if (rule === 'evenodd') {
        for (let i = 0; i + 1 < xs.length; i += 2) addSpan(cov, y, xs[i][0], xs[i + 1][0], 1 / SUB_FILL, W);
      } else {
        let wind = 0;
        for (let i = 0; i < xs.length - 1; i++) {
          wind += xs[i][1];
          if (wind !== 0) addSpan(cov, y, xs[i][0], xs[i + 1][0], 1 / SUB_FILL, W);
        }
      }
    }
  }
  return cov;
}

/* 把一段水平区间以「颜色 × 覆盖率」累加进 acc（acc 为 W*H*4，前 3 通道是加权色、第 4 是覆盖度和）。
   之所以不用"先算覆盖率图再整体着色"，是因为每个侧壁面片的颜色不同（按法线定），
   必须逐面片带色累加；而逐面片遍历整幅画布是不可接受的（几百个面片 × 100 万像素）。 */
function addSpanAcc(acc, y, xa, xb, w, col, W) {
  const a = Math.max(xa, 0), b = Math.min(xb, W);
  if (b <= a) return;
  const r = col[0] * w, g = col[1] * w, bl = col[2] * w;
  const row = y * W;
  const ia = Math.floor(a), ib = Math.floor(b);
  if (ia === ib) {
    const i = (row + ia) * 4, cw = b - a;
    acc[i] += r * cw; acc[i + 1] += g * cw; acc[i + 2] += bl * cw; acc[i + 3] += w * cw;
    return;
  }
  {
    const i = (row + ia) * 4, cw = ia + 1 - a;
    acc[i] += r * cw; acc[i + 1] += g * cw; acc[i + 2] += bl * cw; acc[i + 3] += w * cw;
  }
  for (let x = ia + 1; x < ib; x++) {
    const i = (row + x) * 4;
    acc[i] += r; acc[i + 1] += g; acc[i + 2] += bl; acc[i + 3] += w;
  }
  if (ib < W) {
    const i = (row + ib) * 4, cw = b - ib;
    acc[i] += r * cw; acc[i + 1] += g * cw; acc[i + 2] += bl * cw; acc[i + 3] += w * cw;
  }
}

/* 把一个凸四边形（侧壁面片）带色累加进 acc。
   凸集在任意水平线上的交集是一个区间，所以取交点集合的 min/max 即可，不必按 winding 配对。 */
function splatQuad(acc, q, W, H, sub, col) {
  const S = sub || SUB_QUAD;
  let yMin = Infinity, yMax = -Infinity;
  for (let i = 0; i < 4; i++) { const y = q[i * 2 + 1]; if (y < yMin) yMin = y; if (y > yMax) yMax = y; }
  const y0 = Math.max(0, Math.floor(yMin)), y1 = Math.min(H, Math.ceil(yMax) + 1);
  if (y1 <= y0) return;
  const xs = _ys;
  for (let y = y0; y < y1; y++) {
    for (let s = 0; s < S; s++) {
      const yy = y + (s + 0.5) / S;
      xs.length = 0;
      for (let i = 0; i < 4; i++) {
        const ax = q[i * 2], ay = q[i * 2 + 1];
        const j = (i + 1) & 3;
        const bx = q[j * 2], by = q[j * 2 + 1];
        if (ay === by) continue;
        const lo = ay < by ? ay : by, hi = ay < by ? by : ay;
        if (yy < lo || yy >= hi) continue;
        xs.push(ax + ((yy - ay) / (by - ay)) * (bx - ax));
      }
      if (xs.length < 2) continue;
      let mn = xs[0], mx = xs[0];
      for (let i = 1; i < xs.length; i++) { if (xs[i] < mn) mn = xs[i]; if (xs[i] > mx) mx = xs[i]; }
      addSpanAcc(acc, y, mn, mx, 1 / S, col, W);
    }
  }
}

function maxInto(dst, src) {
  for (let i = 0; i < dst.length; i++) if (src[i] > dst[i]) dst[i] = src[i];
}

/* 标准 over：src 是不透明色 + 覆盖率 */
function composite(canvas, cov, rgb, W, H) {
  const n = W * H, r = rgb[0], g = rgb[1], b = rgb[2];
  for (let i = 0; i < n; i++) {
    let ca = cov[i];
    if (ca <= 0) continue;
    if (ca > 1) ca = 1;
    const da = canvas[i * 4 + 3];
    const oa = ca + da * (1 - ca);
    if (oa <= 0) continue;
    const k = da * (1 - ca);
    canvas[i * 4] = (r * ca + canvas[i * 4] * k) / oa;
    canvas[i * 4 + 1] = (g * ca + canvas[i * 4 + 1] * k) / oa;
    canvas[i * 4 + 2] = (b * ca + canvas[i * 4 + 2] * k) / oa;
    canvas[i * 4 + 3] = oa;
  }
}

/* ========================= 2. 字形轮廓 ========================= */

function glyphContours(font, ch, em) {
  const p = font.getPath(ch, 0, 0, em);
  const out = [];
  let cur = null, x = 0, y = 0;
  for (const c of p.commands) {
    if (c.type === 'M') { cur = []; out.push(cur); x = c.x; y = c.y; cur.push([x, y]); }
    else if (c.type === 'L') { x = c.x; y = c.y; if (cur) cur.push([x, y]); }
    else if (c.type === 'Q' || c.type === 'C') {
      const n = c.type === 'Q' ? 8 : 12;
      const x0 = x, y0 = y;
      for (let i = 1; i <= n; i++) {
        const t = i / n, mt = 1 - t;
        let nx, ny;
        if (c.type === 'Q') {
          nx = mt * mt * x0 + 2 * mt * t * c.x1 + t * t * c.x;
          ny = mt * mt * y0 + 2 * mt * t * c.y1 + t * t * c.y;
        } else {
          nx = mt * mt * mt * x0 + 3 * mt * mt * t * c.x1 + 3 * mt * t * t * c.x2 + t * t * t * c.x;
          ny = mt * mt * mt * y0 + 3 * mt * mt * t * c.y1 + 3 * mt * t * t * c.y2 + t * t * t * c.y;
        }
        if (cur) cur.push([nx, ny]);
      }
      x = c.x; y = c.y;
    }
  }
  return out.filter((c) => c.length >= 3);
}

function transformContours(cs, fn) { return cs.map((c) => c.map(([x, y]) => fn(x, y))); }

function contoursBBox(cs) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const c of cs) for (const [x, y] of c) {
    if (x < x0) x0 = x; if (x > x1) x1 = x;
    if (y < y0) y0 = y; if (y > y1) y1 = y;
  }
  return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0 };
}

function signedArea(c) {
  let a = 0;
  for (let i = 0; i < c.length; i++) {
    const p = c[i], q = c[(i + 1) % c.length];
    a += p[0] * q[1] - q[0] * p[1];
  }
  return a / 2;
}

/* 射线法：点是否在（可能多环的）轮廓集合内 */
function pointInside(cs, x, y) {
  let wind = 0;
  for (const c of cs) {
    for (let i = 0; i < c.length; i++) {
      const ax = c[i][0], ay = c[i][1];
      const bx = c[(i + 1) % c.length][0], by = c[(i + 1) % c.length][1];
      if (ay === by) continue;
      const lo = Math.min(ay, by), hi = Math.max(ay, by);
      if (y < lo || y >= hi) continue;
      if (ax + ((y - ay) / (by - ay)) * (bx - ax) > x) wind += by > ay ? 1 : -1;
    }
  }
  return wind !== 0;
}

/* 判断"外法线"的取法 —— 逐环点测投票。
 *
 * 对每条接近水平的边，取两个候选法线 (+dy,-dx) 与 (-dy,dx)，
 * 各自沿法线向外偏移一小段，落点在字形**之外**的那个才是外法线。
 *
 * 早期写法是"取最水平的那条边，认定它的外法线朝上（y 为负）" —— 这是错的：
 * 底边同样接近水平，但外法线朝下。一旦选中底边，全字形法线整体反转，
 * 结果是"该画的侧壁没画、不该画的画了"（表现为字形左边界算出朝右的法线）。
 *
 * 逐环投票还顺带处理了内孔：TrueType 约定内孔与外轮廓绕向相反，
 * 整环的法线规则会反过来，所以 flip 必须按环分别定。 */
function normalRule(contours) {
  const flips = [];
  const votes = [0, 0];
  for (const c of contours) {
    let v1 = 0, v2 = 0;
    for (let i = 0; i < c.length; i++) {
      const ax = c[i][0], ay = c[i][1];
      const bx = c[(i + 1) % c.length][0], by = c[(i + 1) % c.length][1];
      const dx = bx - ax, dy = by - ay;
      const len = Math.hypot(dx, dy);
      if (len < 3) continue;
      if (Math.abs(dy) / len > 0.12) continue;      /* 只测接近水平的边 */
      const mx = (ax + bx) / 2, my = (ay + by) / 2;
      const e = Math.min(len * 0.2, 6);
      const n1x = dy / len, n1y = -dx / len;
      const in1 = pointInside(contours, mx + n1x * e, my + n1y * e);
      const in2 = pointInside(contours, mx - n1x * e, my - n1y * e);
      if (in1 === in2) continue;                    /* 两边同在内/外，测不准，弃权 */
      if (!in1) v1++; else v2++;
    }
    flips.push(v2 > v1);
    votes[0] += v1; votes[1] += v2;
  }
  if (votes[0] + votes[1] === 0) throw new Error('normalRule：没有可以点测的水平边');
  return { flips, votes };
}

/* 把轮廓拆成带外法线的边。返回 {ax, ay, bx, by, nx, ny, len, ring} */
function edgeList(contours, rule) {
  const out = [];
  for (let ci = 0; ci < contours.length; ci++) {
    const c = contours[ci];
    const flip = rule.flips ? !!rule.flips[ci] : !!rule.flip;
    for (let i = 0; i < c.length; i++) {
      const ax = c[i][0], ay = c[i][1];
      const bx = c[(i + 1) % c.length][0], by = c[(i + 1) % c.length][1];
      const dx = bx - ax, dy = by - ay;
      const len = Math.hypot(dx, dy);
      if (len < 1e-6) continue;
      let nx = dy / len, ny = -dx / len;
      if (flip) { nx = -nx; ny = -ny; }
      out.push({ ax, ay, bx, by, nx, ny, len, ring: ci });
    }
  }
  return out;
}

/* ========================= 3. 挤出与着色 ========================= */

function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
function mix(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}
function hexRGB(h) {
  const s = h.replace('#', '');
  return [parseInt(s.slice(0, 2), 16), parseInt(s.slice(2, 4), 16), parseInt(s.slice(4, 6), 16)];
}

/* 侧面片颜色。两种模式：
   lambert —— 按法线与光源夹角做连续明暗（像一块被照亮的实体）；
   twotone —— 按法线偏竖直/偏水平硬分两档（更像轴测图的三个面）。 */
const LIGHT = (() => { const v = [-0.7071067811865476, -0.7071067811865476]; return v; })();  /* 左上方 */

function sideColorOf(e, side) {
  if (side.mode === 'twotone') {
    return Math.abs(e.ny) >= Math.abs(e.nx) ? side.top : side.flank;
  }
  const t = clamp01((e.nx * LIGHT[0] + e.ny * LIGHT[1] - side.lo) / (side.hi - side.lo));
  return mix(side.dark, side.light, t);
}

/*
 * 生成一枚图标的前景（透明底）。
 *  contours: 已放在画布坐标的轮廓（可多环）
 *  d:        屏幕挤出向量 [dx, dy]（长度 = 厚度像素）
 */
function renderExtrusion(contours, d, palette) {
  const n = SIZE * SIZE;
  const edges = edgeList(contours, normalRule(contours));

  /* --- 侧壁：只取外法线背着挤出方向的那些面（n·d < 0）---
     acc 的前 3 个通道是「颜色 × 覆盖率」的加权和，第 4 个是覆盖度和；
     最后除以覆盖度和就得到"按覆盖度加权平均"的颜色 —— 共享边因此不留缝。 */
  const acc = new Float32Array(n * 4);
  const quad = new Float64Array(8);
  let visibleEdges = 0, totalLen = 0, allLen = 0;
  for (const e of edges) {
    allLen += e.len;
    const dot = e.nx * d[0] + e.ny * d[1];
    if (dot >= 0) continue;      /* 背向观察者，被正面或别的侧壁遮挡 */
    visibleEdges++; totalLen += e.len;
    quad[0] = e.ax; quad[1] = e.ay;
    quad[2] = e.bx; quad[3] = e.by;
    quad[4] = e.bx + d[0]; quad[5] = e.by + d[1];
    quad[6] = e.ax + d[0]; quad[7] = e.ay + d[1];
    splatQuad(acc, quad, SIZE, SIZE, SUB_QUAD, sideColorOf(e, palette.side));
  }
  const fg = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const a = acc[i * 4 + 3];
    if (a <= 0) continue;
    fg[i * 4] = acc[i * 4] / a; fg[i * 4 + 1] = acc[i * 4 + 1] / a; fg[i * 4 + 2] = acc[i * 4 + 2] / a;
    fg[i * 4 + 3] = a > 1 ? 1 : a;
  }
  const sideOnly = fg.slice();

  /* --- 正面：字形平移到 z=D 处，用标准 over 压在侧壁之上 --- */
  const frontContours = transformContours(contours, (x, y) => [x + d[0], y + d[1]]);
  const frontCov = coverageFor(SIZE, SIZE, frontContours, 'nonzero');
  composite(fg, frontCov, palette.front, SIZE, SIZE);

  return { fg, sideOnly, frontCov, edges, visibleEdges, totalLen, allLen };
}

/* ========================= 4. PNG 读写 ========================= */

function writePNG(file, W, H, canvas) {
  const png = new PNG({ width: W, height: H });
  const n = W * H;
  for (let i = 0; i < n; i++) {
    png.data[i * 4] = Math.max(0, Math.min(255, Math.round(canvas[i * 4])));
    png.data[i * 4 + 1] = Math.max(0, Math.min(255, Math.round(canvas[i * 4 + 1])));
    png.data[i * 4 + 2] = Math.max(0, Math.min(255, Math.round(canvas[i * 4 + 2])));
    png.data[i * 4 + 3] = Math.max(0, Math.min(255, Math.round(canvas[i * 4 + 3] * 255)));
  }
  fs.writeFileSync(file, PNG.sync.write(png, { colorType: 6 }));
}

function over(dst, dstW, dx, dy, src, sw, sh) {
  for (let y = 0; y < sh; y++) {
    const ty = dy + y;
    for (let x = 0; x < sw; x++) {
      const si = (y * sw + x) * 4, sa = src[si + 3];
      if (sa <= 0) continue;
      const di = (ty * dstW + dx + x) * 4, da = dst[di + 3];
      const oa = sa + da * (1 - sa);
      const k = da * (1 - sa);
      dst[di] = (src[si] * sa + dst[di] * k) / oa;
      dst[di + 1] = (src[si + 1] * sa + dst[di + 1] * k) / oa;
      dst[di + 2] = (src[si + 2] * sa + dst[di + 2] * k) / oa;
      dst[di + 3] = oa;
    }
  }
}

function resizeBox(src, sw, sh, nw, nh) {
  const out = new Float32Array(nw * nh * 4);
  const fx = sw / nw, fy = sh / nh;
  for (let y = 0; y < nh; y++) {
    const y0 = Math.floor(y * fy), y1 = Math.min(sh, Math.ceil((y + 1) * fy));
    for (let x = 0; x < nw; x++) {
      const x0 = Math.floor(x * fx), x1 = Math.min(sw, Math.ceil((x + 1) * fx));
      let r = 0, g = 0, b = 0, a = 0, cnt = 0;
      for (let yy = y0; yy < y1; yy++) for (let xx = x0; xx < x1; xx++) {
        const i = (yy * sw + xx) * 4, sa = src[i + 3];
        r += src[i] * sa; g += src[i + 1] * sa; b += src[i + 2] * sa; a += sa; cnt++;
      }
      const o = (y * nw + x) * 4;
      if (a > 0) { out[o] = r / a; out[o + 1] = g / a; out[o + 2] = b / a; }
      out[o + 3] = a / cnt;
    }
  }
  return out;
}

function applyRoundMask(canvas, w, h, radius) {
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const px = Math.min(Math.max(x + 0.5, radius), w - radius);
    const py = Math.min(Math.max(y + 0.5, radius), h - radius);
    const dd = Math.hypot(x + 0.5 - px, y + 0.5 - py) - radius;
    canvas[(y * w + x) * 4 + 3] *= Math.min(Math.max(0.5 - dd, 0), 1);
  }
}

function solidBG(W, H, rgb) {
  const bg = new Float32Array(W * H * 4);
  const c = rgb || PAL.bg;
  for (let i = 0; i < W * H; i++) {
    bg[i * 4] = c[0]; bg[i * 4 + 1] = c[1]; bg[i * 4 + 2] = c[2]; bg[i * 4 + 3] = 1;
  }
  return bg;
}

function stats(canvas, W, H) {
  let transparent = 0, x0 = W, y0 = H, x1 = -1, y1 = -1;
  const cnt = new Map();
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4, a = canvas[i + 3];
    if (Math.round(a * 255) === 0) { transparent++; continue; }
    if (a >= 8 / 255) {
      if (x < x0) x0 = x; if (x > x1) x1 = x;
      if (y < y0) y0 = y; if (y > y1) y1 = y;
    }
    if (a >= 0.5) {
      const key = (Math.round(canvas[i]) << 16) | (Math.round(canvas[i + 1]) << 8) | Math.round(canvas[i + 2]);
      cnt.set(key, (cnt.get(key) || 0) + 1);
    }
  }
  const total = Array.from(cnt.values()).reduce((a, b) => a + b, 0) || 1;
  const top = Array.from(cnt.entries()).sort((a, b) => b[1] - a[1]).slice(0, 6)
    .map(([k, v]) => ['#' + k.toString(16).padStart(6, '0').toUpperCase(), +((v * 100) / total).toFixed(1)]);
  return { transparent, bbox: { x0, y0, x1, y1, w: x1 - x0 + 1, h: y1 - y0 + 1 }, top, opaque: total };
}

/* ============================== 5. 主流程 ============================== */

const args = process.argv.slice(2);
const argOf = (k, dflt) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : dflt; };
const outDir = argOf('--out', path.join(os.homedir(), 'codex-freecad-artifacts', 'icon-3d'));
fs.mkdirSync(outDir, { recursive: true });

const CH = argOf('--ch', '元');
const FONT_FILE = argOf('--font', '/system/fonts/FZHeiT-SC-Bold.ttf');
const DEPTH_RATIO = parseFloat(argOf('--depth', '0.26'));   /* 厚度 / 字高 */
const FILL = parseFloat(argOf('--fill', '0.80'));           /* 整体 bbox 占画布比例 */
const DIR_DEG = parseFloat(argOf('--dir', '32'));           /* 挤出方向（屏幕角度，y 向下，正值=向右下） */
const H0 = 700;                                             /* 归一化字高 */
/* 背景层色。华为规范要求背景层满幅、不透明、**不得自行裁圆角** ——
   圆角由系统遮罩加，所以这里必须是整幅纯色，视觉上的"圆角矩形"是系统裁出来的。 */
const BG = hexRGB(argOf('--bg', '#1F2430'));

const fontBuf = fs.readFileSync(FONT_FILE);
const glyphFont = opentype.parse(fontBuf.buffer.slice(fontBuf.byteOffset, fontBuf.byteOffset + fontBuf.byteLength));
const LABEL_FONT = '/system/fonts/HarmonyOS_Sans_SC.ttf';
const labelBuf = fs.readFileSync(LABEL_FONT);
const labelFont = opentype.parse(labelBuf.buffer.slice(labelBuf.byteOffset, labelBuf.byteOffset + labelBuf.byteLength));

/* --- 5a. 归一化字形到字高 H0、居中于原点 --- */
const rawCs = glyphContours(glyphFont, CH, 1000);
const rawBB = contoursBBox(rawCs);
const s0 = H0 / rawBB.h;
const rmx = (rawBB.x0 + rawBB.x1) / 2, rmy = (rawBB.y0 + rawBB.y1) / 2;
const norm = transformContours(rawCs, (x, y) => [(x - rmx) * s0, (y - rmy) * s0]);
const nBB = contoursBBox(norm);

/* --- 5b. 挤出向量（归一化坐标）与整体 bbox --- */
const rad = (DIR_DEG * Math.PI) / 180;
const dUnit = [Math.cos(rad), Math.sin(rad)];
const dep0 = H0 * DEPTH_RATIO;
const d0 = [dUnit[0] * dep0, dUnit[1] * dep0];

const sweep0 = {
  x0: nBB.x0 + Math.min(0, d0[0]), x1: nBB.x1 + Math.max(0, d0[0]),
  y0: nBB.y0 + Math.min(0, d0[1]), y1: nBB.y1 + Math.max(0, d0[1]),
};
const sw0 = sweep0.x1 - sweep0.x0, sh0 = sweep0.y1 - sweep0.y0;
const k = (FILL * SIZE) / Math.max(sw0, sh0);
const cx = (sweep0.x0 + sweep0.x1) / 2, cy = (sweep0.y0 + sweep0.y1) / 2;

const toCanvas = (x, y) => [(x - cx) * k + SIZE / 2, (y - cy) * k + SIZE / 2];
const placed = transformContours(norm, toCanvas);
const d = [d0[0] * k, d0[1] * k];
const pBB = contoursBBox(placed);

console.log('字体 ' + path.basename(FONT_FILE) + '，字 " ' + CH + ' "');
console.log('  原始 bbox ' + rawBB.w.toFixed(0) + '×' + rawBB.h.toFixed(0) + '（em=1000）');
console.log('  挤出方向 ' + DIR_DEG + '°，厚度 ' + (DEPTH_RATIO * 100).toFixed(0) + '% 字高 = ' + dep0.toFixed(0) +
  '（归一化）/ ' + Math.hypot(d[0], d[1]).toFixed(0) + ' px（画布）');
console.log('  缩放 ' + k.toFixed(3) + '，字形 bbox ' + pBB.w.toFixed(0) + '×' + pBB.h.toFixed(0) +
  '，含厚度整体 ' + (FILL * SIZE).toFixed(0) + 'px 上限');

const rule = normalRule(placed);
console.log('  外法线规则（逐环点测投票，票数 = 判为外法线的水平边数）：');
rule.flips.forEach((f, i) => {
  console.log('    环 ' + i + '：' + placed[i].length + ' 点，' + (f ? '翻转 (-dy,dx)' : '直取 (dy,-dx)'));
});
console.log('    合计票 ' + rule.votes[0] + ' : ' + rule.votes[1]);

/* --- 5c. 配色方案 --- */
const SCHEMES = [
  { id: 'A', front: FC.white, side: { mode: 'lambert', dark: FC.deepRed, light: FC.lightRed, lo: -0.22, hi: 1.0 }, desc: '白面 + 红厚度（连续明暗）' },
  { id: 'B', front: FC.blue, side: { mode: 'lambert', dark: FC.deepRed, light: FC.lightRed, lo: -0.22, hi: 1.0 }, desc: '蓝面 + 红厚度（连续明暗）' },
  { id: 'C', front: FC.white, side: { mode: 'twotone', top: FC.lightRed, flank: FC.deepRed }, desc: '白面 + 红厚度（顶/侧硬分两档）' },
  { id: 'D', front: FC.blue, side: { mode: 'twotone', top: FC.lightRed, flank: FC.deepRed }, desc: '蓝面 + 红厚度（顶/侧硬分两档）' },
  { id: 'E', front: FC.white, side: { mode: 'lambert', dark: hexRGB('#2C5FA0'), light: FC.blue, lo: -0.22, hi: 1.0 }, desc: '白面 + 蓝厚度（连续明暗）' },
  { id: 'F', front: FC.lightRed, side: { mode: 'lambert', dark: hexRGB('#2C5FA0'), light: FC.blue, lo: -0.22, hi: 1.0 }, desc: '浅红面 + 蓝厚度（连续明暗）' },
];

const onlySchemes = (argOf('--schemes', '') || '').split(',').map((s) => s.trim()).filter(Boolean);
const ACTIVE = onlySchemes.length ? SCHEMES.filter((s) => onlySchemes.includes(s.id)) : SCHEMES;
if (!ACTIVE.length) throw new Error('--schemes 里没有匹配的方案：' + onlySchemes.join(','));

const made = [];
for (const sc of ACTIVE) {
  const t0 = Date.now();
  const r = renderExtrusion(placed, d, sc);
  const st = stats(r.fg, SIZE, SIZE);
  const comp = solidBG(SIZE, SIZE, BG);
  over(comp, SIZE, 0, 0, r.fg, SIZE, SIZE);
  made.push({ ...sc, ...r, st, comp });
  console.log('');
  console.log('[' + sc.id + '] ' + sc.desc + '   ' + (Date.now() - t0) + 'ms');
  console.log('    可见侧壁边 ' + r.visibleEdges + ' / 总边 ' + r.edges.length +
    '，占总周长 ' + ((r.totalLen / r.allLen) * 100).toFixed(0) + '%');
  console.log('    透明像素 ' + st.transparent + '（' + ((st.transparent * 100 / (SIZE * SIZE)).toFixed(1)) + '%）' +
    '，墨迹 bbox ' + st.bbox.w + '×' + st.bbox.h +
    ' (x ' + st.bbox.x0 + '..' + st.bbox.x1 + ', y ' + st.bbox.y0 + '..' + st.bbox.y1 + ')');
  console.log('    主色 ' + st.top.map(([c, p]) => c + ' ' + p + '%').join(' / '));
}

/* --- 5d. 自检：随机点 vs 独立几何求交 --- */
{
  const n = SIZE * SIZE;
  let checked = 0, agree = 0, mismatch = 0;
  const examples = [];
  const SEED = 20260918;
  let seed = SEED;
  const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
  const main = made.find((m) => m.id === 'B') || made[0];
  const ZSTEP = 96;
  for (let i = 0; i < 500; i++) {
    const px = Math.floor(rnd() * SIZE), py = Math.floor(rnd() * SIZE);
    /* 解析：求最大的 z ∈ [0,1]，使 p − z·d ∈ A。
       注意 z 必须覆盖到 0 —— 字形内部与"紧贴背面"的那条窄带只有 z≈0 才命中，
       早先写成 z = 1 − s/24 只扫到 1/24，漏掉了整块字形内部，误报 13.7% 不一致。 */
    let hit = false;
    for (let s = 0; s <= ZSTEP; s++) {
      const z = 1 - s / ZSTEP;
      if (pointInside(placed, px - z * d[0], py - z * d[1])) { hit = true; break; }
    }
    const a = main.fg[(py * SIZE + px) * 4 + 3];
    const img = a > 0.5;
    checked++;
    if (img === hit) agree++;
    else { mismatch++; if (examples.length < 6) examples.push([px, py, hit, +a.toFixed(2)]); }
  }
  console.log('');
  console.log('[自检] 随机 500 点（每点 ' + (ZSTEP + 1) + ' 层 z 采样），几何求交 vs 渲染掩膜：一致 ' + agree + '，不一致 ' + mismatch +
    '（' + ((mismatch * 100) / checked).toFixed(2) + '%）');
  if (examples.length) console.log('    反例（x, y, 几何判定, 渲染 alpha）：' + JSON.stringify(examples));
}

/* --- 5e. 输出 --- */
const bg = solidBG(SIZE, SIZE, BG);
writePNG(path.join(outDir, 'background-v4.png'), SIZE, SIZE, bg);
for (const m of made) {
  writePNG(path.join(outDir, 'foreground-v4' + m.id + '.png'), SIZE, SIZE, m.fg);
  writePNG(path.join(outDir, 'appgallery-1024-v4' + m.id + '.png'), SIZE, SIZE, m.comp);
  writePNG(path.join(outDir, 'appgallery-216-v4' + m.id + '.png'), 216, 216, resizeBox(m.comp, SIZE, SIZE, 216, 216));
}
const REF = made.find((m) => m.id === 'B') || made[0];
writePNG(path.join(outDir, 'diag-sideonly-v4' + REF.id + '.png'), SIZE, SIZE, REF.sideOnly);

/* --- 5f. 对照图 --- */
function label(canvas, text, x, y, size, color, W, H) {
  let pen = x;
  for (const ch of text) {
    const cs = glyphContours(labelFont, ch, size);
    if (!cs.length) { pen += size * 0.5; continue; }
    const bb = contoursBBox(cs);
    const p = transformContours(cs, (px, py) => [px - bb.x0 + pen, py - bb.y0 + y]);
    composite(canvas, coverageFor(W, H, p, 'nonzero'), color, W, H);
    pen += (bb.w || size * 0.5) + size * 0.06;
  }
  return pen - x;
}

const DESKTOPS = [[0xF2, 0xF3, 0xF5], [0x8A, 0x8F, 0x98], [0x10, 0x13, 0x18], BG];
const CELL = 236, GAP = 22, MARGIN = 26, LABEL = 30, COLS = 4;
const rows = made.map((m) => ({ label: m.id + '：' + m.desc, img: m.comp }));
const SHEET_W = MARGIN * 2 + CELL * COLS + GAP * (COLS - 1);
const SHEET_H = MARGIN * 2 + rows.length * (LABEL + CELL) + (rows.length - 1) * GAP + LABEL;
const sheet = new Float32Array(SHEET_W * SHEET_H * 4);
for (let i = 0; i < SHEET_W * SHEET_H; i++) sheet[i * 4 + 3] = 1;
for (let r = 0; r < rows.length; r++) {
  const baseY = MARGIN + r * (LABEL + CELL + GAP);
  label(sheet, rows[r].label, MARGIN, baseY, 21, [0x1a, 0x1a, 0x1a], SHEET_W, SHEET_H);
  for (let c = 0; c < COLS; c++) {
    const x = MARGIN + c * (CELL + GAP), y = baseY + LABEL;
    for (let yy = 0; yy < CELL; yy++) for (let xx = 0; xx < CELL; xx++) {
      const di = ((y + yy) * SHEET_W + x + xx) * 4;
      sheet[di] = DESKTOPS[c][0]; sheet[di + 1] = DESKTOPS[c][1]; sheet[di + 2] = DESKTOPS[c][2];
    }
    const small = resizeBox(rows[r].img, SIZE, SIZE, CELL, CELL);
    applyRoundMask(small, CELL, CELL, CELL * 0.22);
    over(sheet, SHEET_W, x, y, small, CELL, CELL);
  }
}
label(sheet, '四列：白色桌面 / 中灰 / 近黑 / 应用背景色 #1F2430（圆角是系统遮罩预演，图标本身不含圆角）',
  MARGIN, SHEET_H - MARGIN - 10, 18, [0x33, 0x33, 0x33], SHEET_W, SHEET_H);
writePNG(path.join(outDir, 'review-sheet.png'), SHEET_W, SHEET_H, sheet);

/* 放大细节图（1:1 裁切中心区域），用来看侧壁的面片边界与抗锯齿质量 */
{
  const m = made.find((x) => x.id === 'B') || made[0];
  const CROP = 560, HALF = CROP / 2;
  const cxp = Math.round(SIZE / 2), cyp = Math.round(SIZE / 2);
  const big = new Float32Array(CROP * CROP * 4);
  for (let y = 0; y < CROP; y++) for (let x = 0; x < CROP; x++) {
    const si = ((cyp - HALF + y) * SIZE + (cxp - HALF + x)) * 4;
    const di = (y * CROP + x) * 4;
    for (let c = 0; c < 4; c++) big[di + c] = m.fg[si + c];
  }
  writePNG(path.join(outDir, 'detail-1to1-v4B.png'), CROP, CROP, big);
}

console.log('');
console.log('输出目录：' + outDir);
console.log('  foreground-v4{A..F}.png  appgallery-{1024,216}-v4{A..F}.png  background-v4.png');
console.log('  review-sheet.png（方案 × 四种桌面）  detail-1to1-v4B.png（1:1 细节）  diag-sideonly-v4B.png');
