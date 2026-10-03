// Run state. One mutable object, read and written by battle/run/ui.
import { SPECIES, BAL, HEAVY_NAME, WARDEN_HEAVIES, scaleCard, type El, type Slot, type Status, type CardDef, type TraitKey } from '../core/data';
import { loadout } from './meta';
import { Actor } from '../render/actor';

export interface StatusState { k: Status; t: number; acc?: number }
export interface Mon {
  uid: number;
  key: string;          // base species (cards, stats)
  art: string;          // species drawn on screen (changes on evolution)
  name: string; el: El;
  maxHp: number; hp: number; alive: boolean;
  shield: number; shieldT: number;        // shieldT: seconds since the shield was last added to
  status: StatusState | null;
  ups: Partial<Record<Slot, 'power' | 'cost'>>;
  starter: boolean; evo: number; evolved: boolean; shiny: boolean;
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
  enraged: boolean;
  status: StatusState | null; statusSrc: number; shockCd: number;
  shiftT: number;       // boss: seconds to next element shift
  fleeT: number | null; // wild: seconds until it flees (starts below the capture threshold)
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
  energy: 0, charges: 0, floor: 1, enemy: null as Enemy | null,
  swapCd: 0, autoT: 0,
  chain: 0, chainT: 99, discount: 0,
  wired: false,                          // Live Wire already paid out for the current chain
  /** Bumped whenever a battle/run ends; delayed callbacks compare against it and bail if stale. */
  tok: 0,
  starter: 'emberwick',
  caught: [] as string[],                // species caught this run
  stats: { caught: 0, start: 0, dealt: 0, perfects: 0 },
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

/** A fresh party member. Its moves and Trait come from the saved loadout for its species (§16). */
export function newMon(key: string, shiny = false): Mon {
  const sp = SPECIES[key], lo = loadout(key);
  return { uid: S.uid++, key, art: key, name: sp.name, el: sp.el, maxHp: sp.hp, hp: sp.hp, alive: true, shield: 0, shieldT: 0,
    status: null, ups: {}, starter: false, evo: 0, evolved: false, shiny, reflect: 0, nextStrike: 1,
    moves: { strike: 0, skill: lo.skill, sig: lo.sig }, trait: lo.trait, played: 0 };
}
/** The base card a creature has equipped in a slot (before upgrades and evolution). */
export const baseCard = (c: Mon, slot: Slot): CardDef => { const l = SPECIES[c.key].cards![slot]; return l[c.moves[slot]] ?? l[0]; };

/** The card a ref points at, with upgrades and evolution applied. `pow` scales status durations and Discharge. */
export function cardOf(r: CardRef): { def: CardDef; pow: number; owner: Mon } {
  const owner = mon(r.uid)!, sp = SPECIES[owner.key];
  let base = baseCard(owner, r.slot), pow = 1;
  // a named evolution replaces only the default Signature; an alternate Signature gets the Prime boost
  if (r.slot === 'sig' && owner.evolved) { if (sp.evo && owner.moves.sig === 0) base = sp.evo.sig; else pow *= BAL.primePower; }
  const up = owner.ups[r.slot];
  if (up === 'power') pow *= BAL.upPower;
  const def = { ...scaleCard(base, pow), cost: Math.max(0, base.cost - (up === 'cost' ? 1 : 0)) };
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
export const canCapture = (e: Enemy | null) => !!e && e.kind === 'wild' && e.alive && e.hp / e.max <= BAL.capTh;
export function captureOdds(e: Enemy) {
  const v = BAL.capBase + (BAL.capTh - e.hp / e.max) + (e.status ? BAL.capStatus : 0) + (e.enraged ? BAL.capEnraged : 0);
  return Math.min(BAL.capMax, v);
}
/** The run's starter, if its meter is full and it can evolve right now. */
export function evoCandidate(): Mon | null {
  const c = S.party.find(m => m.starter);
  return c && !c.evolved && c.alive && c.evo >= BAL.evoFill && S.lineup.includes(c.uid) ? c : null;
}

export function actorFor(c: Mon) {
  let a = S.actors[c.uid];
  if (!a) { a = S.actors[c.uid] = new Actor(c.art); a.setShiny(c.shiny); if (c.evolved && c.art === c.key) a.setEvoFallback(true); }
  return a;
}
export function dropActor(uid: number) { S.actors[uid]?.destroy(); delete S.actors[uid]; }
export function clearActors() {
  Object.values(S.actors).forEach(a => a.destroy()); S.actors = {};
  S.em?.destroy(); S.em = null;
  S.titleActor?.destroy(); S.titleActor = null;
}
