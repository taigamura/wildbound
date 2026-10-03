// Image-based art style built from a "pack": a folder of PNG/WebP files plus a manifest.
// This is where AI-generated or hand-drawn art plugs in. Creatures missing from a pack
// fall back to another style, so a pack can be filled in one creature at a time.
import { Container, Sprite, Texture } from 'pixi.js';
import { ELEM, type El } from '../../core/data';
import type { ArtStyle, Ambience, CreatureArt, Pt } from '../types';
import { paintedScene, paintedPedestal, NIGHT, type ScenePalette } from '../shared/painter';
import { mix } from '../sticker/creature';

export interface SpriteEntry {
  /** File name inside the pack folder. Art should face RIGHT. */
  image: string;
  /** Where the feet are, as a fraction of the image (default [0.5, 1] = bottom centre). */
  anchor?: [number, number];
  /** Drawn height in art units. A size-1 creature is ~125 including ears/horns (default 125). */
  height?: number;
  /** Head point as a fraction of the image (projectile target). Default [0.55, 0.45]. */
  head?: [number, number];
  /** Ambient particle emitters as fractions of the image (flame tips etc.). */
  emitters?: [number, number][];
  /** Per-element replacement images, e.g. for the element-shifting boss. */
  variants?: Partial<Record<El, string>>;
  /** If no variant exists for an element, tint the image toward that element's colour. */
  tintByElement?: boolean;
}

export interface SceneSpec { image?: string; horizon?: number; palette?: Partial<ScenePalette> }
export interface PackManifest {
  id: string;
  name: string;
  blurb: string;
  creatures: Record<string, SpriteEntry>;
  /** Background: an image (cover-fit; `horizon` = fraction of image height where the ground starts), or a palette for the painted scene. */
  scene?: SceneSpec;
  /** Biome B background (floors 5–8). Defaults to `scene`. */
  sceneB?: SceneSpec;
  pedestal?: { image?: string };
  ambience?: Partial<Ambience>;
  cssVars?: Record<string, string>;
}

function loadImage(url: string): Promise<Texture> {
  return new Promise((res, rej) => {
    const img = new Image(); img.onload = () => res(Texture.from(img)); img.onerror = () => rej(new Error('Failed to load ' + url)); img.src = url;
  });
}

class SpriteCreature implements CreatureArt {
  view = new Container();
  head: Pt = { x: 0, y: 0 };
  emitters: Pt[] = [];
  private sprite: Sprite;
  constructor(private e: SpriteEntry, private tex: (file: string) => Texture | undefined, el: El) {
    this.sprite = new Sprite(); this.view.addChild(this.sprite); this.setElement(el);
  }
  setElement(el: El) {
    const e = this.e, file = e.variants?.[el] ?? e.image, t = this.tex(file) ?? this.tex(e.image)!;
    const s = this.sprite; s.texture = t;
    const [ax, ay] = e.anchor ?? [0.5, 1]; s.anchor.set(ax, ay);
    const k = (e.height ?? 125) / t.height; s.scale.set(k);
    s.tint = !e.variants?.[el] && e.tintByElement ? mix(0xffffff, ELEM[el].hex, 0.55) : 0xffffff;
    const toArt = ([fx, fy]: [number, number]) => ({ x: (fx - ax) * t.width * k, y: (fy - ay) * t.height * k });
    this.head = toArt(e.head ?? [0.55, 0.45]);
    this.emitters = (e.emitters ?? []).map(toArt);
  }
  destroy() { this.view.destroy({ children: true }); }
}

export function spritePackStyle(m: PackManifest, files: Record<string, string>, fallback: ArtStyle): ArtStyle {
  const textures = new Map<string, Texture>();
  const palOf = (sc?: SceneSpec): ScenePalette => ({ ...NIGHT, ...(sc?.palette || {}), pedestal: { ...NIGHT.pedestal, ...(sc?.palette?.pedestal || {}) } });
  const pal = palOf(m.scene);
  const tex = (f: string) => textures.get(f);
  const sceneFor = (sc?: SceneSpec) => paintedScene(palOf(sc), sc?.image && tex(sc.image) ? { tex: tex(sc.image)!, horizon: sc.horizon ?? 0.4 } : undefined);
  return {
    id: m.id, name: m.name, blurb: m.blurb, cssVars: m.cssVars,
    ambience: { ...fallback.ambience, ...(m.ambience || {}) },
    async preload() {
      const needed = new Set<string>();
      Object.values(m.creatures).forEach(c => { needed.add(c.image); Object.values(c.variants || {}).forEach(v => v && needed.add(v)); });
      if (m.scene?.image) needed.add(m.scene.image);
      if (m.sceneB?.image) needed.add(m.sceneB.image);
      if (m.pedestal?.image) needed.add(m.pedestal.image);
      await Promise.all([...needed].filter(f => !textures.has(f)).map(async f => {
        if (!files[f]) { console.warn(`[art:${m.id}] missing file ${f}`); return; }
        textures.set(f, await loadImage(files[f]));
      }));
      await fallback.preload();
    },
    has: species => !!(m.creatures[species] && tex(m.creatures[species].image)),
    creature(species, el) {
      const e = m.creatures[species];
      return e && tex(e.image) ? new SpriteCreature(e, tex, el) : fallback.creature(species, el);
    },
    scene: biome => sceneFor(biome && m.sceneB ? m.sceneB : m.scene),
    pedestal: () => paintedPedestal(pal, m.pedestal?.image ? tex(m.pedestal.image) : undefined),
  };
}
