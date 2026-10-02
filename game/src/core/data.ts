// Static game content: elements, creatures, cards, icons.
// Balance tweaks belong here.

export type El = 'ember' | 'tide' | 'thorn' | 'volt';

export interface ElementDef { name: string; hex: number; css: string; glow: number[] }
export const ELEM: Record<El, ElementDef> = {
  ember: { name: 'Ember', hex: 0xff6a3d, css: 'var(--ember)', glow: [0xff6a3d, 0xffa23d, 0xffe08a] },
  tide:  { name: 'Tide',  hex: 0x34a8ff, css: 'var(--tide)',  glow: [0x34a8ff, 0x8fe3ff, 0xe8fbff] },
  thorn: { name: 'Thorn', hex: 0x4fcf5c, css: 'var(--thorn)', glow: [0x4fcf5c, 0xb6f27a, 0x2fae55] },
  volt:  { name: 'Volt',  hex: 0xffcf2e, css: 'var(--volt)',  glow: [0xffcf2e, 0xffffff, 0xfff3a0] },
};
export const EL_KEYS = Object.keys(ELEM) as El[];

/** Each element beats the next one in the loop: ember → thorn → volt → tide → ember. */
export const BEATS: Record<El, El> = { ember: 'thorn', thorn: 'volt', volt: 'tide', tide: 'ember' };
export const adv = (a?: El | null, d?: El | null) => (!a || !d) ? 1 : BEATS[a] === d ? 1.5 : BEATS[d] === a ? 0.7 : 1;

export type Feature = 'ears' | 'horns' | 'flame' | 'tail' | 'fin' | 'whisk' | 'leaf' | 'spikes' | 'antenna' | 'wings' | 'crown';
export interface SpeciesDef {
  name: string; el: El; hp: number; atk: number; spd: number; size: number;
  feats: Feature[]; sig: CardId | null; blurb?: string; boss?: boolean;
}
export const SPECIES: Record<string, SpeciesDef> = {
  cindrel:   { name: 'Cindrel',   el: 'ember', hp: 62,  atk: 1.0,  spd: 1.0,  size: 1,    feats: ['ears', 'flame', 'tail'], sig: 'flare', blurb: 'Quick, fiery' },
  magmaw:    { name: 'Magmaw',    el: 'ember', hp: 82,  atk: 1.15, spd: 0.85, size: 1.22, feats: ['horns', 'spikes', 'flame'], sig: 'flare' },
  plipp:     { name: 'Plipp',     el: 'tide',  hp: 68,  atk: 0.95, spd: 1.05, size: 0.95, feats: ['fin', 'tail', 'whisk'], sig: 'torrent', blurb: 'Sturdy healer' },
  brinehorn: { name: 'Brinehorn', el: 'tide',  hp: 86,  atk: 1.05, spd: 0.9,  size: 1.18, feats: ['horns', 'fin', 'whisk'], sig: 'torrent' },
  sproutle:  { name: 'Sproutle',  el: 'thorn', hp: 72,  atk: 0.95, spd: 1.0,  size: 1,    feats: ['leaf', 'ears'], sig: 'bramble', blurb: 'Tanky, shields' },
  barkback:  { name: 'Barkback',  el: 'thorn', hp: 92,  atk: 1.05, spd: 0.8,  size: 1.22, feats: ['spikes', 'leaf'], sig: 'bramble' },
  zapling:   { name: 'Zapling',   el: 'volt',  hp: 56,  atk: 1.05, spd: 1.2,  size: 0.9,  feats: ['antenna', 'ears', 'tail'], sig: 'zap' },
  joltusk:   { name: 'Joltusk',   el: 'volt',  hp: 78,  atk: 1.12, spd: 1.0,  size: 1.12, feats: ['horns', 'antenna', 'wings'], sig: 'zap' },
  noctyrm:   { name: 'Noctyrm',   el: 'ember', hp: 270, atk: 1.3,  spd: 1.0,  size: 1.5,  feats: ['wings', 'tail', 'spikes', 'horns', 'crown'], sig: null, boss: true },
};
export const SMALL = ['cindrel', 'plipp', 'sproutle', 'zapling'];
export const BIG = ['magmaw', 'brinehorn', 'barkback', 'joltusk'];
export const STARTERS = ['cindrel', 'plipp', 'sproutle'];

export type CardId = 'strike' | 'guard' | 'mend' | 'focus' | 'spark' | 'flare' | 'torrent' | 'bramble' | 'zap' | 'inferno' | 'tidal' | 'overgrow' | 'storm';
export interface CardDef {
  name: string; cost: number; el: El | null; txt: string; g?: GlyphKey;
  dmg?: number; hits?: number; shield?: number; heal?: number; focus?: boolean; energy?: number;
  burn?: number; stun?: number; regen?: number; rare?: boolean;
}
export const CARDS: Record<CardId, CardDef> = {
  strike:  { name: 'Strike',  cost: 1, el: null, dmg: 6, txt: "Deal 6 in your partner's element", g: 'claw' },
  guard:   { name: 'Guard',   cost: 1, el: null, shield: 8, txt: '+8 shield', g: 'shield' },
  mend:    { name: 'Mend',    cost: 2, el: null, heal: 12, txt: 'Heal 12', g: 'heart' },
  focus:   { name: 'Focus',   cost: 1, el: null, focus: true, txt: 'Next attack ×2', g: 'star' },
  spark:   { name: 'Spark',   cost: 0, el: null, energy: 2, txt: '+2 energy', g: 'spark' },
  flare:   { name: 'Flare',   cost: 2, el: 'ember', dmg: 11, burn: 4, txt: 'Deal 11, burn 4s' },
  torrent: { name: 'Torrent', cost: 2, el: 'tide',  dmg: 10, heal: 6, txt: 'Deal 10, heal 6' },
  bramble: { name: 'Bramble', cost: 2, el: 'thorn', dmg: 8, shield: 8, txt: 'Deal 8, +8 shield' },
  zap:     { name: 'Zap',     cost: 1, el: 'volt',  dmg: 3, hits: 3, stun: 0.6, txt: '3 × 3, stun' },
  inferno: { name: 'Inferno', cost: 3, el: 'ember', dmg: 26, burn: 3, rare: true, txt: 'Deal 26, burn' },
  tidal:   { name: 'Tidal',   cost: 3, el: 'tide',  dmg: 17, heal: 14, rare: true, txt: 'Deal 17, heal 14' },
  overgrow:{ name: 'Overgrow',cost: 3, el: 'thorn', heal: 10, shield: 12, regen: 6, rare: true, txt: 'Heal 10, +12 shield, regen' },
  storm:   { name: 'Storm',   cost: 3, el: 'volt',  dmg: 4, hits: 6, stun: 1.2, rare: true, txt: '6 × 4, long stun' },
};
export const SIG: Record<El, CardId> = { ember: 'flare', tide: 'torrent', thorn: 'bramble', volt: 'zap' };
export const RARE: Record<El, CardId> = { ember: 'inferno', tide: 'tidal', thorn: 'overgrow', volt: 'storm' };
export const COMMONS: CardId[] = ['guard', 'mend', 'focus', 'spark', 'strike'];
export const STARTING_DECK = (el: El): CardId[] => ['strike', 'strike', 'strike', 'strike', 'guard', 'guard', 'mend', SIG[el], SIG[el]];

export const FLOORS = 8;
export const CAP_TH = 0.4;      // capture unlocks below this HP fraction
export const CAPTURE_COST = 3;
export const ENERGY_RATE = 0.95; // energy per second
export const ENERGY_MAX = 10;
export const HAND = 4;
export const SWAP_COOLDOWN = 4;

export const GLYPH = {
  ember: '<path d="M12 2c1 4 6 6 6 12a6 6 0 0 1-12 0c0-3 2-5 3-6 0 2 1 3 2 3 0-4 1-7 1-9z"/>',
  tide: '<path d="M12 2C9 7 5 11 5 15a7 7 0 0 0 14 0c0-4-4-8-7-13z"/>',
  thorn: '<path d="M20 3C10 3 4 9 4 16c0 2 1 5 1 5s2-6 7-9c-3 3-5 6-6 9 9 0 14-7 14-18z"/>',
  volt: '<path d="M13 1L4 14h7l-2 9 10-13h-7l2-9z"/>',
  shield: '<path d="M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5l8-3z"/>',
  heart: '<path d="M12 21s-8-5-8-11a4.5 4.5 0 0 1 8-3 4.5 4.5 0 0 1 8 3c0 6-8 11-8 11z"/>',
  star: '<path d="M12 2l3 7h7l-5.5 4.5L18.5 21 12 16.5 5.5 21l2-7.5L2 9h7z"/>',
  spark: '<path d="M12 1l2.2 7.8L22 11l-7.8 2.2L12 21l-2.2-7.8L2 11l7.8-2.2z"/>',
  claw: '<path d="M5 18L14 4M9.5 21L18.5 7M14.5 21.5L20.5 12"/>',
  skull: '<path d="M12 2a9 9 0 0 0-9 9c0 3 1.5 5 3 6v4h12v-4c1.5-1 3-3 3-6a9 9 0 0 0-9-9zm-3.5 9a2 2 0 1 1 0 4 2 2 0 0 1 0-4zm7 0a2 2 0 1 1 0 4 2 2 0 0 1 0-4z"/>',
  crown: '<path d="M3 7l4.5 4L12 4l4.5 7L21 7l-2 12H5z"/>',
  moon: '<path d="M15 2a9 9 0 1 0 7 13A8 8 0 0 1 15 2z"/>',
  chest: '<path d="M3 9a5 5 0 0 1 5-5h8a5 5 0 0 1 5 5v1H3zm0 3h7v2h4v-2h7v8H3z"/>',
  paw: '<path d="M12 12c3 0 6 3 6 6 0 2-2 3-3.5 3-1 0-1.5-.7-2.5-.7s-1.5.7-2.5.7C8 21 6 20 6 18c0-3 3-6 6-6zM5 8a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5zm14 0a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5zM9 3a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5zm6 0a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5z"/>',
  sound: '<path d="M3 9h4l5-5v16l-5-5H3zm13.5 3a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4zM14 3.2v2.1a7 7 0 0 1 0 13.4v2.1a9 9 0 0 0 0-17.6z"/>',
  mute: '<path d="M3 9h4l5-5v16l-5-5H3zm13.6-.6L19 10.8l2.4-2.4 1.4 1.4-2.4 2.4 2.4 2.4-1.4 1.4-2.4-2.4-2.4 2.4-1.4-1.4 2.4-2.4-2.4-2.4z"/>',
};
export type GlyphKey = keyof typeof GLYPH;
export const svg = (k: GlyphKey, cls = '') => `<svg viewBox="0 0 24 24" class="${cls}" aria-hidden="true">${GLYPH[k]}</svg>`;
export const elCss = (el?: El | null) => el ? ELEM[el].css : 'var(--neutral)';
export const elHexCss = (el: El) => '#' + ELEM[el].hex.toString(16).padStart(6, '0');
