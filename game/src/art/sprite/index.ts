// Image-based art style built from a "pack": a folder of PNG/WebP files plus a manifest.
// This is where AI-generated or hand-drawn art plugs in. Creatures missing from a pack
// fall back to another style, so a pack can be filled in one creature at a time.
import { Container, Sprite, Texture } from 'pixi.js';
import { ELEM, EL_KEYS, type El } from '../../core/data';
import type { ArtStyle, Ambience, CreatureArt, PedestalArt, Pt, SceneArt } from '../types';
import { paintedScene, paintedPedestal, NIGHT, type ScenePalette } from '../shared/painter';
import { mix } from '../sticker/creature';
import { recolorPixels, isIdentity, type Recolor } from './recolor';
export type { Recolor } from './recolor';

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
  /** Ember-coloured art: bake a hue-remapped copy per element instead of tinting (see recolor.ts).
   *  `true` uses the defaults. Wins over `tintByElement`; `variants` still win over both. */
  recolor?: Recolor | true;
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
  /** Pixel art: sample every texture nearest-neighbour so pixels stay crisp. */
  pixelArt?: boolean;
  /** Code-built background, instead of `scene`/`sceneB` (procedural packs, e.g. hd2d). */
  sceneArt?: (biome: number) => SceneArt;
  /** Code-built pedestal, instead of `pedestal`. */
  pedestalArt?: () => PedestalArt;
}

function loadImage(url: string): Promise<HTMLImageElement> {
  return new Promise((res, rej) => {
    const img = new Image(); img.onload = () => res(img); img.onerror = () => rej(new Error('Failed to load ' + url)); img.src = url;
  });
}

/** Draw an image to a canvas, recolour its pixels for `el`, and return it as a texture. */
function bakeRecolor(img: HTMLImageElement, el: El, o: Recolor): Texture {
  const c = document.createElement('canvas'); c.width = img.naturalWidth; c.height = img.naturalHeight;
  const g = c.getContext('2d', { willReadFrequently: true })!; g.drawImage(img, 0, 0);
  const d = g.getImageData(0, 0, c.width, c.height); recolorPixels(d.data, el, o); g.putImageData(d, 0, 0);
  return Texture.from(c);
}

/** Texture lookup for creatures: a pack file, or that file recoloured for an element. */
type TexFor = (file: string, el?: El, recolor?: Recolor) => Texture | undefined;

class SpriteCreature implements CreatureArt {
  view = new Container();
  head: Pt = { x: 0, y: 0 };
  emitters: Pt[] = [];
  private sprite: Sprite;
  constructor(private e: SpriteEntry, private tex: TexFor, el: El) {
    this.sprite = new Sprite(); this.view.addChild(this.sprite); this.setElement(el);
  }
  setElement(el: El) {
    const e = this.e, variant = e.variants?.[el], rc = !variant && e.recolor ? (e.recolor === true ? {} : e.recolor) : undefined;
    const t = (variant && this.tex(variant)) || this.tex(e.image, el, rc) || this.tex(e.image)!;
    const s = this.sprite; s.texture = t;
    const [ax, ay] = e.anchor ?? [0.5, 1]; s.anchor.set(ax, ay);
    const k = (e.height ?? 125) / t.height; s.scale.set(k);
    s.tint = !variant && !rc && e.tintByElement ? mix(0xffffff, ELEM[el].hex, 0.55) : 0xffffff;
    const toArt = ([fx, fy]: [number, number]) => ({ x: (fx - ax) * t.width * k, y: (fy - ay) * t.height * k });
    this.head = toArt(e.head ?? [0.55, 0.45]);
    this.emitters = (e.emitters ?? []).map(toArt);
  }
  destroy() { this.view.destroy({ children: true }); }
}

export function spritePackStyle(m: PackManifest, files: Record<string, string>, fallback: ArtStyle): ArtStyle {
  const textures = new Map<string, Texture>();
  const images = new Map<string, HTMLImageElement>();
  const baked = new Map<string, Texture>();
  const crisp = (t: Texture) => { if (m.pixelArt) t.source.scaleMode = 'nearest'; return t; };
  const palOf = (sc?: SceneSpec): ScenePalette => ({ ...NIGHT, ...(sc?.palette || {}), pedestal: { ...NIGHT.pedestal, ...(sc?.palette?.pedestal || {}) } });
  const pal = palOf(m.scene);
  const tex = (f: string) => textures.get(f);
  /** Recoloured copies are baked once per (file, element, options) and cached for the session. */
  const texFor: TexFor = (f, el, rc) => {
    if (!el || !rc || isIdentity(el, rc) || !images.has(f)) return tex(f);
    const key = `${f}|${el}|${JSON.stringify(rc)}`;
    let t = baked.get(key);
    if (!t) { t = crisp(bakeRecolor(images.get(f)!, el, rc)); baked.set(key, t); }
    return t;
  };
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
        const img = await loadImage(files[f]); images.set(f, img); textures.set(f, crisp(Texture.from(img)));
      }));
      // Bake every element's recolour now, so a mid-fight element shift (the boss) never hitches.
      for (const c of Object.values(m.creatures)) if (c.recolor) for (const el of EL_KEYS) texFor(c.image, el, c.recolor === true ? {} : c.recolor);
      await fallback.preload();
    },
    creature(species, el) {
      const e = m.creatures[species];
      return e && tex(e.image) ? new SpriteCreature(e, texFor, el) : fallback.creature(species, el);
    },
    scene: biome => m.sceneArt ? m.sceneArt(biome) : sceneFor(biome && m.sceneB ? m.sceneB : m.scene),
    pedestal: () => m.pedestalArt ? m.pedestalArt() : paintedPedestal(pal, m.pedestal?.image ? tex(m.pedestal.image) : undefined),
  };
}
