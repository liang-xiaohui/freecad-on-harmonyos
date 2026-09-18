#!/usr/bin/env node
'use strict';
/*
 * 「元构CAD」分层图标生成器 v3
 * —— 完整保留官方 logo 中除白色 F 之外的全部元素，把白色 F 换成白色「元」
 *
 * 官方 logo（FreeCAD 1.1.2 的 org.freecad.FreeCAD.svg）由 4 个 path 构成，
 * 按绘制顺序：
 *   1. #418FDE 蓝   齿轮（外齿环 + 内孔，evenodd）
 *   2. #FF585D 浅红 两段 45° 斜切（外角 + 内角）
 *   3. #CB333B 深红 左侧斜边带
 *   4. #FEFEFE 白   F 字形           ← 只有这一层被替换
 * 全部包在 <g transform="matrix(2,0,0,2,0.11243557,0)"> 里，viewBox 48×48。
 *
 * 做法：直接解析上游 SVG 的 path d 属性（含科学计数法、隐式 lineto），
 * 展平贝塞尔后用 evenodd 扫描线光栅化，按上游同一套坐标变换铺到 1024×1024。
 * 白 F 那一层换成 HarmonyOS/方正黑体加粗后的「元」字形轮廓。
 *
 * 自检：--selftest 会用同一套渲染器把官方 4 个 path 原样渲染一遍，
 * 与 git HEAD 里的官方 foreground.png 对比 bbox 与主色占比。渲染器忠实，
 * 才说明"保留的元素"与上游逐像素一致。
 *
 * 依赖：opentype.js + pngjs（本机在 ~/node_modules）
 * 用法：node tools/icon/make_yuankou_v3.js [--svg FILE] [--out DIR] [--selftest]
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

function loadMod(name) {
  const cands = [
    name,
    path.join(os.homedir(), 'node_modules', name),
    path.join(os.homedir(), '.cache', 'imgtest', 'node_modules', name),
  ];
  for (const c of cands) {
    try { return require(c); } catch (e) { /* keep trying */ }
  }
  throw new Error('缺少依赖：' + name);
}
const opentype = loadMod('opentype.js');
const { PNG } = loadMod('pngjs');

const LABEL_FONT = '/system/fonts/HarmonyOS_Sans_SC.ttf';
const GLYPH_FONT = '/system/fonts/FZHeiT-SC-Bold.ttf';
const SIZE = 1024;
const SUB = 12;

const PAL = {
  bg: [0x1F, 0x24, 0x30],
  white: [0xFF, 0xFF, 0xFF],
};

/* ============================ 1. SVG path 解析 ============================ */

function tokenize(d) {
  const re = /([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)/g;
  const out = [];
  let m;
  while ((m = re.exec(d)) !== null) out.push(m[1] !== undefined ? { c: m[1] } : { n: parseFloat(m[2]) });
  return out;
}

/* 展平成多边形（返回若干子路径，每条是 [x,y] 数组） */
function parsePath(d, seg) {
  const N = seg || 16;
  const t = tokenize(d);
  const subs = [];
  let i = 0, cur = null;
  let cx = 0, cy = 0, sx = 0, sy = 0;
  let pcx = 0, pcy = 0, pkind = '';
  let pcmd = '';

  const push = (x, y) => { if (cur) cur.push([x, y]); };
  const rd = () => t[i++].n;
  const cubic = (x1, y1, x2, y2, x, y) => {
    const x0 = cx, y0 = cy;
    for (let k = 1; k <= N; k++) {
      const s = k / N, ms = 1 - s;
      push(ms * ms * ms * x0 + 3 * ms * ms * s * x1 + 3 * ms * s * s * x2 + s * s * s * x,
        ms * ms * ms * y0 + 3 * ms * ms * s * y1 + 3 * ms * s * s * y2 + s * s * s * y);
    }
  };
  const quad = (x1, y1, x, y) => {
    const x0 = cx, y0 = cy;
    for (let k = 1; k <= N; k++) {
      const s = k / N, ms = 1 - s;
      push(ms * ms * x0 + 2 * ms * s * x1 + s * s * x,
        ms * ms * y0 + 2 * ms * s * y1 + s * s * y);
    }
  };
  const arc = (rx, ry, rotDeg, laf, sf, x, y) => {
    const x0 = cx, y0 = cy;
    const rot = (rotDeg * Math.PI) / 180, cosR = Math.cos(rot), sinR = Math.sin(rot);
    const dx2 = (x0 - x) / 2, dy2 = (y0 - y) / 2;
    const x1p = cosR * dx2 + sinR * dy2, y1p = -sinR * dx2 + cosR * dy2;
    rx = Math.abs(rx); ry = Math.abs(ry);
    const lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (lam > 1) { const s = Math.sqrt(lam); rx *= s; ry *= s; }
    let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
    const den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
    if (num < 0) num = 0;
    const co = ((laf !== sf) ? 1 : -1) * Math.sqrt(num / den);
    const cxp = (co * rx * y1p) / ry, cyp = (-co * ry * x1p) / rx;
    const ccx = cosR * cxp - sinR * cyp + (x0 + x) / 2;
    const ccy = sinR * cxp + cosR * cyp + (y0 + y) / 2;
    const angle = (ux, uy, vx, vy) => {
      const dd = Math.hypot(ux, uy) * Math.hypot(vx, vy);
      let c = dd === 0 ? 0 : (ux * vx + uy * vy) / dd;
      c = Math.max(-1, Math.min(1, c));
      let a = Math.acos(c);
      if (ux * vy - uy * vx < 0) a = -a;
      return a;
    };
    const ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
    const th1 = angle(1, 0, ux, uy);
    let dth = angle(ux, uy, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
    if (!sf && dth > 0) dth -= 2 * Math.PI;
    if (sf && dth < 0) dth += 2 * Math.PI;
    const steps = Math.max(8, Math.ceil(Math.abs(dth) / (Math.PI / 24)));
    for (let k = 1; k <= steps; k++) {
      const th = th1 + (dth * k) / steps;
      push(ccx + rx * Math.cos(th) * cosR - ry * Math.sin(th) * sinR,
        ccy + rx * Math.cos(th) * sinR + ry * Math.sin(th) * cosR);
    }
  };

  while (i < t.length) {
    let cmd;
    if (t[i].c !== undefined) { cmd = t[i].c; i++; }
    else { if (!pcmd || pcmd === 'Z' || pcmd === 'z') break; cmd = pcmd; }
    const rel = cmd === cmd.toLowerCase();
    const C = cmd.toUpperCase();

    if (C === 'M') {
      let x = rd(), y = rd();
      if (rel) { cx += x; cy += y; } else { cx = x; cy = y; }
      sx = cx; sy = cy;
      cur = []; subs.push(cur); cur.push([cx, cy]);
      pcmd = rel ? 'l' : 'L';       /* M 之后的多余坐标对按 lineto 处理 */
      continue;
    }
    if (C === 'L') {
      let x = rd(), y = rd();
      if (rel) { cx += x; cy += y; } else { cx = x; cy = y; }
      push(cx, cy);
    } else if (C === 'H') {
      const x = rd(); cx = rel ? cx + x : x; push(cx, cy);
    } else if (C === 'V') {
      const y = rd(); cy = rel ? cy + y : y; push(cx, cy);
    } else if (C === 'C') {
      let a = rd(), b = rd(), cc = rd(), dd = rd(), x = rd(), y = rd();
      if (rel) { a += cx; b += cy; cc += cx; dd += cy; x += cx; y += cy; }
      cubic(a, b, cc, dd, x, y);
      pcx = cc; pcy = dd; pkind = 'C'; cx = x; cy = y;
    } else if (C === 'S') {
      let cc = rd(), dd = rd(), x = rd(), y = rd();
      if (rel) { cc += cx; dd += cy; x += cx; y += cy; }
      const a = (pkind === 'C' || pkind === 'S') ? 2 * cx - pcx : cx;
      const b = (pkind === 'C' || pkind === 'S') ? 2 * cy - pcy : cy;
      cubic(a, b, cc, dd, x, y);
      pcx = cc; pcy = dd; pkind = 'S'; cx = x; cy = y;
    } else if (C === 'Q') {
      let a = rd(), b = rd(), x = rd(), y = rd();
      if (rel) { a += cx; b += cy; x += cx; y += cy; }
      quad(a, b, x, y);
      pcx = a; pcy = b; pkind = 'Q'; cx = x; cy = y;
    } else if (C === 'T') {
      let x = rd(), y = rd();
      if (rel) { x += cx; y += cy; }
      const a = (pkind === 'Q' || pkind === 'T') ? 2 * cx - pcx : cx;
      const b = (pkind === 'Q' || pkind === 'T') ? 2 * cy - pcy : cy;
      quad(a, b, x, y);
      pcx = a; pcy = b; pkind = 'T'; cx = x; cy = y;
    } else if (C === 'A') {
      const rx = rd(), ry = rd(), rot = rd(), laf = rd(), sf = rd(), x0 = rd(), y0 = rd();
      let x = x0, y = y0;
      if (rel) { x = cx + x0; y = cy + y0; }
      arc(rx, ry, rot, laf, sf, x, y);
      pcx = x; pcy = y; pkind = 'A'; cx = x; cy = y;
    } else if (C === 'Z') {
      cx = sx; cy = sy;
      pcmd = cmd;
      continue;
    }
    pcmd = cmd;
  }
  return subs.filter((s) => s.length >= 3);
}

function parseSvg(svgText) {
  const vb = /viewBox="([^"]*)"/.exec(svgText);
  const box = vb ? parseFloat(vb[1].trim().split(/[\s,]+/)[2]) : 48;
  const gm = /<g[^>]*transform="matrix\(([^)]*)\)"/.exec(svgText);
  const nums = gm ? gm[1].split(/[\s,]+/).map(Number) : [1, 0, 0, 1, 0, 0];
  const m = { a: nums[0], b: nums[1], c: nums[2], d: nums[3], e: nums[4], f: nums[5] };
  const paths = [];
  const re = /<path\b([\s\S]*?)\/?>/g;
  let pm;
  while ((pm = re.exec(svgText)) !== null) {
    const attrs = pm[1];
    /* 注意：不能写 /d="…"/ —— 它会把 id="path7" 里的 d="path7" 先匹配走，
       得到 d 值 "path7"，其中的 a 又被当成椭圆弧命令。必须要求 d 前面是空白或行首。 */
    const d = /(?:^|[\s"'])d="([^"]*)"/.exec(attrs);
    if (!d) continue;
    const style = /style="([^"]*)"/.exec(attrs);
    let fill = null, rule = 'nonzero';
    if (style) {
      const f = /fill:\s*(#[0-9a-fA-F]{3,8})/.exec(style[1]);
      if (f) fill = f[1];
      const r = /fill-rule:\s*([A-Za-z]+)/.exec(style[1]);
      if (r) rule = r[1];
    }
    if (!fill) {
      const fa = /fill="([^"]*)"/.exec(attrs);
      if (fa) fill = fa[1];
    }
    paths.push({ d: d[1], fill, rule });
  }
  return { box, m, paths };
}

function hexToRgb(h) {
  const s = h.replace('#', '');
  const f = s.length === 3 ? s.split('').map((c) => c + c).join('') : s;
  return [parseInt(f.slice(0, 2), 16), parseInt(f.slice(2, 4), 16), parseInt(f.slice(4, 6), 16)];
}

/* ====================== 2. 光栅化（nonzero / evenodd） ====================== */

function addSpan(cov, y, xa, xb, weight, W) {
  const a = Math.max(xa, 0), b = Math.min(xb, W);
  if (b <= a) return;
  const ia = Math.floor(a), ib = Math.floor(b), row = y * W;
  if (ia === ib) { cov[row + ia] += (b - a) * weight; return; }
  cov[row + ia] += (ia + 1 - a) * weight;
  for (let x = ia + 1; x < ib; x++) cov[row + x] += weight;
  if (ib < W) cov[row + ib] += (b - ib) * weight;
}

function coverageFor(W, H, contours, rule) {
  const cov = new Float32Array(W * H);
  const edges = [];
  for (const c of contours) {
    for (let i = 0; i < c.length; i++) {
      const [ax, ay] = c[i], [bx, by] = c[(i + 1) % c.length];
      if (ay !== by) edges.push([ax, ay, bx, by]);
    }
  }
  if (!edges.length) return cov;
  /* 只扫轮廓实际占据的 y 区间，别白扫整幅画布 */
  let yMin = H, yMax = -1;
  for (const e of edges) {
    if (e[1] < yMin) yMin = e[1]; if (e[1] > yMax) yMax = e[1];
    if (e[3] < yMin) yMin = e[3]; if (e[3] > yMax) yMax = e[3];
  }
  const ys = Math.max(0, Math.floor(yMin)), ye = Math.min(H, Math.ceil(yMax) + 1);
  const xs = [];
  for (let y = ys; y < ye; y++) {
    for (let s = 0; s < SUB; s++) {
      const yy = y + (s + 0.5) / SUB;
      xs.length = 0;
      for (let e = 0; e < edges.length; e++) {
        const [ax, ay, bx, by] = edges[e];
        const lo = ay < by ? ay : by, hi = ay < by ? by : ay;
        if (yy < lo || yy >= hi) continue;
        xs.push([ax + ((yy - ay) / (by - ay)) * (bx - ax), by > ay ? 1 : -1]);
      }
      if (xs.length < 2) continue;
      xs.sort((p, q) => p[0] - q[0]);
      if (rule === 'evenodd') {
        for (let i = 0; i + 1 < xs.length; i += 2) addSpan(cov, y, xs[i][0], xs[i + 1][0], 1 / SUB, W);
      } else {
        let wind = 0;
        for (let i = 0; i < xs.length - 1; i++) {
          wind += xs[i][1];
          if (wind !== 0) addSpan(cov, y, xs[i][0], xs[i + 1][0], 1 / SUB, W);
        }
      }
    }
  }
  return cov;
}

function composite(canvas, cov, rgb, W, H, alphaScale) {
  const [r, g, b] = rgb;
  for (let i = 0; i < W * H; i++) {
    let ca = cov[i];
    if (ca <= 0) continue;
    if (ca > 1) ca = 1;
    const sa = ca * (alphaScale === undefined ? 1 : alphaScale);
    if (sa <= 0) continue;
    const da = canvas[i * 4 + 3];
    const oa = sa + da * (1 - sa);
    if (oa <= 0) continue;
    const k = da * (1 - sa);
    canvas[i * 4] = (r * sa + canvas[i * 4] * k) / oa;
    canvas[i * 4 + 1] = (g * sa + canvas[i * 4 + 1] * k) / oa;
    canvas[i * 4 + 2] = (b * sa + canvas[i * 4 + 2] * k) / oa;
    canvas[i * 4 + 3] = oa;
  }
}

function maxInto(dst, src) {
  for (let i = 0; i < dst.length; i++) if (src[i] > dst[i]) dst[i] = src[i];
}

/* 同色且共享边的两块必须把覆盖度相加：共享边像素两边各只有 ~0.5，
   取 max 会留下 alpha≈0.75 的接缝，在深色底上就是一条浅色细线。 */
function sumInto(dst, src) {
  for (let i = 0; i < dst.length; i++) {
    const v = dst[i] + src[i];
    dst[i] = v > 1 ? 1 : v;
  }
}

/* 图层之间用「按覆盖度加权平均」合成，而不是画家算法的 over。
   官方 logo 的 4 层互不重叠、只在边界处背靠背共享边；共享边像素上两侧各只有 ~0.5 覆盖度，
   用 over 会被算成「另外 0.25 是背景」，alpha 只剩 0.75，在深色底上显出一条暗接缝。
   加权平均则给出 0.5+0.5=1.0 的完整覆盖，边界自然无缝。 */
function renderShapes(W, H, shapes) {
  const n = W * H;
  const accR = new Float32Array(n), accG = new Float32Array(n), accB = new Float32Array(n), accA = new Float32Array(n);
  for (const sh of shapes) {
    let cov = null;
    for (const set of sh.sets) {
      const c = coverageFor(W, H, set, sh.rule || 'nonzero');
      if (!cov) cov = c;
      else if (sh.merge === 'sum') sumInto(cov, c);
      else maxInto(cov, c);
    }
    if (!cov) continue;
    const [r, g, b] = sh.color;
    for (let i = 0; i < n; i++) {
      const c = cov[i];
      if (c <= 0) continue;
      accR[i] += r * c; accG[i] += g * c; accB[i] += b * c; accA[i] += c;
    }
  }
  const canvas = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const a = accA[i];
    if (a <= 0) continue;
    const o = i * 4;
    canvas[o] = accR[i] / a;
    canvas[o + 1] = accG[i] / a;
    canvas[o + 2] = accB[i] / a;
    canvas[o + 3] = a > 1 ? 1 : a;
  }
  return canvas;
}

/* ========================= 3. 字形轮廓与排版 ========================= */

function glyphContours(font, ch, em) {
  const p = font.getPath(ch, 0, 0, em);
  const out = [];
  let cur = null, x = 0, y = 0;
  for (const c of p.commands) {
    if (c.type === 'M') { cur = []; out.push(cur); x = c.x; y = c.y; cur.push([x, y]); }
    else if (c.type === 'L') { x = c.x; y = c.y; if (cur) cur.push([x, y]); }
    else if (c.type === 'Q' || c.type === 'C') {
      const n = c.type === 'Q' ? 10 : 20;
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

/* 形态学膨胀用「多方向平移取并集」近似圆盘。方向数是关键：尖角处相邻两个方向的
   平移尖点间距 = 2r·sin(Δθ/2)，24 方向（15°）、r=16px 时达 4.2px，会在笔画尖端
   留下一圈可见的毛刺；48 方向降到 1.0px，肉眼即不可辨。 */
const EXPAND_DIRS = 48;
function placeGlyph(font, ch, { boxH, cx, cy, embolden }) {
  const raw = glyphContours(font, ch, 1000);
  const bb = contoursBBox(raw);
  const scale = boxH / bb.h;
  const mx = (bb.x0 + bb.x1) / 2, my = (bb.y0 + bb.y1) / 2;
  const placed = transformContours(raw, (x, y) => [(x - mx) * scale + cx, (y - my) * scale + cy]);
  const sets = [placed];
  if (embolden > 0) {
    for (let k = 0; k < EXPAND_DIRS; k++) {
      const a = (k * 2 * Math.PI) / EXPAND_DIRS;
      const dx = Math.cos(a) * embolden, dy = Math.sin(a) * embolden;
      sets.push(transformContours(placed, (x, y) => [x + dx, y + dy]));
    }
  }
  const out = contoursBBox(placed);
  return { sets, bbox: out };
}

/* ============================ 4. PNG 读写与缩放 ============================ */

function writePNG(file, W, H, canvas) {
  const png = new PNG({ width: W, height: H });
  for (let i = 0; i < W * H; i++) {
    png.data[i * 4] = Math.max(0, Math.min(255, Math.round(canvas[i * 4])));
    png.data[i * 4 + 1] = Math.max(0, Math.min(255, Math.round(canvas[i * 4 + 1])));
    png.data[i * 4 + 2] = Math.max(0, Math.min(255, Math.round(canvas[i * 4 + 2])));
    png.data[i * 4 + 3] = Math.max(0, Math.min(255, Math.round(canvas[i * 4 + 3] * 255)));
  }
  fs.writeFileSync(file, PNG.sync.write(png, { colorType: 6 }));
}

function readPNG(file) {
  const png = PNG.sync.read(fs.readFileSync(file));
  const c = new Float32Array(png.width * png.height * 4);
  for (let i = 0; i < c.length; i += 4) {
    c[i] = png.data[i]; c[i + 1] = png.data[i + 1];
    c[i + 2] = png.data[i + 2]; c[i + 3] = png.data[i + 3] / 255;
  }
  return { w: png.width, h: png.height, c };
}

function over(dst, dstW, dx, dy, src, sw, sh) {
  for (let y = 0; y < sh; y++) {
    const ty = dy + y;
    for (let x = 0; x < sw; x++) {
      const sa = src[(y * sw + x) * 4 + 3];
      if (sa <= 0) continue;
      const di = (ty * dstW + dx + x) * 4, si = (y * sw + x) * 4;
      const da = dst[di + 3];
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
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      for (let yy = y0; yy < y1; yy++) for (let xx = x0; xx < x1; xx++) {
        const i = (yy * sw + xx) * 4, sa = src[i + 3];
        r += src[i] * sa; g += src[i + 1] * sa; b += src[i + 2] * sa; a += sa; n++;
      }
      const o = (y * nw + x) * 4;
      if (a > 0) { out[o] = r / a; out[o + 1] = g / a; out[o + 2] = b / a; }
      out[o + 3] = a / n;
    }
  }
  return out;
}

function applyRoundMask(canvas, w, h, radius) {
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const px = Math.min(Math.max(x + 0.5, radius), w - radius);
    const py = Math.min(Math.max(y + 0.5, radius), h - radius);
    const d = Math.hypot(x + 0.5 - px, y + 0.5 - py) - radius;
    canvas[(y * w + x) * 4 + 3] *= Math.min(Math.max(0.5 - d, 0), 1);
  }
}

function solidBG(W, H) {
  const bg = new Float32Array(W * H * 4);
  for (let i = 0; i < W * H; i++) {
    bg[i * 4] = PAL.bg[0]; bg[i * 4 + 1] = PAL.bg[1]; bg[i * 4 + 2] = PAL.bg[2]; bg[i * 4 + 3] = 1;
  }
  return bg;
}

function stats(canvas, W, H) {
  let amin = 999, amax = -1, transparent = 0;
  let x0 = W, y0 = H, x1 = -1, y1 = -1;
  const cnt = new Map();
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4, a = canvas[i + 3];
    if (a < amin) amin = a;
    if (a > amax) amax = a;
    if (Math.round(a * 255) === 0) transparent++;
    if (a >= 8 / 255) {
      if (x < x0) x0 = x; if (x > x1) x1 = x;
      if (y < y0) y0 = y; if (y > y1) y1 = y;
      const key = (Math.round(canvas[i]) << 16) | (Math.round(canvas[i + 1]) << 8) | Math.round(canvas[i + 2]);
      cnt.set(key, (cnt.get(key) || 0) + 1);
    }
  }
  const total = Array.from(cnt.values()).reduce((a, b) => a + b, 0) || 1;
  const top = Array.from(cnt.entries())
    .sort((a, b) => b[1] - a[1]).slice(0, 5)
    .map(([k, n]) => ['#' + k.toString(16).padStart(6, '0').toUpperCase(), +((n * 100) / total).toFixed(1)]);
  return { amin: Math.round(amin * 255), amax: Math.round(amax * 255), transparent, bbox: { x0, y0, x1, y1 }, top };
}

/* ================================ 5. 主流程 ================================ */

const args = process.argv.slice(2);
const argOf = (name, dflt) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : dflt; };
const outDir = argOf('--out', path.join(os.homedir(), 'codex-freecad-artifacts', 'icon-yuankou'));
fs.mkdirSync(outDir, { recursive: true });

function findSvg() {
  const explicit = argOf('--svg', null);
  if (explicit) return explicit;
  const pref = process.env.FREECAD_PREFIX ||
    path.join(os.homedir(), 'CPPLib', 'install', 'freecad', '1.1.2', 'ohos', 'arm64-v8a-gui-qt6');
  const p = path.join(pref, 'share', 'icons', 'hicolor', 'scalable', 'apps', 'org.freecad.FreeCAD.svg');
  if (fs.existsSync(p)) return p;
  throw new Error('找不到官方 logo SVG，请用 --svg 指定，或设置 FREECAD_PREFIX。试过：' + p);
}

const svgFile = findSvg();
const svg = parseSvg(fs.readFileSync(svgFile, 'utf8'));
console.log('官方 SVG：' + svgFile);
console.log('  viewBox ' + svg.box + '，变换 matrix(' + [svg.m.a, svg.m.b, svg.m.c, svg.m.d, svg.m.e, svg.m.f].join(',') + ')，' +
  svg.paths.length + ' 个 path');

const S = SIZE / svg.box;
const toCanvas = (x, y) => [
  (svg.m.a * x + svg.m.c * y + svg.m.e) * S,
  (svg.m.b * x + svg.m.d * y + svg.m.f) * S,
];

const layers = svg.paths.map((p) => {
  const subs = parsePath(p.d, 20);
  const flat = subs.map((s) => s.map(([x, y]) => toCanvas(x, y)));
  return { ...p, rgb: hexToRgb(p.fill), flat, bbox: contoursBBox(flat) };
});

const F_LAYER = layers.find((l) => {
  const [r, g, b] = l.rgb;
  return r > 240 && g > 240 && b > 240;
});
if (!F_LAYER) throw new Error('官方 SVG 里没找到白色层（期望 #FEFEFE）');
const KEEP = layers.filter((l) => l !== F_LAYER);

console.log('  保留层：' + KEEP.map((l) => l.fill + '(' + l.rule + ')').join(', '));
console.log('  替换层：' + F_LAYER.fill + '  bbox x ' + F_LAYER.bbox.x0.toFixed(1) + '..' + F_LAYER.bbox.x1.toFixed(1) +
  ' y ' + F_LAYER.bbox.y0.toFixed(1) + '..' + F_LAYER.bbox.y1.toFixed(1));
const FH = F_LAYER.bbox.h;
const FCX = (F_LAYER.bbox.x0 + F_LAYER.bbox.x1) / 2;
const FCY = (F_LAYER.bbox.y0 + F_LAYER.bbox.y1) / 2;
console.log('  F 高 ' + FH.toFixed(1) + 'px，中心 (' + FCX.toFixed(1) + ', ' + FCY.toFixed(1) + ')');

/* 保留层。深红层与 F 缺口补红层同色（#CB333B）且共享边，合并成一个 shape 用 sum 求并集，
   这样 y=171 的横边和 x=258 的竖边不会留下接缝。绘制顺序仍与上游一致：蓝 → 浅红 → 深红。 */
const DEEP_LAYER = KEEP.find((l) => l.rgb[0] > 150 && l.rgb[1] < 80 && l.rgb[2] < 80) || KEEP[KEEP.length - 1];
const keepShapes = KEEP.filter((l) => l !== DEEP_LAYER).map((l) => ({ sets: [l.flat], color: l.rgb, rule: l.rule }));
keepShapes.push({
  sets: [DEEP_LAYER.flat, F_LAYER.flat],
  color: DEEP_LAYER.rgb,
  rule: F_LAYER.rule,
  merge: 'sum',
});

/* ---- 5a. 自检：原样渲染官方 4 层 ----
   必须用「原始 4 层」，不能用 keepShapes：后者已把 F 层并进深红层，
   再叠一次独立的 F 层会让 F 区域被计入两次，加权平均后 F 变成红白中间色。 */
const official = renderShapes(SIZE, SIZE,
  KEEP.map((l) => ({ sets: [l.flat], color: l.rgb, rule: l.rule }))
    .concat([{ sets: [F_LAYER.flat], color: F_LAYER.rgb, rule: F_LAYER.rule }]));
writePNG(path.join(outDir, 'official-render.png'), SIZE, SIZE, official);
{
  const st = stats(official, SIZE, SIZE);
  console.log('');
  console.log('[自检] 官方 logo 重渲染：bbox x ' + st.bbox.x0 + '..' + st.bbox.x1 + ' y ' + st.bbox.y0 + '..' + st.bbox.y1 +
    '，主色 ' + st.top.map(([c, p]) => c + ' ' + p + '%').join(' / '));
}

/* ---- 5a-2. 诊断：F 那块区域在红蓝图层里原本是什么 ---- */
let fMaskDiag = null;
{
  const keepOnly = renderShapes(SIZE, SIZE, KEEP.map((l) => ({ sets: [l.flat], color: l.rgb, rule: l.rule })));
  writePNG(path.join(outDir, 'diag-keep-only.png'), SIZE, SIZE, keepOnly);
  const fMask = coverageFor(SIZE, SIZE, F_LAYER.flat, F_LAYER.rule);
  fMaskDiag = fMask;
  let n = 0, trans = 0;
  const cnt = new Map();
  for (let i = 0; i < SIZE * SIZE; i++) {
    if (fMask[i] < 0.5) continue;
    n++;
    if (keepOnly[i * 4 + 3] < 0.5) { trans++; continue; }
    const key = (Math.round(keepOnly[i * 4]) << 16) | (Math.round(keepOnly[i * 4 + 1]) << 8) | Math.round(keepOnly[i * 4 + 2]);
    cnt.set(key, (cnt.get(key) || 0) + 1);
  }
  const pct = (v) => ((v * 100) / n).toFixed(1) + '%';
  console.log('');
  console.log('[诊断] F 字形区域内共 ' + n + ' px：');
  console.log('   透明（红蓝图层都没到）= ' + trans + ' px  ' + pct(trans));
  for (const [k, v] of Array.from(cnt.entries()).sort((a, b) => b[1] - a[1]).slice(0, 6)) {
    console.log('   #' + k.toString(16).padStart(6, '0').toUpperCase() + '  ' + v + ' px  ' + pct(v));
  }
  const kst = stats(keepOnly, SIZE, SIZE);
  console.log('   红蓝图层 bbox x ' + kst.bbox.x0 + '..' + kst.bbox.x1 + ' y ' + kst.bbox.y0 + '..' + kst.bbox.y1);
  console.log('   红蓝图层主色 ' + kst.top.map(([c, p]) => c + ' ' + p + '%').join(' / '));
}

/* ---- 5b. 生成「元」替换版 ---- */
const glyphFontBuf = fs.readFileSync(GLYPH_FONT);
const glyphFont = opentype.parse(glyphFontBuf.buffer.slice(glyphFontBuf.byteOffset, glyphFontBuf.byteOffset + glyphFontBuf.byteLength));
const labelFontBuf = fs.readFileSync(LABEL_FONT);
const labelFont = opentype.parse(labelFontBuf.buffer.slice(labelFontBuf.byteOffset, labelFontBuf.byteOffset + labelFontBuf.byteLength));

/* F 的缺口用深红补平（诊断已证明 F 区域内 100% 透明，红蓝图层本身没到那里）。
   补完之后图形才是一个完整的面，白色「元」压在上面，笔画缝隙里露出的是红色而不是洞。 */
const fullShapes = keepShapes;
console.log('');
console.log('补红：F 缺口用深红 #' + DEEP_LAYER.rgb.map((v) => v.toString(16).padStart(2, '0').toUpperCase()).join('') +
  ' 填平，与深红层按 sum 合并（消掉共享边的接缝）');

/* 图形轮廓掩膜：用来把「元」约束在红蓝范围之内 */
const shapeMask = new Uint8Array(SIZE * SIZE);
/* 红蓝底（含补红）用加权平均算一次，后面所有变体共用 */
const baseFg = renderShapes(SIZE, SIZE, fullShapes);
let filledComp = null;
{
  for (let i = 0; i < SIZE * SIZE; i++) shapeMask[i] = baseFg[i * 4 + 3] >= 0.5 ? 1 : 0;
  filledComp = solidBG(SIZE, SIZE);
  over(filledComp, SIZE, 0, 0, baseFg, SIZE, SIZE);
  writePNG(path.join(outDir, 'diag-filled-shape.png'), SIZE, SIZE, filledComp);
}

/* 「元」的全部轮廓点（含加粗偏移）都必须落在图形掩膜内，5×5 邻域一起查 */
function glyphFits(g) {
  for (const set of g.sets) for (const c of set) for (const [x, y] of c) {
    const ix = Math.round(x), iy = Math.round(y);
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
      const px = ix + dx, py = iy + dy;
      if (px < 0 || py < 0 || px >= SIZE || py >= SIZE) return false;
      if (!shapeMask[py * SIZE + px]) return false;
    }
  }
  return true;
}

/* 二分搜索「刚好贴边」的最大字高 */
function maxBoxH(embolden) {
  let lo = 80, hi = 1000;
  for (let it = 0; it < 13; it++) {
    const mid = (lo + hi) / 2;
    const g = placeGlyph(glyphFont, '元', { boxH: mid, cx: FCX, cy: FCY, embolden });
    if (glyphFits(g)) lo = mid; else hi = mid;
  }
  return lo;
}

const SPEC = [
  { id: 'A', e: 0, k: 1.00 },
  { id: 'B', e: 16, k: 1.00 },
  { id: 'C', e: 30, k: 1.00 },
  { id: 'D', e: 16, k: 0.90 },
];
const VARIANTS = SPEC.map((s) => {
  const edge = maxBoxH(s.e);
  return {
    id: s.id, embolden: s.e, boxH: edge * s.k, edge,
    label: '贴边 ' + Math.round(s.k * 100) + '%（贴边上限字高 ' + edge.toFixed(0) + 'px），加粗 ' + s.e + 'px',
  };
});

const made = [];
for (const v of VARIANTS) {
  const g = placeGlyph(glyphFont, '元', { boxH: v.boxH, cx: FCX, cy: FCY, embolden: v.embolden });
  let gcov = null;
  for (const set of g.sets) {
    const c = coverageFor(SIZE, SIZE, set, 'nonzero');
    if (!gcov) gcov = c; else maxInto(gcov, c);
  }
  /* 红蓝底已是加权平均的结果；白色「元」是覆盖层，必须用标准 over 压上去 */
  const fg = baseFg.slice();
  composite(fg, gcov, PAL.white, SIZE, SIZE);
  const comp = solidBG(SIZE, SIZE);
  over(comp, SIZE, 0, 0, fg, SIZE, SIZE);
  const st = stats(fg, SIZE, SIZE);
  let overrun = 0;
  for (let i = 0; i < SIZE * SIZE; i++) if (gcov[i] > 0.5 && !shapeMask[i]) overrun++;
  made.push({ ...v, fg, comp, st, glyphBBox: g.bbox, overrun });
  console.log('');
  console.log('[' + v.id + '] ' + v.label);
  console.log('    ｜元｜ 墨迹 ' + g.bbox.w.toFixed(0) + '×' + g.bbox.h.toFixed(0) +
    '，x ' + g.bbox.x0.toFixed(0) + '..' + g.bbox.x1.toFixed(0) +
    ' y ' + g.bbox.y0.toFixed(0) + '..' + g.bbox.y1.toFixed(0));
  console.log('    越出红蓝轮廓的像素：' + overrun + (overrun === 0 ? '  ✅ 完全落在红蓝范围内' : '  ⚠️'));
  console.log('    主色 ' + st.top.map(([c, p]) => c + ' ' + p + '%').join(' / '));
  writePNG(path.join(outDir, 'foreground-v3' + v.id + '.png'), SIZE, SIZE, fg);
  writePNG(path.join(outDir, 'appgallery-1024-v3' + v.id + '.png'), SIZE, SIZE, comp);
  writePNG(path.join(outDir, 'appgallery-216-v3' + v.id + '.png'), 216, 216, resizeBox(comp, SIZE, SIZE, 216, 216));
  if (v.id === 'A' || v.id === 'B') {
    const redBG = new Float32Array(SIZE * SIZE * 4);
    for (let i = 0; i < SIZE * SIZE; i++) {
      redBG[i * 4] = DEEP_LAYER.rgb[0]; redBG[i * 4 + 1] = DEEP_LAYER.rgb[1];
      redBG[i * 4 + 2] = DEEP_LAYER.rgb[2]; redBG[i * 4 + 3] = 1;
    }
    over(redBG, SIZE, 0, 0, renderShapes(SIZE, SIZE, [{ sets: g.sets, color: PAL.white, rule: 'nonzero' }]), SIZE, SIZE);
    writePNG(path.join(outDir, 'diag-glyph-on-red-' + v.id + '.png'), SIZE, SIZE, redBG);
  }
}

const bg = solidBG(SIZE, SIZE);
writePNG(path.join(outDir, 'background-v3.png'), SIZE, SIZE, bg);

/* ---- 5c. 对照图 ---- */
function label(canvas, text, x, y, size, color, W, H) {
  let pen = x;
  for (const ch of text) {
    const cs = glyphContours(labelFont, ch, size);
    if (!cs.length) { pen += size * 0.5; continue; }
    const bb = contoursBBox(cs);
    const placed = transformContours(cs, (px, py) => [px - bb.x0 + pen, py - bb.y0 + y]);
    composite(canvas, coverageFor(W, H, placed, 'nonzero'), color, W, H);
    pen += (bb.w || size * 0.5) + size * 0.06;
  }
  return pen - x;
}

const CELL = 232, GAP = 22, MARGIN = 26, LABEL = 26;
const COLS = 4;
const rowsDef = [
  { label: '官方 logo 原样（重渲染自检）', img: official, tag: 'official' },
  { label: '红蓝图形 + F 缺口补红（无字，仅作对照）', img: filledComp, tag: 'filled' },
  ...made.map((m) => ({ label: m.id + '：' + m.label, img: m.comp, tag: 'v3' + m.id })),
];
const SHEET_W = MARGIN * 2 + CELL * COLS + GAP * (COLS - 1);
const SHEET_H = MARGIN * 2 + rowsDef.length * (LABEL + CELL) + (rowsDef.length - 1) * GAP + LABEL;
const sheet = new Float32Array(SHEET_W * SHEET_H * 4);
const DESKTOPS = [[0xF2, 0xF3, 0xF5], [0x8A, 0x8F, 0x98], [0x10, 0x13, 0x18], [0x1F, 0x24, 0x30]];
for (let i = 0; i < SHEET_W * SHEET_H; i++) sheet[i * 4 + 3] = 1;

for (let r = 0; r < rowsDef.length; r++) {
  const baseY = MARGIN + r * (LABEL + CELL + GAP);
  label(sheet, rowsDef[r].label, MARGIN, baseY, 20, [0x20, 0x20, 0x20], SHEET_W, SHEET_H);
  for (let c = 0; c < COLS; c++) {
    const x = MARGIN + c * (CELL + GAP), y = baseY + LABEL;
    for (let yy = 0; yy < CELL; yy++) for (let xx = 0; xx < CELL; xx++) {
      const di = ((y + yy) * SHEET_W + x + xx) * 4;
      sheet[di] = DESKTOPS[c][0]; sheet[di + 1] = DESKTOPS[c][1]; sheet[di + 2] = DESKTOPS[c][2];
    }
    const small = resizeBox(rowsDef[r].img, SIZE, SIZE, CELL, CELL);
    applyRoundMask(small, CELL, CELL, CELL * 0.22);
    over(sheet, SHEET_W, x, y, small, CELL, CELL);
  }
}
label(sheet, '四列依次：白色桌面 / 中灰桌面 / 近黑桌面 / 应用背景色 #1F2430（圆角是系统遮罩预演，图标本身不含圆角）',
  MARGIN, SHEET_H - MARGIN - 8, 18, [0x33, 0x33, 0x33], SHEET_W, SHEET_H);
writePNG(path.join(outDir, 'review-sheet.png'), SHEET_W, SHEET_H, sheet);

console.log('');
console.log('输出目录：' + outDir);
console.log('  official-render.png  对照图 review-sheet.png');
console.log('  foreground-v3{A..D}.png  appgallery-{1024,216}-v3{A..D}.png  background-v3.png');
