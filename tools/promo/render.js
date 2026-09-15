'use strict';
/*
 * render.js — 纯 JS 图像渲染内核（无 Pillow / ImageMagick / canvas 依赖）
 *
 * 依赖三个已经存在于本机的 npm 包（路径可用环境变量覆盖）：
 *   jpeg-js    $PROMO_JPEG_JS    默认 /storage/Users/currentUser/node_modules/jpeg-js
 *   pngjs      $PROMO_PNGJS      默认 /storage/Users/currentUser/.cache/imgtest/node_modules/pngjs
 *   opentype.js $PROMO_OPENTYPE  默认 /storage/Users/currentUser/.cache/imgtest/node_modules/opentype.js
 *
 * 画布内部是 Float32 RGB（0..1），全程不透明；需要透明的地方（logo、遮罩）
 * 单独用 alpha mask 合成。
 */

const fs = require('fs');
const path = require('path');

const DEPS = {
  jpeg: process.env.PROMO_JPEG_JS || '/storage/Users/currentUser/node_modules/jpeg-js',
  pngjs: process.env.PROMO_PNGJS || '/storage/Users/currentUser/.cache/imgtest/node_modules/pngjs',
  opentype: process.env.PROMO_OPENTYPE || '/storage/Users/currentUser/.cache/imgtest/node_modules/opentype.js',
};

function dep(name) {
  const base = DEPS[name];
  try {
    if (name === 'pngjs') return require(path.join(base, 'lib/png.js'));
    if (name === 'opentype') return require(path.join(base, 'dist/opentype.js'));
    return require(base);
  } catch (e) {
    throw new Error(`缺少依赖 ${name}（期望在 ${base}）：${e.message}\n` +
      '用 PROMO_JPEG_JS / PROMO_PNGJS / PROMO_OPENTYPE 指定实际路径。');
  }
}

const jpeg = dep('jpeg');
const { PNG } = dep('pngjs');
const opentype = dep('opentype');

// ---------------------------------------------------------------- 颜色

function hex(c) {
  const s = c.replace('#', '');
  const n = parseInt(s.length === 3 ? s.split('').map((x) => x + x).join('') : s, 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}
function mix(a, b, t) {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

// ---------------------------------------------------------------- 画布

class Canvas {
  constructor(w, h) {
    this.w = w;
    this.h = h;
    this.d = new Float32Array(w * h * 3);
  }

  fill(rgb) {
    const d = this.d;
    for (let i = 0; i < d.length; i += 3) {
      d[i] = rgb[0]; d[i + 1] = rgb[1]; d[i + 2] = rgb[2];
    }
  }

  /** 垂直渐变，stops = [[pos 0..1, rgb], ...] 升序 */
  vgrad(stops) {
    for (let y = 0; y < this.h; y++) {
      const t = this.h === 1 ? 0 : y / (this.h - 1);
      let i = 0;
      while (i < stops.length - 2 && t > stops[i + 1][0]) i++;
      const [p0, c0] = stops[i];
      const [p1, c1] = stops[i + 1];
      const k = p1 === p0 ? 0 : (t - p0) / (p1 - p0);
      const c = mix(c0, c1, clamp01(k));
      const row = y * this.w * 3;
      for (let x = 0; x < this.w; x++) {
        const o = row + x * 3;
        this.d[o] = c[0]; this.d[o + 1] = c[1]; this.d[o + 2] = c[2];
      }
    }
  }

  blendPx(x, y, rgb, a) {
    if (a <= 0 || x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const o = (y * this.w + x) * 3;
    const ia = 1 - a;
    this.d[o] = this.d[o] * ia + rgb[0] * a;
    this.d[o + 1] = this.d[o + 1] * ia + rgb[1] * a;
    this.d[o + 2] = this.d[o + 2] * ia + rgb[2] * a;
  }

  /** 加色叠加：用于光晕 */
  addPx(x, y, rgb, g) {
    if (g <= 0 || x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const o = (y * this.w + x) * 3;
    this.d[o] += rgb[0] * g;
    this.d[o + 1] += rgb[1] * g;
    this.d[o + 2] += rgb[2] * g;
  }

  /**
   * 径向光晕。falloff: 1 = 线性外沿, 2 = 二次, 3 = 三次
   * gain 是中心强度（加色），vignette 项可用来只照亮一侧。
   */
  glow(cx, cy, rad, rgb, gain, falloff = 2.4) {
    const x0 = Math.max(0, Math.floor(cx - rad)), x1 = Math.min(this.w - 1, Math.ceil(cx + rad));
    const y0 = Math.max(0, Math.floor(cy - rad)), y1 = Math.min(this.h - 1, Math.ceil(cy + rad));
    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const dx = (x + 0.5 - cx) / rad, dy = (y + 0.5 - cy) / rad;
        const r = Math.sqrt(dx * dx + dy * dy);
        if (r >= 1) continue;
        const f = Math.pow(1 - r, falloff);
        this.addPx(x, y, rgb, gain * f);
      }
    }
  }

  /** 轴对齐实心矩形（半像素对齐，无 AA，用于网格/刻度这类 1px 线） */
  rect(x, y, w, h, rgb, a) {
    const xs = Math.max(0, Math.round(x)), ys = Math.max(0, Math.round(y));
    const xe = Math.min(this.w, Math.round(x + w)), ye = Math.min(this.h, Math.round(y + h));
    for (let yy = ys; yy < ye; yy++) for (let xx = xs; xx < xe; xx++) this.blendPx(xx, yy, rgb, a);
  }

  /** 任意线段（带 AA 的胶囊），用于轴线、括号、线框 */
  segment(x0, y0, x1, y1, width, rgb, a) {
    const hw = width / 2;
    const bx0 = Math.max(0, Math.floor(Math.min(x0, x1) - hw - 1));
    const bx1 = Math.min(this.w - 1, Math.ceil(Math.max(x0, x1) + hw + 1));
    const by0 = Math.max(0, Math.floor(Math.min(y0, y1) - hw - 1));
    const by1 = Math.min(this.h - 1, Math.ceil(Math.max(y0, y1) + hw + 1));
    const vx = x1 - x0, vy = y1 - y0;
    const len2 = vx * vx + vy * vy || 1;
    for (let y = by0; y <= by1; y++) {
      for (let x = bx0; x <= bx1; x++) {
        const px = x + 0.5 - x0, py = y + 0.5 - y0;
        let t = (px * vx + py * vy) / len2;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        const ex = px - vx * t, ey = py - vy * t;
        const dist = Math.sqrt(ex * ex + ey * ey);
        const cov = clamp01(hw + 0.5 - dist);
        if (cov > 0) this.blendPx(x, y, rgb, a * cov);
      }
    }
  }

  /** 用 alpha mask（w*h，0..1）把 rgb 合成进来 */
  compositeMask(mx, my, mask, mw, mh, rgb, a) {
    for (let y = 0; y < mh; y++) {
      const ty = my + y;
      if (ty < 0 || ty >= this.h) continue;
      for (let x = 0; x < mw; x++) {
        const m = mask[y * mw + x];
        if (m <= 0) continue;
        this.blendPx(mx + x, ty, rgb, a * m);
      }
    }
  }

  /** 把 RGBA 图源按 mask 缩放贴入（mask 为目标尺寸） */
  blitMasked(src, sw, sh, dx, dy, dw, dh, mask) {
    const res = resampleRGB(src, sw, sh, dw, dh);
    for (let y = 0; y < dh; y++) {
      const ty = dy + y;
      if (ty < 0 || ty >= this.h) continue;
      for (let x = 0; x < dw; x++) {
        const m = mask ? mask[y * dw + x] : 1;
        if (m <= 0) continue;
        const o = (y * dw + x) * 3;
        this.blendPx(dx + x, ty, [res[o], res[o + 1], res[o + 2]], m);
      }
    }
  }

  /** 贴一张带 alpha 的 RGBA 图（logo 用），按 alpha 合成 */
  blitRGBA(src, sw, sh, dx, dy, dw, dh, alphaScale = 1) {
    const res = resampleRGBA(src, sw, sh, dw, dh);
    for (let y = 0; y < dh; y++) {
      const ty = dy + y;
      if (ty < 0 || ty >= this.h) continue;
      for (let x = 0; x < dw; x++) {
        const o = (y * dw + x) * 4;
        const a = (res[o + 3] / 255) * alphaScale;
        if (a <= 0) continue;
        this.blendPx(dx + x, ty, [res[o] / 255, res[o + 1] / 255, res[o + 2] / 255], a);
      }
    }
  }

  toPNG(file, opts = {}) {
    const png = new PNG({ width: this.w, height: this.h });
    for (let i = 0, n = this.w * this.h; i < n; i++) {
      png.data[i * 4] = Math.round(clamp01(this.d[i * 3]) * 255);
      png.data[i * 4 + 1] = Math.round(clamp01(this.d[i * 3 + 1]) * 255);
      png.data[i * 4 + 2] = Math.round(clamp01(this.d[i * 3 + 2]) * 255);
      png.data[i * 4 + 3] = 255;
    }
    const buf = PNG.sync.write(png, { deflateLevel: 9, colorType: 6 });
    fs.writeFileSync(file, buf);
    return buf.length;
  }
}

// ---------------------------------------------------------------- 缩放（面积平均，分离两趟）

function areaWeights(srcLen, dstLen) {
  // 每个目标像素覆盖的源区间 [a,b)
  const scale = srcLen / dstLen;
  const out = [];
  for (let i = 0; i < dstLen; i++) out.push([i * scale, (i + 1) * scale]);
  return out;
}

function resampleChannel(get, set, sw, sh, dw, dh) {
  const wx = areaWeights(sw, dw);
  const wy = areaWeights(sh, dh);
  const tmp = new Float32Array(dw * sh);
  for (let y = 0; y < sh; y++) {
    for (let x = 0; x < dw; x++) {
      const [a, b] = wx[x];
      const ia = Math.floor(a), ib = Math.min(sw, Math.ceil(b));
      let sum = 0, tot = 0;
      for (let s = ia; s < ib; s++) {
        const w = Math.min(b, s + 1) - Math.max(a, s);
        if (w <= 0) continue;
        sum += get(s, y) * w; tot += w;
      }
      tmp[y * dw + x] = tot ? sum / tot : 0;
    }
  }
  const out = new Float32Array(dw * dh);
  for (let y = 0; y < dh; y++) {
    const [a, b] = wy[y];
    const ia = Math.floor(a), ib = Math.min(sh, Math.ceil(b));
    for (let x = 0; x < dw; x++) {
      let sum = 0, tot = 0;
      for (let s = ia; s < ib; s++) {
        const w = Math.min(b, s + 1) - Math.max(a, s);
        if (w <= 0) continue;
        sum += tmp[s * dw + x] * w; tot += w;
      }
      out[y * dw + x] = tot ? sum / tot : 0;
    }
  }
  return out;
}

/** src: RGBA Uint8 数组（jpeg-js / pngjs 输出）→ Float32 RGB dw*dh*3，取值 0..1 */
function resampleRGB(src, sw, sh, dw, dh) {
  const chans = [0, 1, 2].map((c) =>
    resampleChannel((x, y) => src[(y * sw + x) * 4 + c], null, sw, sh, dw, dh));
  const out = new Float32Array(dw * dh * 3);
  for (let i = 0; i < dw * dh; i++) {
    out[i * 3] = chans[0][i] / 255;
    out[i * 3 + 1] = chans[1][i] / 255;
    out[i * 3 + 2] = chans[2][i] / 255;
  }
  return out;
}

/** 与 resampleRGB 相同，但保留 alpha；先预乘再缩放，避免透明边缘出现黑边 */
function resampleRGBA(src, sw, sh, dw, dh) {
  const n = sw * sh;
  const pre = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const a = src[i * 4 + 3] / 255;
    pre[i * 4] = src[i * 4] * a;
    pre[i * 4 + 1] = src[i * 4 + 1] * a;
    pre[i * 4 + 2] = src[i * 4 + 2] * a;
    pre[i * 4 + 3] = src[i * 4 + 3];
  }
  const chans = [0, 1, 2, 3].map((c) =>
    resampleChannel((x, y) => pre[(y * sw + x) * 4 + c], null, sw, sh, dw, dh));
  const out = new Uint8Array(dw * dh * 4);
  const q = (v) => Math.max(0, Math.min(255, Math.round(v)));
  for (let i = 0; i < dw * dh; i++) {
    const A = chans[3][i];
    out[i * 4 + 3] = q(A);
    if (A > 0.5) {
      out[i * 4] = q((chans[0][i] * 255) / A);
      out[i * 4 + 1] = q((chans[1][i] * 255) / A);
      out[i * 4 + 2] = q((chans[2][i] * 255) / A);
    }
  }
  return out;
}

// ---------------------------------------------------------------- 遮罩

/** 圆角矩形遮罩，基于有符号距离场做 1px AA */
function roundRectMask(w, h, r) {
  const m = new Float32Array(w * h);
  const hw = w / 2, hh = h / 2;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const dx = Math.abs(x + 0.5 - hw) - (hw - r);
      const dy = Math.abs(y + 0.5 - hh) - (hh - r);
      const qx = dx > 0 ? dx : 0, qy = dy > 0 ? dy : 0;
      // 圆角矩形标准 SDF：内部为负
      const dOut = Math.min(Math.max(dx, dy), 0) + Math.sqrt(qx * qx + qy * qy) - r;
      m[y * w + x] = clamp01(0.5 - dOut);
    }
  }
  return m;
}

/** 圆角矩形描边环（外遮罩减内遮罩），宽度 t 会取整成像素 */
function ringMask(w, h, r, t) {
  const it = Math.max(1, Math.round(t));
  const iw = w - 2 * it, ih = h - 2 * it;
  const outer = roundRectMask(w, h, r);
  const inner = iw > 0 && ih > 0 ? roundRectMask(iw, ih, Math.max(0, r - it)) : null;
  const m = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const inside = inner && x >= it && y >= it && x < w - it && y < h - it;
      const iv = inside ? inner[(y - it) * iw + (x - it)] : 0;
      m[y * w + x] = clamp01(outer[y * w + x] - iv);
    }
  }
  return m;
}

/** 可分离盒式模糊（3 趟近似高斯） */
function boxBlur(src, w, h, radius) {
  const r = Math.max(1, Math.round(radius));
  let a = Float32Array.from(src);
  let b = new Float32Array(w * h);
  const pass1d = (inp, out, len, stride, count, offsetStep) => {
    for (let i = 0; i < count; i++) {
      const base = i * offsetStep;
      let sum = 0;
      for (let k = -r; k <= r; k++) {
        const idx = Math.min(len - 1, Math.max(0, k));
        sum += inp[base + idx * stride];
      }
      const norm = 2 * r + 1;
      for (let j = 0; j < len; j++) {
        out[base + j * stride] = sum / norm;
        const add = Math.min(len - 1, j + r + 1);
        const rem = Math.max(0, j - r);
        sum += inp[base + add * stride] - inp[base + rem * stride];
      }
    }
  };
  const passes = 3;
  for (let p = 0; p < passes; p++) {
    pass1d(a, b, w, 1, h, w);            // 横向：每行 count=h，行内步长 1
    pass1d(b, a, h, w, w, 1);            // 纵向：每列 count=w，列内步长 w
  }
  return a;
}

// ---------------------------------------------------------------- 字体与文字

const fontCache = new Map();
function loadFont(file) {
  if (fontCache.has(file)) return fontCache.get(file);
  const b = fs.readFileSync(file);
  const f = opentype.parse(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength));
  fontCache.set(file, f);
  return f;
}

function flatten(font, text, x, baseline, size, tracking) {
  const contours = [];
  let cur = [];
  let pen = x;
  const cmds = [];
  const push = (c) => cmds.push(c);
  for (const ch of Array.from(text)) {
    const g = font.charToGlyph(ch);
    const p = g.getPath(pen, baseline, size);
    for (const c of p.commands) push(c);
    pen += (g.advanceWidth / font.unitsPerEm) * size + (tracking || 0);
  }
  // 展平
  let cx = 0, cy = 0;
  for (const c of cmds) {
    if (c.type === 'M') { if (cur.length > 1) contours.push(cur); cur = []; cx = c.x; cy = c.y; cur.push([cx, cy]); }
    else if (c.type === 'L') { cx = c.x; cy = c.y; cur.push([cx, cy]); }
    else if (c.type === 'Q' || c.type === 'C') {
      const steps = c.type === 'Q' ? 8 : 16;
      const x0 = cx, y0 = cy;
      for (let i = 1; i <= steps; i++) {
        const t = i / steps, mt = 1 - t;
        let px, py;
        if (c.type === 'Q') {
          px = mt * mt * x0 + 2 * mt * t * c.x1 + t * t * c.x;
          py = mt * mt * y0 + 2 * mt * t * c.y1 + t * t * c.y;
        } else {
          px = mt * mt * mt * x0 + 3 * mt * mt * t * c.x1 + 3 * mt * t * t * c.x2 + t * t * t * c.x;
          py = mt * mt * mt * y0 + 3 * mt * mt * t * c.y1 + 3 * mt * t * t * c.y2 + t * t * t * c.y;
        }
        cur.push([px, py]);
      }
      cx = c.x; cy = c.y;
    } else if (c.type === 'Z') {
      if (cur.length > 1) contours.push(cur);
      cur = [];
    }
  }
  if (cur.length > 1) contours.push(cur);
  return contours;
}

/** 把折线加粗成一组四边形（用于仿粗体描边） */
function strokeContours(contours, width) {
  const hw = width / 2;
  const out = [];
  for (const c of contours) {
    const closed = c.length > 2;
    const n = c.length;
    const last = closed ? n : n - 1;
    for (let i = 0; i < last; i++) {
      const p = c[i], q = c[(i + 1) % n];
      let vx = q[0] - p[0], vy = q[1] - p[1];
      const len = Math.hypot(vx, vy) || 1;
      vx /= len; vy /= len;
      const ax = p[0] - vx * hw, ay = p[1] - vy * hw;
      const bx = q[0] + vx * hw, by = q[1] + vy * hw;
      const nx = -vy * hw, ny = vx * hw;
      out.push([[ax + nx, ay + ny], [bx + nx, by + ny], [bx - nx, by - ny], [ax - nx, ay - ny]]);
    }
    // 端点圆帽（开放轮廓用）
    if (!closed) {
      for (const p of [c[0], c[n - 1]]) out.push(circleContour(p[0], p[1], hw, 12));
    }
  }
  return out;
}

function circleContour(cx, cy, r, seg) {
  const pts = [];
  for (let i = 0; i < seg; i++) {
    const a = (i / seg) * Math.PI * 2;
    pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]);
  }
  return pts;
}

/** 非零环绕扫描线填充，纵向 S 倍超采样后盒式降采样 */
function rasterize(contours, S = 4) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const c of contours) for (const [x, y] of c) {
    if (x < x0) x0 = x; if (x > x1) x1 = x;
    if (y < y0) y0 = y; if (y > y1) y1 = y;
  }
  if (!isFinite(x0)) return null;
  const px = 2;
  const bx = Math.floor(x0) - px, by = Math.floor(y0) - px;
  const w = Math.ceil(x1) + px - bx + 1, h = Math.ceil(y1) + px - by + 1;
  if (w <= 0 || h <= 0) return null;
  const mask = new Float32Array(w * h);
  const SH = h * S;
  const SW = w * S;
  const row = new Float64Array(SW + 2);
  const xs = [];
  for (let sy = 0; sy < SH; sy++) {
    const y = by + sy / S + 0.5 / S;
    xs.length = 0;
    for (const c of contours) {
      const n = c.length;
      for (let i = 0; i < n; i++) {
        const [ax, ay] = c[i], [bx2, by2] = c[(i + 1) % n];
        if (ay === by2) continue;
        if ((y >= ay && y < by2) || (y >= by2 && y < ay)) {
          const t = (y - ay) / (by2 - ay);
          xs.push([ax + (bx2 - ax) * t, by2 > ay ? 1 : -1]);
        }
      }
    }
    if (!xs.length) continue;
    xs.sort((a, b) => a[0] - b[0]);
    row.fill(0);
    let wnd = 0;
    for (let i = 0; i < xs.length - 1; i++) {
      wnd += xs[i][1];
      if (wnd === 0) continue;
      const a = (xs[i][0] - bx) * S, b = (xs[i + 1][0] - bx) * S;
      const sa = Math.max(0, a), sb = Math.min(SW, b);
      if (sb <= sa) continue;
      for (let sx = Math.floor(sa); sx < Math.ceil(sb); sx++) {
        const cov = Math.min(sb, sx + 1) - Math.max(sa, sx);
        if (cov > 0) row[sx] += cov;
      }
    }
    const ty = (sy / S) | 0;
    const base = ty * w;
    for (let tx = 0; tx < w; tx++) {
      let s = 0;
      for (let k = 0; k < S; k++) s += row[tx * S + k];
      mask[base + tx] += s / S;
    }
  }
  for (let i = 0; i < mask.length; i++) if (mask[i] > 1) mask[i] = 1;
  return { mask, w, h, x: bx, y: by };
}

function drawText(cv, font, text, opt) {
  const { size, x, baseline, color, alpha = 1, tracking = 0, weight = 0, align = 'left' } = opt;
  const width = measure(font, text, size, tracking);
  const ox = align === 'center' ? x - width / 2 : align === 'right' ? x - width : x;
  const contours = flatten(font, text, ox, baseline, size, tracking);
  const all = weight > 0 ? contours.concat(strokeContours(contours, size * weight)) : contours;
  const r = rasterize(all, 4);
  if (!r) return width;
  cv.compositeMask(r.x, r.y, r.mask, r.w, r.h, color, alpha);
  return width;
}

function measure(font, text, size, tracking = 0) {
  const w = font.getAdvanceWidth(text, size, { kerning: true });
  const n = Array.from(text).length;
  return w + tracking * Math.max(0, n - 1);
}

module.exports = {
  Canvas, hex, mix, clamp01, loadFont, drawText, measure,
  roundRectMask, ringMask, boxBlur, rasterize, flatten, strokeContours, circleContour,
  resampleRGB, resampleRGBA, jpeg, PNG, opentype,
};
