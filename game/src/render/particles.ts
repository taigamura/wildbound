// Pooled sprite particles (additive), shockwave rings, bloom flashes and
// element-flavoured impact bursts. Style-independent.
import { Sprite } from 'pixi.js';
import gsap from 'gsap';
import { L, TEX, TS, type TexName } from './app';
import { U, size } from './layout';
import { ELEM, type El } from '../core/data';
import { rand, pick, REDUCED } from '../core/util';

interface P { s: Sprite; alive: boolean; x: number; y: number; vx: number; vy: number; life: number; max: number; grav: number; drag: number;
  s0: number; s1: number; a0: number; swirl: number; spin: number; streak: boolean; floor: number | null; ts: number }
export interface EmitOpts {
  n?: number; color?: number | number[]; spd?: number; dir?: [number, number]; cone?: number; up?: number; flat?: boolean;
  r?: number; life?: number; grav?: number; drag?: number; swirl?: number; swirlDir?: number; size?: number; size1?: number;
  alpha?: number; tex?: TexName; streak?: boolean; spin?: number; floor?: number; normal?: boolean;
}
type Pt = { x: number; y: number };

const PN = 2200;
const parts: P[] = [];
let pi = 0;
const FX_MUL = REDUCED ? 0.5 : 1;

export function initParticles() {
  for (let i = 0; i < PN; i++) {
    const s = new Sprite(TEX.glow); s.anchor.set(0.5); s.blendMode = 'add'; s.visible = false; L.front.addChild(s);
    parts.push({ s, alive: false, x: 0, y: 0, vx: 0, vy: 0, life: 0, max: 1, grav: 0, drag: 1, s0: 1, s1: 1, a0: 1, swirl: 0, spin: 0, streak: false, floor: null, ts: 64 });
  }
  for (let i = 0; i < 12; i++) { const s = new Sprite(TEX.ring); s.anchor.set(0.5); s.blendMode = 'add'; s.visible = false; L.glow.addChild(s); rings.push(s); }
  for (let i = 0; i < 6; i++) { const s = new Sprite(TEX.soft); s.anchor.set(0.5); s.blendMode = 'add'; s.visible = false; L.glow.addChild(s); blooms.push(s); }
}

/** Speeds, sizes, gravity and radius are in world units (U); positions in pixels. */
export function emit(x: number, y: number, o: EmitOpts) {
  const n = Math.max(1, Math.round((o.n || 20) * FX_MUL));
  const cols = Array.isArray(o.color) ? o.color : [o.color ?? 0xffffff];
  const texName = o.tex || 'glow', tex = TEX[texName];
  for (let k = 0; k < n; k++) {
    const p = parts[pi]; pi = (pi + 1) % PN;
    let dx: number, dy: number;
    if (o.dir) { const c = o.cone ?? 0.4; dx = o.dir[0] + rand(-c, c); dy = o.dir[1] + rand(-c, c); }
    else { const a = Math.random() * Math.PI * 2; dx = Math.cos(a); dy = Math.sin(a); }
    if (o.up) dy = -Math.abs(dy) * o.up - 0.2;
    if (o.flat) dy *= 0.2;
    const len = Math.hypot(dx, dy) || 1, sp = (o.spd ?? 3) * (0.35 + Math.random() * 0.85) * U;
    p.vx = dx / len * sp; p.vy = dy / len * sp;
    const r = (o.r || 0) * U; p.x = x + rand(-r, r); p.y = y + rand(-r, r) * (o.flat ? 0.3 : 1);
    p.life = 0; p.max = (o.life ?? 0.8) * (0.55 + Math.random() * 0.7);
    p.grav = (o.grav ?? 0) * U; p.drag = o.drag ?? 1;
    p.swirl = o.swirlDir ?? ((o.swirl || 0) * (Math.random() < 0.5 ? 1 : -1));
    p.s0 = (o.size ?? 0.25) * (0.55 + Math.random() * 0.9) * U * 1.6; p.s1 = o.size1 ?? 0.1; p.a0 = o.alpha ?? 1;
    p.streak = !!o.streak; p.spin = o.spin ? rand(-o.spin, o.spin) : 0; p.floor = o.floor ?? null; p.ts = TS[texName]; p.alive = true;
    const s = p.s; if (s.texture !== tex) s.texture = tex;
    s.tint = pick(cols); s.visible = true; s.alpha = 0; s.rotation = o.spin ? rand(0, 6) : 0; s.blendMode = o.normal ? 'normal' : 'add';
    s.x = p.x; s.y = p.y; s.scale.set(p.s0 / p.ts);
  }
}

export function updateParticles(dt: number) {
  for (let i = 0; i < PN; i++) {
    const p = parts[i]; if (!p.alive) continue;
    p.life += dt; const t = p.life / p.max;
    if (t >= 1) { p.alive = false; p.s.visible = false; continue; }
    const dr = Math.max(0, 1 - p.drag * dt);
    p.vx *= dr; p.vy = p.vy * dr + p.grav * dt;
    if (p.swirl) { const a = p.swirl * dt, c = Math.cos(a), s = Math.sin(a), vx = p.vx; p.vx = vx * c - p.vy * s; p.vy = vx * s + p.vy * c; }
    p.x += p.vx * dt; p.y += p.vy * dt;
    if (p.floor != null && p.y > p.floor && p.vy > 0) { p.y = p.floor; p.vy *= -0.35; p.vx *= 0.7; }
    const sz = p.s0 * (1 + (p.s1 - 1) * t) / p.ts, s = p.s;
    s.x = p.x; s.y = p.y; s.alpha = p.a0 * (t < 0.08 ? t / 0.08 : 1 - (t - 0.08) / 0.92);
    if (p.streak) { s.rotation = Math.atan2(p.vy, p.vx); s.scale.set(sz * (1 + Math.min(3, Math.hypot(p.vx, p.vy) / (U * 3))), sz); }
    else { s.scale.set(sz); if (p.spin) s.rotation += p.spin * dt; }
  }
}

const rings: Sprite[] = [];
/** Shockwave ring. flat = squashed onto the ground plane. */
export function ring(x: number, y: number, hex: number, scale = 2, dur = 0.5, flat = true) {
  const s = rings.find(r => !r.visible) || rings[0]; gsap.killTweensOf(s); gsap.killTweensOf(s.scale);
  s.visible = true; s.x = x; s.y = y; s.tint = hex; s.alpha = 0.95; const k = scale * U / TS.ring * 1.6;
  s.scale.set(0.05, flat ? 0.02 : 0.05);
  gsap.to(s.scale, { x: k, y: flat ? k * 0.32 : k, duration: dur, ease: 'power2.out' });
  gsap.to(s, { alpha: 0, duration: dur, ease: 'power1.in', onComplete: () => { s.visible = false; } });
}

const blooms: Sprite[] = [];
/** Soft additive bloom at a point: the 2D stand-in for a light flash. */
export function lightFlash(hex: number, pos: Pt, v = 4) {
  const s = blooms.find(b => !b.visible) || blooms[0]; gsap.killTweensOf(s);
  s.visible = true; s.x = pos.x; s.y = pos.y; s.tint = hex; s.alpha = 0.55 * Math.min(1.4, v / 4);
  s.scale.set(U * 3.2 * Math.min(1.5, v / 4 + 0.4) / TS.soft);
  gsap.to(s, { alpha: 0, duration: 0.35, onComplete: () => { s.visible = false; } });
}

export function burst(p: Pt, el: El | null, power = 1) {
  const c = el ? ELEM[el].glow : [0xffffff, 0xd9ccff, 0x9b7bff];
  switch (el) {
    case 'ember':
      emit(p.x, p.y, { n: 50 * power, color: c, spd: 4.2 * power, life: 0.85, size: 0.3, size1: 0.05, grav: -2.6, drag: 2.2 });
      emit(p.x, p.y, { n: 22 * power, color: [0xfff1b0, 0xffa23d], spd: 7, life: 0.4, size: 0.18, drag: 4, tex: 'spark', streak: true }); break;
    case 'tide':
      emit(p.x, p.y, { n: 46 * power, color: c, spd: 4.6 * power, up: 1.2, life: 1.0, size: 0.22, size1: 0.5, grav: 9, drag: 0.5, floor: p.y + U * 0.9 });
      emit(p.x, p.y + U * 0.8, { n: 22 * power, color: c, spd: 3, flat: true, life: 0.6, size: 0.2, drag: 3 }); break;
    case 'thorn':
      emit(p.x, p.y, { n: 30 * power, color: c, spd: 3.4 * power, life: 1.3, size: 0.32, size1: 0.6, grav: 1.4, drag: 2.4, swirl: 6, tex: 'leaf', spin: 8 });
      emit(p.x, p.y, { n: 16 * power, color: c, spd: 3, life: 0.6, size: 0.22, drag: 3 }); break;
    case 'volt':
      emit(p.x, p.y, { n: 50 * power, color: c, spd: 8 * power, life: 0.32, size: 0.22, size1: 0.2, drag: 7, tex: 'spark', streak: true });
      emit(p.x, p.y, { n: 6 * power, color: [0xffffff], spd: 1, life: 0.15, size: 0.9, size1: 0.2, drag: 3, tex: 'star', spin: 6 }); break;
    default:
      emit(p.x, p.y, { n: 40 * power, color: c, spd: 4.5 * power, life: 0.6, size: 0.25, drag: 3 });
  }
  emit(p.x, p.y, { n: 14 * power, color: [0xffffff], spd: 7, life: 0.22, size: 0.16, drag: 5, tex: 'spark', streak: true });
  ring(p.x, p.y, el ? ELEM[el].hex : 0xd9ccff, 1.4 * power, 0.45, false);
}

/** Fireflies and drifting leaves. Colors come from the active art style's ambience. */
let ambT = 0, leafT = 0;
export function ambient(dt: number, fireflies: number[], leaves: number[]) {
  const { W, H } = size;
  ambT += dt; if (ambT > 0.07) { ambT = 0; emit(rand(0, W), rand(H * 0.3, H * 0.95), { n: 1, color: fireflies, spd: 0.25, life: 3.5, size: 0.11, size1: 1, grav: -0.06, drag: 0.2, alpha: 0.85 }); }
  leafT += dt; if (leafT > 0.5) { leafT = 0; emit(rand(-W * 0.1, W), -10, { n: 1, color: leaves, spd: 0.6, dir: [0.4, 1], cone: 0.2, life: 9, size: 0.2, size1: 1, grav: 0.05, drag: 0.1, alpha: 0.45, tex: 'leaf', spin: 1.5, swirl: 0.6, normal: true }); }
}
