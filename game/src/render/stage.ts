// The stage: the active style's scene plus the two pedestals, and the arena tint.
// Rebuilt whenever the art style changes.
import { L } from './app';
import { size, horizon } from './layout';
import { getStyle } from '../art/registry';
import type { SceneArt, PedestalArt } from '../art/types';

let scene: SceneArt | null = null;
export let pedE: PedestalArt | null = null;
export let pedP: PedestalArt | null = null;
let tint = 0x9b7bff;

export const tintArena = (hex: number) => { tint = hex; };
export const arenaTint = () => tint;

export function buildStage() {
  scene?.destroy(); pedE?.destroy(); pedP?.destroy();
  L.bg.removeChildren(); L.deco.removeChildren();
  const st = getStyle();
  scene = st.scene(); scene.mount(L.bg, L.deco); scene.resize(size.W, size.H, horizon());
  pedE = st.pedestal(); pedP = st.pedestal(); L.plat.addChild(pedE.view, pedP.view);
  tint = st.ambience.neutral;
}
export function resizeStage() { scene?.resize(size.W, size.H, horizon()); }
export function updateScene(t: number, dt: number) { scene?.update(t, dt); }
