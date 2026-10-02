// Small helpers shared everywhere.
export const $ = (s: string): any => document.querySelector(s);
export const rand = (a: number, b: number) => a + Math.random() * (b - a);
export const pick = <T>(a: T[]): T => a[Math.floor(Math.random() * a.length)];
export const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
export function shuffle<T>(a: T[]): T[] {
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}
export const REDUCED = matchMedia('(prefers-reduced-motion: reduce)').matches;
