// Active art style. Switch with useStyle(id); the choice is saved.
import type { ArtStyle } from './types';
import { stickerStyle } from './sticker';
import { packStyles } from './packs';
import { store } from '../core/platform';

export const STYLES: ArtStyle[] = [stickerStyle, ...packStyles];
let current: ArtStyle = stickerStyle;

export const getStyle = () => current;

/** Requested style: ?art=<id> in the URL wins, then the saved choice. */
export function initialStyleId() {
  const q = new URLSearchParams(location.search).get('art');
  return q || store.get('art', stickerStyle.id);
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
