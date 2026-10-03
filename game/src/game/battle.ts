// Real-time combat: lineup deck, bench-card swaps, auto attacks, enemy intents and heavies,
// statuses, Perfect Swap, chain meter, capture, evolution. Spec: CLAUDE.md §3–§5, §9.
import { Container, Graphics, Sprite } from 'pixi.js';
import gsap from 'gsap';
import { L, TEX, TS } from '../render/app';
import { U, EPOS, PPOS } from '../render/layout';
import { emit, burst, ring, lightFlash } from '../render/particles';
import { popNum, banner, flash, vignette, toast, shake, hitStop, slowMo, callout } from '../render/fx';
import { Actor, shieldPulse } from '../render/actor';
import { tintArena, setBiome } from '../render/stage';
import { getStyle } from '../art/registry';
import { S, act, mon, team, newMon, activeActor, actorFor, dropActor, cardOf, cardCost, cardBlock, isHeavy, heavyOf, inPerfectWindow, canCapture, captureOdds, evoCandidate,
  type Mon, type MapNode, type Enemy, type CardRef } from './state';
import { slots, show, paintCard, refreshHand, renderBench, renderPlayerPlate, renderEnemyPlate } from './ui';
import { placePlayer, afterFight, onCaught, endRun } from './run';
import { BAL, ELEM, EL_KEYS, SPECIES, SLOTS, STATUS_OF, STATUS_DUR, STATUS_NAME, STATUS_EL, adv, resists, biomeOf, elHexCss,
  type CardDef, type El, type Slot, type Status } from '../core/data';
import { rand, pick, shuffle } from '../core/util';
import { SFX, audio } from '../core/audio';
import { haptic } from '../core/platform';

type Pt = { x: number; y: number };
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/* ================= setup ================= */
export function startBattle(n: MapNode) {
  S.tok++; const tok = S.tok;
  const sp = SPECIES[n.sp!], lvl = n.lvl ?? S.floor;
  const kind = n.type === 'alpha' ? 'alpha' : n.type === 'warden' ? 'warden' : n.type === 'boss' ? 'boss' : 'wild';
  const alpha = kind === 'alpha', hpF = 1 + BAL.hpPerFloor * (lvl - 1), dmgF = 1 + BAL.dmgPerFloor * (lvl - 1);
  const max = Math.round(kind === 'boss' ? sp.hp : kind === 'warden' ? BAL.wardenHp
    : BAL.wildHp * (0.6 + 0.4 * sp.hp / 55) * hpF * (alpha ? BAL.alphaHp : 1));
  const dmg = kind === 'boss' ? BAL.bossDmg : kind === 'warden' ? BAL.wardenDmg : BAL.enemyDmg * (sp.atk ?? 1) * dmgF * (alpha ? BAL.alphaDmg : 1);
  const iv = BAL.intent / (sp.spd ?? 1);
  const e: Enemy = {
    key: n.sp!, name: (alpha ? 'Alpha ' : '') + sp.name, el: kind === 'boss' ? pick(EL_KEYS) : sp.el, kind, alive: true, max, hp: max, dmg, iv,
    t: 0, windup: iv, count: 0, enraged: false, status: null, statusSrc: 0, shockCd: 0, shiftT: BAL.bossShift, fleeT: null, perfect: false, heavyIdx: 0,
  };
  S.enemy = e;
  S.energy = BAL.energyStart; S.swapCd = 0; S.autoT = 0; S.chain = 0; S.chainT = 99; S.discount = 0;
  team().forEach(c => { c.shield = 0; c.status = null; c.reflect = 0; c.nextStrike = 1; });
  if (!S.lineup.includes(S.active)) S.active = S.lineup[0];
  if (!act()?.alive) S.active = healthiest()!.uid;
  buildDeck();

  setBiome(biomeOf(S.floor));
  S.em?.destroy();
  const m = new Actor(n.sp!, e.el); S.em = m; if (alpha) m.extra = 1.15;
  m.root.parent?.setChildIndex(m.root, 0);   // enemy draws behind the partner
  m.off.y = -6; tintArena(ELEM[e.el].hex);
  placePlayer(true);
  show(null); renderPlayerPlate(); renderEnemyPlate(); renderBench(); refreshHand();
  slots.forEach((b, i) => { b.classList.remove('deal'); void b.offsetWidth; b.style.animationDelay = (i * 0.06) + 's'; b.classList.add('deal'); });
  S.mode = 'intro';
  const sub = kind === 'boss' ? 'The final guardian' : kind === 'warden' ? 'Warden of the wild' : alpha ? 'Alpha · can’t be caught' : 'Wild encounter';
  gsap.to(m.off, { y: 0, duration: 0.55, ease: 'power3.in', delay: 0.25, onComplete: () => {
    if (tok !== S.tok) return; const p = EPOS();
    SFX.stomp(); haptic('heavy'); shake(0.55); ring(p.x, p.y, ELEM[e.el].hex, 3, 0.7);
    emit(p.x, p.y, { n: 70, color: [0x8a90b8, 0x5a6088, ...ELEM[e.el].glow], spd: 4, flat: true, life: 0.8, size: 0.3, size1: 1.4, drag: 3, alpha: 0.6 });
    gsap.fromTo(m.sq.scale, { x: 1.4, y: 0.55 }, { x: 1, y: 1, duration: 0.6, ease: 'elastic.out(1,0.35)' });
    banner(e.name, sub, elHexCss(e.el));
    gsap.delayedCall(0.45, () => { if (tok === S.tok) S.mode = 'battle'; });
  } });
}
const healthiest = () => team().filter(c => c.alive).sort((a, b) => b.hp / b.maxHp - a.hp / a.maxHp)[0];

/* ================= deck & hand ================= */
function buildDeck() {
  S.draw = shuffle(team().filter(c => c.alive).flatMap(c => SLOTS.map(slot => ({ uid: c.uid, slot }))));
  S.disc = []; S.hand = [];
  for (let i = 0; i < BAL.hand; i++) S.hand.push(nextCard());
}
function nextCard(): CardRef | null {
  if (!S.draw.length) { S.draw = shuffle(S.disc); S.disc = []; }
  return S.draw.pop() || null;
}
/** Fill slot i now; repaint after the play animation. */
function drawInto(i: number, delay = 0.3) {
  S.hand[i] = nextCard();
  const tok = S.tok;
  gsap.delayedCall(delay, () => {
    if (tok !== S.tok) return;
    const b = slots[i]; b.classList.remove('play'); paintCard(b, S.hand[i]);
    if (S.hand[i]) { b.classList.remove('deal'); b.style.animationDelay = '0s'; void b.offsetWidth; b.classList.add('deal'); }
  });
}
/** A creature fainted: its cards leave the fight. */
function purgeCards(uid: number) {
  S.draw = S.draw.filter(r => r.uid !== uid); S.disc = S.disc.filter(r => r.uid !== uid);
  S.hand.forEach((r, i) => { if (r && r.uid === uid) { slots[i].classList.add('play'); drawInto(i, 0.25); } });
  // an empty slot can be refilled now that the pool changed
  S.hand.forEach((r, i) => { if (!r && !slots[i].classList.contains('play')) drawInto(i, 0); });
}

export function playCard(i: number) {
  audio(); const r = S.hand[i], b = slots[i]; if (!r || S.mode !== 'battle') return;
  const block = cardBlock(r);
  if (block) { b.classList.remove('deny'); void b.offsetWidth; b.classList.add('deny'); SFX.deny(); haptic('warning'); if (block === 'swap') toast('Swapping is cooling down'); return; }
  const { def, pow, owner } = cardOf(r);
  S.energy -= cardCost(r); S.discount = 0;
  S.hand[i] = null; S.disc.push(r);
  b.classList.remove('deal'); b.classList.add('play'); SFX.card(); haptic('light');
  drawInto(i);
  // chain: within the window of the last card → +1 step
  S.chain = S.chainT <= BAL.chainWin ? Math.min(BAL.chainMax, S.chain + 1) : 0; S.chainT = 0;
  if (owner.uid !== S.active) swapTo(owner.uid, 'card');
  resolveCard(def, pow, owner, r.slot);
  if (def.chain) S.chain = Math.min(BAL.chainMax, S.chain + def.chain);
  refreshHand();
}

function resolveCard(C: CardDef, pow: number, me: Mon, slot: Slot) {
  const pm = actorFor(me), pp = pm.head();
  if (C.energy) { S.energy = Math.min(BAL.energyMax, S.energy + C.energy); emit(pp.x, pp.y, { n: 40, color: [0xc8b4ff, 0xffffff, 0x9b7bff], spd: 3, life: 0.6, size: 0.2, drag: 2, swirl: 8 }); SFX.energy(); }
  if (C.selfDmg) hurtMon(me, C.selfDmg, null, false, true);
  if (C.discount) { S.discount = C.discount; SFX.focus(); popNum({ x: pp.x, y: pp.y - U * 0.8 }, '−1', 'shield', 'Next card'); }
  if (C.reflect) { me.reflect = C.reflect; SFX.shield(); popNum({ x: pp.x, y: pp.y - U * 0.8 }, Math.round(C.reflect * 100) + '%', 'shield', 'Thornveil'); }
  if (C.nextStrike) { me.nextStrike = C.nextStrike; SFX.focus(); stars(); }
  if (C.cleanse) team().forEach(c => { c.status = null; });
  if (C.shield) addShield(me, C.shield);
  if (C.shieldTeam) team().filter(c => c.alive).forEach(c => addShield(c, C.shieldTeam!));
  if (C.heal) healMon(me, C.heal);
  if (C.healTeam) team().filter(c => c.alive).forEach(c => healMon(c, C.healTeam!));

  let dmg = C.dmg ?? 0;
  if (C.fromShield) { dmg = Math.round(me.shield * pow); me.shield = 0; }
  if (slot === 'strike' && me.nextStrike > 1 && dmg) { dmg *= me.nextStrike; me.nextStrike = 1; }
  const chainMul = 1 + BAL.chainStep * S.chain, el = me.el, big = (C.cost >= 3 || dmg >= 14), tok = S.tok, uid = me.uid;
  if (!dmg && !C.status) return;
  lunge(pm, dmg ? 0.35 : 0.2);
  projectile(pp, () => S.em!.head(), el, dmg ? { size: big ? 0.42 : 0.26, arc: big ? 1.6 : 0.7, dur: big ? 0.42 : 0.3 } : { size: 0.18, arc: 1, dur: 0.32 }, () => {
    const e = S.enemy; if (tok !== S.tok || !e || !e.alive) return;
    if (dmg) {
      const bonus = C.bonusBurned && e.status?.k === 'burn' ? C.bonusBurned : 0;
      const dealt = hurtEnemy((dmg + bonus) * chainMul, el, uid, { big, bonus: !!bonus });
      if (C.lifesteal && dealt) healMon(me, Math.round(dealt * C.lifesteal));
    }
    if (C.status && e.alive) applyEnemyStatus(C.status, pow, uid);
  });
}
function stars() {
  for (let k = 0; k < 3; k++) gsap.delayedCall(k * 0.08, () => { const p = PPOS(); emit(p.x, p.y, { n: 22, color: [0xffcf6b, 0xfff1b0], spd: 2.4, dir: [0, -1], cone: 0.2, life: 0.8, size: 0.2, r: 0.5, tex: 'star', spin: 5 }); });
}

/* ================= statuses ================= */
function applyEnemyStatus(k: Status, pow: number, src: number) {
  const e = S.enemy!, m = S.em!, hp = m.head();
  if (k === 'shock') {
    if (e.shockCd > 0) { popNum({ x: hp.x, y: hp.y - U * 0.9 }, 'Immune', 'weak', `${Math.ceil(e.shockCd)}s`); return; }
    const heavy = isHeavy(e) && e.t > 0.3;
    e.t = 0; e.perfect = false; e.shockCd = BAL.shockImmune;
    lightning(PPOS(), hp, 'volt'); burst(hp, 'volt', 0.8); m.hitFlash();
    popNum({ x: hp.x, y: hp.y - U * 1 }, 'Shock', '', heavy ? 'Wind-up broken' : 'Reset', ELEM.volt.css);
    return;
  }
  e.status = { k, t: STATUS_DUR[k] * pow, acc: 0 }; e.statusSrc = src;
  popNum({ x: hp.x, y: hp.y - U * 1 }, STATUS_NAME[k], '', '', ELEM[STATUS_EL[k]].css);
  burst(hp, STATUS_EL[k], 0.5);
}
function applyMonStatus(c: Mon, k: Status) {
  const hp = actorFor(c).head();
  if (k === 'shock') { S.chain = 0; S.chainT = 99; S.swapCd = Math.max(S.swapCd, BAL.swapCd); popNum({ x: hp.x, y: hp.y - U * 1.1 }, 'Shocked', '', 'Chain lost', ELEM.volt.css); return; }
  c.status = { k, t: STATUS_DUR[k], acc: 0 };
  popNum({ x: hp.x, y: hp.y - U * 1.1 }, STATUS_NAME[k], '', '', ELEM[STATUS_EL[k]].css);
}
const soakMul = (s: { k: Status } | null) => s?.k === 'soak' ? BAL.soakMult : 1;

/* ================= visuals ================= */
function lunge(a: Actor, amt: number) {
  const enemy = a === S.em, dx = enemy ? -1 : 1, dy = enemy ? 0.6 : -0.6;
  gsap.timeline().to(a.off, { x: dx * amt, y: dy * amt, duration: 0.09, ease: 'power2.out' }).to(a.off, { x: 0, y: 0, duration: 0.22, ease: 'power2.inOut' });
}
function projectile(from: Pt, to: () => Pt, el: El | null, o: { size: number; arc: number; dur: number }, onHit: () => void) {
  const col = el ? ELEM[el].hex : 0xd9ccff, glow = el ? ELEM[el].glow : [0xffffff, 0xd9ccff];
  const c = new Container(), halo = new Sprite(TEX.glow), core = new Sprite(TEX.glow);
  [halo, core].forEach(s => { s.anchor.set(0.5); s.blendMode = 'add'; c.addChild(s); }); halo.tint = col; L.glow.addChild(c);
  const a = { ...from }, st = { t: 0 };
  const trail = el === 'tide' ? { grav: 4 } : el === 'ember' ? { grav: -2 } : el === 'thorn' ? { swirl: 5, tex: 'leaf' as const, spin: 6 } : el === 'volt' ? { drag: 6, tex: 'spark' as const, streak: true } : {};
  gsap.to(st, { t: 1, duration: o.dur, ease: 'power1.in', onUpdate() {
    const t = st.t, b = to(); c.x = lerp(a.x, b.x, t); c.y = lerp(a.y, b.y, t) - Math.sin(t * Math.PI) * o.arc * U;
    const s = o.size * U * 2.6 / TS.glow; halo.scale.set(s * (1 + Math.sin(t * 40) * 0.15)); core.scale.set(s * 0.45);
    emit(c.x, c.y, { n: 3, color: glow, spd: 0.6, life: 0.45, size: o.size * 1.1, size1: 0.1, drag: 2, r: o.size * 0.3, ...trail });
  }, onComplete() { c.destroy({ children: true }); onHit(); } });
}
function lightning(a: Pt, b: Pt, el: El) {
  const glow = ELEM[el].glow, g = new Graphics(); g.blendMode = 'add'; L.glow.addChild(g);
  const pts = [a.x, a.y];
  for (let s = 1; s <= 8; s++) { const t = s / 8; let x = lerp(a.x, b.x, t), y = lerp(a.y, b.y, t); if (s < 8) { x += rand(-0.35, 0.35) * U; y += rand(-0.35, 0.35) * U; } pts.push(x, y); }
  const path = () => { g.moveTo(pts[0], pts[1]); for (let i = 2; i < pts.length; i += 2) g.lineTo(pts[i], pts[i + 1]); };
  path(); g.stroke({ width: U * 0.28, color: ELEM[el].hex, alpha: 0.35, cap: 'round', join: 'round' });
  path(); g.stroke({ width: U * 0.07, color: 0xffffff, alpha: 1, cap: 'round', join: 'round' });
  for (let i = 0; i < pts.length; i += 2) emit(pts[i], pts[i + 1], { n: 3, color: [0xffffff, ...glow], spd: 1.5, life: 0.25, size: 0.16, drag: 4, tex: 'spark', streak: true });
  gsap.to(g, { alpha: 0, duration: 0.2, onComplete: () => g.destroy() });
  SFX.zap(); lightFlash(ELEM[el].hex, b, 3);
}

/* ================= damage ================= */
/** Damage the enemy. `src` is the uid of the creature that dealt it (0 = none), for the evolution meter. */
function hurtEnemy(amount: number, el: El, src: number, o: { dot?: boolean; big?: boolean; small?: boolean; bonus?: boolean } = {}) {
  const e = S.enemy, m = S.em; if (!e || !e.alive || !m) return 0;
  const a = adv(el, e.el), dmg = Math.max(1, Math.round(amount * a * soakMul(e.status)));
  e.hp = Math.max(0, e.hp - dmg); S.stats.dealt += dmg;
  const sm = src ? mon(src) : null; if (sm && sm.starter && !sm.evolved) sm.evo = Math.min(BAL.evoFill, sm.evo + dmg);
  const hp = m.head();
  popNum({ x: hp.x, y: hp.y - U * 0.7 }, dmg, a > 1 ? 'crit' : a < 1 ? 'weak' : o.dot ? 'dot' : '',
    a > 1 && !o.dot ? 'Super' : a < 1 && !o.dot ? 'RESIST' : o.bonus ? 'Burned!' : '', ELEM[el].css);
  if (o.dot) emit(hp.x, hp.y, { n: 10, color: ELEM[el].glow, spd: 1.5, up: 1, life: 0.7, size: 0.22, grav: -2 });
  else {
    burst(hp, el, o.big ? 1.6 : o.small ? 0.55 : 1); m.hitFlash(); lightFlash(ELEM[el].hex, hp, o.big ? 7 : 4);
    gsap.fromTo(m.off, { x: 0.22, y: -0.12 }, { x: 0, y: 0, duration: 0.35, ease: 'power2.out' });
    if (a > 1 || o.big) { hitStop(0.06); shake(o.big ? 0.6 : 0.4); flash(o.big ? 0.3 : 0.18); SFX.crit(); }
    else { shake(o.small ? 0.12 : 0.22); SFX.hit(el); }
    if (!o.small) haptic('medium');
  }
  if (e.kind === 'wild' && e.fleeT == null && e.hp > 0 && e.hp / e.max <= BAL.capTh) {
    e.fleeT = BAL.fleeTime; toast(`${e.name} is weak. Catch it before it flees!`);
  }
  if (e.hp <= 0) enemyDown();
  return dmg;
}
/** Damage one of your creatures. el = null for self-inflicted damage. */
function hurtMon(c: Mon, amount: number, el: El | null, heavy: boolean, self = false) {
  if (!c.alive) return 0;
  const pm = actorFor(c), a = el ? adv(el, c.el) : 1;
  let dmg = Math.max(1, Math.round(amount * a * soakMul(c.status))); const hp = pm.head(), raw = dmg;
  let absorbed = 0; if (c.shield >= 1) { absorbed = Math.min(Math.floor(c.shield), dmg); c.shield -= absorbed; dmg -= absorbed; }
  if (absorbed) { popNum({ x: hp.x - U * 0.4, y: hp.y - U * 0.5 }, absorbed, 'shield', 'Blocked'); emit(hp.x, hp.y, { n: 30, color: [0x8fe3ff, 0xffffff], spd: 4, life: 0.4, size: 0.16, drag: 4, tex: 'spark', streak: true }); SFX.shield(); if (c.uid === S.active) gsap.fromTo(shieldPulse, { s: 1.25 }, { s: 1, duration: 0.3 }); }
  if (dmg > 0) {
    c.hp = Math.max(0, c.hp - dmg);
    popNum({ x: hp.x, y: hp.y - U * 0.7 }, dmg, 'player' + (a > 1 ? ' crit' : ''), a > 1 ? 'Super' : a < 1 ? 'RESIST' : '');
    if (!self) { pm.hitFlash(); vignette(); SFX.ouch(); shake(heavy ? 0.6 : 0.35); haptic(heavy ? 'heavy' : 'medium'); if (heavy) hitStop(0.06); }
    gsap.fromTo(pm.off, { x: -0.22, y: 0.1 }, { x: 0, y: 0, duration: 0.35, ease: 'power2.out' });
  }
  if (el && !self) { burst(hp, el, heavy ? 1.3 : 0.8); lightFlash(ELEM[el].hex, hp, 4); }
  if (c.reflect > 0 && el && !self && S.enemy?.alive) {
    const back = Math.round(raw * c.reflect); c.reflect = 0;
    const tok = S.tok; projectile(hp, () => S.em!.head(), c.el, { size: 0.3, arc: 0.4, dur: 0.25 }, () => { if (tok === S.tok) hurtEnemy(back, c.el, c.uid, { small: true }); });
  }
  if (c.hp <= 0) monDown(c);
  return dmg;
}
function addShield(c: Mon, v: number) {
  c.shield += v; c.shieldT = 0; const hp = actorFor(c).head();
  if (c.uid !== S.active) return;
  popNum({ x: hp.x, y: hp.y - U * 0.8 }, '+' + v, 'shield', 'Shield');
  emit(hp.x, hp.y, { n: 40, color: [0x8fe3ff, 0xffffff, 0x3fb6ff], spd: 2.2, life: 0.7, size: 0.18, drag: 2.5, swirl: 9, r: 0.5 });
  gsap.fromTo(shieldPulse, { s: 0.3 }, { s: 1, duration: 0.4, ease: 'back.out(2)' }); SFX.shield();
}
function healMon(c: Mon, v: number) {
  if (!c.alive) return;
  c.hp = Math.min(c.maxHp, c.hp + v);
  if (c.uid !== S.active) return;
  const hp = actorFor(c).head(), p = PPOS();
  popNum({ x: hp.x + U * 0.3, y: hp.y - U * 0.8 }, '+' + Math.round(v), 'heal');
  emit(p.x, p.y, { n: 45, color: [0x6ff0a0, 0xc8ffd9, 0xffffff], spd: 2.2, dir: [0, -1], cone: 0.25, life: 1, size: 0.22, drag: 1, r: 0.5, swirl: 4 });
  ring(p.x, p.y, 0x6ff0a0, 1.6); SFX.heal();
}

/* ================= enemy ================= */
function startWindup(e: Enemy) { e.t = 0; e.perfect = false; e.windup = e.iv + (isHeavy(e) ? BAL.heavyExtra : 0); }

function autoAttack() {
  const me = act(), pm = activeActor(); if (!me || !me.alive || !pm || !S.enemy || !S.enemy.alive) return;
  const tok = S.tok, uid = me.uid; lunge(pm, 0.22);
  projectile(pm.head(), () => S.em!.head(), me.el, { size: 0.16, arc: 0.35, dur: 0.26 }, () => { if (tok === S.tok) hurtEnemy(BAL.autoDmg, me.el, uid, { small: true }); });
}
function enemyAttack() {
  const e = S.enemy!, m = S.em!, heavy = isHeavy(e), hv = heavyOf(e), el = heavy ? hv.el : e.el;
  const dmg = e.dmg * (heavy ? BAL.heavyMult : 1), tok = S.tok, perfect = e.perfect;
  e.count++; if (heavy && e.kind === 'warden') e.heavyIdx++;
  startWindup(e);
  const land = (amount: number, last: boolean) => {
    if (tok !== S.tok || !e.alive) return;
    const me = act(); if (!me || !me.alive) return;
    if (heavy && perfect && resists(me.el, el)) { reflect(amount, el); return; }
    hurtMon(me, amount, el, heavy && last);
    if (heavy && last && me.alive) applyMonStatus(me, STATUS_OF[el]);
  };
  if (e.kind === 'boss' && heavy) {  // charged volley
    gsap.fromTo(m.sq.scale, { y: 1 }, { y: 1.25, duration: 0.25, yoyo: true, repeat: 1 });
    for (let k = 0; k < 3; k++) gsap.delayedCall(0.2 + k * 0.12, () => {
      if (tok !== S.tok || !e.alive || !activeActor()) return;
      projectile(m.head(), () => activeActor()!.head(), el, { size: 0.4, arc: 0.9, dur: 0.3 }, () => land(dmg / 3, k === 2));
    });
    return;
  }
  const P = PPOS(), E = EPOS(), tx = (P.x - E.x) / U * 0.62, ty = (P.y - E.y) / U * 0.62;
  if (heavy) emit(E.x, E.y, { n: 40, color: ELEM[el].glow, spd: 3, dir: [0, -1], cone: 0.5, life: 0.5, size: 0.25, r: 0.5 });
  gsap.timeline()
    .to(m.off, { x: -tx * 0.1, y: -ty * 0.1 - (heavy ? 0.4 : 0.15), duration: heavy ? 0.22 : 0.1, ease: 'power1.out' })
    .to(m.off, { x: tx, y: ty, duration: 0.12, ease: 'power3.in', onComplete: () => land(dmg, true) })
    .to(m.off, { x: 0, y: 0, duration: 0.32, ease: 'power2.out' });
}
/** Perfect Swap payoff when the heavy lands: no damage, part of it bounces back. */
function reflect(amount: number, el: El) {
  const me = act(), hp = activeActor()!.head(), tok = S.tok;
  popNum({ x: hp.x, y: hp.y - U * 0.9 }, '0', 'shield', 'Perfect block');
  emit(hp.x, hp.y, { n: 60, color: [0xffffff, ...ELEM[me.el].glow], spd: 5, life: 0.5, size: 0.2, drag: 3, tex: 'spark', streak: true });
  ring(hp.x, hp.y, ELEM[me.el].hex, 2.2, 0.4, false); SFX.shield();
  projectile(hp, () => S.em!.head(), el, { size: 0.45, arc: 0.6, dur: 0.3 }, () => { if (tok === S.tok) hurtEnemy(amount * BAL.perfectReflect, el, me.uid, { big: true }); });
}
function shiftBoss() {
  const e = S.enemy!, m = S.em!; e.el = pick(EL_KEYS.filter(k => k !== e.el)); m.setElement(e.el); tintArena(ELEM[e.el].hex);
  const E = EPOS(); burst(m.head(), e.el, 1.4); ring(E.x, E.y, ELEM[e.el].hex, 3.2, 0.7); flash(0.25, elHexCss(e.el));
  SFX.swap(); haptic('medium'); renderEnemyPlate(); refreshHand(); toast('Noctyrm shifts to ' + ELEM[e.el].name);
}

/* ================= swapping & fainting ================= */
/** Tap on a bench portrait. */
export function swapTap(uid: number) {
  audio(); if (S.mode !== 'battle') return;
  const c = mon(uid); if (!c || !c.alive || uid === S.active) return;
  if (S.swapCd > 0 || S.energy < BAL.swapCost) { SFX.deny(); haptic('warning'); if (S.swapCd <= 0) toast(`Swapping costs ${BAL.swapCost} energy`); return; }
  S.energy -= BAL.swapCost; swapTo(uid, 'tap');
}
/** Make `uid` the lead. Logic is instant; the visuals catch up. */
function swapTo(uid: number, how: 'tap' | 'card' | 'forced') {
  const old = activeActor(), prev = act(), tok = S.tok;
  S.active = uid; S.autoT = 0; if (how !== 'forced') S.swapCd = BAL.swapCd;
  SFX.swap(); haptic('light');
  const p = PPOS(); emit(p.x, p.y, { n: 70, color: ELEM[(prev ?? act()).el].glow, spd: 4, dir: [0, -1], cone: 0.12, life: 0.6, size: 0.22, r: 0.35, tex: 'spark', streak: true });
  if (old && old !== activeActor()) gsap.to(old.sq.scale, { x: 0.01, y: 1.7, duration: 0.14, ease: 'power2.in', onComplete: () => { if (tok !== S.tok) return; if (act() && activeActor() !== old) old.visible = false; old.sq.scale.set(1); } });
  placePlayer(true, old);
  renderPlayerPlate(); renderBench(); refreshHand();
  const e = S.enemy;
  if (how !== 'forced' && e && e.alive && inPerfectWindow(e) && resists(act().el, heavyOf(e).el)) perfectSwap();
}
function perfectSwap() {
  const e = S.enemy!; e.perfect = true; S.stats.perfects++;
  S.energy = Math.min(BAL.energyMax, S.energy + BAL.perfectRefund);
  hitStop(0.12); slowMo(BAL.slowDur, BAL.slowScale); flash(0.5, '#fff'); haptic('heavy'); SFX.crit();
  callout('PERFECT', elHexCss(act().el));
  const p = activeActor()!.head(); popNum({ x: p.x, y: p.y - U * 1.3 }, '+' + BAL.perfectRefund, 'shield', 'Energy');
  ring(p.x, p.y, 0xffffff, 3, 0.5, false);
}
function monDown(c: Mon) {
  c.alive = false; c.shield = 0; c.status = null; const tok = S.tok, lead = c.uid === S.active;
  SFX.ko(); haptic('error'); shake(0.5); hitStop(0.12);
  purgeCards(c.uid); renderBench();
  if (lead) {
    const pm = actorFor(c);
    gsap.to(pm.flip, { rotation: -1.2, duration: 0.4, ease: 'power2.in' });
    gsap.to(pm.sq.scale, { x: 0.01, y: 0.01, duration: 0.5, delay: 0.35, ease: 'power2.in', onComplete: () => {
      const p = PPOS(); emit(p.x, p.y - U * 0.4, { n: 60, color: [0x9aa3c7, 0x5a6088, 0xffffff], spd: 2, up: 1, life: 1, size: 0.25, grav: -1, drag: 1.5 });
    } });
  }
  const next = healthiest();
  if (!next) { S.mode = 'over'; gsap.delayedCall(1.2, () => { if (tok === S.tok) endRun(false); }); return; }
  if (lead) {
    banner(c.name + ' fainted', 'Next partner in', '#ff5a6e');
    gsap.delayedCall(0.9, () => { if (tok !== S.tok || act()?.alive) return; const n = healthiest(); if (n) swapTo(n.uid, 'forced'); });
  } else toast(c.name + ' fainted on the bench');
}
function enemyDown() {
  const e = S.enemy!, m = S.em!; e.alive = false; S.mode = 'end'; const tok = S.tok;
  SFX.ko(); haptic('heavy'); hitStop(0.14); shake(0.6); flash(0.4);
  gsap.to(m.sq.scale, { x: 1.45, y: 0.22, duration: 0.35, ease: 'power2.in' });
  gsap.delayedCall(0.32, () => {
    const p = m.head(), E = EPOS(); m.visible = false;
    for (let k = 0; k < 3; k++) gsap.delayedCall(k * 0.1, () => burst(p, e.el, 1.2));
    emit(p.x, p.y, { n: 150, color: ELEM[e.el].glow, spd: 5, up: 1, life: 1.6, size: 0.26, grav: -1.5, drag: 1.4, swirl: 2 });
    emit(p.x, p.y, { n: 20, color: [0xffcf6b, 0xffffff], spd: 4, up: 1, life: 1.4, size: 0.4, grav: 2, drag: 1, tex: 'star', spin: 6 });
    ring(E.x, E.y, ELEM[e.el].hex, 4, 0.9);
  });
  const boss = e.kind === 'boss';
  banner(boss ? 'Noctyrm falls' : 'Victory', boss ? 'The expedition is complete' : e.kind === 'warden' ? 'The Warden yields' : 'Choose a reward', '#ffcf6b'); SFX.win();
  gsap.delayedCall(1.4, () => { if (tok === S.tok) { haptic('success'); afterFight('win'); } });
}
function enemyFlees() {
  const e = S.enemy!, m = S.em!; e.alive = false; S.mode = 'end'; const tok = S.tok;
  SFX.swap(); haptic('warning');
  gsap.to(m.off, { x: 5, y: -1, duration: 0.6, ease: 'power2.in' });
  gsap.to(m.sq.scale, { x: 0.6, y: 1.3, duration: 0.3, yoyo: true, repeat: 1 });
  const E = EPOS(); emit(E.x, E.y, { n: 60, color: [0x8a90b8, 0x5a6088], spd: 3, flat: true, life: 0.7, size: 0.3, size1: 1.4, drag: 3, alpha: 0.6 });
  banner('It fled', 'No reward this time', '#98a1c8');
  gsap.delayedCall(1.3, () => { if (tok === S.tok) afterFight('flee'); });
}

/* ================= capture ================= */
export function tryCapture() {
  audio(); const e = S.enemy, m = S.em;
  if (S.mode !== 'battle' || !e || !m || !canCapture(e)) return;
  if (S.charges <= 0) { SFX.deny(); haptic('warning'); toast('No Capture charges left'); return; }
  S.charges--; S.mode = 'anim'; SFX.throw(); haptic('medium'); const tok = S.tok;
  const orb = new Container(), og = new Graphics(), halo = new Sprite(TEX.glow);
  halo.anchor.set(0.5); halo.blendMode = 'add'; halo.tint = 0x9b7bff; halo.scale.set(2.2);
  og.circle(0, 0, 20).fill(0xf4eeff).stroke({ width: 4, color: 0x14102a });
  og.moveTo(-20, 0).arc(0, 0, 20, Math.PI, 0, true).fill(0x7d5cff);
  og.moveTo(-20, 0).lineTo(20, 0).stroke({ width: 5, color: 0x14102a }); og.circle(0, 0, 7).fill(0xffcf6b).stroke({ width: 3, color: 0x14102a });
  orb.addChild(halo, og); L.glow.addChild(orb); orb.scale.set(U / 46);
  const a = activeActor()!.head(), st = { t: 0 };
  const success = Math.random() < captureOdds(e);

  gsap.to(st, { t: 1, duration: 0.55, ease: 'power1.inOut', onUpdate() {
    const b = m.head(); orb.x = lerp(a.x, b.x, st.t); orb.y = lerp(a.y, b.y - U * 0.2, st.t) - Math.sin(st.t * Math.PI) * 1.6 * U; orb.rotation += 0.35;
    emit(orb.x, orb.y, { n: 3, color: [0xffcf6b, 0xd9ccff, 0xffffff], spd: 0.4, life: 0.5, size: 0.16, drag: 2 });
  }, onComplete() {
    if (tok !== S.tok) { orb.destroy({ children: true }); return; }
    const b = m.head(); lightFlash(0xffffff, b, 8); flash(0.35); shake(0.3); haptic('medium');
    emit(b.x, b.y, { n: 90, color: ELEM[e.el].glow, spd: 3, life: 0.6, size: 0.24, drag: 1, swirlDir: 10 });
    gsap.to(m.sq.scale, { x: 0.01, y: 0.01, duration: 0.3, ease: 'power2.in' });
    const E = EPOS(); gsap.to(orb, { x: E.x, y: E.y - U * 0.25, rotation: 0, duration: 0.45, delay: 0.3, ease: 'bounce.out', onComplete: wobble });
  } });

  function wobble() {
    let k = 0; const breakAt = 1 + Math.floor(Math.random() * 2);
    const step = () => {
      if (tok !== S.tok) { orb.destroy({ children: true }); return; }
      if (k === 3 || (!success && k === breakAt)) return finish();
      k++; SFX.tick(); haptic('light');
      emit(orb.x, orb.y, { n: 14, color: [0xffcf6b, 0xffffff], spd: 2, up: 1, life: 0.45, size: 0.18, drag: 3, tex: 'star', spin: 6 });
      gsap.fromTo(orb, { rotation: 0 }, { rotation: (k % 2 ? 1 : -1) * 0.5, duration: 0.12, yoyo: true, repeat: 1, ease: 'power1.inOut', onComplete: () => { gsap.delayedCall(0.28, step); } });
    };
    gsap.delayedCall(0.25, step);
  }
  function finish() {
    const E = EPOS();
    if (success) {
      e!.alive = false; S.mode = 'end'; SFX.caught(); haptic('heavy'); shake(0.3);
      for (let j = 0; j < 4; j++) gsap.delayedCall(j * 0.12, () => {
        emit(orb.x, orb.y, { n: 40, color: [0xffcf6b, 0xfff1b0, 0xffffff, ELEM[e!.el].hex], spd: 5, up: 1.3, life: 1.2, size: 0.22, grav: 4, drag: 0.8, floor: E.y });
        emit(orb.x, orb.y, { n: 8, color: [0xffcf6b, 0xffffff], spd: 4, up: 1, life: 1, size: 0.4, grav: 3, drag: 1, tex: 'star', spin: 8 });
        ring(orb.x, E.y, 0xffcf6b, 2 + j);
      });
      gsap.to(orb.scale, { x: 0.01, y: 0.01, duration: 0.4, delay: 0.7, onComplete: () => { orb.destroy({ children: true }); } });
      banner('Caught!', SPECIES[e!.key].name + ' joins you', '#ffcf6b'); S.stats.caught++;
      gsap.delayedCall(1.5, () => { if (tok === S.tok) onCaught(e!); });
    } else {
      SFX.broke(); haptic('error'); shake(0.45); flash(0.3);
      emit(orb.x, orb.y, { n: 80, color: [0xffffff, 0xd9ccff, 0xffcf6b], spd: 6, life: 0.5, size: 0.2, drag: 3, tex: 'spark', streak: true });
      orb.destroy({ children: true }); e!.enraged = true; e!.t = Math.max(e!.t, e!.windup * 0.5);
      gsap.to(m!.sq.scale, { x: 1, y: 1, duration: 0.5, ease: 'back.out(3)' }); banner('Broke free', 'It is enraged', '#ff5a6e');
      gsap.delayedCall(0.4, () => { if (tok === S.tok) S.mode = 'battle'; });
    }
  }
}

/* ================= evolution ================= */
export function tryEvolve() {
  audio(); const c = evoCandidate(); if (S.mode !== 'battle' || !c) return;
  if (S.energy < BAL.evoCost) { SFX.deny(); haptic('warning'); toast(`Evolving costs ${BAL.evoCost} energy`); return; }
  S.energy -= BAL.evoCost;
  const sp = SPECIES[c.key], evoKey = sp.evo?.key, hasArt = !!evoKey && (getStyle().has?.(evoKey) ?? true);
  c.evolved = true; c.art = hasArt ? evoKey! : c.key; c.name = evoKey ? SPECIES[evoKey].name : 'Prime ' + sp.name;
  c.maxHp = Math.round(c.maxHp * BAL.evoHp); c.hp = c.maxHp;
  slowMo(BAL.slowDur, BAL.slowScale); flash(0.7, elHexCss(c.el)); haptic('heavy'); shake(0.5); SFX.win();
  callout('EVOLVED', elHexCss(c.el));
  const lead = c.uid === S.active;
  dropActor(c.uid);
  if (lead) {
    placePlayer(true);
    const p = PPOS(), a = activeActor()!;
    for (let k = 0; k < 3; k++) gsap.delayedCall(k * 0.1, () => burst(a.head(), c.el, 1.4));
    emit(p.x, p.y, { n: 120, color: ELEM[c.el].glow, spd: 5, up: 1.2, life: 1.2, size: 0.26, grav: -1, drag: 1.2, swirl: 3 });
    ring(p.x, p.y, ELEM[c.el].hex, 4, 0.8);
  }
  banner(c.name, 'Max HP +50% · Signature upgraded', elHexCss(c.el));
  renderPlayerPlate(); renderBench(); refreshHand();
}

/* ================= per-frame simulation ================= */
function tickStatusOnMon(c: Mon, dt: number) {
  const s = c.status; if (!s) return;
  s.t -= dt;
  if (s.k === 'burn') { s.acc = (s.acc ?? 0) + dt; if (s.acc >= 0.5) { s.acc = 0; hurtMon(c, BAL.burnDps * 0.5, null, false, true); } }
  if (s.t <= 0 && c.status === s) c.status = null;
}
export function tickBattle(dt: number, t: number) {
  const e = S.enemy, m = S.em;
  if (m) {  // wind-up aura before an attack
    if (e && e.alive && S.mode === 'battle') { const w = e.t / e.windup; m.aura.tint = ELEM[isHeavy(e) ? heavyOf(e).el : e.el].hex; m.aura.alpha = w > 0.75 ? (w - 0.75) * (isHeavy(e) ? 4 : 3.2) * (0.6 + 0.4 * Math.sin(t * 30)) : 0; }
    else m.aura.alpha = 0;
  }
  if (S.mode !== 'battle') return;
  const me = act();
  const rooted = me?.status?.k === 'root' ? 1 - BAL.rootSlow : 1;
  S.energy = Math.min(BAL.energyMax, S.energy + dt * BAL.energyRate * rooted);
  if (S.swapCd > 0) S.swapCd = Math.max(0, S.swapCd - dt);
  S.chainT += dt; if (S.chainT > BAL.chainWin) S.chain = 0;
  if (me && me.alive) { S.autoT += dt; if (S.autoT >= BAL.autoIv) { S.autoT = 0; autoAttack(); } }
  for (const c of team()) {
    if (!c.alive) continue;
    if (c.shield > 0) { c.shieldT += dt; if (c.shieldT > BAL.shieldDelay) { c.shield -= c.shield * BAL.shieldDecay * dt; if (c.shield < 0.5) c.shield = 0; } }
    tickStatusOnMon(c, dt);
    if (S.mode !== 'battle') return;
  }
  if (!e || !e.alive || !m) return;
  if (e.shockCd > 0) e.shockCd = Math.max(0, e.shockCd - dt);
  const rate = (e.status?.k === 'root' ? 1 - BAL.rootSlow : 1) * (e.enraged ? BAL.enrageSpeed : 1);
  e.t += dt * rate; if (e.t >= e.windup) enemyAttack();
  if (!e.alive || S.mode !== 'battle') return;
  const p = m.head();
  if (e.t / e.windup > 0.75 && Math.random() < dt * 30) emit(p.x, p.y + U * 0.3, { n: 2, color: ELEM[isHeavy(e) ? heavyOf(e).el : e.el].glow, spd: 1.2, r: 0.5, life: 0.4, size: 0.18, drag: 2, swirlDir: 6 });
  const s = e.status;
  if (s) {
    s.t -= dt;
    if (s.k === 'burn') {
      s.acc = (s.acc ?? 0) + dt;
      if (s.acc >= 0.5) { s.acc = 0; hurtEnemy(BAL.burnDps * 0.5, 'ember', e.statusSrc, { dot: true }); }
      if (Math.random() < dt * 20) emit(p.x, p.y, { n: 1, color: ELEM.ember.glow, spd: 0.8, r: 0.4, up: 1, life: 0.6, size: 0.2, grav: -2 });
    } else if (s.k === 'soak' && Math.random() < dt * 12) emit(p.x, p.y - U * 0.4, { n: 1, color: ELEM.tide.glow, spd: 0.5, r: 0.5, life: 0.6, size: 0.16, grav: 6 });
    else if (s.k === 'root' && Math.random() < dt * 8) emit(p.x, p.y + U * 0.6, { n: 1, color: ELEM.thorn.glow, spd: 0.6, r: 0.6, up: 0.6, life: 0.9, size: 0.2, tex: 'leaf', spin: 4 });
    if (s.t <= 0 && e.status === s) e.status = null;
  }
  if (!e.alive) return;
  if (e.kind === 'boss') { e.shiftT -= dt; if (e.shiftT <= 0) { e.shiftT = BAL.bossShift; shiftBoss(); } }
  if (e.fleeT != null) { e.fleeT -= dt; if (e.fleeT <= 0) enemyFlees(); }
}

/** Dev helpers (window.__wb.debug in dev builds). */
export const debug = {
  hurt: (f = 0.65) => { const e = S.enemy; if (e && e.alive) hurtEnemy(e.max * f, e.el, 0, { small: true }); },
  energy: () => { S.energy = BAL.energyMax; },
  evo: () => { const c = S.party.find(m => m.starter); if (c) c.evo = BAL.evoFill; },
  /** Add a creature to the party (and lineup if there's room). Use on the map, before a fight. */
  add: (key: string) => { const c = newMon(key); S.party.push(c); if (S.lineup.length < BAL.lineup) S.lineup.push(c.uid); return c.uid; },
  heavy: () => { const e = S.enemy; if (e) { while (!isHeavy(e)) e.count++; e.windup = e.iv + BAL.heavyExtra; e.t = e.windup - 1; } },
};
