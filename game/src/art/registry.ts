// Active art style. Switch with useStyle(id); the choice is saved.
import type { ArtStyle } from './types';
import { stickerStyle } from './sticker';
import { packStyles } from './packs';
import { store } from '../core/platform';

/** The style a new install starts with (CLAUDE.md §13). Listed first in the picker. */
export const DEFAULT_STYLE = 'hd2d';
const all = [stickerStyle, ...packStyles];
export const STYLES: ArtStyle[] = [...all.filter(s => s.id === DEFAULT_STYLE), ...all.filter(s => s.id !== DEFAULT_STYLE)];
let current: ArtStyle = stickerStyle;

export const getStyle = () => current;

/** Requested style: ?art=<id> in the URL wins, then the saved choice, then DEFAULT_STYLE. */
export function initialStyleId() {
  const q = new URLSearchParams(location.search).get('art');
  return q || store.get('art', DEFAULT_STYLE);
}

export async function useStyle(id: string) {
  const next = STYLES.find(s => s.id === id) ?? stickerStyle;
  try { await next.preload(); current = next; }
  catch (e) { console.warn('[art] failed to load', id, e); await stickerStyle.preload(); current = stickerStyle; }
  store.set('art', current.id);
  const root = document.documentElement;
  STYLES.forEach(s => Object.keys(s.cssVars || {}).forEach(k => root.style.removeProperty(k)));
  Object.entries(current.cssVars || {}).forEach(([k, v]) => root.style.setProperty(k, v));
  return current;
}
