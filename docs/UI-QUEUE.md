# UI follow-ups

The ten-idea redesign and the Crystal Foil card all landed on 2026-10-08 (branch `ui-redesign`; CLAUDE.md Part 1 describes the result). Mockups for reference: [UI Directions](https://claude.ai/artifact/MPJsU1buebf2HxwtBvdJRe), [Crystal Foil Card](https://claude.ai/artifact/Ge6iFSZwyQszhBxsWeN54w).

What's left, smallest first. Each change still has to pass `scripts/ui-check.sh`; when it changes the look, check the shots, then `--update` the goldens in the same commit.

## Check on a real iPhone first
- Frame rate with the new shaders (card foil sheen, crystal orb, face dimming) on top of the 3D stage.
- Whether Pixelify Sans stays crisp at device scale (display sizes are multiples of 11 for its pixel grid).
- Safe-area insets: the UI check simulates 47/34 px, but nothing has been measured on a device.

## Decisions
- Map: the first medallion starts selected so §6's gold range and material chance are always visible; tapping it once travels straight away. Start with nothing selected instead?
- Collection is titled "Collection" (matches the dock and the spec); the mockup said "Bestiary".

## Small polish
- Reward option cards: rules text is about 9px at 390 wide; give the three reward cards a larger variant.
- Shiny creatures' faces (cards, rail, bench) show without the shiny hue shift.
- Face crops have square corners, so up to 1 px can show past the face window's rounded frame.
- The hold preview shows the hand's short rules text; write full-sentence card text for it.
- The "Victory" ribbon pops its chips but doesn't slide in with the sheet.
- Battle stage gained about 75 px (the mockup asked for 90); the always-reserved heavy-banner strip costs the rest.

## Test coverage gaps
- `inspect` at 375×667: the simulated press doesn't register, so the hold preview is only checked at 390×844.
- The shop's can't-afford state has no shot (the UI-check save always has 240 gold).
