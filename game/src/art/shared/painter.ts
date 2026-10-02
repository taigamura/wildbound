// Procedural scene + pedestal painter, driven by a palette. Used by the sticker style,
// and by sprite packs as a fallback when they don't ship a background image.
import { Container, Graphics, Sprite, Texture } from 'pixi.js';
import { canvasTex, TEX, TS } from '../../render/app';
import { ELEM, EL_KEYS } from '../../core/data';
import { rand, pick } from '../../core/util';
import type { SceneArt, PedestalArt } from '../types';

export interface ScenePalette {
  sky: [string, string, string];        // top, middle, horizon
  celestial: 'moon' | 'sun' | 'none';
  celestialColor: string;
  celestialGlow: string;                 // rgba(...) inner glow colour
  stars: number;                         // how many painted stars (0 = none)
  twinkleColors: number[];
  hills: [string, string];               // far, near
  trees: string;
  ground: [string, string, string];      // top, middle, bottom
  grass: string;                         // rgba stroke
  crystalColors: number[];               // glowing crystal clusters
  mushroomColors: number[];
  pedestal: { top: number; rim: number; inner: number; shadow: number };
}

export const NIGHT: ScenePalette = {
  sky: ['#2a1a5e', '#1a1745', '#141b3a'], celestial: 'moon', celestialColor: '#efe9ff', celestialGlow: 'rgba(200,180,255,.35)',
  stars: 140, twinkleColors: [0xffffff, 0xd9ccff, 0x8fe3ff],
  hills: ['#1d1f4d', '#171a3d'], trees: '#0f1430', ground: ['#16224a', '#121c3a', '#0c1226'], grass: 'rgba(120,140,255,.12)',
  crystalColors: EL_KEYS.map(k => ELEM[k].hex), mushroomColors: [0x6ef3ff, 0xff7ad9, 0xb48cff],
  pedestal: { top: 0x1d2b52, rim: 0x2c3c70, inner: 0x24366a, shadow: 0x05070f },
};

/** Paints the static backdrop into one texture; adds animated twinkles and glowing props on top. */
export function paintedScene(pal: ScenePalette, image?: { tex: Texture; horizon: number }): SceneArt {
  let bg: Container, deco: Container, backdrop: Sprite | null = null;
  const twinkles: (Sprite & { ph?: number })[] = [];
  const props: { c: Container; halo: Sprite; ph: number }[] = [];

  function clear() {
    if (backdrop) { if (!image) backdrop.texture.destroy(true); backdrop.destroy(); backdrop = null; }
    twinkles.forEach(t => t.destroy()); twinkles.length = 0;
    props.forEach(p => p.c.destroy({ children: true })); props.length = 0;
  }

  function paint(W: number, H: number, hz: number) {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    return canvasTex(Math.ceil(W * dpr), Math.ceil(H * dpr), g => {
      g.scale(dpr, dpr);
      const sky = g.createLinearGradient(0, 0, 0, hz + 40); sky.addColorStop(0, pal.sky[0]); sky.addColorStop(0.7, pal.sky[1]); sky.addColorStop(1, pal.sky[2]);
      g.fillStyle = sky; g.fillRect(0, 0, W, hz + 40);
      if (pal.celestial !== 'none') {
        const sun = pal.celestial === 'sun';
        const mx = sun ? W * 0.3 : W * 0.78, my = sun ? hz - H * 0.04 : H * 0.1, mr = Math.min(W, H) * (sun ? 0.11 : 0.06);
        const halo = g.createRadialGradient(mx, my, mr * 0.5, mx, my, mr * 4); halo.addColorStop(0, pal.celestialGlow); halo.addColorStop(1, 'rgba(0,0,0,0)');
        g.fillStyle = halo; g.fillRect(0, 0, W, hz + 20);
        g.fillStyle = pal.celestialColor; g.beginPath(); g.arc(mx, my, mr, 0, Math.PI * 2); g.fill();
        if (!sun) { g.fillStyle = pal.sky[0]; g.beginPath(); g.arc(mx + mr * 0.45, my - mr * 0.2, mr * 0.88, 0, Math.PI * 2); g.fill(); }
      }
      for (let i = 0; i < pal.stars; i++) { g.fillStyle = `rgba(223,228,255,${rand(0.25, 0.9)})`; g.fillRect(rand(0, W), rand(0, hz * 0.95), rand(0.8, 1.8), rand(0.8, 1.8)); }
      const hill = (y: number, amp: number, col: string, seed: number) => {
        g.fillStyle = col; g.beginPath(); g.moveTo(0, H); g.lineTo(0, y);
        for (let x = 0; x <= W + 20; x += 20) g.lineTo(x, y - Math.sin(x * 0.008 + seed) * amp - Math.sin(x * 0.021 + seed * 2) * amp * 0.4);
        g.lineTo(W, H); g.closePath(); g.fill();
      };
      hill(hz - 30, 26, pal.hills[0], 1); hill(hz - 8, 18, pal.hills[1], 3);
      g.fillStyle = pal.trees;
      for (let x = -20; x < W + 20; x += rand(12, 22)) { const th = rand(30, 80); g.beginPath(); g.moveTo(x - th * 0.22, hz + 6); g.lineTo(x, hz + 6 - th); g.lineTo(x + th * 0.22, hz + 6); g.closePath(); g.fill(); }
      const gr = g.createLinearGradient(0, hz, 0, H); gr.addColorStop(0, pal.ground[0]); gr.addColorStop(0.5, pal.ground[1]); gr.addColorStop(1, pal.ground[2]);
      g.fillStyle = gr; g.fillRect(0, hz + 4, W, H);
      g.strokeStyle = pal.grass; g.lineWidth = 1.5;
      for (let i = 0; i < 160; i++) { const x = rand(0, W), y = rand(hz + 10, H), s = rand(3, 8) * (0.5 + (y - hz) / H); g.beginPath(); g.moveTo(x, y); g.lineTo(x - s * 0.4, y - s); g.moveTo(x, y); g.lineTo(x + s * 0.4, y - s * 1.1); g.stroke(); }
    });
  }

  function addProps(W: number, H: number, hz: number) {
    for (let i = 0; i < 9; i++) {
      const side = i % 2 ? 1 : -1;
      const x = side > 0 ? rand(W * 0.72, W * 1.02) : rand(-W * 0.02, W * 0.28);
      const y = rand(hz + 12, H * 0.98), depth = (y - hz) / (H - hz), s = (0.4 + depth) * Math.min(W, H) * 0.05;
      const c = new Container(); c.x = x; c.y = y;
      const halo = new Sprite(TEX.soft); halo.anchor.set(0.5); halo.blendMode = 'add'; halo.alpha = 0.35; halo.scale.set(s / 40); halo.y = -s * 0.8; c.addChild(halo);
      const g = new Graphics();
      if (Math.random() < 0.6) {
        const col = pick(pal.crystalColors); halo.tint = col;
        ([[0, 1.6, 0.42], [-0.45, 1.0, 0.3], [0.42, 1.15, 0.32]] as const).forEach(([dx, hh, ww]) => {
          g.poly([dx * s - ww * s, 0, dx * s, -hh * s, dx * s + ww * s, 0, dx * s, 0.2 * s]).fill({ color: col, alpha: 0.85 }).stroke({ width: 2, color: 0xffffff, alpha: 0.35 });
          g.poly([dx * s, -hh * s, dx * s + ww * s, 0, dx * s, 0.2 * s]).fill({ color: 0x000000, alpha: 0.25 });
        });
      } else {
        const cc = pick(pal.mushroomColors); halo.tint = cc;
        g.roundRect(-s * 0.12, -s * 0.8, s * 0.24, s * 0.8, s * 0.1).fill(0xd8d2ff);
        g.ellipse(0, -s * 0.8, s * 0.55, s * 0.32).fill(cc); g.ellipse(-s * 0.18, -s * 0.9, s * 0.08, s * 0.06).fill({ color: 0xffffff, alpha: 0.7 });
      }
      c.addChild(g); deco.addChild(c); props.push({ c, halo, ph: rand(0, 6) });
    }
  }

  return {
    mount(b, d) { bg = b; deco = d; },
    resize(W, H, hz) {
      clear();
      if (image) {
        const s = new Sprite(image.tex), tw = image.tex.width, th = image.tex.height;
        const sc = Math.max(W / tw, H / th); s.scale.set(sc);
        s.x = (W - tw * sc) / 2; s.y = clampY(hz - image.horizon * th * sc, H - th * sc, 0);
        backdrop = s;
      } else backdrop = new Sprite(paint(W, H, hz));
      if (!image) { backdrop.width = W; backdrop.height = H; }
      bg.addChildAt(backdrop, 0);
      if (pal.twinkleColors.length && pal.stars > 0) for (let i = 0; i < 26; i++) {
        const s = new Sprite(TEX.star) as Sprite & { ph?: number }; s.anchor.set(0.5); s.blendMode = 'add';
        s.x = rand(0, W); s.y = rand(0, H * 0.32); s.scale.set(rand(0.12, 0.3)); s.tint = pick(pal.twinkleColors); s.ph = rand(0, 6);
        bg.addChild(s); twinkles.push(s);
      }
      addProps(W, H, hz);
    },
    update(t) {
      twinkles.forEach(s => { s.alpha = 0.4 + 0.6 * Math.abs(Math.sin(t * 1.3 + (s.ph || 0))); });
      props.forEach(p => { p.halo.alpha = 0.22 + 0.18 * Math.sin(t * 1.6 + p.ph); });
    },
    destroy: clear,
  };
}
const clampY = (v: number, min: number, max: number) => Math.max(min, Math.min(max, v));

/** Oval stone platform with a rotating rune and a glowing rim tinted by the arena colour. */
export function paintedPedestal(pal: ScenePalette, image?: Texture): PedestalArt {
  const view = new Container();
  const base = new Graphics(); view.addChild(base);
  const img = image ? new Sprite(image) : null; if (img) { img.anchor.set(0.5, 0.35); view.addChild(img); }
  const rim = new Sprite(TEX.ring); rim.anchor.set(0.5); rim.blendMode = 'add'; view.addChild(rim);
  const runeWrap = new Container(), rune = new Graphics(); runeWrap.addChild(rune); runeWrap.scale.y = 0.28; view.addChild(runeWrap);
  const glow = new Sprite(TEX.soft); glow.anchor.set(0.5); glow.blendMode = 'add'; glow.alpha = 0.25; view.addChild(glow);
  let lastW = 0;
  return {
    view,
    update(x, y, w, tint, t) {
      view.x = x; view.y = y;
      if (Math.abs(lastW - w) > 0.5) {
        lastW = w; base.clear();
        if (img) { img.width = w * 2.1; img.scale.y = img.scale.x; }
        else {
          base.ellipse(0, 6, w * 1.05, w * 0.3).fill({ color: pal.pedestal.shadow, alpha: 0.6 });
          base.ellipse(0, 0, w, w * 0.28).fill(pal.pedestal.top).stroke({ width: 3, color: pal.pedestal.rim });
          base.ellipse(0, -2, w * 0.82, w * 0.2).fill({ color: pal.pedestal.inner, alpha: 0.8 });
        }
        rune.clear(); const pts: number[] = [];
        for (let i = 0; i < 6; i++) { const a = i / 6 * Math.PI * 2; pts.push(Math.cos(a) * w * 0.66, Math.sin(a) * w * 0.66); }
        rune.poly(pts).stroke({ width: 2.5, color: 0xffffff, alpha: 0.5 });
      }
      rim.scale.set(w * 2.02 / TS.ring, w * 0.58 / TS.ring); rim.tint = tint; rim.alpha = 0.55 + Math.sin(t * 2) * 0.15;
      rune.rotation = t * 0.25; rune.tint = tint;
      glow.scale.set(w * 2.2 / TS.soft, w * 0.7 / TS.soft); glow.tint = tint;
    },
    destroy() { view.destroy({ children: true }); },
  };
}
