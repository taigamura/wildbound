// Entry point: boots Pixi, loads the art style, wires modules and runs the frame loop.
import './style.css';
import gsap from 'gsap';
import { app, initApp } from './render/app';
import { U, measureBand, easeLayout, EPOS, PPOS, TPOS } from './render/layout';
import { initParticles, updateParticles, ambient } from './render/particles';
import { feel, applyShake } from './render/fx';
import { initShield, updateShield } from './render/actor';
import { buildStage, resizeStage, updateScene, pedE, pedP, arenaTint } from './render/stage';
import { getStyle, useStyle, initialStyleId } from './art/registry';
import { S, act, activeActor } from './game/state';
import { initHud, syncHUD } from './game/ui';
import { playCard, swapTo, tryCapture, tickBattle } from './game/battle';
import { initRunUi, toTitle } from './game/run';
import { SPECIES } from './core/data';
import { $ } from './core/util';
import { audio } from './core/audio';
import { notifyReady } from './core/platform';

let T = 0;
function frame(tk: { deltaMS: number }) {
  const real = Math.min(tk.deltaMS / 1000, 0.05); let dt = real;
  // hit-stop: slow the whole world (sim, particles, tweens) for a few frames on big hits
  if (feel.hitStop > 0) { feel.hitStop -= real; dt *= 0.06; gsap.globalTimeline.timeScale(0.06); }
  else gsap.globalTimeline.timeScale(1);
  T += dt; easeLayout(real);

  tickBattle(dt, T);
  const amb = getStyle().ambience; ambient(dt, amb.fireflies, amb.leaves);
  updateParticles(dt);
  updateScene(T, dt);

  const E = EPOS(), P = PPOS(), tint = arenaTint();
  // pedestals
  if (pedE) { pedE.view.visible = !!S.em; if (S.em) pedE.update(E.x, E.y, U * 1.05 * S.em.extra * SPECIES[S.em.key].size, tint, T); }
  if (pedP) {
    const pa = S.mode === 'title' ? S.titleActor : activeActor();
    pedP.view.visible = !!pa;
    if (pa) { const pos = S.mode === 'title' ? TPOS() : P; pedP.update(pos.x, pos.y, U * 1.05 * pa.extra * SPECIES[pa.key].size, tint, T); }
  }
  // actors
  if (S.em) { S.em.place(E.x, E.y, -1); S.em.update(dt); }
  Object.values(S.actors).forEach(a => { if (!a.visible) return; a.place(P.x, P.y, 1); a.update(dt); });
  if (S.titleActor) { const t = TPOS(); S.titleActor.place(t.x, t.y, Math.sin(T * 0.6) > 0 ? 1 : -1); S.titleActor.update(dt); }
  updateShield(activeActor(), act()?.shield ?? 0, S.mode !== 'title', T);

  applyShake(real, U);
  if (S.mode === 'battle' || S.mode === 'anim' || S.mode === 'intro' || S.mode === 'end') syncHUD();
}

async function boot() {
  await initApp($('#gl'));
  initParticles(); initShield();
  measureBand(true);
  await useStyle(initialStyleId());
  buildStage();
  initHud(playCard, i => swapTo(i), tryCapture);
  initRunUi();
  if (new URLSearchParams(location.search).has('export-pack')) {
    const { exportPack } = await import('./tools/exportPack');
    await exportPack(undefined, 3, !(window as any).__noDownload);
  }
  toTitle();
  app.ticker.add(frame);
  addEventListener('resize', () => { measureBand(true); resizeStage(); });
  document.addEventListener('contextmenu', e => e.preventDefault());
  document.addEventListener('pointerdown', () => audio(), { once: true });
  notifyReady();
  if (import.meta.env.DEV) (window as any).__wb = S;
}
boot();
