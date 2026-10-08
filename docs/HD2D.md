# HD-2D character template (ChatGPT)

The art direction is **HD-2D**, in the spirit of Octopath Traveler: low-resolution pixel-art sprites placed in a lit, painterly diorama with depth of field and bloom. The cast is **monsters and humanoid characters**. Humanoids are generated in ChatGPT with this template; monsters use the same Style Block so the two never look like they come from different games.

The rules this follows live in [CLAUDE.md](../CLAUDE.md) §13 (art direction) and Part 2 "Art space". In the game, sprites are listed in `godot/art/hd2d/manifest.gd` (species → image, feet anchor, head point, emitters, recolour).

## Why sprites drift, and what stops it

ChatGPT drifts when the prompt changes wording, when a chat accumulates history, and when the model is left to choose resolution, palette, light or pose. The template removes each of those choices:

| Drift source | Lock |
|---|---|
| Wording varies between prompts | The **Style Block** is pasted verbatim, every time. Only the **Subject Block** changes. |
| Model "remembers" earlier attempts | **One new chat per character.** Never generate two characters in one chat. |
| No visual reference | Attach the **anchor sprite** for the body type (Step 1) to every prompt. Text alone drifts; text plus a reference barely does. |
| Resolution and pixel size wander | The prompt asks for a sprite height in pixels (ChatGPT lands near it, not on it), and `scripts/hd2d-sprite.py` snaps every result onto its own true grid. The manifest `height` then sets the in-game size. |
| Palette wanders | The Style Block fixes the palette rules. The script can also lock a sprite to the anchor's palette (`--palette-from`, optional). |
| Pose, proportions, facing, framing wander | Fixed in the Style Block: idle, three-quarter view, facing right, full body, margin. |
| Free-text descriptions invite invention | The Subject Block uses short fixed fields with a closed vocabulary where possible. |

## The locked constants

These are the style. Changing one means regenerating every sprite, so change them only on purpose and update this file.

| Constant | Value |
|---|---|
| In-game height | Humanoid figures are **128 art units** tall, size-1 monsters **100**. The normalizer's manifest `height` enforces this, whatever the sprite's pixel count. Pixel size stays close across sprites because the prompts ask for matching pixel heights |
| Humanoid height | about **128 px** (head to feet), **chibi**: **3 heads tall** (the head, crown to chin, is about 43 px; torso about one head; legs shorter than one head), like Octopath Traveler's field sprites. Big head and eyes, compact body, short limbs, but always an adult character |
| Monster height | about **100 px × species size** (`SPECIES[key].size` in `godot/core/data.gd`): a size-1 creature is 100 px, Kilnback (1.22) is 122 px |
| View and facing | Three-quarter view, **facing right** (the game mirrors enemies) |
| Pose | Standing idle, feet on one baseline. Humanoids: weight on the back leg. Monsters: weight centred |
| Light | Single warm key light from the **upper left**; cool fill from the right |
| Shading | Per material: 1 highlight, 1 base, 2 shadow tones. Shadows hue-shift toward violet-blue, highlights toward warm yellow |
| Outline | 1 px, a darker shade of the neighbouring colour ("selective outline"). **Never pure black.** |
| Palette | At most **32 colours** asked for in the prompt (the normalizer keeps up to 64 to avoid dropping accents), slightly desaturated, warm-leaning |
| Element accents | Ember `#FF6A3D`, Tide `#34A8FF`, Thorn `#4FCF5C`, Volt `#FFCF2E` (the game's element colours, `ELEM` in `godot/core/data.gd`) |
| Background | Transparent. No ground shadow (the game draws one), no scenery, no text |

What the sprite does **not** include: depth of field, bloom, glow, light shafts, particles. In HD-2D those come from the engine around the sprite (pillar 5: motion and effects come from code). A sprite with baked-in glow looks wrong once the engine adds its own.

## Step 1: anchors, one per body type

Anchors are the approved sprites every later prompt is compared against. There is one per body type, and each prompt attaches the one closest to what you're making, so the reference shows the right build as well as the style. All anchors share one style, so any of them keeps the pixel size, palette, outline and light consistent.

| Anchor | What it is | Attach it for |
|---|---|---|
| `anchors/humanoid.png` | Sable: chibi human, rival tamer | humanoid characters |
| `anchors/biped.png` | Ember fox: upright creature, half humanoid, half monster | biped monsters, companions that stand like a person |
| `anchors/quadruped.png` | Emberwing dragon: four-legged winged creature | quadruped and serpent monsters, dragons (Noctyrm), and anything without a closer anchor yet |
| `anchors/shell.png` | Brinecrab: low, heavy shelled creature | shell monsters (Brinecrab, Coilsnail) |
| `anchors/blob.png` | Puddlet: legless rounded body | blob monsters (Puddlet) |
| `anchors/winged.png` | Brambat: hovering, wings spread | flying monsters (Brambat, Skiray) |

Attach **only the matching anchor**: attaching a humanoid to a monster prompt pulls the monster toward human posture and clothes (that is how the Ember fox got its scarf and boots).

The shell, blob and winged anchors were made with [Part A of hd2d/prompts.md](hd2d/prompts.md#part-a-make-the-missing-anchors), which has the step-by-step procedure and a ready-to-paste prompt for each. Each is also a roster creature's sprite. The steps below are the general recipe for any future body type.

**Adding an anchor** for a new body type (e.g. a serpent if the quadruped doesn't fit):
1. New chat. Attach the closest existing anchor and paste the prompt for that kind ([B](#b-any-later-female-humanoid-attach-humanoidpng) or [C](#c-monster-attach-the-matching-anchor)). The first anchor ever, with nothing to attach, used [prompt A](#a-first-humanoid-anchor-no-attachments).
2. Regenerate until one is right against the [checklist](#checklist). Expect 5–10 tries; this is the one place to be picky.
3. Normalize it (Step 3), save it as `docs/hd2d/anchors/<body-type>.png`, and add a row to the table above.

## Step 2: generate a character

New chat. Attach the anchor for the body type (table in Step 1). Paste the prompt below, with the Subject Block filled in. For ready-to-paste versions, see [Copy-paste prompts](#copy-paste-prompts).

```
Use the attached image as the style reference. Match its pixel size, palette, outline, shading and lighting exactly. Do not copy its design, pose details or colours beyond the palette. Make a new character described in SUBJECT.

STYLE (fixed, do not reinterpret):
HD-2D pixel-art game sprite: low-resolution hand-placed pixel art, the kind used for characters in modern HD-2D JRPGs. The character is exactly [HEIGHT] pixels tall from the top of the head to the soles of the feet, on a strict square pixel grid. Every pixel is a crisp, solid square: no anti-aliasing, no soft edges, no gradients, no blur, no noise, no dithering except small deliberate 2-pixel patterns on cloth. At most 32 colours, slightly desaturated and warm-leaning. One warm key light from the upper left, a faint cool fill from the right. Each material has one highlight, one base and two shadow tones; shadows shift toward violet-blue, highlights toward warm yellow. Outline is 1 pixel wide and is a darker shade of the colour beside it, never pure black. [BODY] Three-quarter view, body and face turned to the RIGHT side of the image, both feet on one flat baseline. Whole body in frame with empty space on every side. Exactly one character. Transparent background. No ground shadow, no floor, no scenery, no glow, no bloom, no light rays, no particles, no text, no border, no UI, no watermark, no sprite sheet, no extra poses.

SUBJECT:
[paste the filled Subject Block]
```

- **Humanoid:** `[HEIGHT]` = 128, `[BODY]` = "Super-deformed (SD) chibi proportions, like the field sprites in Octopath Traveler: the head, from crown to chin, is one third of the total height (about 43 of the 128 pixels); the torso is about as tall as the head; the legs are shorter than the head is tall; short arms; big readable eyes. Not realistic proportions, not a tall anime figure. Clear readable silhouette with a strong outline shape. Still clearly an adult: a mature face and an adult outfit, not a child. Relaxed idle pose, weight on the back leg, arms loose."
- **Monster:** `[HEIGHT]` = 100 × the species size, `[BODY]` = "Creature proportions: compact, chunky, readable at small size. A creature, not a person: no clothing, no accessories, no human posture. Standing idle pose, weight centred."

### Subject Block: humanoid

Keep each field to one short line. Fill every field; an empty field is a choice left to the model.

```
Name: 
Gender: (woman / man)
Role: (one: tamer, rival tamer, warden-keeper, merchant, healer, scholar, scout, villager, villain)
Build: (one: slim, average, sturdy, broad). At chibi scale build is a hint, not a figure
Age: (one: young adult in her/his twenties, adult, older). Always an adult.
Silhouette hook: (the ONE shape that identifies them at a glance, e.g. "wide-brimmed hat", "long scarf trailing left", "huge backpack")
Hair: (colour and shape)
Outfit: (three pieces, top to bottom, e.g. "hooded short cloak, belted tunic, tall boots")
Colours: (primary / secondary / accent, plain names, e.g. "moss green / bone white / brass")
Element: (one of Ember, Tide, Thorn, Volt, or None) shown as a small accent only: (e.g. "Ember: orange gem on the belt")
Prop: (one held item, in the hand nearest the viewer, or "none")
Expression: (one: calm, determined, cheerful, wary, smug, confident smirk, tired)
Pose accent: (one small touch on the idle pose, e.g. "hand on hip", "hair flick", or "none")
```

### Subject Block: monster

```
Name: 
Element: (Ember / Tide / Thorn / Volt), main body colour from that element's accent
Size: (the species size, e.g. 1.0)
Body plan: (one: biped, quadruped, serpent, winged, blob, shell)
Silhouette hook: (the ONE identifying shape, e.g. "candle-flame tail", "bell-shaped head")
Features: (2–3 from: ears, horns, flame, tail, fin, whiskers, leaf, spikes, antenna, wings, crown)
Colours: (primary / secondary / accent)
Expression: (one: curious, fierce, sleepy, proud, mischievous)
```

Use the species' `feats` in `godot/core/data.gd` for Features, so the image matches the creature's design.

### Fixing one thing

When a result is close, fix it in the same chat with a narrow edit. Name what stays:

```
Same character, same pose, same palette, same pixel size. Change only: [one thing].
```

If a humanoid comes back with adult proportions (ChatGPT's most common drift), use: `Same character, same outfit, same palette. Change only: super-deformed chibi proportions, the head is one third of the total height, legs shorter than the head.`

If two edits in a row don't land, start a new chat; more edits in one chat drift further.

## Copy-paste prompts

Ready to paste as is. Swap the SUBJECT for your own character; leave everything above it alone.

**Generating with Codex instead of by hand:** the `/hd2d-batch` skill (`.claude/skills/hd2d-batch/`) runs `scripts/hd2d-codex.py` to generate the next few creatures in fresh Codex sessions (anchor attached, flat magenta background keyed out by the normalizer), then reviews, normalizes and wires them in. It checks first that Codex's image tool is offered, since it disappears while the daily image quota is used up.

**Every creature, the Warden and the boss** have their own ready-to-paste prompt, normalize command and manifest notes in [hd2d/prompts.md](hd2d/prompts.md), in the order to make them (the new anchors first). It is generated from one Style Block, with the body and baseline sentences adjusted per body plan (biped, quadruped, shell, blob, winged), so only the SUBJECT differs within a plan. The prompts below are the templates and the humanoid examples.

The appeal comes from the character design: a strong silhouette, big expressive hair, a distinctive outfit, a confident expression and a clear pose accent, the way Octopath's cast reads at a glance. At chibi proportions, body shape barely reads; the **head, hair and silhouette hook** carry the character, so push those (hair volume, hat, scarf, coat tails, a prop) rather than figure or fine detail. Describe characters with words like *stylish*, *cool* and *striking*. **Do not combine chibi proportions with alluring or revealing wording** ("alluring", "glamorous", bare shoulders, short hems, thigh-high boots): ChatGPT blocks that mix, because big-headed childlike proportions plus suggestive styling reads as sexualizing a child, and it fails with a generic "error on my side" message rather than a refusal. Outfits should be full, practical adventuring clothes. Always state an age in the twenties or older and keep "still clearly an adult" in the Style Block, so the chibi proportions don't turn into a child.

### A. First humanoid anchor (no attachments)

Use this for Step 1. Nothing is attached yet, so this is the only prompt without the reference line.

```
Make one game character sprite.

STYLE (fixed, do not reinterpret):
HD-2D pixel-art game sprite: low-resolution hand-placed pixel art, the kind used for characters in modern HD-2D JRPGs. The character is exactly 128 pixels tall from the top of the head to the soles of the feet, on a strict square pixel grid. Every pixel is a crisp, solid square: no anti-aliasing, no soft edges, no gradients, no blur, no noise, no dithering except small deliberate 2-pixel patterns on cloth. At most 32 colours, slightly desaturated and warm-leaning. One warm key light from the upper left, a faint cool fill from the right. Each material has one highlight, one base and two shadow tones; shadows shift toward violet-blue, highlights toward warm yellow. Outline is 1 pixel wide and is a darker shade of the colour beside it, never pure black. Super-deformed (SD) chibi proportions, like the field sprites in Octopath Traveler: the head, from crown to chin, is one third of the total height (about 43 of the 128 pixels); the torso is about as tall as the head; the legs are shorter than the head is tall; short arms; big readable eyes. Not realistic proportions, not a tall anime figure. Clear readable silhouette with a strong outline shape. Still clearly an adult: a mature face and an adult outfit, not a child. Relaxed idle pose, weight on the back leg, arms loose. Three-quarter view, body and face turned to the RIGHT side of the image, both feet on one flat baseline. Whole body in frame with empty space on every side. Exactly one character. Transparent background. No ground shadow, no floor, no scenery, no glow, no bloom, no light rays, no particles, no text, no border, no UI, no watermark, no sprite sheet, no extra poses.

SUBJECT:
A stylish, confident adult woman, the cool rival of a JRPG.
Name: Sable
Gender: woman
Role: rival tamer
Build: slim
Age: young adult in her twenties
Silhouette hook: long high ponytail sweeping back to the left
Hair: glossy crimson, long high ponytail, side-swept fringe
Outfit: long charcoal coat with a high crimson-lined collar, fitted vest with a wide belt, tall boots
Colours: charcoal black / crimson / gold
Element: Ember: a small orange gem on the belt buckle
Prop: a gold capture lantern hanging from the hand nearest the viewer
Expression: confident smirk
Pose accent: free hand on hip
```

### B. Any later female humanoid (attach humanoid.png)

```
Use the attached image as the style reference. Match its pixel size, palette, outline, shading and lighting exactly. Do not copy its design, pose details or colours beyond the palette. Make a new character described in SUBJECT.

STYLE (fixed, do not reinterpret):
HD-2D pixel-art game sprite: low-resolution hand-placed pixel art, the kind used for characters in modern HD-2D JRPGs. The character is exactly 128 pixels tall from the top of the head to the soles of the feet, on a strict square pixel grid. Every pixel is a crisp, solid square: no anti-aliasing, no soft edges, no gradients, no blur, no noise, no dithering except small deliberate 2-pixel patterns on cloth. At most 32 colours, slightly desaturated and warm-leaning. One warm key light from the upper left, a faint cool fill from the right. Each material has one highlight, one base and two shadow tones; shadows shift toward violet-blue, highlights toward warm yellow. Outline is 1 pixel wide and is a darker shade of the colour beside it, never pure black. Super-deformed (SD) chibi proportions, like the field sprites in Octopath Traveler: the head, from crown to chin, is one third of the total height (about 43 of the 128 pixels); the torso is about as tall as the head; the legs are shorter than the head is tall; short arms; big readable eyes. Not realistic proportions, not a tall anime figure. Clear readable silhouette with a strong outline shape. Still clearly an adult: a mature face and an adult outfit, not a child. Relaxed idle pose, weight on the back leg, arms loose. Three-quarter view, body and face turned to the RIGHT side of the image, both feet on one flat baseline. Whole body in frame with empty space on every side. Exactly one character. Transparent background. No ground shadow, no floor, no scenery, no glow, no bloom, no light rays, no particles, no text, no border, no UI, no watermark, no sprite sheet, no extra poses.

SUBJECT:
A graceful, calm adult woman, a stylish JRPG heroine.
Name: Maren
Gender: woman
Role: tamer
Build: slim
Age: young adult in her twenties
Silhouette hook: wide-brimmed sun hat tilted forward
Hair: long wavy silver-blue hair down to the waist
Outfit: loose blouse with wide sleeves, long wrap skirt with a sash, travel sandals
Colours: sea blue / ivory / coral
Element: Tide: a blue shell pendant on a short necklace
Prop: none
Expression: calm
Pose accent: hand lifting the brim of her hat
```

### C. Monster (attach the matching anchor)

```
Use the attached image as the style reference. Match its pixel size, palette, outline, shading and lighting exactly. Do not copy its design, pose details or colours beyond the palette. Make a new creature described in SUBJECT.

STYLE (fixed, do not reinterpret):
HD-2D pixel-art game sprite: low-resolution hand-placed pixel art, the kind used for characters in modern HD-2D JRPGs. The character is exactly 100 pixels tall from the top of the head to the soles of the feet, on a strict square pixel grid. Every pixel is a crisp, solid square: no anti-aliasing, no soft edges, no gradients, no blur, no noise, no dithering except small deliberate 2-pixel patterns on cloth. At most 32 colours, slightly desaturated and warm-leaning. One warm key light from the upper left, a faint cool fill from the right. Each material has one highlight, one base and two shadow tones; shadows shift toward violet-blue, highlights toward warm yellow. Outline is 1 pixel wide and is a darker shade of the colour beside it, never pure black. Creature proportions: compact, chunky, readable at small size. A creature, not a person: no clothing, no accessories, no human posture. Standing idle pose, weight centred. Three-quarter view, body and face turned to the RIGHT side of the image, both feet on one flat baseline. Whole body in frame with empty space on every side. Exactly one character. Transparent background. No ground shadow, no floor, no scenery, no glow, no bloom, no light rays, no particles, no text, no border, no UI, no watermark, no sprite sheet, no extra poses.

SUBJECT:
Name: Emberwick
Element: Ember, main body colour #FF6A3D
Size: 1.0
Body plan: biped
Silhouette hook: a candle-flame on top of its head
Features: ears, flame, tail
Colours: ember orange / cream / charcoal
Expression: curious
```

For a monster bigger than size 1, change `100` to 100 × its size (Kilnback: 122).

## Step 3: normalize

ChatGPT's "pixel art" is rendered at high resolution: each of its "pixels" is a soft, slightly uneven square of about 8–12 source pixels, with tens of thousands of colours and a semi-transparent fringe. The normalizer finds that grid and snaps to it:

```bash
python3 scripts/hd2d-sprite.py raw.png out.png                              # humanoid (128 units tall in game)
python3 scripts/hd2d-sprite.py raw.png out.png --kind monster --size 1.22   # Kilnback (122 units)
```

It removes the background (or uses the existing transparency), crops, and measures the source's own pixel size from the periodic colour edges. Then each source pixel becomes exactly one sprite pixel, taking the cell's most common colour (not an average, so edges and small accents stay crisp; a clearly darker colour wins with a third of the cell, so 1 px outlines and eyes survive). It reduces to 64 colours (always including the four element accents and a trim gold, `RESERVED` in the script), makes alpha hard, drops small detached specks (baked-in particles; `--keep-islands` keeps them), adds a margin, and scales back up by a whole number with nearest-neighbour to about 512 px. Nothing is merged away, so the result keeps the source's detail.

It prints the grid it found and the manifest numbers (`anchor`, `height`, `head`) to paste into its entry in `godot/art/hd2d/manifest.gd`. `height` is set from `--kind`/`--size`, so the figure shows at the right size in game whatever its pixel count. `head` is an estimate; nudge it in the browser.

Options: `--palette-from anchor.png` locks the colours to an anchor's; `--height N` forces a fixed pixel height instead of snapping (this merges detail if N is below the source grid's height).

## Checklist

Reject and regenerate if any is true:
- [ ] Faces left, or faces the viewer straight on
- [ ] Cropped anywhere (head, feet, prop)
- [ ] More than one figure, a sprite sheet, or extra poses
- [ ] Background, floor, cast shadow, glow, sparkles or text
- [ ] Soft or blurry edges that survive normalization (the source was painted, not pixel art)
- [ ] Pure black outline
- [ ] Light coming from the right or from below
- [ ] Proportions clearly off from the anchor. For humanoids, measure the source: the head (crown to chin) should be about a third of the figure's height. Reject 4+ heads (a tall anime figure) or a 2-head baby shape
- [ ] A humanoid that looks younger than an adult
- [ ] The normalizer reports a source grid far from the anchor's (they are 8–11 px): the pixels will look a different size from the rest of the cast

## Where things go

- Approved anchors: `docs/hd2d/anchors/`, one per body type (table in Step 1). They are the style's source of truth; replacing one is a style change.
- Finished creature sprites: `godot/art/hd2d/<species>.png`, with an entry in `godot/art/hd2d/manifest.gd` keyed by species key (set `recolor` to null so its painted colours are kept).
- Humanoids have no in-game slot yet (CLAUDE.md §15). Keep normalized sprites that aren't anchors in `docs/hd2d/characters/` until they do.
