// HD-2D diorama: the procedural background and pedestal of the hd2d pack (CLAUDE.md §13).
//
// Every plane is painted once per resize into a small canvas at low resolution (P screen
// px per art pixel), so the frame loop only moves sprites; there are no live filters.
//   bg:   sky → far ridge + ruins (blurred) → mid treeline (soft) → sun/moon bloom → ground (crisp pixels, nearest)
//   deco: near framing trunk/pillar/lanterns (soft) → light shafts (additive) → glows →
//         out-of-focus foreground strips top and bottom (heavy blur, tilt-shift) → bokeh → motes → key-light wash → vignette
// Depth of field is baked: the ground band where creatures stand is the only crisp plane,
// and blur grows with distance from it. Parallax is a slow camera "breath" around that plane.
import { Container, Sprite, Texture } from 'pixi.js';
import { TEX, TS } from '../../../render/app';
import type { PedestalArt, SceneArt } from '../../types';

type Pt2 = [number, number];

interface Look {
  sky: [string, string, string];
  celestial: { moon: boolean; x: number; y: number; color: string; glow: number; stars: number };
  clouds: string | null;
  ridge: [string, string, string];          // back, front, lit
  ruins: [string, string];                  // body, lit edge
  windows: string | null;                   // warm castle windows (night)
  tree: [string, string, string];           // shadow, mid, lit
  pines: boolean;
  bark: [string, string, string];           // dark, mid, lit
  canopy: [string, string];                 // near canopy dark, lit edge
  ground: string[];                         // dark → light ramp
  stone: string[];                          // flagstones dark → light
  moss: string;
  flowers: string[];
  warmPool: string | null;                  // lantern light on the ground
  lanterns: boolean;
  fg: string;                               // out-of-focus foreground silhouettes
  shaft: number; shaftAlpha: number;
  key: number; keyAlpha: number;            // upper-left key-light wash
  glow: number;                             // lantern / window glow
  bokeh: number[];
  motes: number[]; firefly: boolean;
  vignette: string;
}

/** Biome A (floors 1–4): sunlit forest ruins, warm. */
const FOREST: Look = {
  sky: ['#79aecb', '#d9dcb8', '#f6d595'],
  celestial: { moon: false, x: 0.16, y: 0.13, color: '#fff6d8', glow: 0xffe7a8, stars: 0 },
  clouds: '#fff3dc',
  ridge: ['#a7bdb6', '#8aa596', '#d3dbbd'],
  ruins: ['#7d9488', '#c3cdb0'],
  windows: null,
  tree: ['#3f5f45', '#5f8253', '#a6c06e'],
  pines: false,
  bark: ['#2c2a22', '#4a4434', '#9c8c5e'],
  canopy: ['#203722', '#5d7d3e'],
  ground: ['#2f4a2c', '#3e5e33', '#53763d', '#6c8f46', '#8eab58', '#bdc67a'],
  stone: ['#5a5444', '#776f5a', '#968c74', '#b5aa8c'],
  moss: '#6f9a45',
  flowers: ['#fff1c9', '#ffd36e', '#ff9fb3'],
  warmPool: null,
  lanterns: false,
  fg: '#1a2a17',
  shaft: 0xffe2a0, shaftAlpha: 0.2,
  key: 0xffd28a, keyAlpha: 0.24,
  glow: 0xffd27a,
  bokeh: [0xffe6a8, 0xfff3d0, 0xd8f0a0],
  motes: [0xfff2c0, 0xffe08a, 0xffffff], firefly: false,
  vignette: 'rgba(38,24,8,.6)',
};

/** Biome B (floors 5–8): moonlit dusk, cool blue with warm lanterns. */
const MOONLIT: Look = {
  sky: ['#10183a', '#263867', '#6d7fae'],
  celestial: { moon: true, x: 0.2, y: 0.12, color: '#eef3ff', glow: 0xb8ccff, stars: 90 },
  clouds: null,
  ridge: ['#33447a', '#28365f', '#5a71a8'],
  ruins: ['#222d52', '#56699c'],
  windows: '#ffc56e',
  tree: ['#151d3a', '#22305a', '#5b70a8'],
  pines: true,
  bark: ['#0e1226', '#1a2140', '#6577ad'],
  canopy: ['#0c1128', '#3a4c80'],
  ground: ['#121a34', '#1b2646', '#26345a', '#33456f', '#465c8a', '#6479a8'],
  stone: ['#2b3252', '#3b4468', '#4f5a82', '#6a759c'],
  moss: '#3d5a6e',
  flowers: ['#9fd8ff', '#c9b8ff', '#ffe0a0'],
  warmPool: '#c98a52',
  lanterns: true,
  fg: '#070b1c',
  shaft: 0xa8c4ff, shaftAlpha: 0.13,
  key: 0x9fb8ff, keyAlpha: 0.18,
  glow: 0xffb35c,
  bokeh: [0xffb35c, 0xffd28a, 0x8fb4ff],
  motes: [0xffd27a, 0xffb85c, 0xfff0b0], firefly: true,
  vignette: 'rgba(4,6,22,.7)',
};

const P = 3;      // screen px per art pixel for the pixel planes
const PS = 4;     // ...for the sky

/* ---------- small helpers ---------- */

function rng(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map(v => (v + 0.5) / 16);
const dither = (x: number, y: number) => BAYER[(y & 3) * 4 + (x & 3)];
const hexNum = (s: string) => parseInt(s.slice(1), 16);
const rgb = (s: string): [number, number, number] => { const n = hexNum(s); return [n >> 16, (n >> 8) & 255, n & 255]; };

function makeCanvas(w: number, h: number) {
  const c = document.createElement('canvas'); c.width = Math.max(1, Math.ceil(w)); c.height = Math.max(1, Math.ceil(h)); return c;
}
const ctx2d = (c: HTMLCanvasElement) => c.getContext('2d', { willReadFrequently: true })!;

function boxLine(a: Float32Array, start: number, stride: number, len: number, r: number, tmp: Float32Array) {
  const inv = 1 / (2 * r + 1); let sum = 0;
  for (let i = -r; i <= r; i++) sum += a[start + Math.min(len - 1, Math.max(0, i)) * stride];
  for (let i = 0; i < len; i++) {
    tmp[i] = sum * inv;
    sum += a[start + Math.min(len - 1, i + r + 1) * stride] - a[start + Math.max(0, i - r) * stride];
  }
  for (let i = 0; i < len; i++) a[start + i * stride] = tmp[i];
}
/** Gaussian-ish blur (3 box passes, premultiplied alpha), in place. The canvases are tiny, so this costs a few ms once per resize. */
function blur(c: HTMLCanvasElement, r: number) {
  r = Math.round(r); if (r <= 0) return c;
  const g = ctx2d(c), w = c.width, h = c.height, img = g.getImageData(0, 0, w, h), d = img.data, n = w * h;
  const ch = [0, 1, 2, 3].map(() => new Float32Array(n));
  for (let i = 0; i < n; i++) { const a = d[i * 4 + 3] / 255; ch[3][i] = a; ch[0][i] = d[i * 4] * a; ch[1][i] = d[i * 4 + 1] * a; ch[2][i] = d[i * 4 + 2] * a; }
  const tmp = new Float32Array(Math.max(w, h));
  for (const a of ch) for (let p = 0; p < 3; p++) {
    for (let y = 0; y < h; y++) boxLine(a, y * w, 1, w, r, tmp);
    for (let x = 0; x < w; x++) boxLine(a, x, w, h, r, tmp);
  }
  for (let i = 0; i < n; i++) { const a = ch[3][i]; d[i * 4 + 3] = a * 255; if (a > 0.002) { d[i * 4] = ch[0][i] / a; d[i * 4 + 1] = ch[1][i] / a; d[i * 4 + 2] = ch[2][i] / a; } }
  g.putImageData(img, 0, 0); return c;
}
/** Pixel-art edges: alpha becomes 0 or 1 (canvas paths anti-alias; pixel art doesn't). */
function hardAlpha(c: HTMLCanvasElement) {
  const g = ctx2d(c), img = g.getImageData(0, 0, c.width, c.height), d = img.data;
  for (let i = 3; i < d.length; i += 4) d[i] = d[i] > 110 ? 255 : 0;
  g.putImageData(img, 0, 0); return c;
}
function toTex(c: HTMLCanvasElement, nearest: boolean) {
  const t = Texture.from(c); if (nearest) t.source.scaleMode = 'nearest'; return t;
}
const px = (g: CanvasRenderingContext2D, col: string, x: number, y: number, w = 1, h = 1) => { g.fillStyle = col; g.fillRect(Math.round(x), Math.round(y), w, h); };
const disc = (g: CanvasRenderingContext2D, col: string, x: number, y: number, r: number) => { g.fillStyle = col; g.beginPath(); g.arc(x, y, Math.max(0.5, r), 0, Math.PI * 2); g.fill(); };

/* ---------- plane painters (all coordinates in low-res art pixels) ---------- */

function paintSky(L: Look, w: number, h: number, hz: number, R: () => number) {
  const c = makeCanvas(w, h), g = ctx2d(c);
  const grd = g.createLinearGradient(0, 0, 0, hz); grd.addColorStop(0, L.sky[0]); grd.addColorStop(0.62, L.sky[1]); grd.addColorStop(1, L.sky[2]);
  g.fillStyle = grd; g.fillRect(0, 0, w, h);
  const cx = L.celestial.x * w, cy = L.celestial.y * h;
  const halo = g.createRadialGradient(cx, cy, 0, cx, cy, w * 0.9);
  halo.addColorStop(0, L.celestial.moon ? 'rgba(200,215,255,.35)' : 'rgba(255,246,214,.55)'); halo.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = halo; g.fillRect(0, 0, w, h);
  if (L.clouds) {   // soft cumulus banks, lit from the upper left
    g.globalAlpha = 0.5;
    for (let i = 0; i < 9; i++) {
      const x = R() * w, y = hz * (0.25 + R() * 0.45), s = w * (0.05 + R() * 0.07);
      for (let k = 0; k < 5; k++) disc(g, L.clouds, x + (k - 2) * s * 0.8, y + Math.abs(k - 2) * s * 0.25, s * (1 - Math.abs(k - 2) * 0.18));
    }
    g.globalAlpha = 1;
  }
  blur(c, 2);
  for (let i = 0; i < L.celestial.stars; i++) { g.fillStyle = `rgba(230,236,255,${0.25 + R() * 0.6})`; g.fillRect(Math.floor(R() * w), Math.floor(R() * hz * 0.85), 1, 1); }
  if (L.celestial.moon) {
    const r = Math.max(3, w * 0.055);
    disc(g, L.celestial.color, cx, cy, r);
    disc(g, 'rgba(160,175,215,.35)', cx + r * 0.25, cy + r * 0.15, r * 0.35);
    disc(g, 'rgba(160,175,215,.3)', cx - r * 0.35, cy - r * 0.3, r * 0.2);
  }
  return c;
}

/** Distant ridges with ruins (colonnade by day, a castle with lit windows by night). Returns window points. */
function paintFar(L: Look, w: number, h: number, hz: number, R: () => number) {
  const c = makeCanvas(w, h), g = ctx2d(c), wins: Pt2[] = [];
  const ph = [R() * 6, R() * 6, R() * 6, R() * 6];
  const ridge = (x: number, base: number, amp: number, s: number) => base - amp * (0.55 + 0.3 * Math.sin(x * 0.045 * s + ph[0]) + 0.2 * Math.sin(x * 0.11 * s + ph[1]) + 0.08 * Math.sin(x * 0.31 + ph[2]));
  const fill = (col: string, base: number, amp: number, s: number) => {
    for (let x = 0; x < w; x++) {
      const y = Math.round(ridge(x, base, amp, s)), yn = Math.round(ridge(x + 1, base, amp, s));
      px(g, col, x, y, 1, h - y);
      if (yn < y) px(g, L.ridge[2], x, y, 1, Math.min(6, (y - yn) * 3 + 1));   // slope facing the key light
    }
  };
  fill(L.ridge[0], hz - h * 0.03, h * 0.16, 1);
  // ruins on the front ridge
  const front = (x: number) => Math.round(ridge(x, hz + 1, h * 0.07, 1.6));
  const rx = Math.round(w * (L.windows ? 0.66 : 0.6));
  if (!L.windows) {
    const n = 7, gap = Math.max(3, Math.round(w * 0.022));
    let top = front(rx) - Math.round(h * 0.07);
    for (let i = 0; i < n; i++) {
      const x = rx + i * gap, broken = i === 2 || i === 5, ch = Math.round(h * (broken ? 0.035 : 0.07));
      px(g, L.ruins[0], x, front(x) - ch, 2, ch + 4); px(g, L.ruins[1], x, front(x) - ch, 1, ch);
      if (!broken && i < 4) top = front(x) - ch;
    }
    px(g, L.ruins[0], rx - 1, top - 2, gap * 4 + 2, 2); px(g, L.ruins[1], rx - 1, top - 2, gap * 4 + 2, 1);   // surviving architrave
    const tx = Math.round(w * 0.2), th = Math.round(h * 0.12);                                               // lone tower
    px(g, L.ruins[0], tx, front(tx) - th, 5, th + 4); px(g, L.ruins[1], tx, front(tx) - th, 1, th);
    px(g, L.ruins[0], tx + 1, front(tx) - th - 2, 2, 2);
  } else {
    const bw = Math.round(w * 0.16), by = front(rx) - Math.round(h * 0.06);
    px(g, L.ruins[0], rx, by, bw, h - by);
    [[0, 0.13], [0.42, 0.18], [0.85, 0.11]].forEach(([fx, fh]) => {
      const x = rx + Math.round(fx * bw) - 1, th = Math.round(h * fh);
      px(g, L.ruins[0], x, by - th, 4, th); px(g, L.ruins[1], x, by - th, 1, th);
      for (let k = 0; k < 4; k++) px(g, L.ruins[0], x + 2 - Math.ceil(k / 2), by - th - 4 + k, Math.max(1, k + 1), 1);   // spire
      wins.push([x + 2, by - th * 0.6]); px(g, L.windows!, x + 2, Math.round(by - th * 0.6), 1, 1);
    });
    for (let k = 0; k < 3; k++) { const x = rx + 3 + Math.round(R() * (bw - 6)), y = by + 2 + Math.round(R() * 3); px(g, L.windows, x, y, 1, 1); wins.push([x, y]); }
  }
  fill(L.ridge[1], hz + 1, h * 0.07, 1.6);
  return { c, wins };
}

/** Mid treeline (round canopies by day, pines by night) with broken pillars. */
function paintMid(L: Look, w: number, h: number, hz: number, R: () => number) {
  const c = makeCanvas(w, h), g = ctx2d(c), base = hz + 2;
  for (let x = -6; x < w + 6; x += 4 + R() * 7) {
    const th = h * (0.12 + R() * 0.12) * (0.7 + 0.5 * Math.abs(Math.sin(x * 0.05)));
    if (L.pines) {
      for (let k = 0; k < 3; k++) {
        const ty = base - th * (0.3 + k * 0.28), hw = th * (0.32 - k * 0.07);
        g.fillStyle = L.tree[k === 2 ? 1 : 0]; g.beginPath(); g.moveTo(x - hw, ty + th * 0.3); g.lineTo(x, ty - th * 0.2); g.lineTo(x + hw, ty + th * 0.3); g.fill();
        g.strokeStyle = L.tree[2]; g.lineWidth = 1; g.beginPath(); g.moveTo(x - hw + 0.5, ty + th * 0.3); g.lineTo(x, ty - th * 0.2); g.stroke();   // moonlit left edge
      }
    } else {
      px(g, L.tree[0], x - 1, base - th * 0.4, 2, th * 0.4);
      const r = th * 0.32;
      disc(g, L.tree[0], x, base - th * 0.6, r); disc(g, L.tree[0], x + r * 0.7, base - th * 0.45, r * 0.8);
      disc(g, L.tree[1], x - r * 0.25, base - th * 0.66, r * 0.72);
      disc(g, L.tree[2], x - r * 0.45, base - th * 0.76, r * 0.32);
    }
  }
  // two broken pillars standing in front of the treeline
  [[0.24, 0.17], [0.8, 0.12]].forEach(([fx, fh]) => {
    const x = Math.round(w * fx), ph = Math.round(h * fh), pw = 4;
    px(g, L.ruins[0], x, base - ph, pw, ph + 2); px(g, L.ruins[1], x, base - ph, 1, ph);
    px(g, L.ruins[0], x - 1, base - ph - 2, pw + 2, 2); px(g, L.ruins[1], x - 1, base - ph - 2, pw + 2, 1);
    px(g, L.ruins[0], x + 1, base - ph - 4, 2, 2);                   // jagged break
    for (let k = 0; k < 6; k++) px(g, L.moss, x + Math.round(R() * pw), base - Math.round(R() * ph * 0.7), 1, 1);
  });
  return c;
}

/** The ground plane: dithered light ramp, a ruined flagstone plaza where the fight happens, grass and flowers. */
function paintGround(L: Look, w: number, h: number, R: () => number, pools: Pt2[]) {
  const c = makeCanvas(w, h), g = ctx2d(c), top = 3;
  const ramp = L.ground.map(rgb), n = ramp.length - 1, warm = L.warmPool ? rgb(L.warmPool) : null;
  const img = g.createImageData(w, h), d = img.data;
  const edge = Array.from({ length: w }, (_, x) => top - Math.round(1 + Math.sin(x * 0.7) + Math.sin(x * 0.23 + 2) + R() * 1.2));
  // light: hazy-bright far, darker near, a pool of key light where the fight happens, brighter toward the light (left)
  const light = (x: number, y: number) => {
    const t = Math.max(0, (y - top) / (h - top)), fx = x / w;
    const pool = Math.exp(-(((fx - 0.5) / 0.4) ** 2) - (((t - 0.3) / 0.32) ** 2));
    return 0.62 - 0.42 * t + 0.28 * pool + 0.12 * (1 - fx);
  };
  const level = (x: number, y: number, lv: number) => Math.max(0, Math.min(n, Math.floor(lv * n + 0.5 + (dither(x, y) - 0.5) * 0.55)));
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (y < edge[x]) continue;
    const k = level(x, y, light(x, y) - (y <= edge[x] + 1 ? 0.15 : 0));
    let [r, gg, b] = ramp[k];
    if (warm) {
      let wv = 0; for (const [lx, ly] of pools) wv += Math.exp(-(((x - lx) / (w * 0.13)) ** 2) - (((y - ly) / (h * 0.09)) ** 2));
      const a = wv > 0.62 ? 0.42 : wv > 0.3 + dither(x, y) * 0.2 ? 0.24 : 0;   // two stepped rings of lantern light
      r += (warm[0] - r) * a; gg += (warm[1] - gg) * a; b += (warm[2] - b) * a;
    }
    const i = (y * w + x) * 4; d[i] = r; d[i + 1] = gg; d[i + 2] = b; d[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  // flagstone plaza, broken at the edges
  const sr = L.stone, cy = top + (h - top) * 0.3;
  for (let y = top + 1, row = 0; y < h * 0.85; row++) {
    const t = (y - top) / (h - top), rh = Math.round(3 + 5 * t), tw = Math.round(6 + 12 * t), off = row % 2 ? tw / 2 : 0;
    for (let x = -off; x < w; x += tw) {
      const mx = (x + tw / 2) / w - 0.5, my = (y + rh / 2 - cy) / (h * 0.36);
      const inside = mx * mx / 0.1 + my * my;
      if (inside > 1 - R() * 0.25 || R() < 0.12 + inside * 0.25) continue;
      const lit = 0.62 - 0.3 * t + 0.25 * (0.5 - mx) + 0.2 * (1 - inside);
      const k = Math.max(1, Math.min(3, Math.floor(lit * 3 + R() * 0.6)));
      const x0 = Math.round(x) + 1, y0 = Math.round(y);
      px(g, sr[0], x0 - 1, y0 - 1, tw + 1, rh + 1);                  // grout lines, so the slabs read as stone, not stripes
      px(g, sr[k], x0, y0, tw - 1, rh - 1);
      px(g, sr[Math.min(3, k + 1)], x0, y0, tw - 1, 1);               // lit top edge
      px(g, sr[Math.max(0, k - 1)], x0 + tw - 2, y0 + 1, 1, rh - 2);  // shaded right edge
      if (R() < 0.35) px(g, L.moss, x0 + Math.round(R() * (tw - 3)), y0 + rh - 2, 1 + Math.round(R() * 2), 1);
    }
    y += rh;
  }
  // grass tufts (denser toward the edges and the front) and flowers
  for (let i = 0; i < w * h / 80; i++) {
    const x = Math.floor(R() * w), y = top + Math.floor(R() * (h - top)), t = (y - top) / (h - top);
    const mx = x / w - 0.5, my = (y - cy) / (h * 0.36);
    if (mx * mx / 0.1 + my * my < 0.9 && R() < 0.9) continue;
    const k = level(x, y, light(x, y)), s = 1 + Math.round(t * 2 * R());
    const dk = L.ground[Math.max(0, k - 1)], lt = L.ground[Math.min(n, k + 1)];
    px(g, dk, x, y - s, 1, s + 1); px(g, dk, x - 1, y - s + 1, 1, s); px(g, dk, x + 1, y - s + 1, 1, s);
    px(g, lt, x - 1, y - s, 1, 1); if (s > 1) px(g, lt, x + 1, y - s, 1, 1);
  }
  for (let i = 0; i < w * h / 600; i++) {
    const x = Math.floor(R() * w), y = top + 2 + Math.floor(R() * (h - top - 2));
    px(g, L.flowers[Math.floor(R() * L.flowers.length)], x, y, 1, 1);
  }
  return c;
}

/** Near framing: a big tree trunk on the left; a broken pillar (day) or stone lantern (night) on the right. Returns lantern points. */
function paintSides(L: Look, w: number, h: number, hz: number, pad: number, R: () => number) {
  const c = makeCanvas(w, h), g = ctx2d(c), lamps: Pt2[] = [], feet: Pt2[] = [];
  const gy = (f: number) => Math.round(hz + (h - hz) * f);
  // left trunk
  const tx = pad + Math.round(w * 0.015), tw = Math.round(w * 0.085), foot = gy(0.5);
  for (let y = 0; y < foot; y++) {
    const flare = y > foot - 8 ? (y - (foot - 8)) * 0.9 : 0, x0 = Math.round(tx - flare), ww = Math.round(tw + flare * 1.6);
    px(g, L.bark[1], x0 - pad, y, ww + pad, 1);
    px(g, L.bark[0], x0 + ww - 2, y, 2, 1);                                   // the inner face turns away from the key light
    if (R() < 0.35) px(g, L.bark[0], x0 + Math.round(R() * (ww - 3)), y, 1, 2 + Math.round(R() * 3));
  }
  for (let y = 0; y < foot - 4; y++) if ((y >> 2) % 3 !== 0) px(g, L.bark[2], tx + Math.round(tw * 0.3), y, 1, 1);   // lit bark ridge
  // left canopy mass
  for (let i = 0; i < 16; i++) {
    const x = pad + R() * w * 0.32 - w * 0.04, y = R() * h * 0.12, r = w * (0.04 + R() * 0.05);
    disc(g, L.canopy[0], x, y, r);
    if (R() < 0.6) disc(g, L.canopy[1], x - r * 0.35, y - r * 0.2, r * 0.45);
  }
  // roots and moss at the foot
  for (let k = 0; k < 10; k++) px(g, L.moss, tx - 4 + Math.round(R() * (tw + 8)), foot - Math.round(R() * 3), 1 + Math.round(R()), 1);

  const rx = Math.round(w - pad - w * 0.11);
  if (!L.lanterns) {
    // broken fluted pillar with ivy
    const pw = Math.round(w * 0.075), pf = gy(0.42), ptop = Math.round(h * 0.2);
    for (let y = ptop; y < pf; y++) {
      const jag = y < ptop + 5 ? Math.round(R() * 3) : 0;
      for (let x = jag; x < pw; x++) {
        const f = x % 4, col = x < 2 ? L.stone[3] : f === 0 ? L.stone[0] : x > pw - 3 ? L.stone[0] : L.stone[f === 1 ? 2 : 1];
        px(g, col, rx + x, y, 1, 1);
      }
    }
    px(g, L.stone[1], rx - 2, pf - 4, pw + 4, 4); px(g, L.stone[2], rx - 2, pf - 4, pw + 4, 1);
    for (let k = 0; k < 40; k++) { const y = ptop + Math.round(R() * (pf - ptop)), x = rx + Math.round(R() * pw * 0.7); px(g, k % 3 ? L.canopy[1] : L.moss, x, y, 1 + Math.round(R()), 1); }
  } else {
    // stone lanterns (tōrō): right, large and near; left, small at the trunk's foot
    const lantern = (x: number, foot: number, s: number) => {
      const bw = Math.round(7 * s), ph = Math.round(18 * s), bx = x - Math.round(bw / 2);
      px(g, L.stone[1], bx + 2, foot - ph, bw - 4, ph); px(g, L.stone[3], bx + 2, foot - ph, 1, ph);
      px(g, L.stone[0], bx, foot - 2, bw, 2);
      const fy = foot - ph - Math.round(6 * s);
      px(g, L.stone[1], bx, fy, bw, Math.round(6 * s)); px(g, '#ffd27a', bx + 2, fy + 2, bw - 4, Math.max(1, Math.round(6 * s) - 3));
      px(g, L.stone[2], bx - 2, fy - 2, bw + 4, 2); px(g, L.stone[3], bx - 2, fy - 2, bw + 4, 1);
      px(g, L.stone[1], bx + 1, fy - 4, bw - 2, 2); px(g, L.stone[1], x - 1, fy - 6, 2, 2);
      lamps.push([x, fy + 3 * s]); feet.push([x, foot]);
    };
    lantern(rx + 6, gy(0.46), 1.6);
    lantern(tx + tw + 14, gy(0.3), 0.9);
  }
  return { c, lamps, feet };
}

/** Out-of-focus foreground: hanging leaves or branches along the top, tall grass along the bottom. */
function paintFg(L: Look, w: number, h: number, top: boolean, R: () => number) {
  const c = makeCanvas(w, h), g = ctx2d(c);
  g.fillStyle = L.fg;
  if (top) {
    for (let i = 0; i < 26; i++) {
      const x = R() * w, len = h * (0.25 + R() * 0.45), r = w * (0.02 + R() * 0.035);
      if (L.pines) { g.fillRect(x - w * 0.12, len * 0.4, w * 0.24, 1.5); for (let k = 0; k < 6; k++) disc(g, L.fg, x - w * 0.1 + k * w * 0.04, len * 0.4 + 2, r * 0.7); }
      else { g.beginPath(); g.ellipse(x, len * 0.6, r, len * 0.5, (R() - 0.5) * 0.6, 0, Math.PI * 2); g.fill(); }
    }
    g.fillRect(0, 0, w, h * 0.18);
  } else {
    for (let i = 0; i < 40; i++) {
      const x = R() * w, ht = h * (0.3 + R() * 0.45), lean = (R() - 0.5) * w * 0.08, bw = w * (0.008 + R() * 0.012);
      g.beginPath(); g.moveTo(x - bw, h); g.quadraticCurveTo(x + lean * 0.3, h - ht * 0.6, x + lean, h - ht); g.quadraticCurveTo(x + lean * 0.3 + bw, h - ht * 0.5, x + bw, h); g.fill();
    }
    g.fillRect(0, h * 0.75, w, h * 0.25);
  }
  return blur(c, 3);
}

function shaftTexture() {
  const c = makeCanvas(32, 256), g = ctx2d(c);
  const across = g.createLinearGradient(0, 0, 32, 0);
  across.addColorStop(0, 'rgba(255,255,255,0)'); across.addColorStop(0.5, 'rgba(255,255,255,1)'); across.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = across; g.fillRect(0, 0, 32, 256);
  g.globalCompositeOperation = 'destination-in';
  const along = g.createLinearGradient(0, 0, 0, 256);
  along.addColorStop(0, 'rgba(255,255,255,.9)'); along.addColorStop(0.55, 'rgba(255,255,255,.45)'); along.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = along; g.fillRect(0, 0, 32, 256);
  return toTex(c, false);
}

function vignetteTexture(col: string) {
  const c = makeCanvas(90, 160), g = ctx2d(c);
  const r = g.createRadialGradient(45, 86, 20, 45, 86, 104);
  r.addColorStop(0, 'rgba(0,0,0,0)'); r.addColorStop(0.55, 'rgba(0,0,0,0)'); r.addColorStop(1, col);
  g.fillStyle = r; g.fillRect(0, 0, 90, 160);
  return toTex(c, false);
}

/* ---------- the scene ---------- */

interface Plane { c: Container; depth: number; x0: number; sway?: Sprite; swayAmt?: number }
interface Mote { s: Sprite; vx: number; vy: number; ph: number; a: number }

export function hd2dScene(biome: number): SceneArt {
  const L = biome ? MOONLIT : FOREST;
  let bg: Container, deco: Container;
  let made: { root: Container[]; textures: Texture[] } | null = null;
  let key = '', W = 0, H = 0;
  const planes: Plane[] = [];
  const shafts: { s: Sprite; a: number; ph: number }[] = [];
  const glows: { s: Sprite; a: number; ph: number; flicker: boolean }[] = [];
  const bokeh: { s: Sprite; a: number; ph: number; x0: number; y0: number }[] = [];
  const motes: Mote[] = [];

  function clear() {
    if (!made) return;
    made.root.forEach(c => c.destroy({ children: true }));
    made.textures.forEach(t => t.destroy(true));
    made = null; planes.length = shafts.length = glows.length = bokeh.length = motes.length = 0;
  }

  function build(hz: number) {
    const R = rng(biome ? 7331 : 4242), textures: Texture[] = [], root: Container[] = [];
    const pad = Math.ceil(W * 0.06 / P) * P, lw = Math.ceil((W + pad * 2) / P), lh = Math.ceil(H / P), lhz = Math.round(hz / P);
    const bgRoot = new Container(), decoRoot = new Container(); bg.addChild(bgRoot); deco.addChild(decoRoot); root.push(bgRoot, decoRoot);
    const plane = (parent: Container, cv: HTMLCanvasElement, scale: number, depth: number, nearest: boolean, y = 0, sway = 0) => {
      const t = toTex(cv, nearest); textures.push(t);
      const c = new Container(), s = new Sprite(t); s.scale.set(scale);
      if (sway) { s.anchor.set(0, 1); s.y = cv.height * scale; }
      c.addChild(s); c.x = -pad; c.y = y; parent.addChild(c);
      planes.push({ c, depth, x0: -pad, sway: sway ? s : undefined, swayAmt: sway });
      return c;
    };
    const glow = (parent: Container, x: number, y: number, size: number, tint: number, a: number, flicker = false) => {
      const s = new Sprite(TEX.soft); s.anchor.set(0.5); s.blendMode = 'add'; s.tint = tint; s.alpha = a;
      s.scale.set(size / TS.soft); s.x = x; s.y = y; parent.addChild(s); glows.push({ s, a, ph: R() * 6, flicker });
      return s;
    };

    // sky, at PS px per pixel, smooth
    const sw = Math.ceil((W + pad * 2) / PS), sh = Math.ceil((hz + 40) / PS);
    plane(bgRoot, paintSky(L, sw, sh, Math.round(hz / PS), R), PS, 0.4, false);
    const cel = planes[planes.length - 1].c, celX = L.celestial.x * sw * PS, celY = L.celestial.y * sh * PS;
    glow(cel, celX, celY, Math.min(W, H) * (L.celestial.moon ? 0.7 : 1.3), L.celestial.glow, L.celestial.moon ? 0.35 : 0.6);
    if (L.celestial.stars) for (let i = 0; i < 18; i++) {
      const s = new Sprite(TEX.star); s.anchor.set(0.5); s.blendMode = 'add'; s.tint = 0xdfe6ff; s.scale.set(0.1 + R() * 0.15);
      s.x = R() * (W + pad * 2); s.y = R() * hz * 0.7; cel.addChild(s); glows.push({ s, a: 0.7, ph: R() * 6, flicker: true });
    }
    // far ridge + ruins: strongest blur
    const far = paintFar(L, lw, lhz + 6, lhz, R); blur(far.c, 2);
    const farC = plane(bgRoot, far.c, P, 0.8, false);
    far.wins.forEach(([x, y]) => glow(farC, x * P, y * P, U8(W) * 0.5, L.glow, 0.35, true));
    // mid treeline: softer blur, gentle sway
    const mid = paintMid(L, lw, lhz + 6, lhz, R); hardAlpha(mid); blur(mid, 1);
    plane(bgRoot, mid, P, 0.5, false, 0, 0.012);
    // ground: the in-focus plane, crisp pixels, no parallax
    const pools: Pt2[] = [];
    const sides = paintSides(L, lw, lh, lhz, Math.round(pad / P), R);
    const gTop = lhz - 3, gh = lh - gTop;
    sides.feet.forEach(([x, y]) => pools.push([x - pad / P, y - gTop]));
    plane(bgRoot, paintGround(L, Math.ceil(W / P), gh, R, pools), P, 0, true, gTop * P).x = 0;
    planes[planes.length - 1].x0 = 0;
    // near framing: slightly soft (closer than the focus plane)
    hardAlpha(sides.c); blur(sides.c, 1);
    const sideC = plane(decoRoot, sides.c, P, -0.6, false, 0, 0.005);
    sides.lamps.forEach(([x, y]) => { glow(sideC, x * P, y * P, U8(W) * 1.4, L.glow, 0.55, true); glow(sideC, x * P, y * P, U8(W) * 0.45, 0xfff0c8, 0.6, true); });

    // light shafts from the upper left (additive)
    const st = shaftTexture(); textures.push(st);
    for (let i = 0; i < 5; i++) {
      const s = new Sprite(st); s.anchor.set(0.5, 0); s.blendMode = 'add'; s.tint = L.shaft;
      s.rotation = -0.42 - R() * 0.12; s.x = -W * 0.1 + i * W * 0.15 + R() * W * 0.06; s.y = -H * 0.05;
      s.width = W * (0.07 + R() * 0.12); s.height = H * (0.75 + R() * 0.3);
      decoRoot.addChild(s); shafts.push({ s, a: L.shaftAlpha * (0.6 + R() * 0.6), ph: R() * 6 });
    }
    // out-of-focus foreground strips (tilt-shift)
    const fgH = Math.ceil(H * 0.14 / P);
    plane(decoRoot, paintFg(L, lw, fgH, true, R), P, -1, false, -P * 2);
    plane(decoRoot, paintFg(L, lw, fgH, false, R), P, -1, false, H - fgH * P + P * 2);
    for (let i = 0; i < 7; i++) {
      const s = new Sprite(TEX.soft); s.anchor.set(0.5); s.blendMode = 'add'; s.tint = L.bokeh[i % L.bokeh.length];
      const topSide = i % 2 === 0, x0 = R() * W, y0 = topSide ? R() * H * 0.12 : H - R() * H * 0.14;
      s.scale.set(W * (0.06 + R() * 0.08) / TS.soft * 2); s.x = x0; s.y = y0;
      decoRoot.addChild(s); bokeh.push({ s, a: 0.12 + R() * 0.16, ph: R() * 6, x0, y0 });
    }
    // dust motes in the light, or fireflies at night
    for (let i = 0; i < 34; i++) {
      const s = new Sprite(TEX.glow); s.anchor.set(0.5); s.blendMode = 'add'; s.tint = L.motes[i % L.motes.length];
      s.scale.set((L.firefly ? 0.09 : 0.05) + R() * 0.06); s.x = R() * W; s.y = H * (0.08 + R() * 0.62);
      decoRoot.addChild(s); motes.push({ s, vx: (R() - 0.3) * 6, vy: -(2 + R() * 6), ph: R() * 6, a: 0.35 + R() * 0.5 });
    }
    // key-light wash (bloom from the upper left) and vignette
    glow(decoRoot, W * 0.06, H * 0.02, Math.max(W, H) * 1.3, L.key, L.keyAlpha);
    const vt = vignetteTexture(L.vignette); textures.push(vt);
    const v = new Sprite(vt); v.width = W; v.height = H; decoRoot.addChild(v);
    made = { root, textures };
  }

  return {
    mount(b, d) { bg = b; deco = d; },
    resize(w, h, hz) {
      const k = `${w}x${h}x${Math.round(hz)}`; if (k === key && made) return;
      key = k; W = w; H = h; clear(); build(hz);
    },
    update(t, dt) {
      const A = W * 0.018, cam = Math.sin(t * 0.09) + 0.45 * Math.sin(t * 0.053 + 1.3);
      for (const p of planes) {
        p.c.x = p.x0 + cam * A * p.depth;
        if (p.sway) p.sway.skew.x = Math.sin(t * 0.7 + p.depth * 3) * (p.swayAmt || 0);
      }
      for (const s of shafts) s.s.alpha = s.a * (0.65 + 0.35 * Math.sin(t * 0.35 + s.ph));
      for (const g of glows) if (g.flicker) g.s.alpha = g.a * (0.78 + 0.14 * Math.sin(t * 7.3 + g.ph) + 0.08 * Math.sin(t * 12.1 + g.ph * 2));
      for (const b of bokeh) { b.s.alpha = b.a * (0.7 + 0.3 * Math.sin(t * 0.5 + b.ph)); b.s.x = b.x0 + Math.sin(t * 0.13 + b.ph) * W * 0.03; b.s.y = b.y0 + Math.cos(t * 0.11 + b.ph) * H * 0.008; }
      const k = Math.min(dt, 0.1);
      for (const m of motes) {
        m.s.x += (m.vx + Math.sin(t * 0.8 + m.ph) * 8) * k; m.s.y += m.vy * k;
        if (m.s.y < H * 0.04) { m.s.y = H * 0.72; m.s.x = Math.random() * W; }
        if (m.s.x > W + 10) m.s.x = -10; else if (m.s.x < -10) m.s.x = W + 10;
        const tw = Math.sin(t * (L.firefly ? 2.2 : 1.1) + m.ph);
        m.s.alpha = m.a * (L.firefly ? Math.max(0, tw) ** 2 : 0.55 + 0.45 * tw);
      }
    },
    destroy() { clear(); key = ''; },
  };
}
/** A size unit for glows that tracks the screen (glows read the same on phones and tablets). */
const U8 = (W: number) => Math.min(W, 520) * 0.18;

/* ---------- pedestal: a lit pixel-art stone disc ---------- */

let pedTex: Texture | null = null;
function pedestalTexture() {
  if (pedTex) return pedTex;
  const w = 48, h = 17, cx = 23.5, cy = 6.5, rx = 23, ry = 6, thick = 4;
  const ramp = ['#3b3644', '#544d5c', '#71697a', '#918a96', '#b8b0b4', '#d8d0c4'].map(rgb);
  const c = makeCanvas(w, h), g = ctx2d(c), img = g.createImageData(w, h), d = img.data, R = rng(99);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const nx = (x + 0.5 - cx) / rx, nyTop = (y + 0.5 - cy) / ry, nySide = (y + 0.5 - cy - thick) / ry;
    const onTop = nx * nx + nyTop * nyTop <= 1, onSide = !onTop && nx * nx + nySide * nySide <= 1 && y + 0.5 > cy;
    if (!onTop && !onSide) continue;
    let lv: number;
    if (onTop) {
      const rim = nx * nx + nyTop * nyTop > 0.78;
      lv = 0.62 - 0.22 * nx - 0.28 * nyTop + (rim ? -0.18 : 0) + (R() < 0.06 ? -0.2 : 0);   // key light from the upper left
      const ring = Math.abs(Math.sqrt(nx * nx + nyTop * nyTop) - 0.55) < 0.06;                  // carved ring
      if (ring) lv -= 0.16;
    } else lv = 0.3 - 0.2 * nx - (y > h - 3 ? 0.12 : 0) + ((x & 3) === 0 ? -0.06 : 0);
    const k = Math.max(0, Math.min(ramp.length - 1, Math.floor(lv * (ramp.length - 1) + dither(x, y) * 0.9)));
    const i = (y * w + x) * 4; [d[i], d[i + 1], d[i + 2]] = ramp[k]; d[i + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  pedTex = toTex(c, true);
  return pedTex;
}

export function hd2dPedestal(): PedestalArt {
  const view = new Container();
  const shadow = new Sprite(TEX.soft); shadow.anchor.set(0.5); shadow.tint = 0x000000; shadow.alpha = 0.55;
  const glow = new Sprite(TEX.soft); glow.anchor.set(0.5); glow.blendMode = 'add'; glow.alpha = 0.22;
  const disc = new Sprite(pedestalTexture()); disc.anchor.set(23.5 / 48, 6.5 / 17);
  const rim = new Sprite(TEX.ring); rim.anchor.set(0.5); rim.blendMode = 'add';
  const sheen = new Sprite(TEX.soft); sheen.anchor.set(0.5); sheen.blendMode = 'add'; sheen.tint = 0xfff0d0; sheen.alpha = 0.18;
  view.addChild(shadow, glow, disc, rim, sheen);
  return {
    view,
    update(x, y, w, tint, t) {
      view.x = x; view.y = y;
      disc.width = w * 2.1; disc.scale.y = disc.scale.x;
      // soft contact shadow, pushed down-right (light from the upper left)
      shadow.scale.set(w * 2.6 / TS.soft, w * 0.85 / TS.soft); shadow.x = w * 0.12; shadow.y = w * 0.16;
      glow.scale.set(w * 2.4 / TS.soft, w * 0.8 / TS.soft); glow.tint = tint; glow.alpha = 0.18 + Math.sin(t * 2) * 0.05;
      rim.scale.set(w * 1.75 / TS.ring, w * 0.46 / TS.ring); rim.tint = tint; rim.alpha = 0.28 + Math.sin(t * 2) * 0.08;
      sheen.scale.set(w * 0.9 / TS.soft, w * 0.25 / TS.soft); sheen.x = -w * 0.35; sheen.y = -w * 0.08;
    },
    destroy() { view.destroy({ children: true }); },
  };
}
