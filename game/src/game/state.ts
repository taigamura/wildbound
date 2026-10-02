// Run state. One mutable object, read and written by battle/run/ui.
import { SPECIES, type El, type CardId } from '../core/data';
import { Actor } from '../render/actor';

export interface Mon {
  uid: number; key: string; name: string; el: El; lvl: number;
  maxHp: number; hp: number; atk: number; alive: boolean; shield: number;
}
export interface Enemy {
  key: string; name: string; el: El; lvl: number; elite: boolean; boss: boolean; alive: boolean;
  hp: number; max: number; dmg: number; iv: number; t: number; stun: number;
  burn: number; burnAcc: number; burnDps: number; count: number; enraged: boolean; shiftT: number;
}
export type NodeType = 'wild' | 'elite' | 'spring' | 'cache' | 'boss';
export interface MapNode { type: NodeType; sp?: string }
export type Mode = 'title' | 'map' | 'intro' | 'battle' | 'anim' | 'end' | 'reward' | 'over';

export const S = {
  mode: 'title' as Mode,
  party: [] as Mon[], active: 0,
  deck: [] as CardId[], draw: [] as CardId[], disc: [] as CardId[], hand: [] as (CardId | null)[],
  energy: 3, floor: 1, enemy: null as Enemy | null,
  focus: false, swapCd: 0, swapping: false, autoT: 0,
  regen: { t: 0, acc: 0, amt: 0 },
  /** Bumped whenever a battle/run ends; delayed callbacks compare against it and bail if stale. */
  tok: 0,
  starter: 'cindrel',
  stats: { caught: 0, start: 0, dealt: 0 },
  nodes: [] as MapNode[],
  actors: {} as Record<number, Actor>,   // party members by uid
  em: null as Actor | null,              // enemy
  titleActor: null as Actor | null,
  uid: 1,
};

export const act = () => S.party[S.active];
export const activeActor = () => { const c = act(); return c ? S.actors[c.uid] ?? null : null; };

export function levelUp(c: Mon, heal = true) { c.lvl++; c.maxHp += 6; c.atk *= 1.07; if (heal) c.hp = Math.min(c.maxHp, c.hp + 6); }
export function newMon(key: string, lvl = 1): Mon {
  const sp = SPECIES[key];
  const c: Mon = { uid: S.uid++, key, name: sp.name, el: sp.el, lvl: 1, maxHp: sp.hp, hp: sp.hp, atk: sp.atk, alive: true, shield: 0 };
  for (let i = 1; i < lvl; i++) levelUp(c, false);
  c.hp = c.maxHp; return c;
}
export function actorFor(c: Mon) { return S.actors[c.uid] ??= new Actor(c.key); }
export function clearActors() {
  Object.values(S.actors).forEach(a => a.destroy()); S.actors = {};
  S.em?.destroy(); S.em = null;
  S.titleActor?.destroy(); S.titleActor = null;
}
