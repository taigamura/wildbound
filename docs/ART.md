# Art styles and art packs

The rules for the art boundary and art space live in [CLAUDE.md](../CLAUDE.md) (Part 2, "Rules"), and the asset list in its §13. This file is the how-to.

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

Packs are discovered automatically at build time and appear in the title-screen picker. The Dusk pack is a complete working example.

### Image rules

- **One creature per image, facing right.** The game mirrors the art for enemies.
- **Transparent background.** Leave some empty margin around the creature.
- **Consistent framing across creatures.** Feet near the bottom, roughly centred.
- **Size:** about 512 px tall is plenty. Prefer WebP to keep the app small, because images are inlined into the build.
- **Keys:** images are keyed by species key, the lowercase creature name: the 12 creatures (`emberwick`, `cinderpip`, …), the 3 evolutions (`pyrowl`, `lanternmere`, `morelord`), the Warden (`warden`) and the boss (`noctyrm`). See `SPECIES` in `game/src/core/data.ts`.
- **Evolutions:** if a pack has no image for an evolved form, the game draws the base creature's image scaled ×1.2 with a glow, rather than falling back to Sticker.
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
}
```

- **Missing creatures** fall back to the Sticker style, so you can fill a pack in one creature at a time.
- **Background:** set `scene.image: 'background.png'` and `scene.horizon` (the fraction of the image height where the ground starts). Or give `scene.palette` to recolour the painted scene, as Dusk does. `scene` is biome A (floors 1–4); `sceneB` (same shape) is biome B (floors 5–8) and defaults to `scene`.
- **Pedestals:** set `pedestal.image` for a custom platform image. It's drawn centred on the creature's feet.

### Getting the framing right

Open the game with `?export-pack` (for example `http://localhost:5173/?export-pack`). The browser downloads:
- a PNG of every creature
- `creatures.json` with exact anchors, heights and head points

Use these PNGs as reference images or img2img inputs for your AI generator, so the new art lines up with the game.

### Workflow for an AI art pass

1. Run `?export-pack` and copy the outputs into `packs/<new-id>/`.
2. Copy `packs/dusk/manifest.ts`, then change `id`, `name` and `blurb`.
3. Replace PNGs one by one with generated art. After each one, check it in the browser (`npm run dev`, then pick the style on the title screen) and nudge `anchor`, `head` and `height` until the creature sits on its pedestal.
4. Once you're happy with the style, make it the default by returning it first in `STYLES` in `art/registry.ts`, or delete the others.

## 2. Code style (procedural)

Implement `ArtStyle` yourself. See `art/sticker/` for a full example:
- `creature()` returns a `CreatureArt` drawn in art space (facing right, feet at (0,0), about 100 units tall)
- `scene(biome)` returns a `SceneArt` for biome 0 or 1
- `has(species)` (optional) says whether the style has its own art for a species; return false for evolved forms you don't draw, so the game uses the scaled-base fallback
- `pedestal()` returns a `PedestalArt`

Register the style in `STYLES` in `art/registry.ts`.

## What a style does *not* control

These live outside the art layer on purpose:
- **Effects:** particles, projectiles, lightning, rings
- **Animation:** squash and stretch, lunges, knockback, idle bob
- **The HUD:** it's DOM and CSS. A style can override CSS variables via `cssVars`, for example `{ '--panel': 'rgba(40,20,50,.85)' }`.
