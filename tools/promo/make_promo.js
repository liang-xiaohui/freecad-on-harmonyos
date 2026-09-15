#!/usr/bin/env node
'use strict';
/*
 * make_promo.js — 生成 AppGallery 上架用的 16:9 介绍套图
 *
 * 为什么不用现成工具：本机没有 Pillow / ImageMagick / ffmpeg / canvas / sharp 可用，
 * 所以这里用纯 JS（jpeg-js + pngjs + opentype.js）自己排版。
 *
 * 用法：
 *   node tools/promo/make_promo.js                    # 全部 5 张
 *   node tools/promo/make_promo.js --only 03          # 只做某一张
 *   node tools/promo/make_promo.js --contact-sheet    # 额外拼一张预览图（不进 store-assets）
 *
 * 输入：store-assets/screenshots/*.jpg（真机 2472x1608 窗口截图）
 * 输出：store-assets/screenshots-16x9/*.png（1920x1080，16:9）
 */

const fs = require('fs');
const path = require('path');
const R = require('./render.js');

const ROOT = path.resolve(__dirname, '..', '..');
const SHOT_DIR = path.join(ROOT, 'store-assets', 'screenshots');
const OUT_DIR = path.join(ROOT, 'store-assets', 'screenshots-16x9');
const COPY = JSON.parse(fs.readFileSync(path.join(__dirname, 'promo-copy.json'), 'utf8'));
const LOGO_PNG = path.join(ROOT, 'store-assets', 'icon', 'foreground-1024.png');
const FONT_SC = process.env.PROMO_FONT_SC || '/system/fonts/HarmonyOS_Sans_SC.ttf';
const FONT_LATIN = process.env.PROMO_FONT_LATIN || '/system/fonts/HarmonyOS_Sans.ttf';

// ---- 版面常量（1920x1080）------------------------------------------------
const W = 1920, H = 1080;
const CARD_H = 734;
const CARD_W = Math.round(CARD_H * (2472 / 1608)); // 保持截图原始 3:2，绝不变形
const CARD_X = Math.round((W - CARD_W) / 2);
const CARD_Y = 306;
const R0 = COPY.card.radius || 16;
const BORDER = COPY.card.border || 1.4;
const BRAND_LOGO_H = 40;
const ACCENT_BAR = { w: 44, h: 4, y: 118 };

const BG_TOP = R.hex('#080A0F');
const BG_MID = R.hex('#0E131D');
const BG_BOT = R.hex('#0A0D14');
const INK = R.hex('#FFFFFF');
const INK_SUB = R.hex('#A3AEC2');
const INK_DIM = R.hex('#7A869B');
const GRID = R.hex('#6E86A8');

// ---- 载入素材 -----------------------------------------------------------
const fonts = {
  sc: R.loadFont(FONT_SC),
  latin: R.loadFont(FONT_LATIN),
};

function loadLogo() {
  const png = R.PNG.sync.read(fs.readFileSync(LOGO_PNG));
  // 裁掉透明留白，只留实际内容
  let x0 = png.width, y0 = png.height, x1 = -1, y1 = -1;
  for (let y = 0; y < png.height; y++) {
    for (let x = 0; x < png.width; x++) {
      if (png.data[(y * png.width + x) * 4 + 3] > 8) {
        if (x < x0) x0 = x; if (x > x1) x1 = x;
        if (y < y0) y0 = y; if (y > y1) y1 = y;
      }
    }
  }
  const cw = x1 - x0 + 1, ch = y1 - y0 + 1;
  const buf = new Uint8Array(cw * ch * 4);
  for (let y = 0; y < ch; y++) {
    for (let x = 0; x < cw; x++) {
      const s = ((y + y0) * png.width + (x + x0)) * 4;
      const d = (y * cw + x) * 4;
      buf[d] = png.data[s]; buf[d + 1] = png.data[s + 1];
      buf[d + 2] = png.data[s + 2]; buf[d + 3] = png.data[s + 3];
    }
  }
  return { data: buf, w: cw, h: ch };
}

// ---- 背景 ---------------------------------------------------------------
function paintBackground(cv, accent) {
  cv.vgrad([[0, BG_TOP], [0.45, BG_MID], [1, BG_BOT]]);
  cv.glow(960, 660, 860, accent, 0.20, 2.6);
  cv.glow(260, 120, 540, accent, 0.10, 2.8);
  cv.glow(1800, 1010, 520, accent, 0.06, 3.0);

  // 蓝图网格：48px 细线 + 240px 主线，越靠下越淡
  for (let x = 0; x <= W; x += 48) {
    const major = x % 240 === 0;
    cv.rect(x, 0, 1, H, GRID, major ? 0.050 : 0.026);
  }
  for (let y = 0; y <= H; y += 48) {
    const major = y % 240 === 0;
    cv.rect(0, y, W, 1, GRID, major ? 0.050 : 0.026);
  }

  // 四角制图括号
  const M = 40, ARM = 56, LW = 2;
  const corners = [[M, M, 1, 1], [W - M, M, -1, 1], [M, H - M, 1, -1], [W - M, H - M, -1, -1]];
  for (const [x, y, sx, sy] of corners) {
    cv.segment(x, y, x + ARM * sx, y, LW, accent, 0.42);
    cv.segment(x, y, x, y + ARM * sy, LW, accent, 0.42);
  }

  // 等轴测线框立方体（CAD 隐喻），贴在卡片右侧
  const cubeC = [1730, 700], cubeS = 128;
  const P = (a, b) => [cubeC[0] + a * cubeS, cubeC[1] + b * cubeS];
  const wf = [
    [[0, -1], [0.866, -0.5]], [[0.866, -0.5], [0, 0]], [[0, 0], [-0.866, -0.5]], [[-0.866, -0.5], [0, -1]],
    [[-0.866, -0.5], [-0.866, 0.5]], [[-0.866, 0.5], [0, 1]], [[0, 1], [0, 0]], [[0, 1], [0.866, 0.5]],
    [[0.866, 0.5], [0.866, -0.5]],
  ];
  for (const [a, b] of wf) {
    const p = P(...a), q = P(...b);
    cv.segment(p[0], p[1], q[0], q[1], 2, R.hex('#7FA6D8'), 0.085);
  }

  // 左侧标尺
  const rx = 72;
  const ry0 = 176, ry1 = 1040;
  cv.rect(rx, ry0, 1, ry1 - ry0, GRID, 0.11);
  for (let y = ry0, i = 0; y <= ry1; y += 40, i++) {
    const major = i % 5 === 0;
    cv.rect(rx, y, major ? 15 : 8, 1, major ? accent : GRID, major ? 0.42 : 0.16);
  }
}

// ---- 页眉 ---------------------------------------------------------------
function paintHeader(cv, cfg, idx, accent, logo) {
  const baseline = 84;
  cv.blitRGBA(logo.data, logo.w, logo.h, 72, 46, Math.round((BRAND_LOGO_H * logo.w) / logo.h), BRAND_LOGO_H);
  const nameW = R.drawText(cv, fonts.latin, COPY.brand.name, {
    size: 30, x: 126, baseline, color: INK, weight: 0.016, align: 'left',
  });
  R.drawText(cv, fonts.latin, COPY.brand.tag, {
    size: 19, x: 126 + nameW + 14, baseline: baseline - 1, color: INK_DIM, align: 'left',
  });

  // 右上页码
  const idW = R.measure(fonts.latin, cfg.id, 22, 0);
  const total = String(COPY.brand.total).padStart(2, '0');
  const totW = R.measure(fonts.latin, ` / ${total}`, 22, 0);
  const x0 = W - 72 - idW - totW;
  R.drawText(cv, fonts.latin, cfg.id, { size: 22, x: x0, baseline, color: accent, weight: 0.02 });
  R.drawText(cv, fonts.latin, ` / ${total}`, { size: 22, x: x0 + idW, baseline, color: INK_DIM });
}

// ---- 文字块 -------------------------------------------------------------
function paintHeaderText(cv, cfg, accent, accentB) {
  // 强调条
  const bar = R.roundRectMask(ACCENT_BAR.w, ACCENT_BAR.h, ACCENT_BAR.h / 2);
  cv.compositeMask(Math.round((W - ACCENT_BAR.w) / 2), ACCENT_BAR.y, bar, ACCENT_BAR.w, ACCENT_BAR.h, accent, 1);

  R.drawText(cv, fonts.latin, cfg.kicker, {
    size: 19, x: W / 2, baseline: 160, color: accent, alpha: 0.95, tracking: 7, weight: 0.02, align: 'center',
  });
  R.drawText(cv, fonts.sc, cfg.title, {
    size: 46, x: W / 2, baseline: 226, color: INK, weight: 0.024, align: 'center',
  });
  R.drawText(cv, fonts.sc, cfg.sub, {
    size: 21.5, x: W / 2, baseline: 270, color: INK_SUB, align: 'center',
  });
}

// ---- 截图画卡 -----------------------------------------------------------
function paintCard(cv, shot, accent) {
  const card = R.roundRectMask(CARD_W, CARD_H, R0);
  const dark = [0.01, 0.012, 0.02];

  const sh = R.boxBlur(card, CARD_W, CARD_H, 14);
  cv.compositeMask(CARD_X, CARD_Y + 18, sh, CARD_W, CARD_H, dark, 0.72);

  const gl = R.boxBlur(card, CARD_W, CARD_H, 34);
  cv.compositeMask(CARD_X, CARD_Y + 8, gl, CARD_W, CARD_H, accent, 0.16);

  cv.blitMasked(shot.data, shot.width, shot.height, CARD_X, CARD_Y, CARD_W, CARD_H, card);

  const ring = R.ringMask(CARD_W, CARD_H, R0, BORDER);
  cv.compositeMask(CARD_X, CARD_Y, ring, CARD_W, CARD_H, R.hex('#FFFFFF'), 0.14);

  // 顶部 3px 高光条：现代卡片语言
  const top = new Float32Array(CARD_W * CARD_H);
  for (let y = 0; y < 3; y++) for (let x = 0; x < CARD_W; x++) top[y * CARD_W + x] = ring[y * CARD_W + x];
  cv.compositeMask(CARD_X, CARD_Y, top, CARD_W, CARD_H, accent, 0.95);
}

// ---- 单张渲染 -----------------------------------------------------------
function renderOne(cfg, idx, logo) {
  const shotPath = path.join(SHOT_DIR, cfg.shot);
  if (!fs.existsSync(shotPath)) throw new Error(`找不到截图：${shotPath}`);
  const shot = R.jpeg.decode(fs.readFileSync(shotPath), { useTArray: true, formatAsRGBA: true });
  const accent = R.hex(cfg.accent);
  const accentB = R.hex(cfg.accentB);

  const cv = new R.Canvas(W, H);
  paintBackground(cv, R.mix(accent, accentB, 0.5));
  paintHeaderText(cv, cfg, accent, accentB);
  paintCard(cv, shot, accent);
  paintHeader(cv, cfg, idx, accent, logo);

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const outPath = path.join(OUT_DIR, cfg.out);
  const bytes = cv.toPNG(outPath);
  return { path: outPath, bytes, shot: cfg.shot, shotSize: `${shot.width}x${shot.height}` };
}

// ---- 预览拼图（只进 artifacts，不入库）----------------------------------
function contactSheet(results, logo) {
  const COLS = 3, TW = 640, TH = 360;
  const rows = Math.ceil(results.length / COLS);
  const cv = new R.Canvas(COLS * TW, rows * TH);
  cv.fill(R.hex('#05070B'));
  results.forEach((r, i) => {
    const png = R.PNG.sync.read(fs.readFileSync(r.path));
    const x = (i % COLS) * TW, y = Math.floor(i / COLS) * TH;
    cv.blitMasked(png.data, png.width, png.height, x, y, TW, TH, null);
  });
  const out = process.env.PROMO_PREVIEW || path.join(ROOT, 'store-assets', '.promo-preview.png');
  cv.toPNG(out);
  return out;
}

// ---- main ---------------------------------------------------------------
function main() {
  const args = process.argv.slice(2);
  const onlyIdx = args.indexOf('--only');
  const only = onlyIdx >= 0 ? args[onlyIdx + 1] : null;
  const logo = loadLogo();

  const list = COPY.images.filter((c) => !only || c.id === only);
  if (!list.length) throw new Error(`--only ${only} 没有匹配到任何配置`);

  const results = [];
  list.forEach((cfg, i) => {
    const t0 = Date.now();
    const r = renderOne(cfg, COPY.images.indexOf(cfg) + 1, logo);
    results.push(r);
    console.log(
      `${path.basename(r.path)}  ${r.shotSize} -> ${W}x${H}  ` +
      `${(r.bytes / 1024 / 1024).toFixed(2)} MB  ${Date.now() - t0} ms  (${r.shot})`
    );
  });

  if (args.includes('--contact-sheet')) {
    const p = contactSheet(results, logo);
    console.log('预览拼图:', p);
  }
}

if (require.main === module) main();
module.exports = { renderOne, W, H };
