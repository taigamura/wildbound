// DOM HUD and card faces. Reads state, never changes game rules.
import { measureBand, PPOS, U } from '../render/layout';
import { world } from '../render/app';
import { S, act, mon, team, cardOf, cardCost, cardBlock, isHeavy, heavyOf, inPerfectWindow, type Mon, type CardRef } from './state';
import { BAL, ELEM, SPECIES, TRAITS, STATUS_NAME, STATUS_EL, adv, resists, cardText, svg, elCss, type CardDef, type El, type GlyphKey } from '../core/data';
import { $, clamp } from '../core/util';
import { isMuted, setMuted, audio } from '../core/audio';

export const slots: HTMLButtonElement[] = [];
let segs: HTMLElement;

export interface HudHandlers { play(i: number): void; swap(uid: number): void }
export function initHud(h: HudHandlers) {
  segs = $('#segs');
  for (let i = 0; i < BAL.energyMax; i++) { const s = document.createElement('div'); s.className = 'seg'; s.innerHTML = '<i></i>'; segs.appendChild(s); }
  const hand = $('#hand');
  for (let i = 0; i < BAL.hand; i++) {
    const b = document.createElement('button'); b.className = 'card empty'; b.setAttribute('aria-label', 'Card ' + (i + 1));
    // pointer events, not click: no tap delay. Tap = inspect, flick up = play (see handDown)
    b.addEventListener('pointerdown', e => handDown(i, e));
    b.addEventListener('pointermove', handMove);
    b.addEventListener('pointerup', e => handUp(e, h));
    b.addEventListener('pointercancel', e => handUp(e, null));
    hand.appendChild(b); slots.push(b);
  }
  handEl = hand;
  // tapping anywhere outside the hand puts the inspected card back
  document.addEventListener('pointerdown', e => {
    if (sel >= 0 && !(e.target as Element | null)?.closest?.('#hand .card')) { sel = -1; layoutHand(); }
  }, true);
  addEventListener('resize', queueLayout);
  $('#bench').addEventListener('pointerdown', (e: PointerEvent) => {
    const b = (e.target as HTMLElement).closest('.bmon') as HTMLElement | null; if (!b) return;
    e.preventDefault(); h.swap(+b.dataset.uid!);
  });
  $('#muteBtn').addEventListener('click', () => { setMuted(!isMuted()); paintMute(); audio(); });
  paintMute();
}
export function paintMute() { $('#muteBtn').innerHTML = svg(isMuted() ? 'mute' : 'sound'); }

const SCREENS = ['#scr-title', '#scr-map', '#scr-reward', '#scr-upgrade', '#scr-party', '#scr-end', '#scr-pack', '#scr-coll', '#scr-shop'];
export function show(id: string | null) {
  SCREENS.forEach(s => { $(s).hidden = s !== id; });
  $('#hud').hidden = id !== null;
  $('#chain').hidden = true; $('#heavy').hidden = true;
  requestAnimationFrame(() => measureBand(false));
}

/* ---------- cards ---------- */
function glyphFor(c: CardDef, el: El): GlyphKey {
  if (c.dmg || c.fromShield) return el;
  if (c.status) return STATUS_EL[c.status];
  if (c.shield || c.shieldTeam || c.reflect) return 'shield';
  if (c.heal || c.healTeam) return 'heart';
  if (c.energy) return 'spark';
  return 'star';
}
export interface FaceOpts { cost?: number; owner?: Mon | null; ownerKey?: string; bench?: boolean; strong?: boolean; upgraded?: string; pow?: number }
/** Card face markup. Used in the hand, the reward/upgrade screens and the collection. */
export function cardFace(c: CardDef, el: El, o: FaceOpts = {}) {
  const key = o.owner?.key ?? o.ownerKey, ini = key ? SPECIES[key].name[0] : '';
  const g = glyphFor(c, el);
  return `<span class="cost">${o.cost ?? c.cost}</span>
    ${ini ? `<span class="own" style="--c:${elCss(el)}">${ini}</span>` : ''}
    ${o.bench ? `<span class="swp">${svg('swap')}</span>` : ''}
    ${o.strong ? '<span class="badge">STRONG</span>' : ''}
    ${o.upgraded ? `<span class="upg">${o.upgraded}</span>` : ''}
    <span class="gl">${svg(g)}</span><span class="nm">${c.name}</span><span class="tx">${cardText(c, o.pow ?? 1)}</span>`;
}
export function paintCard(btn: HTMLElement, r: CardRef | null) {
  if (slots.includes(btn as HTMLButtonElement)) queueLayout();   // re-fan after the slot changes
  if (!r || !mon(r.uid)) { btn.className = 'card empty'; btn.innerHTML = ''; delete btn.dataset.k; return; }
  const { def, pow, owner } = cardOf(r), e = S.enemy, bench = r.uid !== S.active;
  const strong = !!(e && (def.dmg || def.fromShield) && adv(owner.el, e.el) > 1);
  const up = owner.ups[r.slot];
  const k = [r.uid, r.slot, def.cost, cardCost(r), bench, strong, up].join('|');
  btn.classList.remove('empty'); btn.classList.add('card'); btn.classList.toggle('benchcard', bench);
  if (btn.dataset.k === k) return;
  btn.dataset.k = k;
  btn.style.setProperty('--c', elCss(owner.el));
  btn.innerHTML = cardFace(def, owner.el, { cost: cardCost(r), owner, bench, strong, pow, upgraded: up === 'power' ? '+30%' : up === 'cost' ? '−1' : '' });
}
export function refreshHand() { slots.forEach((b, i) => { if (!b.classList.contains('play')) paintCard(b, S.hand[i]); }); }

/* ---------- hand: fan, tap to inspect, flick up to play ----------
   Poses go in the individual `translate`/`rotate`/`scale` properties, so the existing
   `transform` keyframes (deal, play, deny) compose on top in the card's own frame.
   Motion here is pure UI (CSS transitions), so it ignores hit-stop and slow-mo. */
const FLICK_DIST = 0.4;   // dragged up more than this × card height → plays on release
const FLICK_VEL = 0.6;    // or released moving up faster than this (px/ms)...
const FLICK_MIN = 0.15;   // ...after at least this × card height of travel
const SLOP = 6;           // px of movement before a press counts as a drag
const FAN_DEG = 8;        // rotation per step from the centre (4 cards → ±4°, ±12°)
const FAN_DROP = 0.06;    // × card width × step² that outer cards sit lower
let handEl: HTMLElement | null = null, sel = -1, selRef: CardRef | null = null, laidQ = false;
interface Pose { x: number; y: number; r: number; s: number; z: number }
interface Drag { b: HTMLButtonElement; i: number; id: number; x0: number; y0: number; moved: boolean; wasSel: boolean; base: Pose; trail: { y: number; t: number }[] }
let drag: Drag | null = null;

function setPose(b: HTMLElement, p: Pose) {
  b.style.translate = `${p.x.toFixed(1)}px ${p.y.toFixed(1)}px`; b.style.rotate = p.r.toFixed(2) + 'deg';
  b.style.scale = String(p.s); b.style.zIndex = String(p.z);
}
/** Fan the slots that hold a card; the inspected one lifts, straightens and grows. */
function poses(): (Pose | null)[] {
  const W = handEl!.clientWidth, cw = slots[0].offsetWidth, ch = slots[0].offsetHeight;
  const live = slots.map((b, i) => b.classList.contains('empty') ? -1 : i).filter(i => i >= 0);
  const n = live.length, si = live.indexOf(sel);
  const step = n > 1 ? Math.min(cw * 0.78, (W - cw * 1.3) / (n - 1)) : 0;
  const out: (Pose | null)[] = slots.map(() => null);
  live.forEach((i, k) => {
    const t = k - (n - 1) / 2;
    const nudge = si >= 0 && k !== si ? (k < si ? -1 : 1) * cw * 0.14 : 0;   // neighbours make room
    out[i] = { x: t * step + nudge, y: cw * FAN_DROP * t * t, r: t * FAN_DEG, s: 1, z: k + 1 };
  });
  if (si >= 0) {
    const p = out[sel]!, s = 1.16, lim = Math.max(0, (W - cw * s) / 2);
    Object.assign(p, { x: clamp(p.x, -lim, lim), y: -ch * 0.3, r: 0, s, z: 20 });
  }
  return out;
}
function layoutHand() {
  laidQ = false; if (!handEl || !handEl.clientWidth || !slots.length) return;
  if (sel >= 0) { const b = slots[sel]; if (b.classList.contains('empty') || b.classList.contains('play') || S.hand[sel] !== selRef) sel = -1; }
  const ps = poses();
  slots.forEach((b, i) => {
    b.classList.toggle('lift', i === sel);
    const p = ps[i]; if (!p || b.classList.contains('play') || b === drag?.b) return;
    if (b.dataset.flown) {   // flicked off the top: the new card deals in from its fan spot, not from up there
      delete b.dataset.flown; b.style.transition = 'none'; setPose(b, p); void b.offsetWidth; b.style.transition = '';
    } else setPose(b, p);
  });
}
function queueLayout() { if (!laidQ) { laidQ = true; queueMicrotask(layoutHand); } }

function handDown(i: number, e: PointerEvent) {
  e.preventDefault(); const b = slots[i];
  if (drag || b.classList.contains('empty') || b.classList.contains('play')) return;
  audio();
  const wasSel = sel === i;
  if (!wasSel) { sel = i; selRef = S.hand[i]; layoutHand(); }   // inspect on touch, instantly
  try { b.setPointerCapture(e.pointerId); } catch { /* pointer already gone */ }
  drag = { b, i, id: e.pointerId, x0: e.clientX, y0: e.clientY, moved: false, wasSel, base: poses()[i]!, trail: [{ y: e.clientY, t: e.timeStamp }] };
}
/** Upward travel and release speed decide the play. */
function flicked(d: Drag, e: PointerEvent) {
  const ch = d.b.offsetHeight, up = d.y0 - e.clientY, t0 = d.trail[0];
  const vel = (t0.y - e.clientY) / Math.max(1, e.timeStamp - t0.t);
  return up > ch * FLICK_DIST || (up > ch * FLICK_MIN && vel > FLICK_VEL);
}
function handMove(e: PointerEvent) {
  const d = drag; if (!d || e.pointerId !== d.id) return;
  const dx = e.clientX - d.x0, dy = e.clientY - d.y0;
  if (!d.moved) { if (Math.hypot(dx, dy) < SLOP) return; d.moved = true; d.b.classList.add('drag'); }
  d.trail.push({ y: e.clientY, t: e.timeStamp });
  while (d.trail.length > 2 && e.timeStamp - d.trail[0].t > 90) d.trail.shift();
  const p = d.base;   // mostly vertical; sideways moves only tilt it, downward is rubber-banded
  setPose(d.b, { x: p.x + dx * 0.3, y: p.y + (dy < 0 ? dy : dy * 0.25), r: clamp(dx * 0.08, -9, 9), s: p.s, z: 30 });
  d.b.classList.toggle('armed', flicked(d, e));
}
function handUp(e: PointerEvent, h: HudHandlers | null) {
  const d = drag; if (!d || e.pointerId !== d.id) return;
  drag = null; d.b.classList.remove('armed');
  if (!d.moved) { d.b.classList.remove('drag'); if (d.wasSel && h) sel = -1; layoutHand(); return; }   // tap
  if (h && flicked(d, e)) {
    h.play(d.i);   // playCard adds .play on success, .deny (shake) on refusal
    if (d.b.classList.contains('play')) { d.b.dataset.flown = '1'; d.b.classList.remove('drag'); return; }   // flies on from here
  }
  d.b.classList.remove('drag'); layoutHand();   // snap back to the inspected pose
}

/* ---------- plates ---------- */
const chip = (id: string, el: El) => `<span class="elchip" id="${id}" style="--c:${elCss(el)}">${svg(el)}${ELEM[el].name}</span>`;
export function renderPlayerPlate() {
  const c = act(); if (!c) return;
  $('#pEl').outerHTML = chip('pEl', c.el); $('#pName').textContent = c.name;
  $('#pLv').innerHTML = (SPECIES[c.key].role ?? '') + (c.trait ? ` · <span class="tr">${TRAITS[c.trait].name}</span>` : '');
}
export function renderEnemyPlate() {
  const e = S.enemy; if (!e) return;
  $('#eEl').outerHTML = chip('eEl', e.el); $('#eName').textContent = e.name;
  $('#eLv').textContent = e.kind === 'boss' ? 'Boss' : e.kind === 'warden' ? 'Warden' : e.kind === 'alpha' ? 'Alpha' : 'Wild';
  $('#floorT').textContent = S.floor;
}
export function renderBench() {
  const b = $('#bench'); b.innerHTML = '';
  team().forEach(c => {
    if (c.uid === S.active) return;
    const btn = document.createElement('button'); btn.className = 'bmon' + (c.alive ? '' : ' down'); btn.style.setProperty('--c', elCss(c.el));
    btn.innerHTML = `<span class="orb">${svg(c.el)}</span><span class="t"><span>${c.name}</span><span class="mini"><i style="width:${c.hp / c.maxHp * 100}%"></i></span></span><span class="adv"></span><span class="cd"></span>`;
    btn.setAttribute('aria-label', 'Swap to ' + c.name); btn.dataset.uid = String(c.uid); b.appendChild(btn);
  });
}
export const monChip = (c: Mon, extra = '') =>
  `<div class="bmon${c.alive ? '' : ' down'}" style="--c:${elCss(c.el)}"><span class="orb">${svg(c.el)}</span><span class="t"><span>${c.name}${extra}</span><span class="mini"><i style="width:${c.hp / c.maxHp * 100}%"></i></span></span></div>`;
export const partyHTML = (list: Mon[] = team()) => list.map(c => monChip(c, c.uid === S.lineup[0] ? ' ★' : '')).join('');

/* ---------- per-frame sync ---------- */
let lastStat = '';
const tag = (txt: string, c: string) => `<span class="tag" style="--c:${c}">${txt}</span>`;
/** Put a DOM element over a point in the Pixi world. */
function pin(el: HTMLElement, x: number, y: number) { el.style.transform = `translate(${Math.round(x + world.x)}px, ${Math.round(y + world.y)}px)`; }

export function syncHUD() {
  const e = S.enemy, me = act(); if (!e || !me) return;
  const battle = S.mode === 'battle';
  const ep = e.hp / e.max * 100; $('#eHp').style.width = ep + '%'; $('#eGhost').style.width = ep + '%';
  $('#eHpT').textContent = Math.ceil(e.hp) + ' / ' + e.max;
  const w = e.t / e.windup, heavy = isHeavy(e), hv = heavyOf(e);
  $('#eInt').style.width = clamp(w, 0, 1) * 100 + '%';
  const ib = $('#eIntBar'); ib.classList.toggle('hot', w > 0.75); ib.classList.toggle('heavy', heavy); ib.classList.toggle('perfect', battle && e.alive && inPerfectWindow(e));
  ib.style.setProperty('--c', elCss(heavy ? hv.el : e.el));
  // heavy telegraph over the enemy
  const hvEl = $('#heavy') as HTMLElement, showHv = battle && e.alive && heavy;
  if (hvEl.hidden === showHv) hvEl.hidden = !showHv;
  if (showHv && S.em) {
    const k = hv.name + hv.el; if (hvEl.dataset.k !== k) { hvEl.dataset.k = k; hvEl.style.setProperty('--c', elCss(hv.el)); hvEl.innerHTML = `${svg(hv.el)}<b>${hv.name}</b>`; }
    const h = S.em.head(); pin(hvEl, h.x - U * 2.3, h.y - U * 0.2); hvEl.classList.toggle('now', inPerfectWindow(e));
  }

  const pp = me.hp / me.maxHp * 100; $('#pHp').style.width = pp + '%'; $('#pGhost').style.width = pp + '%';
  $('#pSh').style.width = clamp(me.shield / me.maxHp * 100, 0, 100) + '%';
  $('#pHpT').textContent = Math.ceil(me.hp) + ' / ' + me.maxHp + (me.shield >= 1 ? `  +${Math.floor(me.shield)}` : '');

  const en = S.energy;
  segs.childNodes.forEach((s: any, i) => { const f = clamp(en - i, 0, 1); s.firstChild.style.width = (f * 100) + '%'; s.classList.toggle('full', f >= 1); });
  $('#enT').innerHTML = Math.floor(en) + `<small>/${BAL.energyMax}</small>`;
  slots.forEach((b, i) => { const r = S.hand[i]; if (!r) return;
    const why = cardBlock(r); b.classList.toggle('poor', why === 'energy' || why === 'busy'); b.classList.toggle('swapcd', why === 'swap'); });

  let es = '', ps = '';
  if (e.status) es += tag(`${STATUS_NAME[e.status.k]} ${e.status.t.toFixed(0)}s`, elCss(STATUS_EL[e.status.k]));
  if (e.shockCd > 0) es += tag(`Shock immune ${Math.ceil(e.shockCd)}s`, 'var(--mute)');
  if (e.kind === 'boss') es += tag(`Shifts in ${Math.ceil(e.shiftT)}s`, 'var(--gold)');
  if (!heavy && (e.count + 2) % BAL.heavyEvery === 0) es += tag('Heavy next', 'var(--foe)');
  if (me.status) ps += tag(`${STATUS_NAME[me.status.k]} ${me.status.t.toFixed(0)}s`, elCss(STATUS_EL[me.status.k]));
  if (S.discount) ps += tag('Next card −1', 'var(--gold)');
  if (me.reflect) ps += tag(`Reflect ${Math.round(me.reflect * 100)}%`, 'var(--shield)');
  if (me.nextStrike > 1) ps += tag(`Strike ×${me.nextStrike}`, 'var(--gold)');
  const a = adv(me.el, e.el);
  if (a > 1) ps += tag(`Strong vs ${ELEM[e.el].name}`, 'var(--gold)');
  else if (a < 1) ps += tag(`Weak vs ${ELEM[e.el].name}`, '#b8bdd6');
  const st = es + '|' + ps; if (st !== lastStat) { lastStat = st; $('#eStat').innerHTML = es; $('#pStat').innerHTML = ps; }

  document.querySelectorAll<HTMLElement>('#bench .bmon').forEach(b => {
    const c = mon(+b.dataset.uid!); if (!c) return;
    (b.querySelector('.cd') as HTMLElement).style.setProperty('--p', (S.swapCd > 0 ? S.swapCd / BAL.swapCd * 100 : 0) + '%');
    (b.querySelector('.mini i') as HTMLElement).style.width = (c.hp / c.maxHp * 100) + '%';
    b.classList.toggle('down', !c.alive);
    const guard = c.alive && heavy && resists(c.el, hv.el);
    b.classList.toggle('guard', guard && battle);
    b.querySelector('.adv')!.innerHTML = guard ? svg('shield') : c.alive && adv(c.el, e.el) > 1 ? '▲' : '';
  });

  // chain counter beside the lead
  const ch = $('#chain') as HTMLElement, showCh = battle && S.chain > 0;
  if (ch.hidden === showCh) ch.hidden = !showCh;
  if (showCh) {
    const k = String(S.chain); if (ch.dataset.k !== k) { ch.dataset.k = k; ch.innerHTML = `×${S.chain + 1}<small>+${Math.round(S.chain * BAL.chainStep * 100)}%</small>`; ch.classList.remove('bump'); void ch.offsetWidth; ch.classList.add('bump'); }
    const p = PPOS(); pin(ch, p.x + U * 1.2, p.y - U * 1.9); ch.classList.toggle('expiring', S.chainT > BAL.chainWin - 0.5);
  }
}
