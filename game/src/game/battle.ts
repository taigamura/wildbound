// Real-time combat: cards, auto attacks, enemy intents, statuses, swapping, capture.
import { Container, Graphics, Sprite } from 'pixi.js';
import gsap from 'gsap';
import { L, TEX, TS } from '../render/app';
import { U, EPOS, PPOS } from '../render/layout';
import { emit, burst, ring, lightFlash } from '../render/particles';
import { popNum, banner, flash, vignette, toast, shake, hitStop } from '../render/fx';
import { Actor, shieldPulse } from '../render/actor';
import { tintArena } from '../render/stage';
import { S, act, activeActor, type MapNode } from './state';
import { slots, show, paintCard, refreshHand, renderBench, renderPlayerPlate, renderEnemyPlate } from './ui';
import { placePlayer, afterWin, onCaught, endRun } from './run';
import { CARDS, ELEM, EL_KEYS, SPECIES, HAND, CAP_TH, CAPTURE_COST, ENERGY_RATE, ENERGY_MAX, SWAP_COOLDOWN, adv, elHexCss, type CardDef, type El } from '../core/data';
import { $, rand, pick, shuffle } from '../core/util';
import { SFX, audio } from '../core/audio';
import { haptic } from '../core/platform';

type Pt = { x: number; y: number };
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/* ================= setup ================= */
export function startBattle(n: MapNode) {
  S.tok++; const tok = S.tok;
  const sp = SPECIES[n.sp!], f = S.floor, elite = n.type === 'elite', boss = n.type === 'boss';
  const hpMul = (1 + 0.17 * (f - 1)) * (elite ? 1.45 : 1), max = Math.round(boss ? sp.hp : sp.hp * 0.78 * hpMul);
  const e = {
    key: n.sp!, name: (elite ? 'Alpha ' : '') + sp.name, el: boss ? pick(EL_KEYS) : sp.el, lvl: f, elite, boss, alive: true, max, hp: max,
    dmg: boss ? 10 : 6 * sp.atk * (1 + 0.12 * (f - 1)) * (elite ? 1.2 : 1), iv: boss ? 2.6 : 3.0 / sp.spd,
    t: 0, stun: 0, burn: 0, burnAcc: 0, burnDps: 0, count: 0, enraged: false, shiftT: 7,
  };
  S.enemy = e;
  S.draw = shuffle(S.deck.slice()); S.disc = []; S.hand = []; for (let i = 0; i < HAND; i++) S.hand.push(S.draw.pop() || null);
  S.energy = 3; S.focus = false; S.swapCd = 0; S.swapping = false; S.autoT = 0; S.regen = { t: 0, acc: 0, amt: 0 };
  S.party.forEach(c => c.shield = 0); if (!act().alive) S.active = S.party.findIndex(c => c.alive);

  S.em?.destroy();
  const m = new Actor(n.sp!, e.el); S.em = m; if (elite) m.extra = 1.15;
  m.root.parent?.setChildIndex(m.root, 0);   // enemy draws behind the partner
  m.off.y = -6; tintArena(ELEM[e.el].hex);
  placePlayer(true);
  show(null); renderPlayerPlate(); renderEnemyPlate(); renderBench(); refreshHand();
  $('#floorT').textContent = S.floor; $('#deckT').textContent = S.deck.length;
  slots.forEach((b, i) => { b.classList.remove('deal'); void b.offsetWidth; b.style.animationDelay = (i * 0.06) + 's'; b.classList.add('deal'); });
  S.mode = 'intro';
  gsap.to(m.off, { y: 0, duration: 0.55, ease: 'power3.in', delay: 0.25, onComplete: () => {
    if (tok !== S.tok) return; const p = EPOS();
    SFX.stomp(); haptic('heavy'); shake(0.55); ring(p.x, p.y, ELEM[e.el].hex, 3, 0.7);
    emit(p.x, p.y, { n: 70, color: [0x8a90b8, 0x5a6088, ...ELEM[e.el].glow], spd: 4, flat: true, life: 0.8, size: 0.3, size1: 1.4, drag: 3, alpha: 0.6 });
    gsap.fromTo(m.sq.scale, { x: 1.4, y: 0.55 }, { x: 1, y: 1, duration: 0.6, ease: 'elastic.out(1,0.35)' });
    banner(boss ? 'Noctyrm' : e.name, boss ? 'The final guardian' : elite ? 'Alpha encounter' : 'Wild encounter', elHexCss(e.el));
    gsap.delayedCall(0.45, () => { if (tok === S.tok) S.mode = 'battle'; });
  } });
}

/* ================= cards ================= */
function drawInto(i: number) {
  if (!S.draw.length) { S.draw = shuffle(S.disc); S.disc = []; }
  S.hand[i] = S.draw.pop() || null;
  const b = slots[i]; b.classList.remove('play'); paintCard(b, S.hand[i], S.enemy);
  b.classList.remove('deal'); b.style.animationDelay = '0s'; void b.offsetWidth; b.classList.add('deal');
}
export function playCard(i: number) {
  audio(); if (S.mode !== 'battle') return;
  const id = S.hand[i]; if (!id) return; const C = CARDS[id], me = act(), b = slots[i];
  if (S.energy < C.cost || !me.alive || S.swapping) { b.classList.remove('deny'); void b.offsetWidth; b.classList.add('deny'); SFX.deny(); haptic('warning'); return; }
  S.energy -= C.cost; S.hand[i] = null; S.disc.push(id);
  b.classList.remove('deal'); b.classList.add('play'); SFX.card(); haptic('select');
  const tok = S.tok; setTimeout(() => { if (tok === S.tok) drawInto(i); }, 300);
  resolveCard(C);
}
function resolveCard(C: CardDef) {
  const me = act(), pm = activeActor()!, pp = pm.head();
  if (C.energy) { S.energy = Math.min(ENERGY_MAX, S.energy + C.energy); emit(pp.x, pp.y, { n: 40, color: [0xc8b4ff, 0xffffff, 0x9b7bff], spd: 3, life: 0.6, size: 0.2, drag: 2, swirl: 8 }); SFX.energy(); }
  if (C.focus) { S.focus = true; SFX.focus();
    for (let k = 0; k < 3; k++) gsap.delayedCall(k * 0.08, () => { const p = PPOS(); emit(p.x, p.y, { n: 22, color: [0xffcf6b, 0xfff1b0], spd: 2.4, dir: [0, -1], cone: 0.2, life: 0.8, size: 0.2, r: 0.5, tex: 'star', spin: 5 }); }); }
  if (C.shield) addShield(C.shield);
  if (C.heal) healActive(C.heal);
  if (C.regen) S.regen = { t: C.regen, acc: 0, amt: 2 };
  if (C.dmg) {
    const el = C.el || me.el; let mult = me.atk * (C.el && C.el === me.el ? 1.25 : 1);  // same-element bonus
    if (S.focus) { mult *= 2; S.focus = false; }
    const hits = C.hits || 1, big = C.cost >= 3; lunge(pm, 0.35);
    if (hits > 1) {
      for (let k = 0; k < hits; k++) gsap.delayedCall(0.08 + k * 0.11, () => {
        if (!S.enemy || !S.enemy.alive || !S.em) return;
        lightning((activeActor() || pm).head(), S.em.head(), el); hurtEnemy(C.dmg! * mult, el, { small: true });
        if (C.stun) S.enemy.stun = Math.max(S.enemy.stun, C.stun);
      });
    } else {
      const tok = S.tok;
      projectile(pp, () => S.em!.head(), el, { size: big ? 0.42 : 0.26, arc: big ? 1.6 : 0.7, dur: big ? 0.42 : 0.3 }, () => {
        if (tok !== S.tok || !S.enemy || !S.enemy.alive) return;
        hurtEnemy(C.dmg! * mult, el, { big });
        if (C.burn) { S.enemy.burn = Math.max(S.enemy.burn, C.burn); S.enemy.burnDps = Math.max(S.enemy.burnDps, 3 * me.atk); }
      });
    }
  }
}

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
function hurtEnemy(amount: number, el: El, o: { dot?: boolean; big?: boolean; small?: boolean } = {}) {
  const e = S.enemy, m = S.em; if (!e || !e.alive || !m) return 0;
  const a = adv(el, e.el), dmg = Math.max(1, Math.round(amount * a)); e.hp = Math.max(0, e.hp - dmg); S.stats.dealt += dmg;
  const hp = m.head();
  popNum({ x: hp.x, y: hp.y - U * 0.7 }, dmg, a > 1 ? 'crit' : a < 1 ? 'weak' : o.dot ? 'dot' : '', a > 1 && !o.dot ? 'Super' : a < 1 && !o.dot ? 'Resisted' : '');
  if (o.dot) emit(hp.x, hp.y, { n: 10, color: ELEM.ember.glow, spd: 1.5, up: 1, life: 0.7, size: 0.22, grav: -2 });
  else {
    burst(hp, el, o.big ? 1.6 : o.small ? 0.55 : 1); m.hitFlash(); lightFlash(ELEM[el].hex, hp, o.big ? 7 : 4);
    gsap.fromTo(m.off, { x: 0.22, y: -0.12 }, { x: 0, y: 0, duration: 0.35, ease: 'power2.out' });
    if (a > 1 || o.big) { hitStop(o.big ? 0.12 : 0.07); shake(o.big ? 0.6 : 0.4); flash(o.big ? 0.35 : 0.2); SFX.crit(); haptic('medium'); }
    else { shake(o.small ? 0.12 : 0.22); SFX.hit(el); haptic('light'); }
  }
  if (e.hp <= 0) enemyDown();
  return dmg;
}
function hurtPlayer(amount: number, el: El, heavy: boolean) {
  const me = act(), pm = activeActor(); if (!me || !me.alive || !pm) return;
  const a = adv(el, me.el); let dmg = Math.max(1, Math.round(amount * a)); const hp = pm.head();
  let absorbed = 0; if (me.shield > 0) { absorbed = Math.min(me.shield, dmg); me.shield -= absorbed; dmg -= absorbed; }
  if (absorbed) { popNum({ x: hp.x - U * 0.4, y: hp.y - U * 0.5 }, absorbed, 'shield', 'Blocked'); emit(hp.x, hp.y, { n: 30, color: [0x8fe3ff, 0xffffff], spd: 4, life: 0.4, size: 0.16, drag: 4, tex: 'spark', streak: true }); SFX.shield(); gsap.fromTo(shieldPulse, { s: 1.25 }, { s: 1, duration: 0.3 }); }
  if (dmg > 0) {
    me.hp = Math.max(0, me.hp - dmg);
    popNum({ x: hp.x, y: hp.y - U * 0.7 }, dmg, 'player' + (a > 1 ? ' crit' : ''), a > 1 ? 'Super' : a < 1 ? 'Resisted' : '');
    pm.hitFlash(); vignette(); SFX.ouch(); shake(heavy ? 0.6 : 0.35); haptic(heavy ? 'heavy' : 'medium'); if (heavy) hitStop(0.1);
    gsap.fromTo(pm.off, { x: -0.22, y: 0.1 }, { x: 0, y: 0, duration: 0.35, ease: 'power2.out' });
  }
  burst(hp, el, heavy ? 1.3 : 0.8); lightFlash(ELEM[el].hex, hp, 4);
  if (me.hp <= 0) playerDown();
}
function addShield(v: number) {
  const me = act(); me.shield += v; const hp = activeActor()!.head();
  popNum({ x: hp.x, y: hp.y - U * 0.8 }, '+' + v, 'shield', 'Shield');
  emit(hp.x, hp.y, { n: 40, color: [0x8fe3ff, 0xffffff, 0x3fb6ff], spd: 2.2, life: 0.7, size: 0.18, drag: 2.5, swirl: 9, r: 0.5 });
  gsap.fromTo(shieldPulse, { s: 0.3 }, { s: 1, duration: 0.4, ease: 'back.out(2)' }); SFX.shield();
}
function healActive(v: number) {
  const me = act(); me.hp = Math.min(me.maxHp, me.hp + v); const hp = activeActor()!.head(), p = PPOS();
  popNum({ x: hp.x + U * 0.3, y: hp.y - U * 0.8 }, '+' + Math.round(v), 'heal');
  emit(p.x, p.y, { n: 45, color: [0x6ff0a0, 0xc8ffd9, 0xffffff], spd: 2.2, dir: [0, -1], cone: 0.25, life: 1, size: 0.22, drag: 1, r: 0.5, swirl: 4 });
  emit(p.x, p.y - U, { n: 6, color: [0x6ff0a0], spd: 1.2, dir: [0, -1], cone: 0.4, life: 1, size: 0.4, tex: 'star', spin: 3 });
  ring(p.x, p.y, 0x6ff0a0, 1.6); SFX.heal();
}

/* ================= turns ================= */
function autoAttack() {
  const me = act(), pm = activeActor(); if (!me || !me.alive || !pm || !S.enemy || !S.enemy.alive) return;
  const tok = S.tok; lunge(pm, 0.22);
  projectile(pm.head(), () => S.em!.head(), me.el, { size: 0.16, arc: 0.35, dur: 0.26 }, () => { if (tok === S.tok) hurtEnemy(3 * me.atk, me.el, { small: true }); });
}
function enemyAttack() {
  const e = S.enemy!, m = S.em!; e.count++; const heavy = e.count % 3 === 0;
  const dmg = e.dmg * (heavy ? 1.7 : 1) * (e.enraged ? 1.15 : 1), tok = S.tok;
  if (e.boss && heavy) {  // charged volley
    gsap.fromTo(m.sq.scale, { y: 1 }, { y: 1.25, duration: 0.25, yoyo: true, repeat: 1 });
    for (let k = 0; k < 3; k++) gsap.delayedCall(0.2 + k * 0.12, () => {
      if (tok !== S.tok || !e.alive || !activeActor()) return;
      projectile(m.head(), () => activeActor()!.head(), e.el, { size: 0.4, arc: 0.9, dur: 0.3 }, () => { if (tok === S.tok && e.alive) hurtPlayer(dmg / 3, e.el, k === 2); });
    });
    return;
  }
  const P = PPOS(), E = EPOS(), tx = (P.x - E.x) / U * 0.62, ty = (P.y - E.y) / U * 0.62;
  if (heavy) emit(E.x, E.y, { n: 40, color: ELEM[e.el].glow, spd: 3, dir: [0, -1], cone: 0.5, life: 0.5, size: 0.25, r: 0.5 });
  gsap.timeline()
    .to(m.off, { x: -tx * 0.1, y: -ty * 0.1 - (heavy ? 0.4 : 0.15), duration: heavy ? 0.22 : 0.1, ease: 'power1.out' })
    .to(m.off, { x: tx, y: ty, duration: 0.12, ease: 'power3.in', onComplete: () => { if (tok === S.tok && e.alive) hurtPlayer(dmg, e.el, heavy); } })
    .to(m.off, { x: 0, y: 0, duration: 0.32, ease: 'power2.out' });
}
function shiftBoss() {
  const e = S.enemy!, m = S.em!; e.el = pick(EL_KEYS.filter(k => k !== e.el)); m.setElement(e.el); tintArena(ELEM[e.el].hex);
  const E = EPOS(); burst(m.head(), e.el, 1.4); ring(E.x, E.y, ELEM[e.el].hex, 3.2, 0.7); flash(0.25, elHexCss(e.el));
  SFX.swap(); haptic('medium'); renderEnemyPlate(); refreshHand(); toast('Noctyrm shifts to ' + ELEM[e.el].name);
}

/* ================= swapping & fainting ================= */
export function swapTo(i: number, forced = false) {
  audio(); if (!(S.mode === 'battle' || (forced && S.mode !== 'over'))) return;
  const c = S.party[i]; if (!c || !c.alive || i === S.active) return;
  if (!forced && (S.swapCd > 0 || S.swapping)) { SFX.deny(); haptic('warning'); return; }
  S.swapping = true; S.swapCd = SWAP_COOLDOWN; const old = activeActor()!, tok = S.tok; SFX.swap(); haptic('light');
  const p = PPOS(); emit(p.x, p.y, { n: 70, color: ELEM[act().el].glow, spd: 4, dir: [0, -1], cone: 0.12, life: 0.6, size: 0.22, r: 0.35, tex: 'spark', streak: true });
  gsap.to(old.sq.scale, { x: 0.01, y: 1.7, duration: 0.18, ease: 'power2.in', onComplete: () => {
    if (tok !== S.tok) return; old.visible = false; old.sq.scale.set(1);
    S.active = i; act().shield = 0; placePlayer(true); renderPlayerPlate(); renderBench(); refreshHand();
    S.autoT = 0; gsap.delayedCall(0.25, () => { S.swapping = false; });
  } });
}
function playerDown() {
  const me = act(); me.alive = false; me.shield = 0; const pm = activeActor()!, tok = S.tok;
  SFX.ko(); haptic('error'); shake(0.5); hitStop(0.12);
  gsap.to(pm.flip, { rotation: -1.2, duration: 0.4, ease: 'power2.in' });
  gsap.to(pm.sq.scale, { x: 0.01, y: 0.01, duration: 0.5, delay: 0.35, ease: 'power2.in', onComplete: () => {
    const p = PPOS(); emit(p.x, p.y - U * 0.4, { n: 60, color: [0x9aa3c7, 0x5a6088, 0xffffff], spd: 2, up: 1, life: 1, size: 0.25, grav: -1, drag: 1.5 });
  } });
  renderBench();
  const next = S.party.findIndex(c => c.alive);
  if (next >= 0) { banner(me.name + ' fainted', 'Next partner in', '#ff5a6e'); gsap.delayedCall(0.9, () => { if (tok === S.tok) { S.swapping = false; S.swapCd = 0; swapTo(next, true); } }); }
  else { S.mode = 'over'; gsap.delayedCall(1.2, () => endRun(false)); }
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
  banner(e.boss ? 'Noctyrm falls' : 'Victory', e.boss ? 'The expedition is complete' : '+1 level for the party', '#ffcf6b'); SFX.win();
  gsap.delayedCall(1.4, () => { if (tok === S.tok) { haptic('success'); afterWin(null); } });
}

/* ================= capture ================= */
export function tryCapture() {
  audio(); const e = S.enemy, m = S.em;
  if (S.mode !== 'battle' || !e || !m || !e.alive || e.boss || e.hp / e.max > CAP_TH) return;
  if (S.energy < CAPTURE_COST) { SFX.deny(); haptic('warning'); return; }
  S.energy -= CAPTURE_COST; S.mode = 'anim'; SFX.throw(); haptic('medium'); const tok = S.tok;
  const orb = new Container(), og = new Graphics(), halo = new Sprite(TEX.glow);
  halo.anchor.set(0.5); halo.blendMode = 'add'; halo.tint = 0x9b7bff; halo.scale.set(2.2);
  og.circle(0, 0, 20).fill(0xf4eeff).stroke({ width: 4, color: 0x14102a });
  og.moveTo(-20, 0).arc(0, 0, 20, Math.PI, 0, true).fill(0x7d5cff);
  og.moveTo(-20, 0).lineTo(20, 0).stroke({ width: 5, color: 0x14102a }); og.circle(0, 0, 7).fill(0xffcf6b).stroke({ width: 3, color: 0x14102a });
  orb.addChild(halo, og); L.glow.addChild(orb); orb.scale.set(U / 46);
  const a = activeActor()!.head(), st = { t: 0 };
  // capture odds: 35% at the threshold, up to 90% near zero HP; alphas are harder
  let chance = 0.35 + (1 - (e.hp / e.max) / CAP_TH) * 0.55; if (e.elite) chance *= 0.8;
  const success = Math.random() < chance;

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
      e!.alive = false; S.mode = 'end'; SFX.caught(); haptic('success'); shake(0.3);
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
      orb.destroy({ children: true }); e!.enraged = true; e!.t = Math.max(e!.t, e!.iv * 0.5);
      gsap.to(m!.sq.scale, { x: 1, y: 1, duration: 0.5, ease: 'back.out(3)' }); banner('Broke free', 'It is enraged', '#ff5a6e');
      gsap.delayedCall(0.4, () => { if (tok === S.tok) S.mode = 'battle'; });
    }
  }
}

/* ================= per-frame simulation ================= */
export function tickBattle(dt: number, t: number) {
  const e = S.enemy, m = S.em;
  if (m) {  // wind-up aura before an attack
    if (e && e.alive && S.mode === 'battle') { const w = e.t / e.iv; m.aura.tint = ELEM[e.el].hex; m.aura.alpha = w > 0.75 ? (w - 0.75) * 3.2 * (0.6 + 0.4 * Math.sin(t * 30)) : 0; }
    else m.aura.alpha = 0;
  }
  if (S.mode !== 'battle') return;
  const me = act();
  S.energy = Math.min(ENERGY_MAX, S.energy + dt * ENERGY_RATE);
  if (S.swapCd > 0) S.swapCd = Math.max(0, S.swapCd - dt);
  if (me && me.alive && !S.swapping) { S.autoT += dt; if (S.autoT >= 2.4 / SPECIES[me.key].spd) { S.autoT = 0; autoAttack(); } }
  if (e && e.alive && m) {
    if (e.stun > 0) e.stun -= dt; else { e.t += dt * (e.enraged ? 1.25 : 1); if (e.t >= e.iv) { e.t = 0; enemyAttack(); } }
    const p = m.head();
    if (e.t / e.iv > 0.75 && e.stun <= 0 && Math.random() < dt * 30) emit(p.x, p.y + U * 0.3, { n: 2, color: ELEM[e.el].glow, spd: 1.2, r: 0.5, life: 0.4, size: 0.18, drag: 2, swirlDir: 6 });
    if (e.stun > 0 && Math.random() < dt * 14) emit(p.x, p.y - U * 0.9, { n: 1, color: [0xffd23f, 0xffffff], spd: 1.5, flat: true, life: 0.5, size: 0.22, swirlDir: 12, tex: 'star', spin: 6 });
    if (e.burn > 0) {
      e.burn -= dt; e.burnAcc += dt;
      if (e.burnAcc >= 0.5) { e.burnAcc = 0; hurtEnemy(e.burnDps * 0.5, 'ember', { dot: true }); }
      if (Math.random() < dt * 20) emit(p.x, p.y, { n: 1, color: ELEM.ember.glow, spd: 0.8, r: 0.4, up: 1, life: 0.6, size: 0.2, grav: -2 });
    }
    if (e.boss && e.alive) { e.shiftT -= dt; if (e.shiftT <= 0) { e.shiftT = 7; shiftBoss(); } }
  }
  if (S.regen.t > 0 && me && me.alive) {
    S.regen.t -= dt; S.regen.acc += dt;
    if (S.regen.acc >= 1) { S.regen.acc = 0; me.hp = Math.min(me.maxHp, me.hp + S.regen.amt); const p = PPOS(); emit(p.x, p.y, { n: 8, color: [0x6ff0a0, 0xffffff], spd: 1.2, dir: [0, -1], cone: 0.3, life: 0.8, size: 0.16, r: 0.4 }); }
  }
}
