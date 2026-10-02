// PixiJS application, world layers and shared effect textures.
// Art styles draw INTO these layers; they never create their own app.
import { Application, Container, Texture } from 'pixi.js';

export const app = new Application();
export const world = new Container();   // shaken by screen shake
export const L = {
  bg: new Container(),      // scene: sky, far background (art style)
  deco: new Container(),    // scene: props in front of the background (art style)
  plat: new Container(),    // pedestals under creatures (art style)
  actors: new Container(),  // creatures
  front: new Container(),   // particles
  glow: new Container(),    // projectiles, rings, bloom, shield
};

export function canvasTex(w: number, h: number, draw: (g: CanvasRenderingContext2D, w: number, h: number) => void) {
  const c = document.createElement('canvas'); c.width = Math.max(1, w); c.height = Math.max(1, h);
  draw(c.getContext('2d')!, w, h); return Texture.from(c);
}

/** Effect textures (style-independent). TS = visible diameter in px, used to size sprites in world units. */
export const TEX = {} as Record<'glow' | 'soft' | 'spark' | 'leaf' | 'star' | 'ring', Texture>;
export const TS = { glow: 64, soft: 128, spark: 16, leaf: 24, star: 40, ring: 108 };
export type TexName = keyof typeof TS;

function buildTextures() {
  TEX.glow = canvasTex(64, 64, g => { const r = g.createRadialGradient(32, 32, 0, 32, 32, 32); r.addColorStop(0, 'rgba(255,255,255,1)'); r.addColorStop(0.22, 'rgba(255,255,255,.85)'); r.addColorStop(0.55, 'rgba(255,255,255,.2)'); r.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = r; g.fillRect(0, 0, 64, 64); });
  TEX.soft = canvasTex(128, 128, g => { const r = g.createRadialGradient(64, 64, 0, 64, 64, 64); r.addColorStop(0, 'rgba(255,255,255,.9)'); r.addColorStop(0.4, 'rgba(255,255,255,.35)'); r.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = r; g.fillRect(0, 0, 128, 128); });
  TEX.spark = canvasTex(64, 16, g => { const r = g.createLinearGradient(0, 0, 64, 0); r.addColorStop(0, 'rgba(255,255,255,0)'); r.addColorStop(0.7, 'rgba(255,255,255,.9)'); r.addColorStop(1, 'rgba(255,255,255,1)'); g.fillStyle = r; g.beginPath(); g.ellipse(32, 8, 32, 5, 0, 0, Math.PI * 2); g.fill(); });
  TEX.leaf = canvasTex(32, 32, g => { g.fillStyle = '#fff'; g.beginPath(); g.moveTo(4, 16); g.quadraticCurveTo(16, 0, 28, 16); g.quadraticCurveTo(16, 32, 4, 16); g.fill(); });
  TEX.star = canvasTex(48, 48, g => { g.fillStyle = '#fff'; g.shadowColor = '#fff'; g.shadowBlur = 6; g.beginPath(); for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4, r = i % 2 ? 6 : 20; g.lineTo(24 + Math.cos(a) * r, 24 + Math.sin(a) * r); } g.closePath(); g.fill(); });
  TEX.ring = canvasTex(128, 128, g => { g.strokeStyle = '#fff'; g.lineWidth = 6; g.shadowColor = '#fff'; g.shadowBlur = 10; g.beginPath(); g.arc(64, 64, 54, 0, Math.PI * 2); g.stroke(); });
}

export async function initApp(canvas: HTMLCanvasElement) {
  await app.init({ canvas, resizeTo: window, antialias: true, autoDensity: true,
    resolution: Math.min(window.devicePixelRatio || 1, 2), background: 0x0a0f1f, powerPreference: 'high-performance' });
  app.stage.addChild(world);
  Object.values(L).forEach(c => world.addChild(c));
  buildTextures();
}
