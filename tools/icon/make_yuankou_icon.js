#!/usr/bin/env node
'use strict';
/*
 * 「元构CAD」分层图标生成器（无 Pillow / 无 SVG 渲染器环境）
 *
 * 用 HarmonyOS Sans SC 取「元」的字形轮廓，按 FreeCAD logo 的同一套品牌色与
 * 「方正几何块面 + 中央字形」风格重画一个**自有造型**：
 *   v1 方环：八段式切角方环（红/蓝/浅红），中央白色「元」
 *   v2 六角：六段式六角环（工程螺母感），中央白色「元」
 *
 * 为什么不是"把官方 logo 的 F 换成元"：那等于原封不动地留下 45° 斜切红边带 +
 * 蓝色齿轮，只换中间一个字。图标与 FPA 商标的差异只剩字形本身，平台图像比对
 * 极易再判"相似"，FPA 品牌指南也明文禁止改动其 logo 造型。保留的是**风格语言**
 * （同一套品牌色、同样的方块几何、同样的深色底），换掉的是**具体图形**。
 *
 * 依赖：opentype.js + pngjs（本机在 ~/node_modules）
 * 用法：node tools/icon/make_yuankou_icon.js [--out DIR]
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

const FONT_PATH = '/system/fonts/HarmonyOS_Sans_SC.ttf';
const SIZE = 1024;
const SUB = 12;

const PAL = {
  blue:  [0x41, 0x8F, 0xDE],
  red:   [0xCB, 0x33, 0x3B],
  lred:  [0xFF, 0x58, 0x5D],
  white: [0xFF, 0xFF, 0xFF],
  bg:    [0x1F, 0x24, 0x30],
};

/* ---------- 字形轮廓 ---------- */
function glyphContours(font, ch, em) {
  const p = font.getPath(ch, 0, 0, em);
  const contours = [];
  let cur = null, x = 0, y = 0;
  for (const c of p.commands) {
    if (c.type === 'M') { cur = []; contours.push(cur); x = c.x; y = c.y; cur.push([x, y]); }
    else if (c.type === 'L') { x = c.x; y = c.y; if (cur) cur.push([x, y]); }
    else if (c.type === 'Q' || c.type === 'C') {
      const n = c.type === 'Q' ? 12 : 20;
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
  return contours.filter((c) => c.length >= 3);
}

function transformContours(contours, fn) {
  return contours.map((c) => c.map(([x, y]) => fn(x, y)));
}

function contoursBBox(contours) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const c of contours) for (const [x, y] of c) {
    if (x < x0) x0 = x; if (x > x1) x1 = x;
    if (y < y0) y0 = y; if (y > y1) y1 = y;
  }
  return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0 };
}

/* ---------- 扫描线光栅化（非零环绕 + y 方向 SUB 倍子采样 + x 方向小数覆盖） ---------- */
function addSpan(cov, y, xa, xb, weight, W) {
  let a = Math.max(xa, 0), b = Math.min(xb, W);
  if (b <= a) return;
  const ia = Math.floor(a), ib = Math.floor(b), row = y * W;
  if (ia === ib) { cov[row + ia] += (b - a) * weight; return; }
  cov[row + ia] += (ia + 1 - a) * weight;
  for (let x = ia + 1; x < ib; x++) cov[row + x] += weight;
  if (ib < W) cov[row + ib] += (b - ib) * weight;
}

function coverageFor(W, H, contours) {
  const cov = new Float32Array(W * H);
  const edges = [];
  for (const c of contours) {
    for (let i = 0; i < c.length; i++) {
      const [ax, ay] = c[i], [bx, by] = c[(i + 1) % c.length];
      if (ay !== by) edges.push([ax, ay, bx, by]);
    }
  }
  const xs = [];
  for (let y = 0; y < H; y++) {
    for (let s = 0; s < SUB; s++) {
      const yy = y + (s + 0.5) / SUB;
      xs.length = 0;
      for (let e = 0; e < edges.length; e++) {
        const [ax, ay, bx, by] = edges[e];
        const lo = ay < by ? ay : by, hi = ay < by ? by : ay;
        if (yy < lo || yy >= hi) continue;
        const t = (yy - ay) / (by - ay);
        xs.push([ax + t * (bx - ax), by > ay ? 1 : -1]);
      }
      if (xs.length < 2) continue;
      xs.sort((p, q) => p[0] - q[0]);
      let wind = 0;
      for (let i = 0; i < xs.length - 1; i++) {
        wind += xs[i][1];
        if (wind !== 0) addSpan(cov, y, xs[i][0], xs[i + 1][0], 1 / SUB, W);
      }
    }
  }
  return cov;
}

/* ---------- 合成 ---------- */
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

function renderShapes(W, H, shapes) {
  const canvas = new Float32Array(W * H * 4);
  for (const sh of shapes) {
    if (!sh.sets || !sh.sets.length) continue;
    let cov = null;
    for (const set of sh.sets) {
      const c = coverageFor(W, H, set);
      if (!cov) cov = c; else maxInto(cov, c);
    }
    composite(canvas, cov, sh.color, W, H, sh.alpha);
  }
  return canvas;
}

/* ---------- 造型 ---------- */
/* 一个环形分段 = 一个闭合轮廓；sets 的元素是"轮廓列表"，故这里再包一层 */
function seg(oA, oB, iB, iA) { return [[oA, oB, iB, iA]]; }

function ringSegments(outer, inner, colors) {
  const n = outer.length;
  const shapes = [];
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    shapes.push({ sets: [seg(outer[i], outer[j], inner[j], inner[i])], color: PAL[colors[i]] });
  }
  return shapes;
}

const V1_OUTER = [[232, 92], [792, 92], [932, 232], [932, 792], [792, 932], [232, 932], [92, 792], [92, 232]];
const V1_INNER = [[269.3, 182], [754.7, 182], [842, 269.3], [842, 694.7], [694.7, 842], [269.3, 842], [182, 754.7], [182, 269.3]];
const V1_COLORS = ['red', 'lred', 'blue', 'lred', 'blue', 'lred', 'red', 'lred'];

const V2_OUTER = [[512, 42], [919, 277], [919, 747], [512, 982], [105, 747], [105, 277]];
const V2_INNER = [[512, 139], [835, 325.5], [835, 698.5], [512, 885], [189, 698.5], [189, 325.5]];
const V2_COLORS = ['lred', 'blue', 'blue', 'lred', 'red', 'red'];

function variantShapes(name, glyphConts) {
  if (name === 'v1') return ringSegments(V1_OUTER, V1_INNER, V1_COLORS);
  if (name === 'v2') return ringSegments(V2_OUTER, V2_INNER, V2_COLORS);
  throw new Error('未知变体 ' + name);
}

function centeredGlyph(font, box, embolden) {
  const raw = glyphContours(font, '元', 1000);
  const bb = contoursBBox(raw);
  const scale = box / Math.max(bb.w, bb.h);
  const cx = (bb.x0 + bb.x1) / 2, cy = (bb.y0 + bb.y1) / 2;
  const placed = transformContours(raw, (x, y) => [
    (x - cx) * scale + SIZE / 2,
    (y - cy) * scale + SIZE / 2,
  ]);
  const sets = [placed];
  if (embolden > 0) {
    for (let k = 0; k < 8; k++) {
      const a = (k * Math.PI) / 4;
      const dx = Math.cos(a) * embolden, dy = Math.sin(a) * embolden;
      sets.push(transformContours(placed, (x, y) => [x + dx, y + dy]));
    }
  }
  return { sets, color: PAL.white };
}

/* ---------- PNG 输出与工具 ---------- */
function writePNG(file, W, H, canvas) {
  const png = new PNG({ width: W, height: H });
  for (let i = 0; i < W * H; i++) {
    png.data[i * 4] = Math.round(canvas[i * 4]);
    png.data[i * 4 + 1] = Math.round(canvas[i * 4 + 1]);
    png.data[i * 4 + 2] = Math.round(canvas[i * 4 + 2]);
    png.data[i * 4 + 3] = Math.round(canvas[i * 4 + 3] * 255);
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
      const tx = dx + x;
      const sa = src[(y * sw + x) * 4 + 3];
      if (sa <= 0) continue;
      const di = (ty * dstW + tx) * 4, si = (y * sw + x) * 4;
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
      for (let yy = y0; yy < y1; yy++) {
        for (let xx = x0; xx < x1; xx++) {
          const i = (yy * sw + xx) * 4, sa = src[i + 3];
          r += src[i] * sa; g += src[i + 1] * sa; b += src[i + 2] * sa; a += sa; n++;
        }
      }
      const o = (y * nw + x) * 4;
      if (a > 0) { out[o] = r / a; out[o + 1] = g / a; out[o + 2] = b / a; }
      out[o + 3] = a / n;
    }
  }
  return out;
}

function applyRoundMask(canvas, w, h, radius) {
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const cxp = Math.min(Math.max(x + 0.5, radius), w - radius);
      const cyp = Math.min(Math.max(y + 0.5, radius), h - radius);
      const d = Math.hypot(x + 0.5 - cxp, y + 0.5 - cyp) - radius;
      const a = Math.min(Math.max(0.5 - d, 0), 1);
      canvas[(y * w + x) * 4 + 3] *= a;
    }
  }
}

/* ---------- 主流程 ---------- */
const args = process.argv.slice(2);
const outDir = (() => {
  const i = args.indexOf('--out');
  return i >= 0 ? args[i + 1] : path.join(os.homedir(), 'codex-freecad-artifacts', 'icon-yuankou');
})();
fs.mkdirSync(outDir, { recursive: true });

const fontBuf = fs.readFileSync(FONT_PATH);
const font = opentype.parse(fontBuf.buffer.slice(fontBuf.byteOffset, fontBuf.byteOffset + fontBuf.byteLength));

const GLYPH_BOX = { v1: 450, v2: 420 };
const GLYPH_BOLD = 8;
const results = {};

for (const name of ['v1', 'v2']) {
  const shapes = variantShapes(name, null).concat([centeredGlyph(font, GLYPH_BOX[name], GLYPH_BOLD)]);
  const fg = renderShapes(SIZE, SIZE, shapes);

  const bg = new Float32Array(SIZE * SIZE * 4);
  for (let i = 0; i < SIZE * SIZE; i++) {
    bg[i * 4] = PAL.bg[0]; bg[i * 4 + 1] = PAL.bg[1]; bg[i * 4 + 2] = PAL.bg[2]; bg[i * 4 + 3] = 1;
  }

  const comp = bg.slice();
  over(comp, SIZE, 0, 0, fg, SIZE, SIZE);

  writePNG(path.join(outDir, `foreground-${name}.png`), SIZE, SIZE, fg);
  writePNG(path.join(outDir, `background-${name}.png`), SIZE, SIZE, bg);
  writePNG(path.join(outDir, `appgallery-1024-${name}.png`), SIZE, SIZE, comp);
  writePNG(path.join(outDir, `appgallery-216-${name}.png`), 216, 216, resizeBox(comp, SIZE, SIZE, 216, 216));

  let amin = 999, amax = -1;
  for (let i = 3; i < fg.length; i += 4) { const v = fg[i]; if (v < amin) amin = v; if (v > amax) amax = v; }
  const bbox = (() => {
    let x0 = SIZE, y0 = SIZE, x1 = -1, y1 = -1;
    for (let y = 0; y < SIZE; y++) for (let x = 0; x < SIZE; x++) {
      if (fg[(y * SIZE + x) * 4 + 3] >= 8 / 255) {
        if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
      }
    }
    return { x0, y0, x1, y1 };
  })();
  let transparent = 0;
  for (let i = 3; i < fg.length; i += 4) if (Math.round(fg[i] * 255) === 0) transparent++;

  results[name] = { fg, comp, amin: Math.round(amin * 255), amax: Math.round(amax * 255), bbox, transparent };
  console.log(`${name}: 前景 alpha ${Math.round(amin * 255)}~${Math.round(amax * 255)}，透明像素 ${transparent}，` +
    `bbox x ${bbox.x0}..${bbox.x1} y ${bbox.y0}..${bbox.y1}`);
}

/* 对照图：3 行（官方现状 / v1 / v2）× 3 列（浅 / 中 / 深桌面），带圆角遮罩预演 */
const CELL = 300, GAP = 30, MARGIN = 30, LABEL = 34;
const SHEET_W = MARGIN * 2 + CELL * 3 + GAP * 2;
const SHEET_H = MARGIN * 2 + (LABEL + CELL) * 3 + GAP * 2 + LABEL;
const sheet = new Float32Array(SHEET_W * SHEET_H * 4);
const DESKTOPS = [[0xF2, 0xF3, 0xF5], [0x8A, 0x8F, 0x98], [0x10, 0x13, 0x18]];
for (let i = 0; i < SHEET_W * SHEET_H; i++) { sheet[i * 4 + 3] = 1; }

const cur = readPNG(path.join(__dirname, '..', '..', 'AppScope', 'resources', 'base', 'media', 'background.png'));
const curFg = readPNG(path.join(__dirname, '..', '..', 'AppScope', 'resources', 'base', 'media', 'foreground.png'));
const curComp = new Float32Array(cur.c.length);
for (let i = 0; i < cur.c.length; i++) curComp[i] = cur.c[i];
over(curComp, cur.w, 0, 0, curFg.c, curFg.w, curFg.h);

const rows = [
  { label: '现状：官方 logo（FPA 商标本体）', img: curComp },
  { label: 'v1 方环：八段切角环 + 白色「元」', img: results.v1.comp },
  { label: 'v2 六角：六段六角环 + 白色「元」', img: results.v2.comp },
];

function label(text, x, y, size, color) {
  let pen = x;
  for (const ch of text) {
    const cs = glyphContours(font, ch, size);
    const bb = contoursBBox(cs);
    const placed = transformContours(cs, (px, py) => [px - bb.x0 + pen, py - bb.y0 + y]);
    composite(sheet, coverageFor(SHEET_W, SHEET_H, placed), color, SHEET_W, SHEET_H);
    pen += (bb.w || size * 0.5) + size * 0.06;
  }
}

for (let r = 0; r < rows.length; r++) {
  const baseY = MARGIN + r * (LABEL + CELL + GAP);
  label(rows[r].label, MARGIN, baseY, 24, [0x20, 0x20, 0x20]);
  for (let c = 0; c < 3; c++) {
    const x = MARGIN + c * (CELL + GAP), y = baseY + LABEL;
    for (let yy = 0; yy < CELL; yy++) {
      for (let xx = 0; xx < CELL; xx++) {
        const di = ((y + yy) * SHEET_W + x + xx) * 4;
        sheet[di] = DESKTOPS[c][0]; sheet[di + 1] = DESKTOPS[c][1]; sheet[di + 2] = DESKTOPS[c][2];
      }
    }
    const small = resizeBox(rows[r].img, SIZE, SIZE, CELL, CELL);
    applyRoundMask(small, CELL, CELL, CELL * 0.22);
    over(sheet, SHEET_W, x, y, small, CELL, CELL);
  }
}
label('左：浅色桌面   中：中灰桌面   右：深色桌面（圆角为系统遮罩预演，图标本身不含圆角）',
  MARGIN, SHEET_H - MARGIN - 10, 22, [0x33, 0x33, 0x33]);
writePNG(path.join(outDir, 'review-sheet.png'), SHEET_W, SHEET_H, sheet);

console.log('输出目录：' + outDir);
console.log('  foreground-{v1,v2}.png  background-{v1,v2}.png  appgallery-{1024,216}-{v1,v2}.png');
console.log('  review-sheet.png（三行三列对照）');
