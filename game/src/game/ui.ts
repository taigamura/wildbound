// DOM HUD and screens. Reads state, never changes game rules.
import { measureBand } from '../render/layout';
import { S, act } from './state';
import { CARDS, ELEM, CAP_TH, CAPTURE_COST, ENERGY_MAX, HAND, SWAP_COOLDOWN, adv, svg, elCss, type CardId, type CardDef, type El } from '../core/data';
import { $, clamp } from '../core/util';
import { isMuted, setMuted, audio } from '../core/audio';
import type { Enemy, Mon } from './state';

export const slots: HTMLButtonElement[] = [];
let segs: HTMLElement;

export function initHud(onPlay: (i: number) => void, onSwap: (i: number) => void, onCapture: () => void) {
  segs = $('#segs');
  for (let i = 0; i < ENERGY_MAX; i++) { const s = document.createElement('div'); s.className = 'seg'; s.innerHTML = '<i></i>'; segs.appendChild(s); }
  const hand = $('#hand');
  for (let i = 0; i < HAND; i++) {
    const b = document.createElement('button'); b.className = 'card empty'; b.setAttribute('aria-label', 'Card ' + (i + 1));
    // pointerdown, not click: no tap delay, cards feel instant
    b.addEventListener('pointerdown', e => { e.preventDefault(); onPlay(i); });
    hand.appendChild(b); slots.push(b);
  }
  $('#bench').addEventListener('pointerdown', (e: PointerEvent) => {
    const b = (e.target as HTMLElement).closest('.bmon') as HTMLElement | null; if (!b) return;
    e.preventDefault(); onSwap(+b.dataset.i!);
  });
  $('#capBtn').addEventListener('pointerdown', (e: PointerEvent) => { e.preventDefault(); onCapture(); });
  $('#muteBtn').addEventListener('click', () => { setMuted(!isMuted()); paintMute(); audio(); });
  paintMute();
}
export function paintMute() { $('#muteBtn').innerHTML = svg(isMuted() ? 'mute' : 'sound'); }

export function show(id: string | null) {
  ['#scr-title', '#scr-map', '#scr-reward', '#scr-catch', '#scr-end'].forEach(s => { $(s).hidden = s !== id; });
  $('#hud').hidden = id !== null;
  requestAnimationFrame(() => measureBand(false));
}

/* ---------- cards ---------- */
export function cardEffEl(C: CardDef): El | null { const me = act(); return C.el || (C.dmg && me ? me.el : null); }
function cardColor(C: CardDef) {
  if (C.el) return elCss(C.el);
  return C.g === 'heart' ? 'var(--hp)' : C.g === 'shield' ? 'var(--shield)' : C.g === 'star' || C.g === 'spark' ? 'var(--gold)' : 'var(--neutral)';
}
export function cardHTML(id: CardId, enemy: Enemy | null) {
  const C = CARDS[id], g = C.g || C.el!, eff = cardEffEl(C);
  const strong = enemy && C.dmg && eff && adv(eff, enemy.el) > 1;
  return `<span class="cost">${C.cost}</span>${C.rare ? '<span class="rare"></span>' : ''}${strong ? '<span class="badge">STRONG</span>' : ''}
    <span class="gl">${svg(g, g === 'claw' ? 'stroke' : '')}</span><span class="nm">${C.name}</span><span class="tx">${C.txt}</span>`;
}
export function paintCard(btn: HTMLElement, id: CardId | null, enemy: Enemy | null) {
  if (!id) { btn.className = 'card empty'; btn.innerHTML = ''; return; }
  btn.classList.remove('empty'); btn.classList.add('card');
  btn.style.setProperty('--c', cardColor(CARDS[id]));
  btn.innerHTML = cardHTML(id, enemy); btn.dataset.id = id;
}
export function refreshHand() { slots.forEach((b, i) => { if (!b.classList.contains('play')) paintCard(b, S.hand[i], S.enemy); }); }

/* ---------- plates ---------- */
const chip = (id: string, el: El) => `<span class="elchip" id="${id}" style="--c:${elCss(el)}">${svg(el)}${ELEM[el].name}</span>`;
export function renderPlayerPlate() {
  const c = act(); if (!c) return;
  $('#pEl').outerHTML = chip('pEl', c.el); $('#pName').textContent = c.name; $('#pLv').textContent = 'Lv ' + c.lvl;
}
export function renderEnemyPlate() {
  const e = S.enemy; if (!e) return;
  $('#eEl').outerHTML = chip('eEl', e.el); $('#eName').textContent = e.name;
  $('#eLv').textContent = e.boss ? 'Boss' : (e.elite ? 'Alpha · ' : '') + 'Lv ' + e.lvl;
}
export function renderBench() {
  const b = $('#bench'); b.innerHTML = '';
  S.party.forEach((c, i) => {
    if (i === S.active) return;
    const btn = document.createElement('button'); btn.className = 'bmon' + (c.alive ? '' : ' down'); btn.style.setProperty('--c', elCss(c.el));
    btn.innerHTML = `<span class="orb">${svg(c.el)}</span><span class="t"><span>${c.name}</span><span class="mini"><i style="width:${c.hp / c.maxHp * 100}%"></i></span></span><span class="adv"></span><span class="cd"></span>`;
    btn.setAttribute('aria-label', 'Swap to ' + c.name); btn.dataset.i = String(i); b.appendChild(btn);
  });
}
export const partyHTML = () => S.party.map((c: Mon) =>
  `<div class="bmon${c.alive ? '' : ' down'}" style="--c:${elCss(c.el)}"><span class="orb">${svg(c.el)}</span><span class="t"><span>${c.name} · ${c.lvl}</span><span class="mini"><i style="width:${c.hp / c.maxHp * 100}%"></i></span></span></div>`).join('');
export function deckHTML() {
  const counts: Record<string, number> = {}; S.deck.forEach(id => counts[id] = (counts[id] || 0) + 1);
  return Object.entries(counts).map(([id, n]) => { const C = CARDS[id as CardId];
    return `<span class="dchip" style="--c:${C.el ? elCss(C.el) : 'var(--neutral)'}">${C.name}${n > 1 ? ' ×' + n : ''}</span>`; }).join('');
}

/* ---------- per-frame sync ---------- */
let lastStat = '';
export function syncHUD() {
  const e = S.enemy, me = act(); if (!e || !me) return;
  const ep = e.hp / e.max * 100; $('#eHp').style.width = ep + '%'; $('#eGhost').style.width = ep + '%';
  $('#eHpT').textContent = Math.ceil(e.hp) + ' / ' + e.max;
  $('#eInt').style.width = (e.t / e.iv) * 100 + '%';
  $('#eIntBar').classList.toggle('hot', e.t / e.iv > 0.75 && e.stun <= 0);
  const pp = me.hp / me.maxHp * 100; $('#pHp').style.width = pp + '%'; $('#pGhost').style.width = pp + '%';
  $('#pSh').style.width = clamp(me.shield / me.maxHp * 100, 0, 100) + '%';
  $('#pHpT').textContent = Math.ceil(me.hp) + ' / ' + me.maxHp + (me.shield > 0 ? `  +${Math.ceil(me.shield)}` : '');
  const en = S.energy;
  segs.childNodes.forEach((s: any, i) => { const f = clamp(en - i, 0, 1); s.firstChild.style.width = (f * 100) + '%'; s.classList.toggle('full', f >= 1); });
  $('#enT').innerHTML = Math.floor(en) + `<small>/${ENERGY_MAX}</small>`;
  slots.forEach((b, i) => { const id = S.hand[i]; if (!id) return;
    b.classList.toggle('poor', !(S.energy >= CARDS[id].cost && S.mode === 'battle' && me.alive && !S.swapping)); });
  const capOk = S.mode === 'battle' && !e.boss && e.alive && e.hp / e.max <= CAP_TH;
  const cb = $('#capBtn'); if (cb.hidden === capOk) cb.hidden = !capOk; cb.disabled = S.energy < CAPTURE_COST;
  let es = '', ps = '';
  if (e.burn > 0) es += `<span class="tag" style="--c:var(--ember)">Burn ${e.burn.toFixed(0)}s</span>`;
  if (e.stun > 0) es += `<span class="tag" style="--c:var(--volt)">Stunned</span>`;
  if (e.enraged) es += `<span class="tag" style="--c:var(--foe)">Enraged</span>`;
  if (e.boss) es += `<span class="tag" style="--c:var(--gold)">Shifts in ${Math.ceil(e.shiftT)}s</span>`;
  if ((e.count + 1) % 3 === 0) es += `<span class="tag" style="--c:var(--foe)">Heavy hit next</span>`;
  if (S.focus) ps += `<span class="tag" style="--c:var(--gold)">Focus ×2</span>`;
  if (S.regen.t > 0) ps += `<span class="tag" style="--c:var(--hp)">Regen ${S.regen.t.toFixed(0)}s</span>`;
  const a = adv(me.el, e.el);
  if (a > 1) ps += `<span class="tag" style="--c:var(--gold)">Strong vs ${ELEM[e.el].name}</span>`;
  else if (a < 1) ps += `<span class="tag" style="--c:#b8bdd6">Weak vs ${ELEM[e.el].name}</span>`;
  const st = es + '|' + ps; if (st !== lastStat) { lastStat = st; $('#eStat').innerHTML = es; $('#pStat').innerHTML = ps; }
  document.querySelectorAll<HTMLElement>('#bench .bmon').forEach(b => {
    const c = S.party[+b.dataset.i!];
    (b.querySelector('.cd') as HTMLElement).style.setProperty('--p', (S.swapCd > 0 ? S.swapCd / SWAP_COOLDOWN * 100 : 0) + '%');
    (b.querySelector('.mini i') as HTMLElement).style.width = (c.hp / c.maxHp * 100) + '%';
    b.classList.toggle('down', !c.alive);
    b.querySelector('.adv')!.textContent = c.alive && adv(c.el, e.el) > 1 ? '▲' : '';
  });
}
