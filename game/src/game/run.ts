// Run flow outside combat: title, daily pack, collection, map, nodes, rewards, upgrades,
// catching, lineup, end of run. Spec: CLAUDE.md §2, §5–§7, §11.
import gsap from 'gsap';
import { U, PPOS, TPOS, measureBand } from '../render/layout';
import { emit, ring } from '../render/particles';
import { toast } from '../render/fx';
import { Actor } from '../render/actor';
import { buildStage, tintArena, setBiome } from '../render/stage';
import { STYLES, getStyle, useStyle } from '../art/registry';
import { S, act, newMon, actorFor, dropActor, clearActors, cardOf, baseCard, type MapNode, type Mon, type Enemy } from './state';
import { show, cardFace, partyHTML } from './ui';
import { startBattle } from './battle';
import { BAL, ELEM, SPECIES, SLOTS, ROSTER, POOL_A, POOL_B, STARTERS, adv, biomeOf, scalable, svg, elCss, type GlyphKey, type Slot } from '../core/data';
import { $, rand, pick } from '../core/util';
import { SFX, audio } from '../core/audio';
import { haptic } from '../core/platform';
import * as meta from './meta';

const btn = (cls: string, html: string, onClick: () => void, color?: string) => {
  const b = document.createElement('button'); b.className = cls; b.innerHTML = html; if (color) b.style.setProperty('--c', color);
  b.addEventListener('click', () => { audio(); SFX.pick(); haptic('select'); onClick(); }); return b;
};
const nodeBtn = (g: GlyphKey, title: string, sub: string, color: string, onClick: () => void) =>
  btn('node', `<span class="orb">${svg(g)}</span><span><b>${title}</b><span>${sub}</span></span>`, onClick, color);

/* ================= run start ================= */
export function startRun() {
  audio(); haptic('medium');
  clearActors();
  S.tok++; S.uid = 1;
  const c = newMon(S.starter, meta.isShiny(S.starter)); c.starter = true;
  S.party = [c]; S.lineup = [c.uid]; S.active = c.uid; S.floor = 1; S.charges = BAL.startCharges; S.caught = [];
  S.stats = { caught: 0, start: performance.now(), dealt: 0, perfects: 0 };
  meta.saveStarter(S.starter);
  setBiome(0); placePlayer(true); SFX.win(); showMap();
}

/** Show the lead on its pedestal and hide everyone else (except `keep`, which may be animating out). */
export function placePlayer(pop: boolean, keep: Actor | null = null) {
  Object.values(S.actors).forEach(a => { if (a !== keep) a.visible = false; });
  const c = act(); if (!c) return;
  const a = actorFor(c); a.visible = true; a.off.x = 0; a.off.y = 0; a.sq.scale.set(1); a.flip.rotation = 0;
  if (pop) {
    const p = PPOS(); a.sq.scale.set(0.01); gsap.to(a.sq.scale, { x: 1, y: 1, duration: 0.5, ease: 'back.out(2.5)' });
    emit(p.x, p.y, { n: 60, color: ELEM[c.el].glow, spd: 2.5, dir: [0, -1], cone: 0.35, life: 0.9, size: 0.22, drag: 1.5, r: 0.4 });
    ring(p.x, p.y, ELEM[c.el].hex, 1.8);
    if (c.shiny) sparkle(p.x, p.y - U);
  }
}
function sparkle(x: number, y: number) {
  emit(x, y, { n: 24, color: [0xffffff, 0xffe9a8, 0xc8f0ff], spd: 2.6, life: 0.9, size: 0.3, drag: 1.5, tex: 'star', spin: 6 });
}

/* ================= map ================= */
function wildNode(f: number, pool: string[], avoidEl?: string): MapNode {
  let p = pool; if (avoidEl) p = p.filter(k => SPECIES[k].el !== avoidEl);
  const sp = pick(p.length ? p : pool);
  return { type: 'wild', sp, lvl: f + (biomeOf(f) === 1 && POOL_A.includes(sp) ? BAL.biomeBBonus : 0) };
}
function genNodes(f: number): MapNode[] {
  if (f === BAL.floors) return [{ type: 'boss', sp: 'noctyrm', lvl: f }];
  if (f === 4) return [{ type: 'warden', sp: 'warden', lvl: f }];
  if (biomeOf(f) === 0) {
    const a = wildNode(f, POOL_A), out: MapNode[] = [a, wildNode(f, POOL_A, SPECIES[a.sp!].el)];
    if (Math.random() < 0.5) out.push(f === 1 || Math.random() < 0.5 ? { type: 'spring' } : { ...wildNode(f, POOL_A), type: 'alpha' });
    return out;
  }
  const poolB = POOL_B.concat(POOL_A), w = wildNode(f, poolB);
  const out: MapNode[] = [w, { ...wildNode(f, poolB, SPECIES[w.sp!].el), type: 'alpha' }];
  if (Math.random() < 0.6) out.push({ type: 'spring' });
  return out;
}
function nodeView(n: MapNode): { c: string; g: GlyphKey; t: string; s: string } {
  if (n.type === 'wild' || n.type === 'alpha') {
    const sp = SPECIES[n.sp!], el = sp.el, a = adv(act().el, el);
    const parts = [ELEM[el].name, n.type === 'alpha' ? 'tougher · 2 rewards · can’t be caught' : meta.isOwned(n.sp!) ? 'catchable' : 'catchable · NEW'];
    if (a > 1) parts.push('your lead is strong here'); else if (a < 1) parts.push('your lead is weak here');
    return { c: elCss(el), g: n.type === 'alpha' ? 'skull' : 'paw', t: (n.type === 'alpha' ? 'Alpha ' : 'Wild ') + sp.name, s: parts.join(' · ') };
  }
  if (n.type === 'spring') return { c: 'var(--hp)', g: 'moon', t: 'Moon Spring', s: 'Heal the party to full and gain a Capture charge' };
  if (n.type === 'warden') return { c: 'var(--thorn)', g: 'crown', t: 'Gravewood', s: 'Warden · its heavies alternate Thorn and Ember' };
  return { c: 'var(--foe)', g: 'crown', t: 'Noctyrm', s: 'Boss · changes element every 7 seconds' };
}
/** `reroll` = false keeps this floor's nodes (coming back from the lineup screen). */
export function showMap(reroll = true) {
  S.mode = 'map'; S.enemy = null; S.em?.destroy(); S.em = null; tintArena(getStyle().ambience.neutral);
  setBiome(biomeOf(S.floor)); placePlayer(false);
  if (reroll || !S.nodes.length) S.nodes = genNodes(S.floor);
  $('#mapEyebrow').textContent = (S.floor === BAL.floors ? 'Final floor' : `Floor ${S.floor} of ${BAL.floors}`) + (biomeOf(S.floor) ? ' · The Dusklands' : ' · The Greenwood');
  $('#trail').innerHTML = Array.from({ length: BAL.floors }, (_, i) => `<i class="${i + 1 < S.floor ? 'done' : i + 1 === S.floor ? 'now' : i + 1 === BAL.floors || i + 1 === 4 ? 'boss' : ''}"></i>`).join('');
  const nodes = $('#nodes'); nodes.innerHTML = '';
  S.nodes.forEach(n => { const h = nodeView(n); nodes.appendChild(nodeBtn(h.g, h.t, h.s, h.c, () => chooseNode(n))); });
  $('#mapParty').innerHTML = partyHTML();
  $('#mapCharges').innerHTML = `${svg('orb')} ${S.charges} Capture charge${S.charges === 1 ? '' : 's'}`;
  $('#lineupBtn').hidden = S.party.length < 2;
  show('#scr-map');
}
function chooseNode(n: MapNode) {
  if (n.type === 'spring') {
    S.party.forEach(c => { c.alive = true; c.hp = c.maxHp; });
    S.charges++;
    for (let k = 0; k < 4; k++) gsap.delayedCall(k * 0.15, () => {
      const p = PPOS(); emit(p.x, p.y, { n: 40, color: [0x6ff0a0, 0xc8ffd9, 0x8fe3ff], spd: 2, dir: [0, -1], cone: 0.5, life: 1.3, size: 0.24, drag: 1, r: 0.6, swirl: 3 }); ring(p.x, p.y, 0x6ff0a0, 2);
    });
    SFX.heal(); haptic('success'); toast('Party fully healed · +1 Capture charge'); nextFloor(); return;
  }
  startBattle(n);
}
function nextFloor() { S.floor++; showMap(); }

/* ================= after a fight ================= */
/** Revive and tidy the party, then route to rewards / next floor / end. */
export function afterFight(result: 'win' | 'flee', caught: Mon | null = null) {
  const e = S.enemy;
  S.party.forEach(c => {
    if (!c.alive) { c.alive = true; c.hp = Math.round(c.maxHp * BAL.reviveHp); }
    c.shield = 0; c.status = null; c.reflect = 0; c.nextStrike = 1;
  });
  if (!S.lineup.includes(S.active)) S.active = S.lineup[0];
  if (e && e.kind === 'boss' && result === 'win') { endRun(true); return; }
  S.em?.destroy(); S.em = null; placePlayer(false);
  if (result === 'flee') { nextFloor(); return; }
  showReward(e?.kind === 'alpha' ? 2 : 1, caught);
}
export function onCaught(e: Enemy) {
  const c = newMon(e.key, meta.isShiny(e.key)); c.hp = Math.round(c.maxHp * BAL.caughtHp);
  S.caught.push(e.key);
  if (S.party.length < BAL.partyMax) { join(c); afterFight('win', c); return; }
  S.mode = 'reward';
  $('#ctTitle').textContent = 'Make room for ' + c.name + '?';
  const list = $('#ctList'); list.innerHTML = '';
  S.party.forEach(p => list.appendChild(nodeBtn(p.el, 'Release ' + p.name, `${ELEM[p.el].name} · ${Math.ceil(p.hp)}/${p.maxHp} HP${p.starter ? ' · your starter' : ''}`, elCss(p.el), () => {
    const li = S.lineup.indexOf(p.uid);
    dropActor(p.uid); S.party = S.party.filter(x => x !== p); S.party.push(c);
    if (li >= 0) S.lineup[li] = c.uid;
    if (S.active === p.uid) S.active = S.lineup[0];
    afterFight('win', c);
  })));
  list.appendChild(nodeBtn('paw', `Let ${c.name} go`, 'Keep your current party', 'var(--neutral)', () => afterFight('win', null)));
  show('#scr-catch');
}
function join(c: Mon) { S.party.push(c); if (S.lineup.length < BAL.lineup) S.lineup.push(c.uid); }

/* ================= rewards ================= */
const upgradable = () => S.party.some(c => SLOTS.some(s => !c.ups[s]));
function showReward(picks: number, caught: Mon | null) {
  S.mode = 'reward';
  const done = () => caught ? showParty(nextFloor, `${caught.name} joined. Set your lineup.`) : nextFloor();
  if (picks <= 0) { done(); return; }
  $('#rwEyebrow').textContent = picks > 1 ? `Victory · ${picks} picks` : 'Victory';
  $('#rwTitle').textContent = 'Choose a reward';
  $('#rwSub').textContent = caught ? `${caught.name} joined your party with its 3 cards.` : 'Knocked-out partners are back on their feet at 25%.';
  const box = $('#rewards'); box.innerHTML = '';
  const next = () => showReward(picks - 1, caught);
  const opt = (g: GlyphKey, name: string, txt: string, color: string, ok: boolean, onPick: () => void) => {
    const b = document.createElement('button'); b.className = 'card deal'; b.style.setProperty('--c', color); b.disabled = !ok;
    b.innerHTML = `<span class="gl">${svg(g)}</span><span class="nm">${name}</span><span class="tx">${txt}</span>`;
    b.addEventListener('click', () => { audio(); SFX.pick(); haptic('select'); onPick(); }); box.appendChild(b);
  };
  opt('up', 'Upgrade', 'One card: +30% effect or −1 cost', 'var(--gold)', upgradable(), () => showUpgrade(next, () => showReward(picks, caught)));
  opt('heart', 'Heal', `Whole party +${Math.round(BAL.healReward * 100)}% HP`, 'var(--hp)', true, () => {
    S.party.forEach(c => { c.alive = true; c.hp = Math.min(c.maxHp, c.hp + Math.round(c.maxHp * BAL.healReward)); }); SFX.heal(); next();
  });
  opt('orb', 'Capture', '+1 Capture charge', 'var(--neutral)', true, () => { S.charges++; next(); });
  [...box.children].forEach((c, i) => (c as HTMLElement).style.animationDelay = (i * 0.08) + 's');
  $('#rwDeck').textContent = `${S.charges} charge${S.charges === 1 ? '' : 's'} · ${S.party.length}/${BAL.partyMax} in party`;
  $('#skipBtn').onclick = () => { SFX.pick(); next(); };
  show('#scr-reward');
}
function showUpgrade(onDone: () => void, onBack: () => void) {
  const list = $('#upList'), choice = $('#upChoice'); list.innerHTML = ''; choice.innerHTML = ''; choice.hidden = true;
  S.party.forEach(c => {
    const row = document.createElement('div'); row.className = 'uprow';
    row.innerHTML = `<div class="upname" style="--c:${elCss(c.el)}">${svg(c.el)}${c.name}</div>`;
    const cards = document.createElement('div'); cards.className = 'upcards';
    SLOTS.forEach(slot => {
      const { def, pow } = cardOf({ uid: c.uid, slot }), up = c.ups[slot];
      const b = document.createElement('button'); b.className = 'card mini'; b.style.setProperty('--c', elCss(c.el)); b.disabled = !!up;
      b.innerHTML = cardFace(def, c.el, { pow, upgraded: up === 'power' ? '+30%' : up === 'cost' ? '−1' : '' });
      b.addEventListener('click', () => { SFX.pick(); haptic('select'); pickUpgrade(c, slot, b); });
      cards.appendChild(b);
    });
    row.appendChild(cards); list.appendChild(row);
  });
  function pickUpgrade(c: Mon, slot: Slot, b: HTMLElement) {
    list.querySelectorAll('.card.sel').forEach(x => x.classList.remove('sel')); b.classList.add('sel');
    const { def } = cardOf({ uid: c.uid, slot }), base = baseCard(c, slot);
    const evoBase = slot === 'sig' && c.evolved && SPECIES[c.key].evo && c.moves.sig === 0 ? SPECIES[c.key].evo!.sig : base;
    choice.innerHTML = `<div class="eyebrow">${def.name}</div>`;
    const row = document.createElement('div'); row.className = 'row2';
    const apply = (u: 'power' | 'cost') => { c.ups[slot] = u; SFX.caught(); haptic('success'); toast(`${def.name} upgraded`); onDone(); };
    const p = document.createElement('button'); p.className = 'big alt'; p.innerHTML = '+30% effect'; p.disabled = !scalable(evoBase); p.onclick = () => apply('power');
    const k = document.createElement('button'); k.className = 'big alt'; k.innerHTML = `−1 cost <small>(${def.cost} → ${Math.max(0, def.cost - 1)})</small>`; k.disabled = def.cost <= 0; k.onclick = () => apply('cost');
    row.append(p, k); choice.appendChild(row); choice.hidden = false;
    choice.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }
  $('#upBack').onclick = () => { SFX.pick(); onBack(); };
  show('#scr-upgrade');
}

/* ================= party / lineup ================= */
export function showParty(onDone: () => void, sub = 'Three creatures fight. Their cards are your deck. ★ is your lead.') {
  S.mode = 'reward';
  $('#ptSub').textContent = sub;
  const render = () => {
    const list = $('#ptList'); list.innerHTML = '';
    S.party.forEach(c => {
      const i = S.lineup.indexOf(c.uid), inLine = i >= 0, lead = i === 0;
      const row = document.createElement('div'); row.className = 'ptrow' + (inLine ? ' on' : ''); row.style.setProperty('--c', elCss(c.el));
      const main = btn('ptmain', `<span class="orb">${svg(c.el)}</span><span><b>${c.name}${c.shiny ? ' ✦' : ''}</b><span>${ELEM[c.el].name} · ${SPECIES[c.key].role ?? ''} · ${Math.ceil(c.hp)}/${c.maxHp} HP</span></span><span class="pill">${lead ? 'Lead' : inLine ? 'Bench' : 'Reserve'}</span>`, () => {
        if (inLine) { if (S.lineup.length > 1) S.lineup.splice(i, 1); }
        else if (S.lineup.length < BAL.lineup) S.lineup.push(c.uid);
        else S.lineup[S.lineup.length - 1] = c.uid;
        render();
      });
      row.appendChild(main);
      if (inLine && !lead) row.appendChild(btn('ptlead', '★', () => { S.lineup.splice(i, 1); S.lineup.unshift(c.uid); render(); }));
      list.appendChild(row);
    });
    const need = Math.min(BAL.lineup, S.party.length);
    const done = $('#ptDone') as HTMLButtonElement; done.disabled = S.lineup.length !== need;
    done.textContent = S.lineup.length === need ? 'Done' : `Pick ${need - S.lineup.length} more`;
  };
  render();
  ($('#ptDone') as HTMLButtonElement).onclick = () => { SFX.pick(); S.active = S.lineup[0]; placePlayer(true); onDone(); };
  show('#scr-party');
}

/* ================= end of run ================= */
let keepPick: string | null = null;
export function endRun(won: boolean) {
  S.mode = 'over'; S.tok++;
  const secs = Math.round((performance.now() - S.stats.start) / 1000), reached = won ? BAL.floors : S.floor;
  meta.recordRun(won, reached);
  $('#endH').textContent = won ? 'Expedition won' : 'Run over';
  $('#endP').textContent = won ? 'Noctyrm is sealed. Your party walks out of the wild.' : `Your party fell on floor ${S.floor}.`;
  $('#endStats').innerHTML = [[reached, 'Floor'], [S.stats.caught, 'Caught'], [S.stats.perfects, 'Perfect'], [`${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`, 'Time']]
    .map(([v, l]) => `<div class="stat"><b>${v}</b><span>${l}</span></div>`).join('');
  $('#endParty').innerHTML = partyHTML(S.party);
  const keep = $('#endKeep'); keep.innerHTML = ''; keepPick = null;
  const species = [...new Set(S.caught)];
  if (won) {
    const fresh = meta.addOwned(species);
    keep.innerHTML = fresh.length ? `<div class="eyebrow">New in your collection</div><p class="sub">${fresh.map(k => SPECIES[k].name).join(', ')}</p>`
      : species.length ? '<p class="sub">Everything you caught was already in your collection.</p>' : '';
  } else if (species.length) {
    keepPick = species.find(k => !meta.isOwned(k)) ?? species[0];
    keep.innerHTML = '<div class="eyebrow">Keep one catch</div>';
    const row = document.createElement('div'); row.className = 'keeprow';
    species.forEach(k => {
      const sp = SPECIES[k], b = btn('keep', `${svg(sp.el)}<b>${sp.name}</b><span>${meta.isOwned(k) ? 'owned' : 'new'}</span>`, () => { keepPick = k; mark(); }, elCss(sp.el));
      b.dataset.k = k; row.appendChild(b);
    });
    const mark = () => row.querySelectorAll<HTMLElement>('.keep').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.k === keepPick)));
    keep.appendChild(row); mark();
  }
  if (won) {
    SFX.win(); haptic('success');
    for (let k = 0; k < 8; k++) gsap.delayedCall(k * 0.25, () => {
      const x = rand(innerWidth * 0.15, innerWidth * 0.85), y = rand(innerHeight * 0.1, innerHeight * 0.35);
      emit(x, y, { n: 60, color: [0xffcf6b, 0xff7a45, 0x3fb6ff, 0x5fd36a, 0xffd23f, 0xc8b4ff], spd: 5, life: 1.6, size: 0.2, grav: 3, drag: 1 });
      emit(x, y, { n: 10, color: [0xffcf6b, 0xffffff], spd: 4, life: 1.6, size: 0.35, grav: 2, drag: 1, tex: 'star', spin: 6 }); ring(x, y, 0xffcf6b, 2.5, 0.6, false);
    });
  } else { SFX.lose(); haptic('error'); }
  S.em?.destroy(); S.em = null;
  $('#againBtn').textContent = `Run again · ${SPECIES[S.starter].name}`;
  show('#scr-end');
}
function leaveEnd() { if (keepPick) { meta.addOwned([keepPick]); keepPick = null; } }

/* ================= title ================= */
function renderStarters() {
  const box = $('#starters'); box.innerHTML = '';
  const own = meta.owned();
  if (!own.includes(S.starter)) S.starter = meta.lastStarter();
  ROSTER.filter(k => own.includes(k)).forEach(k => {
    const sp = SPECIES[k], shiny = meta.isShiny(k);
    const b = btn('starter', `<span class="orb">${svg(sp.el)}</span><b>${sp.name}${shiny ? ' ✦' : ''}</b><span>${sp.role}${STARTERS.includes(k) ? '' : ' · Prime'}</span>`, () => {
      S.starter = k; renderStarters(); showTitleActor(k);
    }, elCss(sp.el));
    b.setAttribute('aria-pressed', String(S.starter === k)); box.appendChild(b);
  });
  const best = meta.best(), wins = meta.wins();
  $('#bestT').textContent = wins ? `Expeditions won: ${wins} · best floor ${best}` : best ? `Best run: floor ${best}` : 'Runs take about five minutes';
  const ready = meta.packReady(), pb = $('#packBtn') as HTMLButtonElement;
  pb.innerHTML = `<b>Daily pack</b><span>${ready ? 'Ready to open' : 'Next in ' + meta.nextPackIn()}</span>`;
  pb.classList.toggle('ready', ready); pb.disabled = !ready;
  $('#collBtn').innerHTML = `<b>Collection</b><span>${own.length} / ${ROSTER.length}${meta.shinies().length ? ` · ${meta.shinies().length} ✦` : ''}</span>`;
}
function renderArtPicker() {
  const box = $('#artPicker'); box.innerHTML = '';
  $('#artRow').hidden = STYLES.length < 2;
  STYLES.forEach(st => {
    const b = document.createElement('button'); b.className = 'artbtn'; b.setAttribute('aria-pressed', String(getStyle().id === st.id));
    b.innerHTML = `<b>${st.name}</b><span>${st.blurb}</span>`;
    b.addEventListener('click', async () => { if (getStyle().id === st.id) return; SFX.pick(); haptic('select'); await useStyle(st.id); applyStyle(); });
    box.appendChild(b);
  });
}
function showTitleActor(key: string, o: { silhouette?: boolean } = {}) {
  S.titleActor?.destroy();
  const a = new Actor(key); a.extra = 1.15; S.titleActor = a;
  const shiny = !o.silhouette && meta.isShiny(key);
  a.setShiny(shiny); a.setSilhouette(!!o.silhouette);
  a.sq.scale.set(0.01); gsap.to(a.sq.scale, { x: 1, y: 1, duration: 0.7, ease: 'elastic.out(1,0.45)' });
  const { x, y } = TPOS();
  if (o.silhouette) { tintArena(0x5a6088); return; }
  emit(x, y - U * 0.6, { n: 90, color: ELEM[a.el].glow, spd: 3.5, up: 1.3, life: 1.1, size: 0.26, grav: 2, drag: 1.2 });
  emit(x, y - U * 0.6, { n: 12, color: [0xffffff, ELEM[a.el].hex], spd: 3, up: 1, life: 1, size: 0.35, grav: 1, drag: 1.2, tex: 'star', spin: 5 });
  if (shiny) sparkle(x, y - U * 1.2);
  ring(x, y, ELEM[a.el].hex, 2.6, 0.7); tintArena(ELEM[a.el].hex);
}
/** Rebuild everything visual after an art-style switch (title screen only). */
function applyStyle() {
  clearActors(); buildStage(); renderArtPicker(); showTitleActor(S.starter);
}
export function toTitle() {
  S.tok++; S.mode = 'title'; clearActors(); setBiome(0);
  renderStarters(); renderArtPicker(); show('#scr-title'); measureBand(true); showTitleActor(S.starter);
}

/* ================= daily pack ================= */
function showPack() {
  const res = meta.openPack(); if (!res) { toTitle(); return; }
  S.mode = 'meta'; S.titleActor?.destroy(); S.titleActor = null;
  const card = $('#packCard'), txt = $('#packTxt');
  card.classList.remove('open'); txt.innerHTML = '<p class="sub">Tap the card</p>';
  const k = res.key, sp = k ? SPECIES[k] : null;
  card.style.setProperty('--c', sp ? elCss(sp.el) : 'var(--gold)');
  $('#packFront').innerHTML = sp ? `<span class="orb">${svg(sp.el)}</span><b>${sp.name}${res.shiny ? ' ✦' : ''}</b><span>${res.shiny ? 'Shiny!' : 'New creature'}</span>` : '<b>All shiny!</b><span>You have every shiny. Nothing left to find… for now.</span>';
  let opened = false;
  const reveal = () => {
    if (opened) return; opened = true; card.classList.add('open'); SFX.caught(); haptic('heavy');
    if (k && sp) {
      showTitleActor(k);
      txt.innerHTML = res.shiny ? `<p class="sub">${sp.name} now shines in every run.</p>` : `<p class="sub">${sp.name} joins your collection. Pick it as a starter, or catch it to use mid-run.</p>`;
    } else txt.innerHTML = '';
  };
  card.onclick = reveal; gsap.delayedCall(1.2, reveal);
  $('#packOk').onclick = () => { SFX.pick(); if (k) S.starter = k; toTitle(); };
  show('#scr-pack'); measureBand(true);
}

/* ================= collection ================= */
function showCollection() {
  S.mode = 'meta';
  const own = meta.owned(), grid = $('#collGrid'); grid.innerHTML = '';
  $('#collCount').textContent = `${own.length} / ${ROSTER.length}`;
  const detail = (k: string) => {
    const sp = SPECIES[k], has = own.includes(k);
    showTitleActor(k, { silhouette: !has });
    (grid as HTMLElement).querySelectorAll<HTMLElement>('.cslot').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.k === k)));
    const d = $('#collDetail');
    d.innerHTML = `<div class="prow"><span class="elchip" style="--c:${elCss(sp.el)}">${svg(sp.el)}${ELEM[sp.el].name}</span><span class="nm">${sp.name}${meta.isShiny(k) ? ' ✦' : ''}</span><span class="sp"></span><span class="lv">${sp.role} · ${sp.hp} HP</span></div>
      ${has ? '' : '<p class="sub">Not found yet. Catch one in a run, or wait for a daily pack.</p>'}`;
    const cards = document.createElement('div'); cards.className = 'upcards';
    SLOTS.forEach(slot => { const c = document.createElement('div'); c.className = 'card mini'; c.style.setProperty('--c', elCss(sp.el)); c.innerHTML = cardFace(sp.cards![slot][0], sp.el); cards.appendChild(c); });
    if (sp.evo) { const c = document.createElement('div'); c.className = 'card mini evo'; c.style.setProperty('--c', elCss(sp.el)); c.innerHTML = cardFace(sp.evo.sig, sp.el) + `<span class="evotag">${SPECIES[sp.evo.key].name}</span>`; cards.appendChild(c); }
    d.appendChild(cards);
  };
  ROSTER.forEach(k => {
    const sp = SPECIES[k], has = own.includes(k);
    const b = btn('cslot' + (has ? '' : ' locked'), `<span class="orb">${has ? svg(sp.el) : '?'}</span><span>${has ? sp.name : '???'}${meta.isShiny(k) ? ' ✦' : ''}</span>`, () => detail(k), has ? elCss(sp.el) : 'var(--mute)');
    b.dataset.k = k; grid.appendChild(b);
  });
  show('#scr-coll'); measureBand(true);
  detail(own.includes(S.starter) ? S.starter : own[0]);
}

export function initRunUi() {
  $('#startBtn').addEventListener('click', startRun);
  $('#againBtn').addEventListener('click', () => { SFX.pick(); leaveEnd(); startRun(); });
  $('#titleBtn').addEventListener('click', () => { SFX.pick(); leaveEnd(); toTitle(); });
  $('#lineupBtn').addEventListener('click', () => { SFX.pick(); showParty(() => showMap(false)); });
  $('#packBtn').addEventListener('click', () => { audio(); SFX.pick(); showPack(); });
  $('#collBtn').addEventListener('click', () => { audio(); SFX.pick(); showCollection(); });
  $('#collBack').addEventListener('click', () => { SFX.pick(); toTitle(); });
  S.starter = meta.lastStarter();
}
