// Dusk: a sample image-based art pack.
//
// The PNGs here were baked from the procedural creatures with the exporter
// (open the game with ?export-pack) in flat mode, so they show the exact framing
// the game expects. Replace any PNG with your own art (AI-generated or drawn),
// keep it facing RIGHT, and adjust that creature's anchor/head/height below.
// Creatures you leave out fall back to the Sticker style.
import type { PackManifest } from '../../sprite';

const manifest: PackManifest = {
  id: 'dusk',
  name: 'Dusk',
  blurb: 'Flat image pack, sunset meadow',
  creatures: {
    cindrel: { image: 'cindrel.png', anchor: [0.62, 0.914], height: 162, head: [0.671, 0.568], emitters: [[0.114, 0.519], [0.658, 0.074]] },
    magmaw: { image: 'magmaw.png', anchor: [0.575, 0.914], height: 162, head: [0.632, 0.568], emitters: [[0.618, 0.074]] },
    plipp: { image: 'plipp.png', anchor: [0.572, 0.903], height: 144, head: [0.619, 0.514] },
    brinehorn: { image: 'brinehorn.png', anchor: [0.45, 0.907], height: 150, head: [0.51, 0.533] },
    sproutle: { image: 'sproutle.png', anchor: [0.5, 0.911], height: 157, head: [0.567, 0.553] },
    barkback: { image: 'barkback.png', anchor: [0.575, 0.911], height: 157, head: [0.632, 0.553] },
    zapling: { image: 'zapling.png', anchor: [0.62, 0.911], height: 157, head: [0.671, 0.554], emitters: [[0.519, 0.096], [0.797, 0.096]] },
    joltusk: { image: 'joltusk.png', anchor: [0.612, 0.911], height: 157, head: [0.664, 0.554], emitters: [[0.509, 0.096], [0.793, 0.096]] },
    noctyrm: { image: 'noctyrm-ember.png', anchor: [0.62, 0.907], height: 150, head: [0.671, 0.533], emitters: [[0.114, 0.48]], variants: { ember: 'noctyrm-ember.png', tide: 'noctyrm-tide.png', thorn: 'noctyrm-thorn.png', volt: 'noctyrm-volt.png' } },
  },
  scene: {
    // To use a painted background instead, add e.g. `image: 'background.png', horizon: 0.42`.
    palette: {
      sky: ['#3a1f5c', '#b4507a', '#f4a261'],
      celestial: 'sun', celestialColor: '#ffd79a', celestialGlow: 'rgba(255,190,120,.45)',
      stars: 25, twinkleColors: [0xffe0b0, 0xffffff],
      hills: ['#7a3a6b', '#5c2c5c'], trees: '#3d1f45',
      ground: ['#4b2a55', '#3a2047', '#22132e'], grass: 'rgba(255,190,160,.14)',
      crystalColors: [0xffb38a, 0xff7aa8, 0xffd36e],
      mushroomColors: [0xffd36e, 0xff8fb0, 0xb48cff],
      pedestal: { top: 0x5b3566, rim: 0x7d4a86, inner: 0x6a3e74, shadow: 0x1a0d22 },
    },
  },
  ambience: { fireflies: [0xffd36e, 0xffb38a, 0xffffff], leaves: [0xff8fb0, 0xffb38a, 0xc86b98], neutral: 0xffb38a },
};

export default manifest;
