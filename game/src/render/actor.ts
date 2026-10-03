// An on-screen creature. Owns position, facing, squash/stretch, hit flash and idle bob,
// and holds whatever CreatureArt the active style provides. Gameplay talks to Actors only.
import { Container, Graphics, Sprite, ColorMatrixFilter } from 'pixi.js';
import gsap from 'gsap';
import { L, TEX, TS } from './app';
import { U } from './layout';
import { emit } from './particles';
import { getStyle } from '../art/registry';
import type { CreatureArt, Pt } from '../art/types';
import { ELEM, SPECIES, type El } from '../core/data';
import { rand, pick, clamp } from '../core/util';

const ART_UNIT = 56; // art-space units per world unit (U)

export class Actor {
  root = new Container();
  flip = new Container();  // facing + scale
  rig = new Container();   // idle bob (driven every frame)
  sq = new Container();    // squash & stretch (gsap)
  aura = new Sprite(TEX.soft);
  shadow = new Graphics();
  art: CreatureArt;
  /** Lunge/knockback offset in world units (tweened). */
  off = { x: 0, y: 0 };
  extra = 1;   // extra scale (alphas, title screen)
  evoScale = 1; // evolution fallback (no evolved art in this style): bigger + glow
  private halo = new Sprite(TEX.soft);
  private look: ColorMatrixFilter | null = null;
  private shiny = false; private silhouette = false;
  k = 1;       // art-space → px
  face = 1;
  el: El;
  private t = rand(0, 10);
  private filter: ColorMatrixFilter | null = null;

  constructor(public key: string, el?: El) {
    this.el = el || SPECIES[key].el;
    this.aura.anchor.set(0.5); this.aura.blendMode = 'add'; this.aura.alpha = 0;
    this.shadow.ellipse(0, 0, 46, 11).fill({ color: 0x000000, alpha: 0.4 });
    this.halo.anchor.set(0.5); this.halo.blendMode = 'add'; this.halo.visible = false;
    this.root.addChild(this.shadow, this.aura, this.halo, this.flip); this.flip.addChild(this.rig); this.rig.addChild(this.sq);
    this.art = getStyle().creature(key, this.el); this.sq.addChild(this.art.view);
    L.actors.addChild(this.root);
  }

  /** Total scale on top of species size (alpha/title extra × evolution fallback). */
  get scaleMul() { return this.extra * this.evoScale; }

  /** Shiny: a hue shift on whatever art the style provides. */
  setShiny(v: boolean) { this.shiny = v; this.applyLook(); }
  /** Unowned creatures in the collection: solid dark shape. */
  setSilhouette(v: boolean) { this.silhouette = v; this.applyLook(); }
  /** Evolved, but the style has no evolved art: draw the base art bigger with a glow. */
  setEvoFallback(v: boolean) { this.evoScale = v ? 1.2 : 1; this.halo.visible = v; }
  private applyLook() {
    if (!this.shiny && !this.silhouette) { if (this.look) { this.sq.filters = null; this.look.destroy(); this.look = null; } return; }
    if (!this.look) { this.look = new ColorMatrixFilter(); this.sq.filters = [this.look]; }
    if (this.silhouette) { this.look.brightness(0, false); this.look.alpha = 1; }
    else { this.look.hue(150, false); this.look.saturate(0.25, true); this.look.alpha = 1; }
  }

  get visible() { return this.root.visible; }
  set visible(v: boolean) { this.root.visible = v; }

  /** Put the feet at (x, y) in px. face 1 = right, -1 = left. */
  place(x: number, y: number, face: number) {
    const s = SPECIES[this.key].size * this.scaleMul;
    this.k = U / ART_UNIT * s; this.face = face;
    this.root.x = x + this.off.x * U; this.root.y = y + this.off.y * U;
    this.flip.scale.set(face * this.k, this.k);
    this.shadow.y = -this.off.y * U; this.shadow.scale.set(this.k * clamp(1 + this.off.y * 0.2, 0.3, 1.2));
    this.aura.scale.set(this.k * 160 / TS.soft); this.aura.y = -48 * this.k;
    if (this.halo.visible) { this.halo.tint = ELEM[this.el].hex; this.halo.scale.set(this.k * 230 / TS.soft); this.halo.y = -50 * this.k; }
  }

  /** Head position in px (projectile target, damage numbers). */
  head(): Pt { return { x: this.root.x + this.art.head.x * this.k * this.face, y: this.root.y + this.art.head.y * this.k }; }

  setElement(el: El) { this.el = el; this.art.setElement(el); }

  setFlash(v: number) {
    if (v <= 0.01) { if (this.filter) { this.flip.filters = null; this.filter.destroy(); this.filter = null; } return; }
    if (!this.filter) { this.filter = new ColorMatrixFilter(); this.flip.filters = [this.filter]; }
    this.filter.brightness(1 + v * 2.2, false);
  }
  hitFlash() {
    const o = { v: 1 }; this.setFlash(1);
    gsap.to(o, { v: 0, duration: 0.22, onUpdate: () => this.setFlash(o.v) });
    gsap.fromTo(this.sq.scale, { x: 1.25, y: 0.75 }, { x: 1, y: 1, duration: 0.45, ease: 'elastic.out(1,0.4)' });
  }

  update(dt: number) {
    this.t += dt; const t = this.t;
    this.rig.y = -Math.abs(Math.sin(t * 3.2)) * 5; this.rig.rotation = Math.sin(t * 1.6) * 0.03;
    this.rig.scale.set(1 + Math.sin(t * 6.4) * 0.015, 1 - Math.sin(t * 6.4) * 0.015);
    this.art.update?.(dt, t);
    if (this.halo.visible) this.halo.alpha = 0.45 + Math.sin(t * 3) * 0.15;
    const em = this.art.emitters;
    if (this.root.visible && em.length && Math.random() < dt * 10) {
      const p = pick(em);
      emit(this.root.x + p.x * this.k * this.face, this.root.y + (p.y + this.rig.y) * this.k, { n: 1, color: ELEM[this.el].glow, spd: 0.4, up: 1, life: 0.8, size: 0.14, grav: -1.2, drag: 1 });
    }
  }

  destroy() {
    [this.off, this.sq.scale, this.flip, this.rig, this.sq, this.root].forEach(o => gsap.killTweensOf(o));
    this.setFlash(0); this.shiny = this.silhouette = false; this.applyLook(); this.art.destroy(); this.root.destroy({ children: true });
  }
}

/* ---------- shield bubble around the active partner ---------- */
const shieldC = new Container();
const shieldRing = new Sprite(); const shieldFill = new Sprite(); const shieldHex = new Graphics();
export const shieldPulse = { s: 1 };
export function initShield() {
  shieldRing.texture = TEX.ring; shieldFill.texture = TEX.soft;
  [shieldRing, shieldFill].forEach(s => { s.anchor.set(0.5); s.blendMode = 'add'; });
  shieldRing.tint = 0x8fe3ff; shieldFill.tint = 0x3fb6ff; shieldFill.alpha = 0.35;
  const p: number[] = []; for (let i = 0; i < 6; i++) { const a = i / 6 * Math.PI * 2 + Math.PI / 6; p.push(Math.cos(a) * 50, Math.sin(a) * 50); }
  shieldHex.poly(p).stroke({ width: 3, color: 0x8fe3ff, alpha: 0.8 }); shieldHex.blendMode = 'add';
  shieldC.addChild(shieldFill, shieldRing, shieldHex); shieldC.alpha = 0; L.glow.addChild(shieldC);
}
export function updateShield(a: Actor | null, shield: number, active: boolean, t: number) {
  if (!a || !a.visible || !active) { shieldC.alpha = 0; return; }
  shieldC.alpha += (Math.min(1, shield / 20) * 0.9 - shieldC.alpha) * 0.2;
  shieldC.x = a.root.x; shieldC.y = a.root.y - 48 * a.k;
  const r = 64 * a.k * shieldPulse.s;
  shieldRing.scale.set(r * 2 / TS.ring); shieldFill.scale.set(r * 2.2 / TS.soft); shieldHex.scale.set(r / 50); shieldHex.rotation = t * 0.6;
}
