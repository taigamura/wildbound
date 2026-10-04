// Run flow outside combat: title (team picker), packs, collection & upgrades, item shop, map, nodes,
// loot, rewards, lineup, end of run. Spec: CLAUDE.md §2, §5–§7, §11, §16.
import gsap from 'gsap';
import { U, PPOS, TPOS, measureBand } from '../render/layout';
import { emit, ring } from '../render/particles';
import { toast } from '../render/fx';
import { Actor } from '../render/actor';
import { buildStage, tintArena, setBiome } from '../render/stage';
import { STYLES, getStyle, useStyle } from '../art/registry';
import { S, act, newMon, actorFor, clearActors, cardOf, baseCard, type MapNode, type Mon, type Enemy } from './state';
import { show, cardFace, partyHTML } from './ui';
import { startBattle } from './battle';
import { BAL, ELEM, EL_KEYS, SPECIES, SLOTS, TRAITS, ROSTER, POOL_A, POOL_B, MATS, MAT_DEF, NO_LOOT, adv, biomeOf, scalable, boostCard, svg, elCss,
  type El, type GlyphKey, type Slot, type TraitKey, type Loot } from '../core/data';
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
/** The title screen's picks, limited to owned species (falls back to the last saved lineup). */
function validPicks() {
  const own = meta.owned(), p = [...new Set(S.picks)].filter(k => own.includes(k)).slice(0, BAL.lineup);
  return p.length ? p : meta.lastLineup();
}
export function startRun() {
  audio(); haptic('medium');
  clearActors();
  S.tok++; S.uid = 1;
  S.picks = validPicks(); meta.saveLineup(S.picks);
  S.party = S.picks.map(k => newMon(k, meta.isShiny(k)));
  S.lineup = S.party.map(c => c.uid); S.active = S.lineup[0]; S.floor = 1;
  S.stats = { start: performance.now(), dealt: 0, perfects: 0 };
  runEss = meta.EMPTY_ESSENCE(); runLoot = NO_LOOT();
  setBiome(0); placePlayer(true); SFX.win(); showMap();
}

/* ================= essence (§16.3) ================= */
let runEss = meta.EMPTY_ESSENCE();
function gain(el: El, n: number) { meta.earn(el, n); runEss[el] += n; }
function fightEssence(e: Enemy) {
  if (e.kind === 'wild') gain(SPECIES[e.key].el, BAL.essWild);
  else if (e.kind === 'alpha') gain(SPECIES[e.key].el, BAL.essAlpha);
  else if (e.kind === 'warden') { gain('thorn', BAL.essWarden); gain('ember', BAL.essWarden); }
  else EL_KEYS.forEach(el => gain(el, BAL.essBoss));
}
/** Essence chips: totals (`plus` = false) or this run's gains, skipping zeros. */
const essHTML = (e: meta.Essence, plus = false) => EL_KEYS.filter(el => !plus || e[el] > 0)
  .map(el => `<span class="ess" style="--c:${elCss(el)}">${svg(el)}${plus ? `+${e[el]} ${ELEM[el].name}` : e[el]}</span>`).join('');
const costHTML = (c: { el: El; n: number }) => `${c.n}${svg(c.el)}`;

/* ================= loot (§5.1) ================= */
let runLoot = NO_LOOT();
/** Bank loot now (kept win or lose) and count it toward this run's total. */
function bank(l: Partial<Loot>) {
  meta.addLoot(l);
  for (const k of Object.keys(l) as (keyof Loot)[]) runLoot[k] += l[k] ?? 0;
}
const floorGold = () => 1 + BAL.goldPerFloor * (S.floor - 1);
/** What a won fight drops. */
function rollLoot(e: Enemy): Loot {
  const l = NO_LOOT(), mat = (n = 1) => { for (let i = 0; i < n; i++) l[meta.randomMat()]++; };
  if (e.kind === 'boss') { l.gold = BAL.bossGold; MATS.forEach(m => l[m]++); }
  else if (e.kind === 'warden') { l.gold = BAL.wardenGold; mat(BAL.wardenMats); }
  else {
    const [lo, hi] = BAL.wildGold, g = lo + Math.floor(Math.random() * (hi - lo + 1));
    if (e.kind === 'alpha') { l.gold = Math.round(g * floorGold() * BAL.alphaGoldMul); mat(BAL.alphaMats); }
    else { l.gold = Math.round(g * floorGold()); if (Math.random() < BAL.wildMatChance) mat(); }
  }
  return l;
}
/** Loot chips: totals (`plus` = false) or gains, skipping zeros. */
function lootHTML(l: Loot, plus = false) {
  const chip = (g: GlyphKey, c: string, n: number, name: string) => (plus && !n) ? '' :
    `<span class="ess" style="--c:${c}">${svg(g)}${plus ? `+${n} ${name}` : n}</span>`;
  return chip('coin', 'var(--gold)', l.gold, 'gold') + MATS.map(m => chip(m, MAT_DEF[m].color, l[m], MAT_DEF[m].name)).join('');
}
const walletText = () => { const w = meta.wallet(); return `${w.gold} gold · ` + MATS.map(m => `${w[m]} ${MAT_DEF[m].name}`).join(' · '); };

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
    const f = floorGold() * (n.type === 'alpha' ? BAL.alphaGoldMul : 1), gold = `${Math.round(BAL.wildGold[0] * f)}–${Math.round(BAL.wildGold[1] * f)} gold`;
    const parts = [ELEM[el].name, n.type === 'alpha' ? `tougher · 2 picks · ${gold} + ${BAL.alphaMats} material` : `${gold} · ${Math.round(BAL.wildMatChance * 100)}% material`];
    if (a > 1) parts.push('your lead is strong here'); else if (a < 1) parts.push('your lead is weak here');
    return { c: elCss(el), g: n.type === 'alpha' ? 'skull' : 'paw', t: (n.type === 'alpha' ? 'Alpha ' : 'Wild ') + sp.name, s: parts.join(' · ') };
  }
  if (n.type === 'spring') return { c: 'var(--hp)', g: 'moon', t: 'Moon Spring', s: 'Heal the party to full' };
  if (n.type === 'warden') return { c: 'var(--thorn)', g: 'crown', t: 'Gravewood', s: `Warden · heavies alternate Thorn and Ember · ${BAL.wardenGold} gold + ${BAL.wardenMats} materials` };
  return { c: 'var(--foe)', g: 'crown', t: 'Noctyrm', s: `Boss · changes element every ${BAL.bossShift}s · ${BAL.bossGold} gold + one of each material` };
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
  $('#mapGold').innerHTML = `${svg('coin')} ${walletText()}`;
  $('#lineupBtn').hidden = S.party.length < 2;
  show('#scr-map');
}
function chooseNode(n: MapNode) {
  if (n.type === 'spring') {
    S.party.forEach(c => { c.alive = true; c.hp = c.maxHp; });
    for (let k = 0; k < 4; k++) gsap.delayedCall(k * 0.15, () => {
      const p = PPOS(); emit(p.x, p.y, { n: 40, color: [0x6ff0a0, 0xc8ffd9, 0x8fe3ff], spd: 2, dir: [0, -1], cone: 0.5, life: 1.3, size: 0.24, drag: 1, r: 0.6, swirl: 3 }); ring(p.x, p.y, 0x6ff0a0, 2);
    });
    SFX.heal(); haptic('success'); toast('Party fully healed'); nextFloor(); return;
  }
  startBattle(n);
}
function nextFloor() { S.floor++; showMap(); }

/* ================= after a fight ================= */
/** Revive and tidy the party, bank the loot, then route to rewards or the end of the run. */
export function afterFight() {
  const e = S.enemy;
  S.party.forEach(c => {
    if (!c.alive) { c.alive = true; c.hp = Math.round(c.maxHp * BAL.reviveHp); }
    c.shield = 0; c.status = null; c.reflect = 0; c.nextStrike = 1;
  });
  if (!S.lineup.includes(S.active)) S.active = S.lineup[0];
  let loot: Loot | null = null;
  if (e) { fightEssence(e); loot = rollLoot(e); bank(loot); }
  if (e && e.kind === 'boss') { endRun(true); return; }
  S.em?.destroy(); S.em = null; placePlayer(false);
  showReward(e?.kind === 'alpha' ? 2 : 1, loot);
}

/* ================= rewards ================= */
const upgradable = () => S.party.some(c => SLOTS.some(s => !c.ups[s]));
function showReward(picks: number, loot: Loot | null) {
  S.mode = 'reward';
  if (picks <= 0) { nextFloor(); return; }
  $('#rwEyebrow').textContent = picks > 1 ? `Victory · ${picks} picks` : 'Victory';
  $('#rwTitle').textContent = 'Choose a reward';
  const got = loot ? lootHTML(loot, true) : '';
  $('#rwSub').innerHTML = (got ? `<span class="esschips" style="justify-content:flex-start;margin-bottom:6px">${got}</span>` : '') + 'Knocked-out partners are back on their feet at 25%.';
  const box = $('#rewards'); box.innerHTML = '';
  const next = () => showReward(picks - 1, loot);
  const opt = (g: GlyphKey, name: string, txt: string, color: string, ok: boolean, onPick: () => void) => {
    const b = document.createElement('button'); b.className = 'card deal'; b.style.setProperty('--c', color); b.disabled = !ok;
    b.innerHTML = `<span class="gl">${svg(g)}</span><span class="nm">${name}</span><span class="tx">${txt}</span>`;
    b.addEventListener('click', () => { audio(); SFX.pick(); haptic('select'); onPick(); }); box.appendChild(b);
  };
  opt('up', 'Upgrade', 'One card: +30% effect or −1 cost', 'var(--gold)', upgradable(), () => showUpgrade(next, () => showReward(picks, loot)));
  opt('heart', 'Heal', `Whole party +${Math.round(BAL.healReward * 100)}% HP`, 'var(--hp)', true, () => {
    S.party.forEach(c => { c.alive = true; c.hp = Math.min(c.maxHp, c.hp + Math.round(c.maxHp * BAL.healReward)); }); SFX.heal(); next();
  });
  opt('jewel', 'Scavenge', '+1 random material: Sword, Orb or Jewel', 'var(--neutral)', true, () => {
    const m = meta.randomMat(); bank({ [m]: 1 }); SFX.caught(); toast(`+1 ${MAT_DEF[m].name}`); next();
  });
  [...box.children].forEach((c, i) => (c as HTMLElement).style.animationDelay = (i * 0.08) + 's');
  $('#rwDeck').textContent = walletText();
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
    choice.innerHTML = `<div class="eyebrow">${def.name}</div>`;
    const row = document.createElement('div'); row.className = 'row2';
    const apply = (u: 'power' | 'cost') => { c.ups[slot] = u; SFX.caught(); haptic('success'); toast(`${def.name} upgraded`); onDone(); };
    const p = document.createElement('button'); p.className = 'big alt'; p.innerHTML = '+30% effect'; p.disabled = !scalable(base); p.onclick = () => apply('power');
    const k = document.createElement('button'); k.className = 'big alt'; k.innerHTML = `−1 cost <small>(${def.cost} → ${Math.max(0, def.cost - 1)})</small>`; k.disabled = def.cost <= 0; k.onclick = () => apply('cost');
    row.append(p, k); choice.appendChild(row); choice.hidden = false;
    choice.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }
  $('#upBack').onclick = () => { SFX.pick(); onBack(); };
  show('#scr-upgrade');
}

/* ================= party / lineup ================= */
/** Reorder the run's lineup: tap a creature (or ★) to make it the lead. */
export function showParty(onDone: () => void, sub = 'Your three creatures fight together and their cards are your deck. Tap one to make it your lead.') {
  S.mode = 'reward';
  $('#ptSub').textContent = sub;
  const render = () => {
    const list = $('#ptList'); list.innerHTML = '';
    S.lineup.forEach((uid, i) => {
      const c = S.party.find(x => x.uid === uid); if (!c) return;
      const lead = i === 0, toLead = () => { S.lineup.splice(i, 1); S.lineup.unshift(c.uid); render(); };
      const row = document.createElement('div'); row.className = 'ptrow on'; row.style.setProperty('--c', elCss(c.el));
      row.appendChild(btn('ptmain', `<span class="orb">${svg(c.el)}</span><span><b>${c.name}${c.shiny ? ' ✦' : ''}</b><span>${ELEM[c.el].name} · ${SPECIES[c.key].role ?? ''} · ${Math.ceil(c.hp)}/${c.maxHp} HP${c.trait ? ' · ' + TRAITS[c.trait].name : ''}</span></span><span class="pill">${lead ? 'Lead' : 'Bench'}</span>`, () => { if (!lead) toLead(); }));
      if (!lead) row.appendChild(btn('ptlead', '★', toLead));
      list.appendChild(row);
    });
    const done = $('#ptDone') as HTMLButtonElement; done.disabled = false; done.textContent = 'Done';
  };
  render();
  ($('#ptDone') as HTMLButtonElement).onclick = () => { SFX.pick(); S.active = S.lineup[0]; placePlayer(true); onDone(); };
  show('#scr-party');
}

/* ================= end of run ================= */
export function endRun(won: boolean) {
  S.mode = 'over'; S.tok++;
  if (won) bank({ gold: BAL.winGold });
  const secs = Math.round((performance.now() - S.stats.start) / 1000), reached = won ? BAL.floors : S.floor;
  meta.recordRun(won, reached);
  $('#endH').textContent = won ? 'Expedition won' : 'Run over';
  $('#endP').textContent = won ? `Noctyrm is sealed. Your party walks out of the wild (+${BAL.winGold} gold).` : `Your party fell on floor ${S.floor}. Your loot is safe.`;
  $('#endStats').innerHTML = [[reached, 'Floor'], [runLoot.gold, 'Gold'], [S.stats.perfects, 'Perfect'], [`${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`, 'Time']]
    .map(([v, l]) => `<div class="stat"><b>${v}</b><span>${l}</span></div>`).join('');
  $('#endParty').innerHTML = partyHTML(S.party);
  $('#endEss').innerHTML = EL_KEYS.some(el => runEss[el]) ? `<span class="eyebrow">Essence</span>${essHTML(runEss, true)}` : '';
  const got = lootHTML(runLoot, true);
  $('#endLoot').innerHTML = got ? `<span class="eyebrow">Loot</span>${got}` : '';
  if (won) {
    SFX.win(); haptic('success');
    for (let k = 0; k < 8; k++) gsap.delayedCall(k * 0.25, () => {
      const x = rand(innerWidth * 0.15, innerWidth * 0.85), y = rand(innerHeight * 0.1, innerHeight * 0.35);
      emit(x, y, { n: 60, color: [0xffcf6b, 0xff7a45, 0x3fb6ff, 0x5fd36a, 0xffd23f, 0xc8b4ff], spd: 5, life: 1.6, size: 0.2, grav: 3, drag: 1 });
      emit(x, y, { n: 10, color: [0xffcf6b, 0xffffff], spd: 4, life: 1.6, size: 0.35, grav: 2, drag: 1, tex: 'star', spin: 6 }); ring(x, y, 0xffcf6b, 2.5, 0.6, false);
    });
  } else { SFX.lose(); haptic('error'); }
  S.em?.destroy(); S.em = null;
  const n = S.picks.length;
  $('#againBtn').textContent = `Run again · ${SPECIES[S.picks[0]].name}${n > 1 ? ` +${n - 1}` : ''}`;
  show('#scr-end');
}
/** Back to the end-of-run screen (from the shop). */
function backToEnd() { S.titleActor?.destroy(); S.titleActor = null; S.mode = 'over'; show('#scr-end'); }

/* ================= title ================= */
/** Team picker: tap to add (up to 3) or remove. The first pick is the lead. */
function renderPicks() {
  const box = $('#starters'); box.innerHTML = '';
  const own = meta.owned();
  S.picks = validPicks();
  ROSTER.filter(k => own.includes(k)).forEach(k => {
    const sp = SPECIES[k], shiny = meta.isShiny(k), i = S.picks.indexOf(k);
    const b = btn('starter', `<span class="orb">${svg(sp.el)}</span><b>${sp.name}${shiny ? ' ✦' : ''}</b><span>${i === 0 ? 'Lead' : i > 0 ? 'Bench' : sp.role}</span>`, () => {
      const j = S.picks.indexOf(k);
      if (j >= 0) { if (S.picks.length > 1) S.picks.splice(j, 1); }
      else if (S.picks.length < BAL.lineup) S.picks.push(k);
      else S.picks[S.picks.length - 1] = k;
      renderPicks(); showTitleActor(S.picks.includes(k) ? k : S.picks[0]);
    }, elCss(sp.el));
    b.setAttribute('aria-pressed', String(i >= 0)); box.appendChild(b);
  });
  $('#pickEyebrow').textContent = `Choose your team · ${S.picks.length}/${BAL.lineup}`;
  const best = meta.best(), wins = meta.wins();
  $('#bestT').textContent = wins ? `Expeditions won: ${wins} · best floor ${best}` : best ? `Best run: floor ${best}` : 'Runs take about five minutes';
  const ready = meta.packReady(), pb = $('#packBtn') as HTMLButtonElement;
  pb.innerHTML = `<b>Daily pack</b><span>${ready ? 'Ready to open' : 'Next in ' + meta.nextPackIn()}</span>`;
  pb.classList.toggle('ready', ready); pb.disabled = !ready;
  $('#collBtn').innerHTML = `<b>Collection</b><span>${own.length} / ${ROSTER.length}${meta.shinies().length ? ` · ${meta.shinies().length} ✦` : ''}</span>`;
  $('#shopBtn').innerHTML = `<b>Item shop</b><span>${meta.wallet().gold} gold</span>`;
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
  clearActors(); buildStage(); renderArtPicker(); showTitleActor(S.picks[0]);
}
export function toTitle() {
  S.tok++; S.mode = 'title'; clearActors(); setBiome(0);
  renderPicks(); renderArtPicker(); show('#scr-title'); measureBand(true); showTitleActor(S.picks[0]);
}

/* ================= packs (§11) ================= */
function showDailyPack() {
  const res = meta.openPack(); if (!res) { toTitle(); return; }
  showPack(res, 'Daily pack', 'One new friend a day', toTitle, true);
}
/** The card-flip reveal for any pack (daily or bought). */
/** `join` = true adds a new creature to the title-screen team if there's room (the daily pack only, so "Run again" keeps its team). */
function showPack(res: meta.PackResult, title: string, blurb: string, back: () => void, join = false) {
  S.mode = 'meta'; S.titleActor?.destroy(); S.titleActor = null;
  $('#scr-pack .logo h1').textContent = title; $('#scr-pack .logo p').textContent = blurb;
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
      txt.innerHTML = res.shiny ? `<p class="sub">${sp.name} now shines in every run.</p>` : `<p class="sub">${sp.name} joins your collection. Add it to your team on the title screen.</p>`;
    } else txt.innerHTML = '';
  };
  card.onclick = reveal; gsap.delayedCall(1.2, reveal);
  $('#packOk').onclick = () => {
    SFX.pick();
    if (join && k && !res.shiny && !S.picks.includes(k) && S.picks.length < BAL.lineup) S.picks.push(k);
    back();
  };
  show('#scr-pack'); measureBand(true);
}

/* ================= item shop (§5.3) ================= */
function showShop(back: () => void) {
  S.mode = 'meta';
  const w = meta.wallet(), again = () => showShop(back);
  $('#shopWallet').innerHTML = lootHTML(w);
  const buy = $('#shopBuy'), sell = $('#shopSell'); buy.innerHTML = ''; sell.innerHTML = '';
  const add = (box: HTMLElement, g: GlyphKey, t: string, sub: string, c: string, ok: boolean, fn: () => void) => {
    const b = nodeBtn(g, t, sub, c, fn); b.disabled = !ok; box.appendChild(b);
  };
  const paid = () => { SFX.caught(); haptic('success'); again(); };
  MATS.forEach(m => add(buy, m, `${MAT_DEF[m].name} · ${BAL.shopMat} gold`, `${MAT_DEF[m].track} upgrades · you have ${w[m]}`, MAT_DEF[m].color,
    w.gold >= BAL.shopMat, () => { if (meta.buyMat(m)) paid(); }));
  const empty = meta.packEmpty();
  add(buy, 'star', `Creature pack · ${BAL.shopPack} gold`, empty ? 'You own every creature and every shiny' : 'A creature you don’t own, else a shiny',
    'var(--gold)', !empty && w.gold >= BAL.shopPack, () => { const r = meta.buyPack(); if (r) showPack(r, 'Creature pack', 'Fresh from the shop', again); });
  MATS.forEach(m => add(sell, m, `Sell a ${MAT_DEF[m].name} · +${BAL.shopSell} gold`, `You have ${w[m]}`, MAT_DEF[m].color,
    w[m] > 0, () => { if (meta.sellMat(m)) paid(); }));
  ($('#shopBack') as HTMLButtonElement).onclick = () => { SFX.pick(); back(); };
  show('#scr-shop'); measureBand(true);
}

/* ================= collection & loadouts (§11, §16) ================= */
type Pending = { slot: 'skill' | 'sig'; i: number } | { trait: TraitKey } | null;
function showCollection() {
  S.mode = 'meta';
  const own = meta.owned(), grid = $('#collGrid'); grid.innerHTML = '';
  $('#collCount').textContent = `${own.length} / ${ROSTER.length}`;
  let cur = '', pending: Pending = null;
  const detail = (k: string) => {
    cur = k; pending = null;
    showTitleActor(k, { silhouette: !own.includes(k) });
    (grid as HTMLElement).querySelectorAll<HTMLElement>('.cslot').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.k === k)));
    render();
  };
  /** The unlock panel for a locked option: what it costs and an Unlock button (disabled if too poor). */
  const unlockBox = (what: string, c: { el: El; n: number }, onUnlock: () => boolean) => {
    const have = meta.essence()[c.el], box = document.createElement('div'); box.className = 'upchoice';
    box.innerHTML = `<p class="sub">${what}</p>`;
    const b = document.createElement('button'); b.className = 'big alt'; b.disabled = have < c.n;
    b.innerHTML = have < c.n ? `Unlock <small>· need ${c.n - have} more ${ELEM[c.el].name}</small>` : `Unlock <small>· ${c.n} ${ELEM[c.el].name} Essence</small>`;
    b.onclick = () => { if (!onUnlock()) return; SFX.caught(); haptic('success'); pending = null; render(); };
    box.appendChild(b); return box;
  };
  const render = () => {
    const k = cur, sp = SPECIES[k], has = own.includes(k), lo = meta.loadout(k), bo = meta.boosts(k);
    $('#collEss').innerHTML = essHTML(meta.essence()) + lootHTML(meta.wallet());
    const d = $('#collDetail');
    d.innerHTML = `<div class="prow"><span class="elchip" style="--c:${elCss(sp.el)}">${svg(sp.el)}${ELEM[sp.el].name}</span><span class="nm">${sp.name}${meta.isShiny(k) ? ' ✦' : ''}</span><span class="sp"></span><span class="lv">${sp.role} · ${has ? Math.round(sp.hp * bo.vital) : sp.hp} HP</span></div>
      ${has ? '' : '<p class="sub">Not found yet. Open a daily pack, or buy one in the item shop.</p>'}`;
    if (!has) {
      const cards = document.createElement('div'); cards.className = 'upcards';
      SLOTS.forEach(slot => { const c = document.createElement('div'); c.className = 'card mini'; c.style.setProperty('--c', elCss(sp.el)); c.innerHTML = cardFace(sp.cards![slot][0], sp.el); cards.appendChild(c); });
      d.appendChild(cards); return;
    }
    // card slots: one row each, options in columns
    SLOTS.forEach(slot => {
      const sec = document.createElement('div'); sec.className = 'loslot';
      sec.innerHTML = `<div class="eyebrow">${slot === 'strike' ? 'Strike' : slot === 'skill' ? 'Skill' : 'Signature'}</div>`;
      const cards = document.createElement('div'); cards.className = 'upcards lo';
      sp.cards![slot].forEach((def, i) => {
        const on = slot === 'strike' || (slot === 'skill' ? lo.skill : lo.sig) === i, open = meta.moveUnlocked(k, slot, i);
        const b = document.createElement('button'); b.className = 'card mini' + (open ? '' : ' locked'); b.style.setProperty('--c', elCss(sp.el));
        b.setAttribute('aria-pressed', String(on));
        if (pending && 'slot' in pending && pending.slot === slot && pending.i === i) b.classList.add('sel');
        b.innerHTML = cardFace(boostCard(def, bo.power, bo.spirit), sp.el) + (open ? '' : `<span class="lock">${costHTML(meta.moveCost(k))}</span>`);
        b.addEventListener('click', () => {
          if (slot === 'strike' || on) return;
          audio(); SFX.pick(); haptic('select');
          if (open) { meta.setMove(k, slot, i); pending = null; } else pending = { slot, i };
          render();
        });
        cards.appendChild(b);
      });
      sec.appendChild(cards);
      if (pending && 'slot' in pending && pending.slot === slot) {
        const p = pending, def = sp.cards![slot][p.i];
        sec.appendChild(unlockBox(`Unlock <b>${def.name}</b> for ${sp.name}'s ${slot === 'skill' ? 'Skill' : 'Signature'} slot.`, meta.moveCost(k),
          () => meta.unlockMove(k, p.slot, p.i) && meta.setMove(k, p.slot, p.i)));
      }
      d.appendChild(sec);
    });
    // Trait socket: built-in + learned Traits, then learnable ones (source owned) with their cost
    const sec = document.createElement('div'); sec.className = 'loslot';
    const t = lo.trait;
    sec.innerHTML = `<div class="eyebrow">Trait</div>` + (t ? `<div class="trait-on" style="--c:${elCss(SPECIES[TRAITS[t].from].el)}"><b>${TRAITS[t].name}</b><span>${TRAITS[t].text}</span></div>` : '');
    const opts = document.createElement('div'); opts.className = 'traits';
    const keys = Object.keys(TRAITS) as TraitKey[];
    const usable = keys.filter(x => meta.traitUsable(k, x)).sort((a, b) => +(b === sp.trait) - +(a === sp.trait)), learnable = keys.filter(x => !meta.traitUsable(k, x) && !meta.traitUnlocked(x) && own.includes(TRAITS[x].from));
    [...usable, ...learnable].forEach(x => {
      const def = TRAITS[x], open = usable.includes(x), holder = meta.traitHolder(x);
      const tag = !open ? costHTML(meta.traitCost(x)) : x === sp.trait ? 'Built-in' : holder && holder !== k && x !== t ? `moves from ${SPECIES[holder].name}` : `from ${SPECIES[def.from].name}`;
      const b = document.createElement('button'); b.className = 'trait' + (open ? '' : ' locked'); b.style.setProperty('--c', elCss(SPECIES[def.from].el));
      b.setAttribute('aria-pressed', String(x === t));
      if (pending && 'trait' in pending && pending.trait === x) b.classList.add('sel');
      b.innerHTML = `<b>${def.name}</b><span>${tag}</span>`;
      b.addEventListener('click', () => {
        if (x === t) return;
        audio(); SFX.pick(); haptic('select');
        if (open) { meta.setTrait(k, x); pending = null; } else pending = { trait: x };
        render();
      });
      opts.appendChild(b);
    });
    sec.appendChild(opts);
    const hidden = keys.filter(x => !own.includes(TRAITS[x].from)).length;
    if (hidden) sec.insertAdjacentHTML('beforeend', `<p class="note">${hidden} more Trait${hidden === 1 ? '' : 's'}: own the creature to learn ${hidden === 1 ? 'it' : 'them'}.</p>`);
    if (pending && 'trait' in pending) {
      const x = pending.trait, def = TRAITS[x];
      sec.appendChild(unlockBox(`Learn <b>${def.name}</b>: ${def.text}. Any one creature can socket it besides ${SPECIES[def.from].name}.`, meta.traitCost(x),
        () => meta.unlockTrait(x) && meta.setTrait(k, x)));
    }
    d.appendChild(sec);
    // permanent upgrades (§5.2): one track per material
    const ups = document.createElement('div'); ups.className = 'loslot';
    ups.innerHTML = '<div class="eyebrow">Upgrades</div>';
    const lv = meta.upgrades(k), w = meta.wallet();
    MATS.forEach(m => {
      const def = MAT_DEF[m], n = lv[m], cost = meta.upgradeCost(k, m);
      const row = document.createElement('div'); row.className = 'uptrack'; row.style.setProperty('--c', def.color);
      row.innerHTML = `<div class="prow">${svg(m)}<b>${def.track}</b><span class="sp"></span><span class="lv">Lv ${n} / ${BAL.upMax}</span></div>
        <div class="pips">${Array.from({ length: BAL.upMax }, (_, i) => `<i class="${i < n ? 'on' : ''}"></i>`).join('')}</div><p class="note">${def.text}</p>`;
      const b = document.createElement('button'); b.className = 'big alt';
      if (!cost) { b.disabled = true; b.textContent = 'Max level'; }
      else {
        b.disabled = w.gold < cost.gold || w[m] < cost[m];
        b.innerHTML = `Upgrade <small>· ${cost[m]} ${def.name}${cost[m] > 1 ? 's' : ''} + ${cost.gold} gold</small>`;
        b.onclick = () => { if (!meta.buyUpgrade(k, m)) return; audio(); SFX.caught(); haptic('success'); render(); };
      }
      row.appendChild(b); ups.appendChild(row);
    });
    d.appendChild(ups);
    d.querySelector('.upchoice')?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  };
  ROSTER.forEach(k => {
    const sp = SPECIES[k], has = own.includes(k);
    const b = btn('cslot' + (has ? '' : ' locked'), `<span class="orb">${has ? svg(sp.el) : '?'}</span><span>${has ? sp.name : '???'}${meta.isShiny(k) ? ' ✦' : ''}</span>`, () => detail(k), has ? elCss(sp.el) : 'var(--mute)');
    b.dataset.k = k; grid.appendChild(b);
  });
  show('#scr-coll'); measureBand(true);
  detail(own.includes(S.picks[0]) ? S.picks[0] : own[0]);
}

export function initRunUi() {
  $('#startBtn').addEventListener('click', startRun);
  $('#againBtn').addEventListener('click', () => { SFX.pick(); startRun(); });
  $('#titleBtn').addEventListener('click', () => { SFX.pick(); toTitle(); });
  $('#lineupBtn').addEventListener('click', () => { SFX.pick(); showParty(() => showMap(false)); });
  $('#packBtn').addEventListener('click', () => { audio(); SFX.pick(); showDailyPack(); });
  $('#collBtn').addEventListener('click', () => { audio(); SFX.pick(); showCollection(); });
  $('#collBack').addEventListener('click', () => { SFX.pick(); toTitle(); });
  $('#shopBtn').addEventListener('click', () => { audio(); SFX.pick(); showShop(toTitle); });
  $('#endShopBtn').addEventListener('click', () => { SFX.pick(); showShop(backToEnd); });
  S.picks = meta.lastLineup();
}
