// Discovers every pack under art/packs/<id>/ (manifest.ts + image files) at build time.
// Vite inlines the images into the single-file build, so the iOS app works offline.
import type { PackManifest } from '../sprite';
import { spritePackStyle } from '../sprite';
import { stickerStyle } from '../sticker';

const manifests = import.meta.glob('./*/manifest.ts', { eager: true, import: 'default' }) as Record<string, PackManifest>;
const files = import.meta.glob('./*/*.{png,webp,jpg,jpeg}', { eager: true, query: '?url', import: 'default' }) as Record<string, string>;

export const packStyles = Object.entries(manifests).map(([path, manifest]) => {
  const dir = path.split('/')[1];
  const own: Record<string, string> = {};
  for (const [p, url] of Object.entries(files)) if (p.startsWith(`./${dir}/`)) own[p.slice(dir.length + 3)] = url;
  return spritePackStyle(manifest, own, stickerStyle);
});
