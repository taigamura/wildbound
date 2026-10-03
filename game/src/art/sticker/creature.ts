// "Sticker" creatures: chunky outlined vector characters drawn with PixiJS Graphics.
// Options let the same drawing code produce other looks (the exporter uses flat mode
// to bake a sprite pack).
import { Container, Graphics, Sprite } from 'pixi.js';
import { TEX } from '../../render/app';
import { ELEM, SPECIES, type El } from '../../core/data';
import { rand } from '../../core/util';
import type { CreatureArt, Pt } from '../types';

export interface StickerOpts {
  outline: boolean;   // dark outline around every shape
  glow: boolean;      // additive glows on flames / antennae / crowns
  shine: boolean;     // highlight blob on the body
  outlineColor?: number;
}
export const STICKER: StickerOpts = { outline: true, glow: true, shine: true };

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const mix = (a: number, b: number, t: number) => {
  const ar = a >> 16, ag = a >> 8 & 255, ab = a & 255, br = b >> 16, bg = b >> 8 & 255, bb = b & 255;
  return (Math.round(lerp(ar, br, t)) << 16) | (Math.round(lerp(ag, bg, t)) << 8) | Math.round(lerp(ab, bb, t));
};

export class StickerCreature implements CreatureArt {
  view = new Container();
  head: Pt = { x: 8, y: -56 };
  emitters: Pt[] = [];
  private eyes: Container | null = null;
  private flick: Container[] = [];
  private wings: Container[] = [];
  private blink = rand(1, 4);

  constructor(private species: string, private el: El, private o: StickerOpts = STICKER) { this.draw(); }

  setElement(el: El) { this.el = el; this.draw(); }

  update(dt: number, t: number) {
    this.blink -= dt;
    if (this.eyes && this.blink < 0) { this.eyes.scale.y = 0.12; if (this.blink < -0.1) { this.eyes.scale.y = 1; this.blink = rand(1.5, 4.5); } }
    for (const f of this.flick) f.scale.y = 1 + Math.sin(t * 22 + f.x) * 0.1 + Math.random() * 0.06;
    this.wings.forEach((w, i) => { w.skew.y = Math.sin(t * 8 + i * 1.5) * 0.18; });
  }

  destroy() { this.view.destroy({ children: true }); }

  private draw() {
    const sp = SPECIES[this.species], col = ELEM[this.el].hex, o = this.o, OUT = o.outlineColor ?? 0x14102a;
    const main = mix(col, 0x000000, 0.06), light = mix(col, 0xffffff, 0.5), dark = mix(col, 0x000000, 0.55), bone = 0xfff0d8;
    this.view.removeChildren().forEach(c => c.destroy({ children: true }));
    this.flick = []; this.wings = []; this.emitters = [];
    const S = (w = 5) => o.outline ? { width: w, color: OUT } : { width: 0, color: OUT, alpha: 0 };
    const G = () => { const g = new Graphics(); this.view.addChild(g); return g; };
    const sub = (x: number, y: number) => { const c = new Container(); c.x = x; c.y = y; this.view.addChild(c); return c; };
    const glowAt = (parent: Container, x: number, y: number, s: number, hex: number) => {
      if (!o.glow) return; const g = new Sprite(TEX.glow); g.anchor.set(0.5); g.blendMode = 'add'; g.tint = hex; g.x = x; g.y = y; g.scale.set(s / 64); parent.addChild(g);
    };
    const f = new Set(sp.feats);

    // --- behind the body
    if (f.has('wings')) for (const sx of [-1, 1]) {
      const w = sub(sx < 0 ? -26 : 4, -72), g = new Graphics();
      g.ellipse(-22, -8, 34, 16).fill(dark).stroke(S()); g.ellipse(-26, -8, 22, 8).fill({ color: mix(col, 0xffffff, 0.2), alpha: 0.5 });
      w.addChild(g); w.rotation = sx < 0 ? -0.5 : -0.2; w.alpha = sx < 0 ? 1 : 0.85; this.wings.push(w);
    }
    if (f.has('tail')) { const g = G(); ([[-58, -34, 15], [-72, -48, 12], [-80, -64, 10]] as const).forEach(([x, y, r], i) => g.circle(x, y, r).fill(i === 2 ? light : main).stroke(S())); if (this.el === 'ember') this.emitters.push({ x: -80, y: -64 }); }
    if (f.has('fin')) G().poly([-14, -88, -42, -122, -46, -74]).fill(light).stroke(S());
    if (f.has('spikes')) { const g = G(); for (let k = 0; k < 5; k++) {
      const a = (100 + k * 22) * Math.PI / 180, bx = Math.cos(a) * 50, by = -48 - Math.sin(a) * 44, nx = Math.cos(a), ny = -Math.sin(a), tx = -ny, ty = nx;
      g.poly([bx + tx * 9, by + ty * 9, bx + nx * 24, by + ny * 24, bx - tx * 9, by - ty * 9]).fill(bone).stroke(S(4));
    } }
    if (f.has('ears')) { const g = G();
      g.poly([-36, -78, -30, -124, -6, -92]).fill(main).stroke(S()); g.poly([-29, -84, -27, -112, -12, -92]).fill(light);
      g.poly([6, -94, 24, -128, 36, -82]).fill(main).stroke(S()); g.poly([12, -94, 24, -116, 30, -86]).fill(light); }
    if (f.has('horns')) { const g = G(); g.poly([-16, -88, -30, -126, -2, -94]).fill(bone).stroke(S(4)); g.poly([16, -92, 30, -128, 32, -86]).fill(bone).stroke(S(4)); }
    if (f.has('antenna')) { const g = G();
      g.moveTo(-6, -90).lineTo(-16, -126).stroke({ width: 4, color: o.outline ? OUT : dark, cap: 'round' });
      g.moveTo(16, -92).lineTo(28, -126).stroke({ width: 4, color: o.outline ? OUT : dark, cap: 'round' });
      for (const [x, y] of [[-16, -128], [28, -128]]) { const c = sub(x, y); glowAt(c, 0, 0, 40, 0xfff27a); const d = new Graphics(); d.circle(0, 0, 7).fill(0xfff6b0).stroke(S(3)); c.addChild(d); this.flick.push(c); this.emitters.push({ x, y }); } }

    // --- body
    const body = G();
    body.ellipse(0, -48, 52, 46).fill(main).stroke(S());
    if (o.shine) body.ellipse(-14, -66, 22, 12).fill({ color: 0xffffff, alpha: 0.18 });
    body.ellipse(12, -36, 30, 24).fill(light);
    body.ellipse(-20, -3, 17, 9).fill(dark).stroke(S(4)); body.ellipse(22, -3, 17, 9).fill(dark).stroke(S(4));
    if (f.has('fin')) { const w = sub(-6, -40), g = new Graphics(); g.ellipse(-10, 0, 20, 10).fill(light).stroke(S(4)); w.addChild(g); this.wings.push(w); }
    if (f.has('leaf')) { const g = G(); g.moveTo(2, -92).lineTo(2, -110).stroke({ width: 4, color: o.outline ? OUT : dark });
      for (const sx of [-1, 1]) { const w = sub(2, -108), l = new Graphics(); l.ellipse(sx * 20, 0, 22, 9).fill(light).stroke(S(4)); l.moveTo(0, 0).lineTo(sx * 34, 0).stroke({ width: 2, color: dark }); w.addChild(l); w.rotation = sx * -0.45; this.wings.push(w); } }
    if (f.has('flame')) { const c = sub(4, -90); glowAt(c, 0, -24, 90, 0xff8a3d); const g = new Graphics();
      g.poly([-15, 0, -12, -24, -3, -42, 3, -28, 10, -50, 17, -22, 14, 0]).fill(0xff7a2a).stroke(S(4));
      g.poly([-8, 0, -5, -16, 1, -26, 5, -16, 8, 0]).fill(0xffe08a); c.addChild(g); this.flick.push(c); this.emitters.push({ x: 6, y: -136 }); }
    if (f.has('crown')) { const c = sub(4, -92); glowAt(c, 0, -10, 90, 0xffcf6b); const g = new Graphics();
      g.poly([-26, 0, -22, -26, -12, -10, -2, -32, 8, -10, 18, -26, 24, 0]).fill(0xffcf6b).stroke(S(4)); g.circle(-2, -10, 4).fill(0xff5a6e); c.addChild(g); this.flick.push(c); }

    // --- face
    const eyes = new Container(); eyes.y = -60; this.view.addChild(eyes); this.eyes = eyes;
    const eg = new Graphics(); eyes.addChild(eg);
    for (const [x, s] of [[8, 0.92], [34, 1]] as const) {
      eg.ellipse(x, 0, 11 * s, 13 * s).fill(0xffffff).stroke(o.outline ? { width: 3.5, color: OUT } : { width: 0, alpha: 0 });
      eg.ellipse(x + 3, 1, 6.5 * s, 8 * s).fill(0x14101f); eg.circle(x + 5, -4, 2.6 * s).fill(0xffffff);
    }
    if (sp.boss || sp.warden) { eg.moveTo(-4, -16).lineTo(18, -10).stroke({ width: 4, color: 0x14102a, cap: 'round' }); eg.moveTo(46, -14).lineTo(26, -9).stroke({ width: 4, color: 0x14102a, cap: 'round' }); }
    const mouth = G(); mouth.moveTo(16, -42).quadraticCurveTo(22, -36, 30, -42).stroke({ width: 3, color: 0x14102a, cap: 'round' });
    mouth.circle(-2, -46, 5).fill({ color: 0xff8fb0, alpha: 0.45 }); mouth.circle(44, -45, 4).fill({ color: 0xff8fb0, alpha: 0.45 });
    if (f.has('whisk')) { const g = G(); g.moveTo(42, -48).lineTo(64, -54).stroke({ width: 2.5, color: 0x14102a, cap: 'round' }); g.moveTo(42, -44).lineTo(64, -40).stroke({ width: 2.5, color: 0x14102a, cap: 'round' }); }
  }
}
