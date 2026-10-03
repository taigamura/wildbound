// Dusk: a sample image-based art pack.
//
// The PNGs here were baked from the procedural creatures with the exporter
// (open the game with ?export-pack) in flat mode, so they show the exact framing
// the game expects. Replace any PNG with your own art (AI-generated or drawn),
// keep it facing RIGHT, and adjust that creature's anchor/head/height below.
// Creatures you leave out fall back to the Sticker style (Cinderpip, Puddlet,
// Brambat, Sparkit and the Warden currently do). Evolutions with no image are
// drawn as the base art, scaled up with a glow.
import type { PackManifest } from '../../sprite';

const manifest: PackManifest = {
  id: 'dusk',
  name: 'Dusk',
  blurb: 'Flat image pack, sunset meadow',
  creatures: {
    emberwick: { image: 'emberwick.png', anchor: [0.62, 0.914], height: 162, head: [0.671, 0.568], emitters: [[0.114, 0.519], [0.658, 0.074]] },
    kilnback: { image: 'kilnback.png', anchor: [0.575, 0.914], height: 162, head: [0.632, 0.568], emitters: [[0.618, 0.074]] },
    bellspring: { image: 'bellspring.png', anchor: [0.572, 0.903], height: 144, head: [0.619, 0.514] },
    brinecrab: { image: 'brinecrab.png', anchor: [0.45, 0.907], height: 150, head: [0.51, 0.533] },
    truffmole: { image: 'truffmole.png', anchor: [0.5, 0.911], height: 157, head: [0.567, 0.553] },
    mossling: { image: 'mossling.png', anchor: [0.575, 0.911], height: 157, head: [0.632, 0.553] },
    skiray: { image: 'skiray.png', anchor: [0.62, 0.911], height: 157, head: [0.671, 0.554], emitters: [[0.519, 0.096], [0.797, 0.096]] },
    coilsnail: { image: 'coilsnail.png', anchor: [0.612, 0.911], height: 157, head: [0.664, 0.554], emitters: [[0.509, 0.096], [0.793, 0.096]] },
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
  sceneB: {
    palette: {
      sky: ['#1f2350', '#4a3a7a', '#c07a8a'],
      celestial: 'moon', celestialColor: '#ffe9c8', celestialGlow: 'rgba(255,200,170,.35)',
      stars: 80, twinkleColors: [0xffe0b0, 0xffffff],
      hills: ['#3a2a5c', '#2c2048'], trees: '#1c1430',
      ground: ['#2e2450', '#241c40', '#140f26'], grass: 'rgba(200,170,255,.14)',
      crystalColors: [0x8fe3ff, 0xb48cff, 0xffd36e],
      mushroomColors: [0x8fe3ff, 0xff8fb0, 0xb48cff],
      pedestal: { top: 0x3a2d63, rim: 0x5a4790, inner: 0x46377a, shadow: 0x0d0a1a },
    },
  },
  ambience: { fireflies: [0xffd36e, 0xffb38a, 0xffffff], leaves: [0xff8fb0, 0xffb38a, 0xc86b98], neutral: 0xffb38a },
};

export default manifest;
