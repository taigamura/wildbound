// Persistent progress outside a run: owned creatures, shinies, packs, records, loot, upgrades, Essence.
// Everything goes through core/platform.ts `store` (localStorage in a browser, AsyncStorage in the app).
import { BAL, ROSTER, STARTERS, SPECIES, TRAITS, EL_KEYS, MATS, NO_LOOT, type El, type Slot, type TraitKey, type Mat, type Loot } from '../core/data';
import { store } from '../core/platform';
import { pick } from '../core/util';

const uniq = (a: string[]) => [...new Set(a)].filter(k => ROSTER.includes(k));

export const owned = (): string[] => uniq(store.get<string[]>('owned', STARTERS.slice()).concat(STARTERS));
export const isOwned = (k: string) => owned().includes(k);
export const shinies = (): string[] => uniq(store.get<string[]>('shiny', []));
export const isShiny = (k: string) => shinies().includes(k);

/** Add species to the collection. Returns the ones that were new. */
export function addOwned(keys: string[]): string[] {
  const have = owned(), fresh = uniq(keys).filter(k => !have.includes(k));
  if (fresh.length) store.set('owned', have.concat(fresh));
  return fresh;
}

/** The pack "day" rolls over at 04:00 device-local time. */
function packDay(now = new Date()) {
  const d = new Date(now.getTime() - BAL.packResetHour * 3600e3);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}
export const packReady = () => store.get<string>('packDay', '') !== packDay();
/** Time until the next pack, as "5h 12m". */
export function nextPackIn() {
  const now = new Date(), next = new Date(now);
  next.setHours(BAL.packResetHour, 0, 0, 0); if (next <= now) next.setDate(next.getDate() + 1);
  const m = Math.ceil((next.getTime() - now.getTime()) / 60000);
  return `${Math.floor(m / 60)}h ${m % 60}m`;
}

export type PackResult = { key: string; shiny: boolean } | { key: null; shiny: false };
/** True once every creature is owned and shiny: a pack would have nothing to give. */
export const packEmpty = () => ROSTER.every(k => isOwned(k) && isShiny(k));
/** A pack's contents: a creature you don't own, else a shiny of one you do. */
function rollPack(): PackResult {
  const have = owned(), missing = ROSTER.filter(k => !have.includes(k) && !STARTERS.includes(k));
  if (missing.length) { const key = pick(missing); addOwned([key]); return { key, shiny: false }; }
  const plain = have.filter(k => !isShiny(k));
  if (!plain.length) return { key: null, shiny: false };
  const key = pick(plain); store.set('shiny', shinies().concat(key)); return { key, shiny: true };
}
/** Open today's free pack. Null if it's already been opened today. */
export function openPack(): PackResult | null {
  if (!packReady()) return null;
  store.set('packDay', packDay());
  return rollPack();
}
/** Buy a pack in the shop. Null if too poor or there is nothing left to find (nothing is charged). */
export function buyPack(): PackResult | null {
  if (packEmpty() || !spendLoot({ gold: BAL.shopPack })) return null;
  return rollPack();
}

export function recordRun(won: boolean, floor: number) {
  store.set('best', Math.max(store.get('best', 0), floor));
  if (won) store.set('wins', store.get('wins', 0) + 1);
}
export const best = () => store.get('best', 0);
export const wins = () => store.get('wins', 0);

/** The last lineup taken on a run (owned species only, ≤3, first = lead). */
export function lastLineup(): string[] {
  const legacy = store.get<string>('starter', STARTERS[0]);
  const l = [...new Set(store.get<string[]>('lineup', [legacy]))].filter(isOwned).slice(0, BAL.lineup);
  return l.length ? l : [STARTERS[0]];
}
export const saveLineup = (keys: string[]) => store.set('lineup', keys.slice(0, BAL.lineup));

/* ================= loot, upgrades, shop (§5) ================= */
/** Banked gold and materials. */
export const wallet = (): Loot => ({ ...NO_LOOT(), ...store.get<Partial<Loot>>('loot', {}) });
/** Bank loot (kept whether the run is won or lost). Returns the new totals. */
export function addLoot(l: Partial<Loot>): Loot {
  const w = wallet(); for (const k of Object.keys(l) as (keyof Loot)[]) w[k] += l[k] ?? 0;
  store.set('loot', w); return w;
}
/** Pay for something. False (and nothing spent) if any part is short. */
export function spendLoot(l: Partial<Loot>): boolean {
  const w = wallet(); if ((Object.keys(l) as (keyof Loot)[]).some(k => w[k] < (l[k] ?? 0))) return false;
  for (const k of Object.keys(l) as (keyof Loot)[]) w[k] -= l[k] ?? 0;
  store.set('loot', w); return true;
}
export const buyMat = (m: Mat) => spendLoot({ gold: BAL.shopMat }) && (addLoot({ [m]: 1 }), true);
export const sellMat = (m: Mat) => spendLoot({ [m]: 1 }) && (addLoot({ gold: BAL.shopSell }), true);

/** Upgrade levels per species, one track per material (sword = Power, orb = Spirit, jewel = Vitality). */
export type Ups = Record<Mat, number>;
type AllUps = Record<string, Partial<Ups>>;
export const upgrades = (k: string): Ups => ({ sword: 0, orb: 0, jewel: 0, ...store.get<AllUps>('upgrades', {})[k] });
/** Cost of the next level on a track, or null at max. */
export function upgradeCost(k: string, m: Mat): Loot | null {
  const n = upgrades(k)[m]; if (n >= BAL.upMax) return null;
  return { ...NO_LOOT(), [m]: n + 1, gold: BAL.upGold * (n + 1) };
}
export function buyUpgrade(k: string, m: Mat): boolean {
  const c = upgradeCost(k, m); if (!isOwned(k) || !c || !spendLoot(c)) return false;
  const all = store.get<AllUps>('upgrades', {}); all[k] = { ...upgrades(k), [m]: upgrades(k)[m] + 1 }; store.set('upgrades', all); return true;
}
/** Multipliers a creature's upgrades give: card/auto damage, shield/heal amounts, max HP. */
export function boosts(k: string) {
  const u = upgrades(k);
  return { power: 1 + BAL.upDmg * u.sword, spirit: 1 + BAL.upSpirit * u.orb, vital: 1 + BAL.upHp * u.jewel };
}
export const randomMat = (): Mat => pick(MATS);

/* ================= essence, unlocks, loadouts (§16) ================= */
export type Essence = Record<El, number>;
export const essence = (): Essence => ({ ember: 0, tide: 0, thorn: 0, volt: 0, ...store.get<Partial<Essence>>('essence', {}) });
/** Add essence. Returns the new totals. */
export function earn(el: El, n: number): Essence {
  const e = essence(); e[el] += n; store.set('essence', e); return e;
}
function spend(el: El, n: number) {
  const e = essence(); if (e[el] < n) return false;
  e[el] -= n; store.set('essence', e); return true;
}
export const EMPTY_ESSENCE = (): Essence => Object.fromEntries(EL_KEYS.map(k => [k, 0])) as Essence;

const learned = (): string[] => store.get<string[]>('learned', []);
const learn = (id: string) => store.set('learned', [...new Set(learned().concat(id))]);
const moveId = (k: string, slot: Slot, i: number) => `${k}.${slot}.${i}`;

/** Index 0 (the default card) is always unlocked. */
export const moveUnlocked = (k: string, slot: Slot, i: number) => i === 0 || learned().includes(moveId(k, slot, i));
/** A creature's built-in Trait is always usable by it; others must be learned (and their source owned). */
export const traitUnlocked = (t: TraitKey) => learned().includes('trait.' + t) && isOwned(TRAITS[t].from);
export const traitUsable = (k: string, t: TraitKey) => SPECIES[k].trait === t || traitUnlocked(t);

export const moveCost = (k: string) => ({ el: SPECIES[k].el, n: BAL.moveCost });
export const traitCost = (t: TraitKey) => ({ el: SPECIES[TRAITS[t].from].el, n: BAL.traitCost });

/** Spend essence to unlock an alternate card. False if locked behind ownership, already unlocked, or too poor. */
export function unlockMove(k: string, slot: Slot, i: number): boolean {
  if (!isOwned(k) || moveUnlocked(k, slot, i) || !SPECIES[k].cards?.[slot][i]) return false;
  const c = moveCost(k); if (!spend(c.el, c.n)) return false;
  learn(moveId(k, slot, i)); return true;
}
/** Spend essence so any creature can socket this Trait. Needs its source species owned. */
export function unlockTrait(t: TraitKey): boolean {
  if (traitUnlocked(t) || !isOwned(TRAITS[t].from)) return false;
  const c = traitCost(t); if (!spend(c.el, c.n)) return false;
  learn('trait.' + t); return true;
}

export interface Loadout { skill: number; sig: number; trait: TraitKey | null }
type Saved = Record<string, Partial<Loadout>>;
const saved = (): Saved => store.get<Saved>('loadout', {});
/** The equipped loadout for a species, falling back to defaults for anything locked or missing. */
export function loadout(k: string): Loadout {
  const sp = SPECIES[k], s = saved()[k] ?? {}, def = sp.trait ?? null;
  const pick = (slot: 'skill' | 'sig') => { const i = s[slot] ?? 0; return sp.cards?.[slot][i] && moveUnlocked(k, slot, i) ? i : 0; };
  const trait = s.trait && traitUsable(k, s.trait) ? s.trait : def;
  return { skill: pick('skill'), sig: pick('sig'), trait };
}
export function setMove(k: string, slot: 'skill' | 'sig', i: number) {
  if (!moveUnlocked(k, slot, i)) return false;
  const all = saved(); all[k] = { ...all[k], [slot]: i }; store.set('loadout', all); return true;
}
/**
 * Socket a Trait. A learned (non-built-in) Trait sits in one creature at a time:
 * socketing it here returns any other creature holding it to its built-in Trait.
 */
export function setTrait(k: string, t: TraitKey) {
  if (!traitUsable(k, t)) return false;
  const all = saved();
  if (SPECIES[k].trait !== t) for (const o of Object.keys(all)) if (o !== k && all[o].trait === t) all[o] = { ...all[o], trait: SPECIES[o].trait ?? null };
  all[k] = { ...all[k], trait: t }; store.set('loadout', all); return true;
}
/** Which other species currently holds a learned Trait (for "moves it from X" hints). */
export const traitHolder = (t: TraitKey): string | null =>
  Object.entries(saved()).find(([o, l]) => l.trait === t && SPECIES[o].trait !== t)?.[0] ?? null;
