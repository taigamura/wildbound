# Art styles and art packs

The rules for the art boundary and art space live in [CLAUDE.md](../CLAUDE.md) (Part 2, "Rules"), and the art direction and asset list in its §13. This file is the how-to for packs. To generate HD-2D sprites in ChatGPT with little style drift, use [HD2D.md](HD2D.md).

Everything that defines the look comes from an **art style** (`game/src/art/types.ts`):
- the creatures
- the background scene, one per biome (floors 1–4 and 5–8)
- the pedestals they stand on
- ambient particle colours
- optionally, HUD colour variables

Gameplay, particles, layout and animation never depend on a specific style. Swapping styles changes the look without touching the game.

There are two ways to add a style.

## 1. Image pack (for AI-generated or hand-drawn art)

Create a folder `game/src/art/packs/<id>/` containing:
- your image files (PNG or WebP)
- a `manifest.ts`

Packs are discovered automatically at build time and appear in the title-screen picker. The Dusk pack is a complete working example of an image pack; the HD-2D pack (`packs/hd2d/`, the default style) shows recoloured placeholder sprites plus a code-built background (see [The HD-2D pack](#the-hd-2d-pack)).

### Image rules

- **One creature per image, facing right.** The game mirrors the art for enemies.
- **Transparent background.** Leave some empty margin around the creature.
- **Consistent framing across creatures.** Feet near the bottom, roughly centred.
- **Size:** about 512 px tall is plenty. Prefer WebP to keep the app small, because images are inlined into the build.
- **Keys:** images are keyed by species key, the lowercase creature name: the 12 creatures (`emberwick`, `cinderpip`, …), the Warden (`warden`) and the boss (`noctyrm`). See `SPECIES` in `game/src/core/data.ts`.
- **Shinies** are a hue-shift filter applied by the game. They need no extra art.
- **Boss:** Noctyrm changes element mid-fight. Either provide one image per element (`variants`), or set `tintByElement: true` on a neutral-coloured image.

### Manifest entry per creature

```ts
emberwick: {
  image: 'emberwick.png',
  anchor: [0.5, 0.92],   // where the FEET are, as a fraction of the image (x, y)
  height: 150,           // drawn height in art units; about 125–165 for a size-1 creature
  head: [0.6, 0.5],      // projectile target / damage-number point (fraction of image)
  emitters: [[0.65, 0.08]],  // optional: where ambient sparks rise from (flame tips etc.)
  variants: { tide: 'emberwick-tide.png' },  // optional per-element images
  tintByElement: false,  // optional: tint toward the element colour when no variant exists
  recolor: true,         // optional: Ember-coloured art, hue-remapped per element at load (see below)
}
```

- **Missing creatures** fall back to the Sticker style, so you can fill a pack in one creature at a time.
- **Background:** set `scene.image: 'background.png'` and `scene.horizon` (the fraction of the image height where the ground starts). Or give `scene.palette` to recolour the painted scene, as Dusk does. `scene` is biome A (floors 1–4); `sceneB` (same shape) is biome B (floors 5–8) and defaults to `scene`.
- **Pedestals:** set `pedestal.image` for a custom platform image. It's drawn centred on the creature's feet.
- **Pixel art:** set `pixelArt: true` on the manifest so every texture samples nearest-neighbour and stays crisp. Store pixel sprites at their true grid (one image pixel per sprite pixel); the manifest `height` scales them up.
- **Code-built background:** `sceneArt: biome => SceneArt` and `pedestalArt: () => PedestalArt` replace `scene`/`sceneB`/`pedestal` with your own code (the HD-2D pack's `scene.ts`).

### Recolouring one sprite for every element (`recolor`)

`tintByElement` multiplies the image by the element colour, which turns orange art into mud when the target is blue or green. `recolor` instead bakes a copy per element at load time (once, cached; `art/sprite/recolor.ts`): it maps the Ember hue ramp (magenta-dark outline → crimson shadow → orange base → amber highlight) onto the target element's ramp, so outlines and shadows stay darker and shift the way a pixel artist would shift them. Low-saturation pixels (skin, cream bellies, grey cloth, near-black) and hues outside the warm band keep their colour. Options (`recolor: { ... }` instead of `true`):

| Option | Default | Use |
|---|---|---|
| `maxHue` | 28 | Source hues above this keep their colour. Lower it (e.g. 10) to protect skin tones and gold trim. |
| `minSat` | 0.5 | Pixels less saturated than this keep their colour. |
| `light`, `sat` | 1 | Multiply the brightness / saturation of recoloured pixels (darker Warden). |
| `wash` | none | Multiply every pixel's RGB afterwards, e.g. `[0.8, 0.7, 1]` for a night variant. |
| `ramps` | built in | Per-element `[outline, shadow, base, highlight]` hues, to override a target ramp. |

The source art must be painted in Ember colours (the HD-2D anchors are). `variants` still win over `recolor` for any element they list.

### Getting the framing right

Open the game with `?export-pack` (for example `http://localhost:5173/?export-pack`). The browser downloads:
- a PNG of every creature
- `creatures.json` with exact anchors, heights and head points

Use these PNGs as reference images or img2img inputs for your AI generator, so the new art lines up with the game.

### Workflow for an AI art pass

1. Run `?export-pack` and copy the outputs into `packs/<new-id>/`.
2. Copy `packs/dusk/manifest.ts`, then change `id`, `name` and `blurb`.
3. Replace PNGs one by one with generated art. After each one, check it in the browser (`npm run dev`, then pick the style on the title screen) and nudge `anchor`, `head` and `height` until the creature sits on its pedestal.
4. Once you're happy with the style, make it the default by setting `DEFAULT_STYLE` in `art/registry.ts` to its id.

## The HD-2D pack

`packs/hd2d/` is the default style (`DEFAULT_STYLE` in `art/registry.ts`; `?art=` and the player's saved choice still win).

- **Placeholder cast.** Only the three anchors in `docs/hd2d/anchors/` exist, so every species reuses one, recoloured per element with `recolor`. Within each element in `SPECIES`: the 1st creature uses the fox (`fox.png`, biped), the 2nd uses Sable (`sable.png`, humanoid, `recolor: { maxHue: 10, minSat: 0.55 }` so her skin and trim stay), the 3rd (the tank) uses the dragon (`dragon.png`, quadruped). The Warden is the dragon with a darker, mossier Thorn ramp and 8% more height; Noctyrm is the dragon with a night wash on whichever element it holds.
- **Files** are the anchors downscaled to their true pixel grid (they were exact ×3 nearest upscales), so the three PNGs total about 12 KB.
- **Heights** are the canvas height in art units such that the figure is 128 units for the humanoid and 100 for a size-1 monster (`docs/HD2D.md`); the game multiplies by species `size`.
- **Background and pedestal** are procedural (`packs/hd2d/scene.ts`), no images: a layered diorama painted once per resize into small low-resolution canvases (sky, far ridge and ruins, mid treeline, a crisp pixel ground plane, near framing trunk and pillar or stone lanterns, out-of-focus foreground strips), with depth of field baked in by blurring each plane by its distance from the ground band, plus additive light shafts and glows from the upper-left key light, bokeh, drifting motes or fireflies, a vignette, and a slow parallax "camera breath". No live filters run per frame. Biome A is a sunlit forest ruin; biome B is moonlit with warm lanterns.

**Swapping in a real sprite** for a species: generate it with [HD2D.md](HD2D.md), normalize it with `scripts/hd2d-sprite.py`, downscale it to its true grid (divide by the upscale factor the script used, nearest-neighbour), save it as `packs/hd2d/<species>.png`, and replace that species' entry in `manifest.ts` with its own `image`, `anchor`, `head` and `height` (from the script's output). Drop `recolor` if the sprite is already painted in its element; keep it (with the right `ramps`) only for Ember-painted art.

## 2. Code style (procedural)

Implement `ArtStyle` yourself. See `art/sticker/` for a full example:
- `creature()` returns a `CreatureArt` drawn in art space (facing right, feet at (0,0), about 100 units tall)
- `scene(biome)` returns a `SceneArt` for biome 0 or 1
- `pedestal()` returns a `PedestalArt`

Register the style in `STYLES` in `art/registry.ts`.

## What a style does *not* control

These live outside the art layer on purpose:
- **Effects:** particles, projectiles, lightning, rings
- **Animation:** squash and stretch, lunges, knockback, idle bob
- **The HUD:** it's DOM and CSS. A style can override CSS variables via `cssVars`, for example `{ '--panel': 'rgba(40,20,50,.85)' }`.
