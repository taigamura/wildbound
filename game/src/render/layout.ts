// Stage layout: everything is placed relative to the free band between the HUD's
// top and bottom pieces, in "units" (U pixels). Positions ease toward their targets.
import { clamp } from '../core/util';

export const size = { W: innerWidth, H: innerHeight };
/** One world unit in pixels. Live binding: importers always see the current value. */
export let U = 60;

const T = { U: 60, ex: 0, ey: 0, px: 0, py: 0, tx: 0, ty: 0 };  // targets
const C = { ...T };                                               // current (eased)

const shown = (el: HTMLElement) => el.offsetParent !== null && !el.closest('[hidden]');

export function measureBand(snap = false) {
  size.W = innerWidth; size.H = innerHeight;
  const { W, H } = size;
  let top = 0, bot = H;
  document.querySelectorAll<HTMLElement>('[data-band-top]').forEach(e => { if (shown(e)) top = Math.max(top, e.getBoundingClientRect().bottom); });
  document.querySelectorAll<HTMLElement>('[data-band-bottom]').forEach(e => { if (shown(e)) bot = Math.min(bot, e.getBoundingClientRect().top); });
  if (bot - top < H * 0.22) { top = 0; bot = H * 0.5; }
  const h = bot - top, cx = W / 2;
  T.U = clamp(Math.min(h / 4.8, W / 5), 34, 110);
  const spread = Math.min(W * 0.19, T.U * 1.6);
  T.ex = cx + spread; T.ey = top + h * 0.5;    // enemy: upper right
  T.px = cx - spread; T.py = top + h * 0.92;   // partner: lower left
  T.tx = cx; T.ty = top + h * 0.82;            // title creature: centred
  if (snap) { Object.assign(C, T); U = C.U; }
}
export function easeLayout(dt: number) {
  const k = 1 - Math.exp(-dt * 7);
  for (const key in T) (C as any)[key] += ((T as any)[key] - (C as any)[key]) * k;
  U = C.U;
}
export const EPOS = () => ({ x: C.ex, y: C.ey });
export const PPOS = () => ({ x: C.px, y: C.py });
export const TPOS = () => ({ x: C.tx, y: C.ty });
/** Horizon line used by scene art so creatures always stand below it. */
export const horizon = () => size.H * 0.36;
