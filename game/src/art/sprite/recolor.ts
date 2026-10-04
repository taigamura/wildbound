// Element recolouring for pixel art painted in Ember colours (orange/red, magenta-dark
// outlines, yellow highlights). A plain multiply tint turns orange into mud for blue or
// green, so this remaps HUE instead: the Ember ramp (outline → shadow → base → highlight)
// is mapped piecewise onto the target element's ramp, so shadows and outlines stay darker
// and shift the way a pixel artist would shift them. Low-saturation pixels (skin, cream
// bellies, grey cloth, near-black) and hues outside the warm band keep their colour.
// Pure pixel maths, no DOM, so it can be tested outside the browser.
import type { El } from '../../core/data';

/** Hue ramp as [outline, shadow, base, highlight], in degrees (may be negative or > 360). */
export type Ramp = [number, number, number, number];

export interface Recolor {
  /** Source hues above this keep their colour (degrees, default 28). Lower it (e.g. 10) to keep skin tones. */
  maxHue?: number;
  /** Pixels less saturated than this keep their colour (0–1, default 0.5). */
  minSat?: number;
  /** Multiply the brightness / saturation of recoloured pixels (default 1). */
  light?: number;
  sat?: number;
  /** Multiply EVERY pixel's RGB afterwards (a colour wash), e.g. [0.62, 0.7, 0.95] for a night variant. */
  wash?: [number, number, number];
  /** Override the target ramps per element. */
  ramps?: Partial<Record<El, Ramp>>;
}

/** The source palette's ramp: Ember art drawn to docs/HD2D.md (outline #3a0828-ish, shadow crimson, base #ff6a3d, highlight amber). */
const SRC: Ramp = [-40, -6, 14, 35];

/** Default target ramps. Shadows lean toward violet-blue and highlights toward warm, per docs/HD2D.md. */
export const RAMPS: Record<El, Ramp> = {
  ember: SRC,
  tide: [250, 232, 208, 188],
  thorn: [172, 148, 122, 82],
  volt: [-12, 34, 48, 56],
};
const EL_LIGHT: Record<El, number> = { ember: 1, tide: 1, thorn: 0.88, volt: 1 };
const EL_SAT: Record<El, number> = { ember: 1, tide: 0.95, thorn: 0.8, volt: 0.95 };
/** Brightness curve (v^gamma): yellow only reads as yellow when its shadows are lifted. */
const EL_GAMMA: Record<El, number> = { ember: 1, tide: 1, thorn: 1, volt: 0.72 };

/** True if recolouring to `el` with these options changes nothing (Ember with no extras). */
export const isIdentity = (el: El, o: Recolor) => el === 'ember' && !o.ramps?.ember && !o.wash && (o.light ?? 1) === 1 && (o.sat ?? 1) === 1;

const smooth = (a: number, b: number, x: number) => { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

function mapHue(h: number, r: Ramp) {
  if (h <= SRC[0]) return r[0];
  if (h >= SRC[3]) return r[3];
  for (let i = 0; i < 3; i++) if (h <= SRC[i + 1]) {
    const t = (h - SRC[i]) / (SRC[i + 1] - SRC[i]);
    return r[i] + (r[i + 1] - r[i]) * t;
  }
  return r[3];
}

/** Recolour RGBA pixels in place. */
export function recolorPixels(px: Uint8ClampedArray, el: El, o: Recolor = {}) {
  const ramp = o.ramps?.[el] ?? RAMPS[el];
  const maxHue = o.maxHue ?? 28, minSat = o.minSat ?? 0.5;
  const kv = (o.light ?? 1) * EL_LIGHT[el], ks = (o.sat ?? 1) * EL_SAT[el];
  const wash = o.wash ?? [1, 1, 1];
  const touch = el !== 'ember' || !!o.ramps?.ember || kv !== 1 || ks !== 1;
  for (let i = 0; i < px.length; i += 4) {
    if (px[i + 3] === 0) continue;
    let r = px[i] / 255, g = px[i + 1] / 255, b = px[i + 2] / 255;
    if (touch) {
      const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, v = mx, s = mx ? d / mx : 0;
      let h = 0;
      if (d) h = mx === r ? ((g - b) / d) * 60 : mx === g ? ((b - r) / d + 2) * 60 : ((r - g) / d + 4) * 60;
      if (h < 0) h += 360;
      if (h > 270) h -= 360;   // signed: magenta/crimson are just below 0
      const w = smooth(-75, -60, h) * (1 - smooth(maxHue, maxHue + 12, h)) * smooth(minSat, minSat + 0.12, s);
      if (w > 0) {
        let nh = mapHue(h, ramp) % 360; if (nh < 0) nh += 360;
        const nv = Math.min(1, Math.pow(v, EL_GAMMA[el]) * kv), ns = Math.min(1, s * ks);
        // HSV → RGB
        const c = nv * ns, x = c * (1 - Math.abs(((nh / 60) % 2) - 1)), m = nv - c, k = Math.floor(nh / 60);
        const [rr, gg, bb] = k === 0 ? [c, x, 0] : k === 1 ? [x, c, 0] : k === 2 ? [0, c, x] : k === 3 ? [0, x, c] : k === 4 ? [x, 0, c] : [c, 0, x];
        r += (rr + m - r) * w; g += (gg + m - g) * w; b += (bb + m - b) * w;
      }
    }
    px[i] = r * wash[0] * 255; px[i + 1] = g * wash[1] * 255; px[i + 2] = b * wash[2] * 255;
  }
  return px;
}
