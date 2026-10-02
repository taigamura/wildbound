// Run flow outside combat: title (with art-style picker), map, nodes, rewards, catching, end of run.
import gsap from 'gsap';
import { U, PPOS, TPOS, measureBand } from '../render/layout';
import { emit, ring } from '../render/particles';
import { toast } from '../render/fx';
import { Actor } from '../render/actor';
import { buildStage, tintArena } from '../render/stage';
import { STYLES, getStyle, useStyle } from '../art/registry';
import { S, act, newMon, levelUp, actorFor, clearActors, type MapNode, type Mon, type Enemy } from './state';
import { show, paintCard, partyHTML, deckHTML } from './ui';
import { startBattle } from './battle';
import { CARDS, ELEM, EL_KEYS, SPECIES, SMALL, BIG, STARTERS, SIG, RARE, COMMONS, FLOORS, STARTING_DECK, adv, svg, elCss, type CardId, type GlyphKey } from '../core/data';
import { $, rand, pick, shuffle } from '../core/util';
import { SFX, audio } from '../core/audio';
import { store, haptic } from '../core/platform';

export function startRun() {
  audio(); haptic('medium');
  clearActors();
  S.uid = 1; S.party = [newMon(S.starter)]; S.active = 0; S.floor = 1;
  S.deck = STARTING_DECK(SPECIES[S.starter].el);
  S.stats = { caught: 0, start: performance.now(), dealt: 0 };
  placePlayer(true); SFX.win(); showMap();
}

/** Show the active partner on its pedestal and hide the bench. */
export function placePlayer(pop: boolean) {
  Object.values(S.actors).forEach(a => { a.visible = false; });
  const a = actorFor(act()); a.visible = true; a.off.x = 0; a.off.y = 0; a.sq.scale.set(1); a.flip.rotation = 0;
  if (pop) {
    const p = PPOS(); a.sq.scale.set(0.01); gsap.to(a.sq.scale, { x: 1, y: 1, duration: 0.6, ease: 'back.out(2.5)' });
    emit(p.x, p.y, { n: 60, color: ELEM[act().el].glow, spd: 2.5, dir: [0, -1], cone: 0.35, life: 0.9, size: 0.22, drag: 1.5, r: 0.4 });
    ring(p.x, p.y, ELEM[act().el].hex, 1.8);
  }
}

/* ================= map ================= */
function wildNode(f: number, avoidEl?: string): MapNode {
  let pool = f <= 2 ? SMALL : f <= 4 ? SMALL.concat(BIG) : BIG.concat(SMALL.slice(0, 2));
  if (avoidEl) pool = pool.filter(k => SPECIES[k].el !== avoidEl);
  return { type: 'wild', sp: pick(pool) };
}
function genNodes(f: number): MapNode[] {
  if (f === FLOORS) return [{ type: 'boss', sp: 'noctyrm' }];
  const a = wildNode(f), out: MapNode[] = [a];
  if (f >= 3 && Math.random() < 0.5) out.push({ type: 'elite', sp: pick(BIG) }); else out.push(wildNode(f, SPECIES[a.sp!].el));
  const hurt = S.party.some(c => !c.alive || c.hp / c.maxHp < 0.5);
  if (f === 5 || (f > 1 && Math.random() < (hurt ? 0.6 : 0.35))) out.push(Math.random() < (hurt ? 0.75 : 0.5) ? { type: 'spring' } : { type: 'cache' });
  return out;
}
function nodeView(n: MapNode): { c: string; g: GlyphKey; t: string; s: string } {
  if (n.type === 'wild' || n.type === 'elite') {
    const sp = SPECIES[n.sp!], el = sp.el, a = adv(act().el, el);
    return { c: elCss(el), g: n.type === 'elite' ? 'skull' : 'paw', t: (n.type === 'elite' ? 'Alpha ' : 'Wild ') + sp.name,
      s: `${ELEM[el].name} · Lv ${S.floor}${n.type === 'elite' ? ' · tougher, rare card' : ' · catchable'}${a > 1 ? ' · your partner is strong here' : a < 1 ? ' · your partner is weak here' : ''}` };
  }
  if (n.type === 'spring') return { c: 'var(--hp)', g: 'moon', t: 'Moon Spring', s: 'Heal every partner by half and revive the fainted' };
  if (n.type === 'cache') return { c: 'var(--gold)', g: 'chest', t: 'Relic Cache', s: 'Choose one of three rare cards' };
  return { c: 'var(--foe)', g: 'crown', t: 'Noctyrm', s: 'Boss · changes element every 7 seconds' };
}
export function showMap() {
  S.mode = 'map'; S.enemy = null; S.em?.destroy(); S.em = null; tintArena(getStyle().ambience.neutral);
  S.nodes = genNodes(S.floor);
  $('#mapEyebrow').textContent = S.floor === FLOORS ? 'Final floor' : `Floor ${S.floor} of ${FLOORS}`;
  $('#trail').innerHTML = Array.from({ length: FLOORS }, (_, i) => `<i class="${i + 1 < S.floor ? 'done' : i + 1 === S.floor ? 'now' : i + 1 === FLOORS ? 'boss' : ''}"></i>`).join('');
  const nodes = $('#nodes'); nodes.innerHTML = '';
  S.nodes.forEach(n => {
    const h = nodeView(n), b = document.createElement('button'); b.className = 'node'; b.style.setProperty('--c', h.c);
    b.innerHTML = `<span class="orb">${svg(h.g)}</span><span><b>${h.t}</b><span>${h.s}</span></span>`;
    b.addEventListener('click', () => { SFX.pick(); haptic('select'); chooseNode(n); }); nodes.appendChild(b);
  });
  $('#mapParty').innerHTML = partyHTML(); $('#deckLine').innerHTML = deckHTML();
  show('#scr-map');
}
function chooseNode(n: MapNode) {
  if (n.type === 'spring') {
    S.party.forEach(c => { if (!c.alive) { c.alive = true; c.hp = 0; } c.hp = Math.min(c.maxHp, c.hp + Math.round(c.maxHp * 0.5)); });
    for (let k = 0; k < 4; k++) gsap.delayedCall(k * 0.15, () => {
      const p = PPOS(); emit(p.x, p.y, { n: 40, color: [0x6ff0a0, 0xc8ffd9, 0x8fe3ff], spd: 2, dir: [0, -1], cone: 0.5, life: 1.3, size: 0.24, drag: 1, r: 0.6, swirl: 3 }); ring(p.x, p.y, 0x6ff0a0, 2);
    });
    SFX.heal(); haptic('success'); toast('The spring restores your party'); S.floor++; showMap(); return;
  }
  if (n.type === 'cache') { showReward({ rare: true, cache: true }); return; }
  startBattle(n);
}

/* ================= after a fight ================= */
export function onCaught(e: Enemy) {
  const c = newMon(e.key, Math.max(1, S.floor)); c.hp = Math.round(c.maxHp * 0.7); S.deck.push(SIG[c.el]);
  if (S.party.length < 3) { S.party.push(c); afterWin(c); return; }
  $('#ctTitle').textContent = 'Make room for ' + c.name + '?';
  const list = $('#ctList'); list.innerHTML = '';
  S.party.forEach((p, i) => {
    const b = document.createElement('button'); b.className = 'node'; b.style.setProperty('--c', elCss(p.el));
    b.innerHTML = `<span class="orb">${svg(p.el)}</span><span><b>Release ${p.name}</b><span>Lv ${p.lvl} · ${ELEM[p.el].name} · ${Math.ceil(p.hp)}/${p.maxHp} HP</span></span>`;
    b.addEventListener('click', () => { SFX.pick(); S.actors[p.uid]?.destroy(); delete S.actors[p.uid]; S.party[i] = c; if (i === S.active) placePlayer(true); afterWin(c); });
    list.appendChild(b);
  });
  const k = document.createElement('button'); k.className = 'node';
  k.innerHTML = `<span class="orb">${svg('paw')}</span><span><b>Let ${c.name} go</b><span>Keep your current party</span></span>`;
  k.addEventListener('click', () => { SFX.pick(); afterWin(null); }); list.appendChild(k);
  show('#scr-catch');
}
export function afterWin(caught: Mon | null) {
  const e = S.enemy;
  S.party.forEach(c => { if (!c.alive) { c.alive = true; c.hp = Math.round(c.maxHp * 0.2); } else levelUp(c); c.hp = Math.min(c.maxHp, c.hp + Math.round(c.maxHp * 0.2)); c.shield = 0; });
  if (!act().alive) S.active = S.party.findIndex(c => c.alive);
  if (e && e.boss) { endRun(true); return; }
  placePlayer(false); showReward({ rare: !!(e && e.elite), caught });
}
function rollRewards(rare: boolean): CardId[] {
  const els = [...new Set(S.party.map(c => c.el))], out: CardId[] = []; let guard = 0;
  while (out.length < 3 && guard++ < 60) {
    let id: CardId; const r = Math.random();
    if (rare && out.length === 0) id = RARE[Math.random() < 0.75 ? pick(els) : pick(EL_KEYS)];
    else if (rare && out.length === 1 && Math.random() < 0.6) id = RARE[pick(EL_KEYS)];
    else if (r < 0.5) id = SIG[Math.random() < 0.7 ? pick(els) : pick(EL_KEYS)];
    else if (r < 0.88) id = pick(COMMONS); else id = RARE[pick(els)];
    if (!out.includes(id)) out.push(id);
  }
  return out;
}
function showReward({ rare, cache, caught }: { rare: boolean; cache?: boolean; caught?: Mon | null }) {
  S.mode = 'reward'; if (!cache) { S.em?.destroy(); S.em = null; }
  $('#rwEyebrow').textContent = cache ? 'Relic Cache' : 'Victory · party level up';
  $('#rwTitle').textContent = cache ? 'Choose a rare card' : 'Take a card';
  $('#rwSub').textContent = caught ? `${caught.name} joined, and its ${CARDS[SIG[caught.el]].name} card is in your deck.`
    : cache ? 'Rare cards cost 3 but swing a fight.' : 'Every partner gained a level and recovered some health.';
  const ids = cache ? shuffle(Object.values(RARE).slice()).slice(0, 3) : rollRewards(rare);
  const box = $('#rewards'); box.innerHTML = '';
  ids.forEach((id, i) => {
    const b = document.createElement('button'); paintCard(b, id, null); b.className = 'card deal'; b.style.animationDelay = (i * 0.08) + 's';
    b.addEventListener('click', () => { SFX.pick(); haptic('select'); S.deck.push(id); nextFloor(); }); box.appendChild(b);
  });
  $('#rwDeck').textContent = 'Deck: ' + S.deck.length + ' cards'; show('#scr-reward');
}
function nextFloor() { S.floor++; showMap(); }

export function endRun(won: boolean) {
  S.mode = 'over'; S.tok++;
  const secs = Math.round((performance.now() - S.stats.start) / 1000), reached = won ? FLOORS : S.floor;
  store.set('best', Math.max(store.get('best', 0), reached)); if (won) store.set('wins', store.get('wins', 0) + 1);
  $('#endH').textContent = won ? 'Expedition won' : 'Run over';
  $('#endP').textContent = won ? 'Noctyrm is sealed. Your party walks out of the wild.' : `Your party fell on floor ${S.floor}.`;
  $('#endStats').innerHTML = `<div class="stat"><b>${reached}</b><span>Floor</span></div><div class="stat"><b>${S.stats.caught}</b><span>Caught</span></div><div class="stat"><b>${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}</b><span>Time</span></div>`;
  $('#endParty').innerHTML = partyHTML();
  if (won) {
    SFX.win(); haptic('success');
    for (let k = 0; k < 8; k++) gsap.delayedCall(k * 0.25, () => {
      const x = rand(innerWidth * 0.15, innerWidth * 0.85), y = rand(innerHeight * 0.1, innerHeight * 0.35);
      emit(x, y, { n: 60, color: [0xffcf6b, 0xff7a45, 0x3fb6ff, 0x5fd36a, 0xffd23f, 0xc8b4ff], spd: 5, life: 1.6, size: 0.2, grav: 3, drag: 1 });
      emit(x, y, { n: 10, color: [0xffcf6b, 0xffffff], spd: 4, life: 1.6, size: 0.35, grav: 2, drag: 1, tex: 'star', spin: 6 }); ring(x, y, 0xffcf6b, 2.5, 0.6, false);
    });
  } else { SFX.lose(); haptic('error'); }
  S.em?.destroy(); S.em = null;
  show('#scr-end');
}

/* ================= title ================= */
function renderStarters() {
  const box = $('#starters'); box.innerHTML = '';
  STARTERS.forEach(k => {
    const sp = SPECIES[k], b = document.createElement('button'); b.className = 'starter'; b.style.setProperty('--c', elCss(sp.el));
    b.setAttribute('aria-pressed', String(S.starter === k));
    b.innerHTML = `<span class="orb">${svg(sp.el)}</span><b>${sp.name}</b><span>${ELEM[sp.el].name} · ${sp.blurb}</span>`;
    b.addEventListener('click', () => { audio(); SFX.pick(); haptic('select'); S.starter = k; renderStarters(); showTitleActor(); });
    box.appendChild(b);
  });
  const best = store.get('best', 0), wins = store.get('wins', 0);
  $('#bestT').textContent = wins ? `Expeditions won: ${wins}` : best ? `Best run: floor ${best}` : 'Runs take about five minutes';
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
function showTitleActor() {
  S.titleActor?.destroy();
  const a = new Actor(S.starter); a.extra = 1.15; S.titleActor = a;
  a.sq.scale.set(0.01); gsap.to(a.sq.scale, { x: 1, y: 1, duration: 0.7, ease: 'elastic.out(1,0.45)' });
  const { x, y } = TPOS();
  emit(x, y - U * 0.6, { n: 90, color: ELEM[a.el].glow, spd: 3.5, up: 1.3, life: 1.1, size: 0.26, grav: 2, drag: 1.2 });
  emit(x, y - U * 0.6, { n: 12, color: [0xffffff, ELEM[a.el].hex], spd: 3, up: 1, life: 1, size: 0.35, grav: 1, drag: 1.2, tex: 'star', spin: 5 });
  ring(x, y, ELEM[a.el].hex, 2.6, 0.7); tintArena(ELEM[a.el].hex);
}
/** Rebuild everything visual after an art-style switch (title screen only). */
function applyStyle() {
  clearActors(); buildStage(); renderArtPicker(); showTitleActor();
}
export function toTitle() {
  S.tok++; S.mode = 'title'; clearActors();
  renderStarters(); renderArtPicker(); show('#scr-title'); measureBand(true); showTitleActor();
}
export function initRunUi() {
  $('#startBtn').addEventListener('click', startRun);
  $('#skipBtn').addEventListener('click', () => { SFX.pick(); nextFloor(); });
  $('#againBtn').addEventListener('click', () => { SFX.pick(); toTitle(); });
}
