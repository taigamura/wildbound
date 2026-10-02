// Dev tool: bake the procedural creatures into a sprite pack (PNG per creature + manifest).
// Open the game with ?export-pack in a browser. Useful as a template for AI-generated art:
// it shows the expected canvas framing, feet anchor, head point and emitter positions.
import { Container, Rectangle } from 'pixi.js';
import { app } from '../render/app';
import { StickerCreature, type StickerOpts } from '../art/sticker/creature';
import { SPECIES, EL_KEYS, type El } from '../core/data';
import type { SpriteEntry } from '../art/sprite';

export interface ExportedPack { files: Record<string, string>; creatures: Record<string, SpriteEntry> }

export async function exportPack(opts: StickerOpts = { outline: false, glow: false, shine: false }, scale = 3, download = true): Promise<ExportedPack> {
  const files: Record<string, string> = {}, creatures: Record<string, SpriteEntry> = {};
  for (const key of Object.keys(SPECIES)) {
    const sp = SPECIES[key];
    const els: El[] = sp.boss ? EL_KEYS : [sp.el];
    let entry: SpriteEntry | null = null;
    for (const el of els) {
      const art = new StickerCreature(key, el, opts), holder = new Container();
      art.view.scale.set(scale); holder.addChild(art.view);
      const b = holder.getLocalBounds(), pad = 8 * scale;
      const frame = new Rectangle(Math.floor(b.x - pad), Math.floor(b.y - pad), Math.ceil(b.width + pad * 2), Math.ceil(b.height + pad * 2));
      const canvas = app.renderer.extract.canvas({ target: holder, frame, resolution: 1, clearColor: '#00000000' }) as HTMLCanvasElement;
      const file = sp.boss ? `${key}-${el}.png` : `${key}.png`;
      files[file] = canvas.toDataURL('image/png');
      const norm = (x: number, y: number): [number, number] => [+((x * scale - frame.x) / frame.width).toFixed(3), +((y * scale - frame.y) / frame.height).toFixed(3)];
      if (!entry) entry = { image: file, anchor: norm(0, 0), height: Math.round(frame.height / scale), head: norm(art.head.x, art.head.y), emitters: art.emitters.map(p => norm(p.x, p.y)) };
      if (sp.boss) (entry.variants ||= {})[el] = file;
      art.destroy(); holder.destroy();
    }
    creatures[key] = entry!;
  }
  const result = { files, creatures };
  (window as any).__pack = result;
  if (download) {
    const save = (name: string, href: string) => { const a = document.createElement('a'); a.href = href; a.download = name; a.click(); };
    Object.entries(files).forEach(([n, url]) => save(n, url));
    save('creatures.json', URL.createObjectURL(new Blob([JSON.stringify(creatures, null, 2)], { type: 'application/json' })));
  }
  console.log('[export-pack] done:', Object.keys(files).length, 'images');
  return result;
}
