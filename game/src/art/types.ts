// The art-style contract. Everything visual that is "the look" goes through here;
// gameplay, particles, layout and animation never depend on a specific style.
//
// ART SPACE (what a CreatureArt draws in):
//   - facing RIGHT (the enemy is mirrored by the game)
//   - feet at (0, 0), up is negative y
//   - a size-1 creature is about 100 units tall, head around y = -56
// The game scales art space to the screen and to each species' `size`.
import type { Container } from 'pixi.js';
import type { El } from '../core/data';

export interface Pt { x: number; y: number }

export interface CreatureArt {
  /** Drawn in art space. Added to the actor's squash/stretch container. */
  view: Container;
  /** Where projectiles hit and damage numbers appear (art space). */
  head: Pt;
  /** Points that occasionally emit ambient element particles (flame tips, antennae). */
  emitters: Pt[];
  /** Recolour or swap the art for another element (the boss shifts elements mid-fight). */
  setElement(el: El): void;
  /** Optional style-owned idle detail: blinking, flicker, wing flaps. */
  update?(dt: number, t: number): void;
  destroy(): void;
}

export interface SceneArt {
  mount(bg: Container, deco: Container): void;
  /** Called on start and on every resize. `horizon` is the y creatures stand below. */
  resize(W: number, H: number, horizon: number): void;
  update(t: number, dt: number): void;
  destroy(): void;
}

export interface PedestalArt {
  view: Container;
  /** x/y is the creature's feet, width in px, tint = current arena colour. */
  update(x: number, y: number, width: number, tint: number, t: number): void;
  destroy(): void;
}

export interface Ambience {
  fireflies: number[];   // colours of ambient motes
  leaves: number[];      // colours of drifting leaves
  neutral: number;       // arena tint when no enemy is present
}

export interface ArtStyle {
  id: string;
  name: string;
  blurb: string;
  /** Load textures etc. Called before the style becomes active. */
  preload(): Promise<void>;
  creature(species: string, el: El): CreatureArt;
  scene(): SceneArt;
  pedestal(): PedestalArt;
  ambience: Ambience;
  /** Optional CSS custom properties applied to :root (re-skin the HUD). */
  cssVars?: Record<string, string>;
}
