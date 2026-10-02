# CLAUDE.md

Context for Claude Code working in this repo.

## What this is
Wildbound: portrait iOS 2D creature roguelite. Real-time card combat, catching creatures mid-run, 8 floors, about 5 minute runs. The game is a PixiJS web app (`game/`) shipped inside an Expo WebView shell (`app/`). iOS builds run on EAS, so no Mac is needed.

**The art style is expected to change.** All visuals that define the look go through `game/src/art/` (see `docs/ART.md`). Gameplay code must stay art-agnostic.

## Commands
- `npm run dev`: game at http://localhost:5173 (`?art=<id>` picks a style; `?export-pack` bakes creature PNGs)
- `npm run typecheck`: game + app
- `npm run build`: build the game and embed it into the app (`app/src/game-html.generated.ts`, gitignored)
- `npm run app`: Expo dev server (Expo Go works)
- `cd app && npx expo export --platform ios`: proves the iOS bundle compiles (CI runs this)

## Where things live
- Balance and content: `game/src/core/data.ts`. Enemy scaling is in `game/src/game/battle.ts` (`startBattle`).
- Combat and capture: `game/src/game/battle.ts`. Map, rewards and title: `game/src/game/run.ts`.
- On-screen creatures: `render/actor.ts` (the `Actor` class). Gameplay only ever uses Actors.
- Art: `art/types.ts` (contracts), `art/registry.ts` (active style), `art/sticker/`, `art/sprite/`, `art/packs/<id>/`.
- Host bridge: `core/platform.ts` ↔ `app/src/bridge.ts`. Keep the message types in sync.

## Rules
- **Art boundary:**
  - `game/*` and `render/particles.ts`/`fx.ts` must not import from `art/sticker` or `art/sprite`.
  - Go through `getStyle()` or an `Actor`.
  - A new visual concept that should vary by style (for example an attack sprite) becomes a new optional member of `ArtStyle`, with a style-independent default.
- **Art space:** facing right, feet at (0,0), about 100 units tall for a size-1 creature, head around y = -56. `Actor` scales art space by `U / 56 * species.size`.
- **Stale callbacks:** `S.tok` is bumped when a battle or run ends. Every delayed callback (gsap `delayedCall`/`onComplete`, `setTimeout`) captures `tok` and bails if it changed.
- **Timing:** use gsap for time-based effects so they respect hit-stop (`gsap.globalTimeline.timeScale`).
- **Units:** layout is in units of `U` (px, from `render/layout.ts`). `emit()` speeds, sizes and gravity are in U.
- **Input:** card taps use `pointerdown`, not `click`.
- **Storage and native calls:** never touch `localStorage` or `window.ReactNativeWebView` outside `core/platform.ts`.
- **Native modules:** Expo SDK 57. Install with `npx expo install` so versions match the SDK.
- **Bundle size:** pack images are inlined into the single-file build, so keep them small (WebP, about 512 px).

## Verifying changes
- Run `npm run typecheck` and `npm run build`.
- Play a run in the browser at 390×844 in every art style (switch on the title screen).
- For app-side changes, also run the iOS export.
