// DOM HUD and card faces. Reads state, never changes game rules.
import { measureBand, PPOS, U } from '../render/layout';
import { world } from '../render/app';
import { S, act, mon, team, cardOf, cardCost, cardBlock, isHeavy, heavyOf, inPerfectWindow, canCapture, captureOdds, evoCandidate, type Mon, type CardRef } from './state';
import { BAL, ELEM, SPECIES, TRAITS, STATUS_NAME, STATUS_EL, adv, resists, cardText, svg, elCss, type CardDef, type El, type GlyphKey } from '../core/data';
import { $, clamp } from '../core/util';
import { isMuted, setMuted, audio } from '../core/audio';

export const slots: HTMLButtonElement[] = [];
let segs: HTMLElement;

export interface HudHandlers { play(i: number): void; swap(uid: number): void; capture(): void; evolve(): void }
export function initHud(h: HudHandlers) {
  segs = $('#segs');
  for (let i = 0; i < BAL.energyMax; i++) { const s = document.createElement('div'); s.className = 'seg'; s.innerHTML = '<i></i>'; segs.appendChild(s); }
  const hand = $('#hand');
  for (let i = 0; i < BAL.hand; i++) {
    const b = document.createElement('button'); b.className = 'card empty'; b.setAttribute('aria-label', 'Card ' + (i + 1));
    // pointerdown, not click: no tap delay, cards feel instant
    b.addEventListener('pointerdown', e => { e.preventDefault(); h.play(i); });
    hand.appendChild(b); slots.push(b);
  }
  $('#bench').addEventListener('pointerdown', (e: PointerEvent) => {
    const b = (e.target as HTMLElement).closest('.bmon') as HTMLElement | null; if (!b) return;
    e.preventDefault(); h.swap(+b.dataset.uid!);
  });
  $('#capBtn').addEventListener('pointerdown', (e: PointerEvent) => { e.preventDefault(); h.capture(); });
  $('#evoBtn').addEventListener('pointerdown', (e: PointerEvent) => { e.preventDefault(); h.evolve(); });
  $('#muteBtn').addEventListener('click', () => { setMuted(!isMuted()); paintMute(); audio(); });
  paintMute();
}
export function paintMute() { $('#muteBtn').innerHTML = svg(isMuted() ? 'mute' : 'sound'); }

const SCREENS = ['#scr-title', '#scr-map', '#scr-reward', '#scr-upgrade', '#scr-catch', '#scr-party', '#scr-end', '#scr-pack', '#scr-coll'];
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
  if (!r || !mon(r.uid)) { btn.className = 'card empty'; btn.innerHTML = ''; delete btn.dataset.k; return; }
  const { def, pow, owner } = cardOf(r), e = S.enemy, bench = r.uid !== S.active;
  const strong = !!(e && (def.dmg || def.fromShield) && adv(owner.el, e.el) > 1);
  const up = owner.ups[r.slot];
  const k = [r.uid, r.slot, def.cost, cardCost(r), bench, strong, up, owner.evolved].join('|');
  btn.classList.remove('empty'); btn.classList.add('card'); btn.classList.toggle('benchcard', bench);
  if (btn.dataset.k === k) return;
  btn.dataset.k = k;
  btn.style.setProperty('--c', elCss(owner.el));
  btn.innerHTML = cardFace(def, owner.el, { cost: cardCost(r), owner, bench, strong, pow, upgraded: up === 'power' ? '+30%' : up === 'cost' ? '−1' : '' });
}
export function refreshHand() { slots.forEach((b, i) => { if (!b.classList.contains('play')) paintCard(b, S.hand[i]); }); }

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
  const evoBar = $('#pEvo') as HTMLElement, showEvo = me.starter && !me.evolved;
  if (evoBar.hidden === showEvo) evoBar.hidden = !showEvo;
  if (showEvo) { (evoBar.firstElementChild as HTMLElement).style.width = (me.evo / BAL.evoFill * 100) + '%'; evoBar.classList.toggle('full', me.evo >= BAL.evoFill); }

  const en = S.energy;
  segs.childNodes.forEach((s: any, i) => { const f = clamp(en - i, 0, 1); s.firstChild.style.width = (f * 100) + '%'; s.classList.toggle('full', f >= 1); });
  $('#enT').innerHTML = Math.floor(en) + `<small>/${BAL.energyMax}</small>`;
  $('#chargeT').textContent = S.charges;
  slots.forEach((b, i) => { const r = S.hand[i]; if (!r) return;
    const why = cardBlock(r); b.classList.toggle('poor', why === 'energy' || why === 'busy'); b.classList.toggle('swapcd', why === 'swap'); });

  const cb = $('#capBtn') as HTMLButtonElement, capOk = battle && canCapture(e);
  if (cb.hidden === capOk) cb.hidden = !capOk;
  if (capOk) { cb.disabled = S.charges <= 0; $('#capOdds').textContent = S.charges > 0 ? `${Math.round(captureOdds(e) * 100)}% · ${S.charges} left` : 'No charges'; }
  const vb = $('#evoBtn') as HTMLButtonElement, evo = battle ? evoCandidate() : null;
  if (vb.hidden === !!evo) vb.hidden = !evo;
  if (evo) { vb.disabled = S.energy < BAL.evoCost; vb.style.setProperty('--c', elCss(evo.el)); }

  let es = '', ps = '';
  if (e.status) es += tag(`${STATUS_NAME[e.status.k]} ${e.status.t.toFixed(0)}s`, elCss(STATUS_EL[e.status.k]));
  if (e.shockCd > 0) es += tag(`Shock immune ${Math.ceil(e.shockCd)}s`, 'var(--mute)');
  if (e.enraged) es += tag('Enraged', 'var(--foe)');
  if (e.kind === 'boss') es += tag(`Shifts in ${Math.ceil(e.shiftT)}s`, 'var(--gold)');
  if (e.fleeT != null && e.alive) es += tag(`Flees in ${Math.ceil(e.fleeT)}s`, 'var(--foe)');
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
    b.classList.toggle('evo', evo === c);
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
