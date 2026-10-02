// Screen-level feedback: damage numbers, banners, flashes, shake, hit-stop.
import gsap from 'gsap';
import { world } from './app';
import { $, rand, REDUCED } from '../core/util';

export const feel = { trauma: 0, hitStop: 0 };
type Pt = { x: number; y: number };

export function popNum(pos: Pt, text: string | number, cls = '', label = '') {
  const d = document.createElement('div'); d.className = 'num ' + cls;
  d.style.left = (pos.x + world.x + rand(-18, 18)) + 'px'; d.style.top = (pos.y + world.y) + 'px';
  d.innerHTML = text + (label ? `<small>${label}</small>` : ''); $('#fx').appendChild(d); setTimeout(() => d.remove(), 950);
}
export function banner(text: string, sub = '', color = '#9b7bff') {
  const b = $('#banner'); b.style.setProperty('--bc', color); b.innerHTML = text + (sub ? `<small>${sub}</small>` : '');
  b.classList.remove('go'); void b.offsetWidth; b.classList.add('go');
}
export function flash(op = 0.5, color = '#fff') { const f = $('#flash'); f.style.background = color; gsap.fromTo(f, { opacity: op }, { opacity: 0, duration: 0.35, ease: 'power2.out' }); }
export function vignette() { gsap.fromTo('#vig', { opacity: 0.55 }, { opacity: 0, duration: 0.5 }); }
let toastT = 0;
export function toast(t: string) { const e = $('#toast'); e.textContent = t; e.classList.add('on'); clearTimeout(toastT); toastT = window.setTimeout(() => e.classList.remove('on'), 1800); }
export const shake = (v: number) => { if (!REDUCED) feel.trauma = Math.min(1, feel.trauma + v); };
export const hitStop = (t: number) => { if (!REDUCED) feel.hitStop = Math.max(feel.hitStop, t); };

/** Apply decaying screen shake to the world container. Call once per frame. */
export function applyShake(real: number, U: number) {
  feel.trauma = Math.max(0, feel.trauma - real * 1.6);
  const sh = feel.trauma * feel.trauma;
  world.x = (Math.random() * 2 - 1) * sh * U * 0.35; world.y = (Math.random() * 2 - 1) * sh * U * 0.35;
  world.rotation = (Math.random() * 2 - 1) * sh * 0.02;
}
