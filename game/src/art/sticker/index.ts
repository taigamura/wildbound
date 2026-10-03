// The default style: procedural sticker creatures on a moonlit night scene.
import type { ArtStyle } from '../types';
import { StickerCreature } from './creature';
import { paintedScene, paintedPedestal, NIGHT, EMBERGLOW } from '../shared/painter';

export const stickerStyle: ArtStyle = {
  id: 'sticker',
  name: 'Sticker',
  blurb: 'Outlined vector creatures, moonlit night',
  async preload() { /* procedural: nothing to load */ },
  creature: (species, el) => new StickerCreature(species, el),
  has: () => true,
  scene: biome => paintedScene(biome ? EMBERGLOW : NIGHT),
  pedestal: () => paintedPedestal(NIGHT),
  ambience: { fireflies: [0x9b7bff, 0x6ef3ff, 0xffcf6b, 0xc8ffd9], leaves: [0x6c5ad6, 0x4fcf5c, 0xb48cff], neutral: 0x9b7bff },
};
