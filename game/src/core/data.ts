// Static game content: elements, statuses, roster, cards, balance numbers.
// CLAUDE.md (Part 1) is the spec. Change a number here, change it there too.

export type El = 'ember' | 'tide' | 'thorn' | 'volt';

export interface ElementDef { name: string; hex: number; css: string; glow: number[] }
export const ELEM: Record<El, ElementDef> = {
  ember: { name: 'Ember', hex: 0xff6a3d, css: 'var(--ember)', glow: [0xff6a3d, 0xffa23d, 0xffe08a] },
  tide:  { name: 'Tide',  hex: 0x34a8ff, css: 'var(--tide)',  glow: [0x34a8ff, 0x8fe3ff, 0xe8fbff] },
  thorn: { name: 'Thorn', hex: 0x4fcf5c, css: 'var(--thorn)', glow: [0x4fcf5c, 0xb6f27a, 0x2fae55] },
  volt:  { name: 'Volt',  hex: 0xffcf2e, css: 'var(--volt)',  glow: [0xffcf2e, 0xffffff, 0xfff3a0] },
};
export const EL_KEYS = Object.keys(ELEM) as El[];

/* ================= balance ================= */
export const BAL = {
  floors: 8,
  // elements
  strong: 1.5, weak: 0.66,
  // energy & hand
  energyRate: 1, energyMax: 10, energyStart: 3, hand: 4,
  // swapping
  swapCost: 1, swapCd: 1,
  // auto-attack
  autoIv: 1.5, autoDmg: 2,
  // enemy
  intent: 3, heavyEvery: 3, heavyExtra: 2, heavyMult: 2.5, enemyDmg: 5,
  wildHp: 90, hpPerFloor: 0.15, dmgPerFloor: 0.10, biomeBBonus: 2,
  alphaHp: 1.5, alphaDmg: 1.25,
  wardenHp: 300, wardenDmg: 7, bossDmg: 8, bossShift: 7,
  // perfect swap
  perfectWin: 0.4, perfectReflect: 0.5, perfectRefund: 2, slowScale: 0.3, slowDur: 0.5,
  // chain
  chainWin: 1.5, chainStep: 0.1, chainMax: 5,
  // statuses
  burnDps: 2, burnDur: 4, soakMult: 1.25, soakDur: 4, rootSlow: 0.4, rootDur: 3, shockImmune: 6,
  // shields
  shieldDelay: 3, shieldDecay: 0.2,
  // capture
  capTh: 0.4, capBase: 0.5, capStatus: 0.15, capEnraged: 0.2, capMax: 0.95,
  startCharges: 2, fleeTime: 15, enrageSpeed: 1.3, caughtHp: 0.6,
  // party & run
  partyMax: 6, lineup: 3, reviveHp: 0.25, healReward: 0.4,
  // upgrades & evolution
  upPower: 1.3, evoFill: 150, evoCost: 3, evoHp: 1.5, primePower: 1.4,
  // daily pack
  packResetHour: 4,
  // loadouts & essence (§16)
  essWild: 1, essAlpha: 2, essCatch: 2, essDupe: 3, essWarden: 3, essBoss: 2, moveCost: 5, traitCost: 8,
  // trait numbers
  bulwarkDelay: 3, ebbHeal: 4, deepRoots: 1.5, thirst: 0.3, overshade: 0.5, livewireChain: 3,
};

/** Each element beats the next one in the loop: ember → thorn → volt → tide → ember. */
export const BEATS: Record<El, El> = { ember: 'thorn', thorn: 'volt', volt: 'tide', tide: 'ember' };
export const adv = (a?: El | null, d?: El | null) => (!a || !d) ? 1 : BEATS[a] === d ? BAL.strong : BEATS[d] === a ? BAL.weak : 1;
/** True if a creature of element `def` resists attacks of element `atk`. */
export const resists = (def: El, atk: El) => BEATS[def] === atk;

/* ================= statuses ================= */
export type Status = 'burn' | 'soak' | 'root' | 'shock';
export const STATUS_OF: Record<El, Status> = { ember: 'burn', tide: 'soak', thorn: 'root', volt: 'shock' };
export const STATUS_EL: Record<Status, El> = { burn: 'ember', soak: 'tide', root: 'thorn', shock: 'volt' };
export const STATUS_NAME: Record<Status, string> = { burn: 'Burn', soak: 'Soak', root: 'Root', shock: 'Shock' };
export const STATUS_PAST: Record<Status, string> = { burn: 'Burned', soak: 'Soaked', root: 'Rooted', shock: 'Shocked' };
export const STATUS_DUR: Record<Status, number> = { burn: BAL.burnDur, soak: BAL.soakDur, root: BAL.rootDur, shock: 0 };

/* ================= cards ================= */
export type Slot = 'strike' | 'skill' | 'sig';
export const SLOTS: Slot[] = ['strike', 'skill', 'sig'];
export interface CardDef {
  name: string; cost: number;
  dmg?: number;            // damage in the owner's element
  hits?: number;           // dmg lands this many times (each hit gets the chain bonus)
  bonusIf?: { status: Status; dmg: number };  // extra damage if the target has this status
  fromShield?: boolean;    // damage = owner's shield (consumed)
  status?: Status;         // applied to the enemy (after damage)
  shield?: number;         // shield on self
  shieldTeam?: number;     // shield on every living lineup member
  heal?: number;           // heal self
  healTeam?: number;       // heal every living lineup member
  lifesteal?: number;      // heal self for this fraction of damage dealt
  energy?: number;         // gain energy
  selfDmg?: number;        // take damage
  discount?: number;       // next card costs this much less
  chain?: number;          // extra chain steps
  reflect?: number;        // next hit taken reflects this fraction
  nextStrike?: number;     // next Strike deals ×this
  cleanse?: boolean;       // remove statuses from the team
}

/** Scales every number a "+30% effect" upgrade (or evolution) touches. */
export function scaleCard(c: CardDef, k: number): CardDef {
  if (k === 1) return c;
  const r = (v?: number) => v == null ? v : Math.round(v * k);
  return { ...c, dmg: r(c.dmg), bonusIf: c.bonusIf && { ...c.bonusIf, dmg: r(c.bonusIf.dmg)! }, shield: r(c.shield), shieldTeam: r(c.shieldTeam), heal: r(c.heal),
    healTeam: r(c.healTeam), energy: r(c.energy), lifesteal: c.lifesteal && Math.min(1, +(c.lifesteal * k).toFixed(2)),
    reflect: c.reflect && Math.min(1, +(c.reflect * k).toFixed(2)), nextStrike: c.nextStrike && +(c.nextStrike * k).toFixed(1) };
}
/** True if "+30% effect" changes anything (otherwise only −1 cost is offered). */
export const scalable = (c: CardDef) => !!(c.dmg || c.bonusIf || c.fromShield || c.shield || c.shieldTeam || c.heal || c.healTeam
  || c.energy || c.lifesteal || c.reflect || c.nextStrike || (c.status && c.status !== 'shock'));

/** Short rules text for a card. `pow` is the effect multiplier (status durations and Discharge scale with it). */
export function cardText(c: CardDef, pow = 1): string {
  const out: string[] = [];
  if (c.fromShield) out.push(pow > 1 ? `Dmg = shield ×${pow.toFixed(1)}` : 'Dmg = your shield');
  if (c.dmg) out.push(`${c.dmg} dmg` + (c.hits && c.hits > 1 ? ` ×${c.hits}` : ''));
  if (c.bonusIf) out.push(`+${c.bonusIf.dmg} if ${STATUS_PAST[c.bonusIf.status]}`);
  if (c.status) out.push(STATUS_NAME[c.status] + (c.status !== 'shock' && pow > 1 ? ` ${(STATUS_DUR[c.status] * pow).toFixed(1)}s` : ''));
  if (c.shield) out.push(`shield ${c.shield}`);
  if (c.shieldTeam) out.push(`team shield ${c.shieldTeam}`);
  if (c.heal) out.push(`heal ${c.heal}`);
  if (c.healTeam) out.push(`team heal ${c.healTeam}`);
  if (c.lifesteal) out.push(`heal ${Math.round(c.lifesteal * 100)}% of dmg`);
  if (c.energy) out.push(`+${c.energy} energy`);
  if (c.selfDmg) out.push(`take ${c.selfDmg}`);
  if (c.discount) out.push('next card −1');
  if (c.chain) out.push(`+${c.chain} chain`);
  if (c.reflect) out.push(`reflect ${Math.round(c.reflect * 100)}% next hit`);
  if (c.nextStrike) out.push(`next Strike ×${c.nextStrike}`);
  if (c.cleanse) out.push('cleanse team');
  return out.join(', ');
}

/* ================= traits (§16) ================= */
export type TraitKey = 'afterglow' | 'quickfuse' | 'bulwark' | 'ebb' | 'undercurrent' | 'counterweave'
  | 'deeproots' | 'thirst' | 'overshade' | 'relay' | 'livewire' | 'grounded';
/** Passive rules each creature carries in its socket. `from` is the species it's built in to. */
export const TRAITS: Record<TraitKey, { name: string; from: string; text: string }> = {
  afterglow:    { name: 'Afterglow',    from: 'emberwick',  text: 'When its Burn on the enemy ends, +1 energy' },
  quickfuse:    { name: 'Quickfuse',    from: 'cinderpip',  text: 'Its first card each fight costs 0' },
  bulwark:      { name: 'Bulwark',      from: 'kilnback',   text: 'Its shields start decaying 3s later' },
  ebb:          { name: 'Ebb',          from: 'bellspring', text: 'Heals 4 when swapped out' },
  undercurrent: { name: 'Undercurrent', from: 'puddlet',    text: 'Its heals also cleanse whoever they heal' },
  counterweave: { name: 'Counterweave', from: 'brinecrab',  text: 'A Perfect Swap into it also fires its Strike for free' },
  deeproots:    { name: 'Deep Roots',   from: 'truffmole',  text: 'Root it applies lasts +1.5s' },
  thirst:       { name: 'Thirst',       from: 'brambat',    text: 'Its Strikes heal it for 30% of their damage' },
  overshade:    { name: 'Overshade',    from: 'mossling',   text: 'When it shields itself, the weakest teammate gets half' },
  relay:        { name: 'Relay',        from: 'skiray',     text: 'After a card swaps it in, your next card costs 1 less' },
  livewire:     { name: 'Live Wire',    from: 'sparkit',    text: 'The first time its card reaches chain 3+, +1 energy' },
  grounded:     { name: 'Grounded',     from: 'coilsnail',  text: "Can't be Shocked; a Shock on it gives +1 energy instead" },
};

/* ================= roster ================= */
export type Feature = 'ears' | 'horns' | 'flame' | 'tail' | 'fin' | 'whisk' | 'leaf' | 'spikes' | 'antenna' | 'wings' | 'crown';
export interface SpeciesDef {
  name: string; el: El; hp: number; size: number; feats: Feature[];
  role?: string;
  atk?: number; spd?: number;                    // only used when it's an enemy (default 1)
  cards?: Record<Slot, CardDef[]>;               // per slot: [default, ...alternates] (§16)
  trait?: TraitKey;                              // built-in Trait (§16)
  evo?: { key: string; sig: CardDef };           // named evolution (starters)
  evoOf?: string;                                // art-only species: the evolved form of …
  heavy?: string;                                // heavy attack name override
  warden?: boolean; boss?: boolean;
}
const C = (name: string, cost: number, fx: Omit<CardDef, 'name' | 'cost'>): CardDef => ({ name, cost, ...fx });

export const SPECIES: Record<string, SpeciesDef> = {
  // ---------- Ember
  emberwick: { name: 'Emberwick', el: 'ember', hp: 50, trait: 'afterglow', size: 1, feats: ['ears', 'flame', 'tail'], role: 'Balanced',
    cards: { strike: [C('Peck', 1, { dmg: 6 })], skill: [C('Kindle', 2, { status: 'burn' }), C('Flare Step', 1, { energy: 1, chain: 1 })], sig: [C('Wickflare', 3, { dmg: 14, bonusIf: { status: 'burn', dmg: 8 } }), C('Wildfire', 3, { dmg: 8, status: 'burn', chain: 1 })] },
    evo: { key: 'pyrowl', sig: C('Crownflare', 3, { dmg: 20, bonusIf: { status: 'burn', dmg: 12 }, status: 'burn' }) } },
  pyrowl: { name: 'Pyrowl', el: 'ember', hp: 50, size: 1.2, feats: ['ears', 'flame', 'wings', 'tail'], evoOf: 'emberwick' },
  cinderpip: { name: 'Cinderpip', el: 'ember', hp: 35, trait: 'quickfuse', size: 0.85, feats: ['ears', 'flame'], role: 'Glass cannon', atk: 1.2, spd: 1.1,
    cards: { strike: [C('Scorch', 1, { dmg: 7 })], skill: [C('Flicker', 1, { discount: 1 }), C('Flare Up', 1, { chain: 1, selfDmg: 2 })], sig: [C('Flashfire', 4, { dmg: 24 }), C('Ember Barrage', 3, { dmg: 5, hits: 3 })] } },
  kilnback: { name: 'Kilnback', el: 'ember', hp: 75, trait: 'bulwark', size: 1.22, feats: ['horns', 'spikes', 'flame'], role: 'Tank', atk: 0.85, spd: 0.9,
    cards: { strike: [C('Bash', 1, { dmg: 5 })], skill: [C('Hearth Shell', 2, { shield: 12 }), C('Forge', 2, { shield: 6, nextStrike: 2 })], sig: [C('Slow Burn', 3, { status: 'burn', shield: 8 }), C('Magma Ram', 3, { dmg: 16, selfDmg: 4 })] } },
  // ---------- Tide
  bellspring: { name: 'Bellspring', el: 'tide', hp: 55, trait: 'ebb', size: 0.95, feats: ['fin', 'tail', 'whisk'], role: 'Sustain',
    cards: { strike: [C('Splash', 1, { dmg: 5 })], skill: [C('Drench', 2, { status: 'soak' }), C('Tidecall', 2, { shieldTeam: 5 })], sig: [C('Lantern Tide', 3, { dmg: 10, healTeam: 8 }), C('Undertide', 3, { dmg: 14, bonusIf: { status: 'soak', dmg: 6 } })] },
    evo: { key: 'lanternmere', sig: C('Beacon Tide', 3, { dmg: 14, healTeam: 14 }) } },
  lanternmere: { name: 'Lanternmere', el: 'tide', hp: 55, size: 1.15, feats: ['fin', 'tail', 'whisk', 'antenna'], evoOf: 'bellspring' },
  puddlet: { name: 'Puddlet', el: 'tide', hp: 40, trait: 'undercurrent', size: 0.85, feats: ['fin', 'whisk'], role: 'Healer', atk: 0.9,
    cards: { strike: [C('Drip', 1, { dmg: 4 })], skill: [C('Mend', 2, { heal: 15 }), C('Bubble', 1, { shield: 7 })], sig: [C('Spring Rain', 4, { healTeam: 12, cleanse: true }), C('Wellspring', 3, { healTeam: 6, energy: 2 })] } },
  brinecrab: { name: 'Brinecrab', el: 'tide', hp: 80, trait: 'counterweave', size: 1.18, feats: ['horns', 'fin', 'whisk'], role: 'Tank', atk: 0.9, spd: 0.9,
    cards: { strike: [C('Pinch', 1, { dmg: 6 })], skill: [C('Barnacle', 2, { shield: 14 }), C('Brace', 1, { reflect: 0.3 })], sig: [C('Undertow', 3, { dmg: 12, status: 'soak' }), C('Tidal Clamp', 3, { dmg: 10, shield: 10 })] } },
  // ---------- Thorn
  truffmole: { name: 'Truffmole', el: 'thorn', hp: 55, trait: 'deeproots', size: 1, feats: ['leaf', 'ears'], role: 'Control',
    cards: { strike: [C('Dig', 1, { dmg: 6 })], skill: [C('Tangle', 2, { status: 'root' }), C('Burrow', 2, { shield: 8, nextStrike: 2 })], sig: [C('Sporeburst', 3, { dmg: 12, heal: 6 }), C('Rootquake', 4, { dmg: 16, status: 'root' })] },
    evo: { key: 'morelord', sig: C('Spore Bloom', 3, { dmg: 18, healTeam: 8 }) } },
  morelord: { name: 'Morelord', el: 'thorn', hp: 55, size: 1.2, feats: ['leaf', 'ears', 'spikes', 'crown'], evoOf: 'truffmole' },
  brambat: { name: 'Brambat', el: 'thorn', hp: 40, trait: 'thirst', size: 0.9, feats: ['wings', 'ears', 'spikes'], role: 'Drain', atk: 1.1, spd: 1.1,
    cards: { strike: [C('Nip', 1, { dmg: 5, heal: 2 })], skill: [C('Thornveil', 2, { reflect: 0.5 }), C('Hemlock', 2, { status: 'root', heal: 6 })], sig: [C('Leech Dive', 3, { dmg: 12, lifesteal: 0.5 }), C('Thorn Storm', 4, { dmg: 8, hits: 2, reflect: 0.3 })] } },
  mossling: { name: 'Mossling', el: 'thorn', hp: 50, trait: 'overshade', size: 1.1, feats: ['spikes', 'leaf'], role: 'Support', atk: 0.9,
    cards: { strike: [C('Swat', 1, { dmg: 5 })], skill: [C('Overgrow', 2, { status: 'root', shield: 6 }), C('Photosynth', 2, { healTeam: 5 })], sig: [C('Canopy', 3, { shieldTeam: 8 }), C('Strangle Vine', 3, { dmg: 10, bonusIf: { status: 'root', dmg: 6 } })] } },
  // ---------- Volt
  skiray: { name: 'Skiray', el: 'volt', hp: 45, trait: 'relay', size: 0.9, feats: ['antenna', 'ears', 'tail'], role: 'Tempo', spd: 1.15,
    cards: { strike: [C('Zap', 0, { dmg: 3 })], skill: [C('Static', 2, { status: 'shock' }), C('Tailwind', 1, { chain: 2 })], sig: [C('Gale Strike', 3, { dmg: 10, chain: 1 }), C('Arc Lash', 3, { dmg: 6, status: 'shock' })] } },
  sparkit: { name: 'Sparkit', el: 'volt', hp: 35, trait: 'livewire', size: 0.85, feats: ['antenna', 'tail'], role: 'Glass cannon', atk: 1.2, spd: 1.1,
    cards: { strike: [C('Jolt', 1, { dmg: 7 })], skill: [C('Overcharge', 1, { energy: 2, selfDmg: 4 }), C('Supercharge', 2, { nextStrike: 3 })], sig: [C('Thunderclap', 4, { dmg: 22 }), C('Ball Lightning', 3, { dmg: 14, chain: 1 })] } },
  coilsnail: { name: 'Coilsnail', el: 'volt', hp: 70, trait: 'grounded', size: 1.12, feats: ['horns', 'antenna', 'wings'], role: 'Tank', atk: 0.85, spd: 0.9,
    cards: { strike: [C('Prod', 1, { dmg: 5 })], skill: [C('Capacitor', 2, { shield: 10, nextStrike: 2 }), C('Grounding', 2, { shield: 8, cleanse: true })], sig: [C('Discharge', 3, { fromShield: true }), C('Static Field', 3, { shieldTeam: 6, status: 'shock' })] } },
  // ---------- Warden & boss
  warden: { name: 'Gravewood', el: 'thorn', hp: 300, size: 1.45, feats: ['horns', 'spikes', 'leaf', 'tail'], warden: true },
  noctyrm: { name: 'Noctyrm', el: 'ember', hp: 270, size: 1.5, feats: ['wings', 'tail', 'spikes', 'horns', 'crown'], boss: true, heavy: 'Eclipse Volley' },
};
export const STARTERS = ['emberwick', 'bellspring', 'truffmole'];
/** The 12 collectible creatures, in collection order. */
export const ROSTER = ['emberwick', 'cinderpip', 'kilnback', 'bellspring', 'puddlet', 'brinecrab', 'truffmole', 'brambat', 'mossling', 'skiray', 'sparkit', 'coilsnail'];
export const POOL_A = ['cinderpip', 'puddlet', 'brambat', 'skiray', 'kilnback', 'mossling'];
export const POOL_B = ['brinecrab', 'sparkit', 'coilsnail'];
export const biomeOf = (floor: number) => floor <= 4 ? 0 : 1;

/** Heavy attack names by element. The Warden alternates two. */
export const HEAVY_NAME: Record<El, string> = { ember: 'Blaze Charge', tide: 'Riptide Slam', thorn: 'Bramble Crush', volt: 'Thunder Ram' };
export const WARDEN_HEAVIES: { name: string; el: El }[] = [{ name: 'Bramble Crush', el: 'thorn' }, { name: 'Wildfire Roar', el: 'ember' }];

/* ================= icons ================= */
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
  orb: '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 2a8 8 0 0 1 7.9 7H15a3 3 0 0 0-6 0H4.1A8 8 0 0 1 12 4z"/>',
  swap: '<path d="M7 4L3 8l4 4V9h10V7H7zm10 8v3H7v2h10v3l4-4z"/>',
  up: '<path d="M12 3l8 9h-5v9H9v-9H4z"/>',
  sound: '<path d="M3 9h4l5-5v16l-5-5H3zm13.5 3a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4zM14 3.2v2.1a7 7 0 0 1 0 13.4v2.1a9 9 0 0 0 0-17.6z"/>',
  mute: '<path d="M3 9h4l5-5v16l-5-5H3zm13.6-.6L19 10.8l2.4-2.4 1.4 1.4-2.4 2.4 2.4 2.4-1.4 1.4-2.4-2.4-2.4 2.4-1.4-1.4 2.4-2.4-2.4-2.4z"/>',
};
export type GlyphKey = keyof typeof GLYPH;
export const svg = (k: GlyphKey, cls = '') => `<svg viewBox="0 0 24 24" class="${cls}" aria-hidden="true">${GLYPH[k]}</svg>`;
export const elCss = (el?: El | null) => el ? ELEM[el].css : 'var(--neutral)';
export const elHexCss = (el: El) => '#' + ELEM[el].hex.toString(16).padStart(6, '0');
