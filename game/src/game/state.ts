// Run state. One mutable object, read and written by battle/run/ui.
import { SPECIES, BAL, HEAVY_NAME, WARDEN_HEAVIES, scaleCard, boostCard, type El, type Slot, type Status, type CardDef, type TraitKey } from '../core/data';
import { loadout, boosts } from './meta';
import { Actor } from '../render/actor';

export interface StatusState { k: Status; t: number; acc?: number }
export interface Mon {
  uid: number;
  key: string;          // species (cards, stats, art)
  name: string; el: El;
  maxHp: number; hp: number; alive: boolean;
  shield: number; shieldT: number;        // shieldT: seconds since the shield was last added to
  status: StatusState | null;
  ups: Partial<Record<Slot, 'power' | 'cost'>>;
  shiny: boolean;
  power: number; spirit: number;   // permanent upgrades (§5.2): damage ×power, shield/heal amounts ×spirit (max HP is baked into maxHp)
  reflect: number;      // Thornveil: next hit taken reflects this fraction
  nextStrike: number;   // Capacitor: next Strike multiplier
  moves: Record<Slot, number>;  // equipped card per slot (index into SPECIES[key].cards[slot]), fixed when it joins
  trait: TraitKey | null;       // socketed Trait, fixed when it joins
  played: number;               // cards this creature has played this fight (Quickfuse)
}
export interface CardRef { uid: number; slot: Slot }
export type EnemyKind = 'wild' | 'alpha' | 'warden' | 'boss';
export interface Enemy {
  key: string; name: string; el: El; kind: EnemyKind; alive: boolean;
  hp: number; max: number; dmg: number;
  iv: number;           // normal wind-up length
  t: number;            // progress through the current wind-up (s)
  windup: number;       // length of the current wind-up (s)
  count: number;        // attacks made so far
  status: StatusState | null; statusSrc: number; shockCd: number;
  shiftT: number;       // boss: seconds to next element shift
  perfect: boolean;     // a Perfect Swap was made during this heavy's window
  heavyIdx: number;     // warden: which heavy comes next
}
export type NodeType = 'wild' | 'alpha' | 'spring' | 'warden' | 'boss';
export interface MapNode { type: NodeType; sp?: string; lvl?: number }
export type Mode = 'title' | 'map' | 'intro' | 'battle' | 'anim' | 'end' | 'reward' | 'over' | 'meta';

export const S = {
  mode: 'title' as Mode,
  party: [] as Mon[], lineup: [] as number[], active: 0,   // lineup: uids (≤3), active: uid of the lead
  draw: [] as CardRef[], disc: [] as CardRef[], hand: [] as (CardRef | null)[],
  energy: 0, floor: 1, enemy: null as Enemy | null,
  swapCd: 0, autoT: 0,
  chain: 0, chainT: 99, discount: 0,
  wired: false,                          // Live Wire already paid out for the current chain
  /** Bumped whenever a battle/run ends; delayed callbacks compare against it and bail if stale. */
  tok: 0,
  picks: [] as string[],                 // lineup chosen on the title screen (species keys, first = lead)
  stats: { start: 0, dealt: 0, perfects: 0 },
  nodes: [] as MapNode[],
  actors: {} as Record<number, Actor>,   // party members by uid
  em: null as Actor | null,              // enemy
  titleActor: null as Actor | null,
  uid: 1,
};

export const mon = (uid: number) => S.party.find(c => c.uid === uid);
export const act = () => mon(S.active)!;
export const team = () => S.lineup.map(mon).filter(Boolean) as Mon[];
export const bench = () => team().filter(c => c.uid !== S.active);
export const activeActor = () => { const c = act(); return c ? S.actors[c.uid] ?? null : null; };

/** A fresh party member. Its moves and Trait come from the saved loadout (§16), its numbers from its upgrades (§5.2). */
export function newMon(key: string, shiny = false): Mon {
  const sp = SPECIES[key], lo = loadout(key), b = boosts(key), hp = Math.round(sp.hp * b.vital);
  return { uid: S.uid++, key, name: sp.name, el: sp.el, maxHp: hp, hp, alive: true, shield: 0, shieldT: 0,
    status: null, ups: {}, shiny, power: b.power, spirit: b.spirit, reflect: 0, nextStrike: 1,
    moves: { strike: 0, skill: lo.skill, sig: lo.sig }, trait: lo.trait, played: 0 };
}
/** The base card a creature has equipped in a slot (before upgrades). */
export const baseCard = (c: Mon, slot: Slot): CardDef => { const l = SPECIES[c.key].cards![slot]; return l[c.moves[slot]] ?? l[0]; };

/** The card a ref points at, with in-run and permanent upgrades applied. `pow` scales status durations and Discharge. */
export function cardOf(r: CardRef): { def: CardDef; pow: number; owner: Mon } {
  const owner = mon(r.uid)!, base = baseCard(owner, r.slot), up = owner.ups[r.slot];
  const pow = up === 'power' ? BAL.upPower : 1;
  const def = { ...boostCard(scaleCard(base, pow), owner.power, owner.spirit), cost: Math.max(0, base.cost - (up === 'cost' ? 1 : 0)) };
  return { def, pow, owner };
}
export const cardCost = (r: CardRef) => {
  const { def, owner } = cardOf(r);
  return owner.trait === 'quickfuse' && owner.played === 0 ? 0 : Math.max(0, def.cost - S.discount);   // Quickfuse: first card free
};

/** Why a card can't be played right now ('' = playable). */
export function cardBlock(r: CardRef): '' | 'energy' | 'swap' | 'busy' {
  if (S.mode !== 'battle') return 'busy';
  if (S.energy < cardCost(r)) return 'energy';
  if (r.uid !== S.active && S.swapCd > 0) return 'swap';
  return '';
}

/* ---------- derived enemy state ---------- */
export const isHeavy = (e: Enemy) => (e.count + 1) % BAL.heavyEvery === 0;
/** Element and name of the enemy's next heavy. */
export function heavyOf(e: Enemy): { el: El; name: string } {
  if (e.kind === 'warden') return WARDEN_HEAVIES[e.heavyIdx % WARDEN_HEAVIES.length];
  return { el: e.el, name: SPECIES[e.key].heavy ?? HEAVY_NAME[e.el] };
}
/** True during the last moments of a heavy wind-up, when a resisting swap is Perfect. */
export const inPerfectWindow = (e: Enemy) => isHeavy(e) && e.windup - e.t <= BAL.perfectWin;
export function actorFor(c: Mon) {
  let a = S.actors[c.uid];
  if (!a) { a = S.actors[c.uid] = new Actor(c.key); a.setShiny(c.shiny); }
  return a;
}
export function dropActor(uid: number) { S.actors[uid]?.destroy(); delete S.actors[uid]; }
export function clearActors() {
  Object.values(S.actors).forEach(a => a.destroy()); S.actors = {};
  S.em?.destroy(); S.em = null;
  S.titleActor?.destroy(); S.titleActor = null;
}
