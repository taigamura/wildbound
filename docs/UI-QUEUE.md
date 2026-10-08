# UI redesign queue

Approved redesign work, waiting to be applied. Mockups: [UI directions](https://claude.ai/artifact/MPJsU1buebf2HxwtBvdJRe) (ideas 1–10) and [Crystal Foil Card](https://claude.ai/artifact/Ge6iFSZwyQszhBxsWeN54w) (the chosen card look). All ten ideas were approved on 2026-10-08.

How to work this queue:
- Take items top to bottom; the order is the recommended one (the frame and tokens first, because everything else builds on them).
- Each item ships on its own branch, with `scripts/ui-check.sh` passing. Look at the new shots, then `--update` the goldens in the same commit.
- When an item lands, delete it from this file and move anything it changes in the design spec into CLAUDE.md Part 1 in the same change.
- Sizes: S is under a day, M is a few days, L is a week or more.

## Bug to fix with the first item
- The reward screen says "Knocked-out partners are back on their feet at 25%". Victories don't heal (§4.9). New copy: "HP carries over. Knocked-out creatures stay down until a Spring or a Heal." (`game/run.gd`, `_show_reward`)

## 1. Window frames and three zones (idea 3) · M
`ui/kit.gd`, `ui/screens.gd`, `render/layout.gd`, `game/run.gd`
- One 9-slice window everywhere: thin double gold border, navy glass, small corner studs. Lists live inside one window, split by hairlines, instead of one glowing pill per row.
- Glow only for "selected" and "act now"; everything else flat.
- Every screen has three zones: header (title on a scrim), stage (the creature), sheet (controls). Art never sits under a sheet or header; a stage too short for the creature hides it (already true since the UI check work, see `Layout.room`).
- 8 pt spacing: 8 between related items, 16 inside windows, 24 between groups. Badges stay inside their parent.

## 2. Warm HD-2D palette (idea 1) · S
`ui/kit.gd`, `ui/screens.gd`
- Tokens: parchment ink `#f3ead3` for text, navy glass `#121a33` for windows, brass `#c9a24a` and gold `#f2d68c` for trim and the primary action. Element colours (Ember `#ec7a3c`, Tide `#3f9de4`, Thorn `#5cc062`, Volt `#efc63a`) become accents only: portrait rings, chips, card ribbons.
- Drop the lilac/violet gradients (the `big()` button, logo shader, pack card back).
- The primary CTA becomes a brass plaque with a pressed bottom edge, the only gold-filled shape on a screen.
- Selection is a gold outline plus a lead marker.

## 3. Type system that matches the sprites (idea 2) · S
`ui/kit.gd`, `ui/fonts/`, `ui/screens.gd`
- A pixel display face for titles, names and numbers; one highly legible sans for everything else (mockup uses Pixelify Sans + Atkinson Hyperlegible; both OFL).
- Body sizes 12/14/16, display 20 and 28–40. No tracked uppercase micro-labels.
- Text over the scene sits on a scrim and reaches 4.5:1 (the UI check's `contrast` rule enforces this already).
- Disabled rows keep readable text and say why ("Need 30 gold") instead of dimming the row.

## 4. Card redesign (idea 5) · M
`ui/card_view.gd`, `ui/hand_slot.gd`, `ui/ui.gd`, `ui/kit.gd`, `art/hd2d/manifest.gd`, `ui/rr.gdshader`
- **Look: Crystal Foil** ([mockup](https://claude.ai/artifact/Ge6iFSZwyQszhBxsWeN54w)), picked 2026-10-08: directions 6 (energy crystals) and 8 (Signature foil) from the [card directions page](https://claude.ai/artifact/YKadBLYSQHpxQQgj9CptWe), with the creature's face in the art window instead of the element glyph.
  - Crystal rail down the left edge: one crystal per energy (number under them for 3+); unaffordable crystals turn into red outlines; a −1 cost upgrade leaves a hollow crystal.
  - Foil by slot: Strike plain, Skill crosshatch, Signature gold double frame with a real-time sheen shader.
  - Face window: an `AtlasTexture` crop of the creature's (recoloured) sprite around a new `face` rect per species in `art/hd2d/manifest.gd`, framed in the element colour. No new image files; faces update themselves as real sprites land.
  - **Faces, decided 2026-10-08:** the rule stays (§4.3: cards belong to an element; any living same-element lead plays them). The face window shows every living teammate of the card's element, the card's owner first: one face, or a split window for two or three. A KO removes that face from every card it shared; a card is dead only when no face is left, and then shows its owner greyed under KO. Faces change at run start and on KO/revive, never on a swap.
  - When this lands, update CLAUDE.md §4.3 ("The card face shows that element's icon and colour (no creature portrait)") to describe the faces.
- Cost inside the frame; nothing drawn outside the card's rectangle.
- Fixed anatomy: crystal rail, face window, name, rules box of fixed height. The hand shows the short form; the preview shows full sentences.
- Holding a card shows a large preview in the middle of the stage; the card itself lifts only ~12 px so the party rail and bench stay visible.
- Off-element cards: desaturated, swap glyph in the unlocking element's colour. Status strips (Strong, upgraded, can't afford) get their own row under the rules text.

## 5. Battle HUD diet (idea 4) · M
`ui/ui.gd`, `ui/fx.gd`, `ui/bar.gd`
- Enemy plate on one line: intent ring on the left (fills over the wind-up), name, element, HP bar with the number outside the bar.
- A heavy wind-up becomes a banner under the plate: attack name, element, seconds left, which element resists it. It lives in the header zone, never over the creatures (replaces the floating "Thunder Ram" label).
- Lead plate and bench merge into one party rail: lead with HP and Trait on the left, bench portraits on the right.
- The stage gains about 90 px.

## 6. Energy crystal and readable bench (idea 6) · M
`ui/ui.gd`, `ui/bar.gd`
- Energy becomes a crystal orb beside the hand: the number inside, ten pips around the rim, fills like liquid while it regenerates (replaces the ten lilac pills).
- Bench portraits are 56 px circles. Swap cooldown is a dark wedge with the seconds in the middle; the portrait pops when ready.
- The "cards waiting" count is an element-coloured chip inset at the portrait's lower right.
- During a heavy wind-up, portraits that resist show a shield marker.

## 7. Title as diorama and dock (idea 8) · S
`ui/screens.gd`, `game/run.gd`
- The lead creature stands centre stage with nothing over it; logo on a scrim with a legible tagline.
- One brass "Start expedition" plaque, the current team as small portraits just above it (tap to edit, opens the Team screen).
- Team, Pack, Collection and Shop become a four-icon dock. A gold dot marks "pack ready"; counts under the labels.

## 8. The map as a trail (idea 7) · L
`game/run.gd`, `ui/screens.gd`, `ui/kit.gd`
- A short vertical trail: upcoming floors fade upward toward the Warden (floor 4) or Noctyrm (floor 8); this floor's 2–3 choices are medallions on branching paths.
- Tapping a medallion shows its details in one strip below; a second tap travels. Gold range and material chance stay visible (§6).
- Party as portraits with HP bars, no names. The wallet is one row of icon chips (fixes the two-line wrap).

## 9. Collection as a bestiary (idea 9) · M
`game/run.gd`, `ui/screens.gd`, `render/layout.gd`
- The selected creature gets its own framed specimen window, so it can never collide with the header (today it's hidden at 390×844 for lack of room).
- A six-wide portrait grid with silhouettes for unowned creatures; names only in the detail panel.
- Detail panel tabs: Cards, Trait, Upgrades. Upgrade tracks are five-pip bars with the next cost on the button.

## 10. Reward and results with weight (idea 10) · S
`game/run.gd`, `ui/screens.gd`, `ui/fx.gd`
- A loot ribbon under "Victory" reveals each drop in turn (gold, material, Essence) with a pop and a coin tick; the resting state is fully visible.
- Three tall reward cards in the new card frame (item 4), readable text, and a pip row for picks remaining (Alphas give 2).
- Run over gets the same treatment: floor, gold, Perfect Swaps and time as large pixel numbers, then the run's loot ribbon.
