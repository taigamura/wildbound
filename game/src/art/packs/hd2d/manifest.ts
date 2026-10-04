// HD-2D: low-resolution pixel-art sprites in a lit, painterly diorama (CLAUDE.md §13).
//
// PLACEHOLDER CAST. Only the three HD-2D anchors exist so far (docs/hd2d/anchors/, stored
// here at their true pixel resolution: the anchors are exact ×3 nearest upscales). Every
// species reuses one of them, recoloured per element at load time (`recolor`, see
// art/sprite/recolor.ts). Within each element in SPECIES: 1st → fox (biped), 2nd → Sable
// (humanoid), 3rd, the tank → dragon (quadruped). To swap in a real sprite later, drop
// `<species>.png` (normalized with scripts/hd2d-sprite.py, then downscaled to its true grid)
// into this folder and point that entry's `image`/`anchor`/`head`/`height` at it; drop
// `recolor` if the sprite is already painted in its own element.
//
// Heights: the canvas height in art units, so that the FIGURE is 128 units tall for the
// humanoid and 100 for a size-1 monster (docs/HD2D.md); the Actor multiplies by species size.
// The background and pedestal are procedural (scene.ts): no image files.
import type { PackManifest, SpriteEntry } from '../../sprite';
import type { Recolor } from '../../sprite/recolor';
import { hd2dScene, hd2dPedestal } from './scene';

/** Sable keeps her skin and gold trim: only the hair, coat lining and lantern glass shift. */
const HUMAN: Recolor = { maxHue: 10, minSat: 0.55 };

const fox = (): SpriteEntry => ({ image: 'fox.png', anchor: [0.606, 0.904], height: 124, head: [0.64, 0.34], emitters: [[0.52, 0.1], [0.23, 0.55]], recolor: true });
const sable = (): SpriteEntry => ({ image: 'sable.png', anchor: [0.469, 0.905], height: 158, head: [0.57, 0.25], emitters: [[0.38, 0.69]], recolor: HUMAN });
// The anchor script puts the dragon's feet at its front claws (0.762); 0.6 centres the body on the pedestal.
const dragon = (recolor: Recolor | true = true, height = 124): SpriteEntry => ({ image: 'dragon.png', anchor: [0.6, 0.904], height, head: [0.77, 0.33], recolor });

const manifest: PackManifest = {
  id: 'hd2d',
  name: 'HD-2D',
  blurb: 'Pixel sprites in a lit diorama',
  pixelArt: true,
  creatures: {
    emberwick: fox(), cinderpip: sable(), kilnback: dragon(),
    bellspring: fox(), puddlet: sable(), brinecrab: dragon(),
    truffmole: fox(), brambat: sable(), mossling: dragon(),
    skiray: fox(), sparkit: sable(), coilsnail: dragon(),
    // Gravewood: deeper, mossier green than Mossling, and 8% larger on top of its species size.
    warden: dragon({ ramps: { thorn: [195, 168, 142, 104] }, light: 0.66, sat: 0.85, wash: [0.8, 0.9, 0.74] }, 134),
    // Noctyrm: a night-washed version of whichever element it currently holds.
    noctyrm: dragon({ light: 0.74, sat: 1.1, wash: [0.8, 0.7, 1] }),
  },
  sceneArt: hd2dScene,
  pedestalArt: hd2dPedestal,
  ambience: { fireflies: [0xffe6a8, 0xffd27a, 0xfff6dc], leaves: [0x8fbf5a, 0xd9a441, 0x6e9e48], neutral: 0xffd9a0 },
  cssVars: { '--panel': 'rgba(22,20,34,.86)', '--line': 'rgba(255,226,170,.18)', '--neutral': '#ffd9a0' },
};

export default manifest;
