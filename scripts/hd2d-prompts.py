#!/usr/bin/env python3
"""Writes docs/hd2d/prompts.md, the ChatGPT/Codex prompt for every creature, from one Style Block.

  python3 scripts/hd2d-prompts.py

Edit the designs (C) or the body plans (PLANS) here, never in prompts.md: the file is regenerated,
and scripts/hd2d-codex.py reads its prompts back. Wording rules: docs/HD2D.md.
"""
import pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
STYLE = ("HD-2D pixel-art game sprite: low-resolution hand-placed pixel art, the kind used for characters in modern HD-2D JRPGs. "
 "The creature is exactly {h} pixels tall from {span}, on a strict square pixel grid. "
 "Every pixel is a crisp, solid square: no anti-aliasing, no soft edges, no gradients, no blur, no noise, no dithering except small deliberate 2-pixel patterns on fur or shell. "
 "At most 32 colours, slightly desaturated and warm-leaning. One warm key light from the upper left, a faint cool fill from the right. "
 "Each material has one highlight, one base and two shadow tones; shadows shift toward violet-blue, highlights toward warm yellow. "
 "Outline is 1 pixel wide and is a darker shade of the colour beside it, never pure black. {body} "
 "Three-quarter view, body and face turned to the RIGHT side of the image, {ground}. "
 "Whole body in frame with empty space on every side. Exactly one creature. Transparent background. "
 "No ground shadow, no floor, no scenery, no glow, no bloom, no light rays, no particles, no text, no border, no UI, no watermark, no sprite sheet, no extra poses.")
NOPERSON = "A creature, not a person: no clothing, no accessories, no human posture."
PLANS = {
 "biped": dict(anchor="biped.png", span="the top of the head to the soles of the feet",
   body="Creature proportions: compact, chunky, readable at small size. " + NOPERSON + " Standing upright on its hind legs in an idle pose, weight centred.",
   ground="both feet on one flat baseline"),
 "quadruped": dict(anchor="quadruped.png", span="the top of the head to the soles of the feet",
   body="Creature proportions: compact, chunky, readable at small size. " + NOPERSON + " Standing idle pose on all fours, weight centred.",
   ground="all four feet on one flat baseline"),
 "shell": dict(anchor="shell.png", span="the top of the shell to the soles of the feet",
   body="Creature proportions: low, wide and heavy, with a hard shell that dominates the silhouette; readable at small size. " + NOPERSON + " Standing idle pose, weight low and centred.",
   ground="all its legs (or its flat foot) on one flat baseline"),
 "blob": dict(anchor="blob.png", span="its highest point to the bottom of its body",
   body="Creature proportions: a soft, rounded, legless body, compact and chunky, readable at small size. The body is solid and opaque, not transparent or glassy. " + NOPERSON + " Resting idle pose, weight settled at the bottom.",
   ground="the flat underside of its body resting on one flat baseline"),
 "winged": dict(anchor="winged.png", span="its highest point to its lowest point",
   body="Creature proportions: a compact, chunky body between wide wings, readable at small size. " + NOPERSON + " Hovering idle pose, wings spread wide and level, body centred between them.",
   ground="hovering, with its lowest point (feet or tail tip) on one flat baseline"),
}
# key, name, element, hex, size, plan, pitch, hook, features, colours, expression, notes
EL = {"Ember": "#FF6A3D", "Tide": "#34A8FF", "Thorn": "#4FCF5C", "Volt": "#FFCF2E"}
C = [
 ("brinecrab","Brinecrab","Tide",1.18,"shell","A stout, armoured crab, the Tide tank, with a barnacle-crusted shell and one oversized claw.",
  "one huge clamp claw held up in front, on the side nearest the viewer","horns (two short coral horns on the shell), fin (a fin-like ridge along the shell), whiskers (two long feelers)","tide blue / sand beige / coral pink","proud",
  ""),
 ("puddlet","Puddlet","Tide",0.85,"blob","A small round water-drop creature, the team's gentle healer.",
  "a teardrop-shaped body whose pointed tip curls over at the top","fin (two small side fins used like little arms), whiskers (two long catfish whiskers)","tide blue / pale aqua / white","sleepy",
  ""),
 ("brambat","Brambat","Thorn",0.9,"winged","A small bramble bat with leafy, thorn-edged wings and tiny fangs.",
  "wide leaf-shaped wings with thorny, serrated edges","wings, ears (big pointed ears), spikes (thorns along the wing edges)","thorn green / bark brown / berry red","mischievous",
  ""),
 ("emberwick","Emberwick","Ember",1.0,"biped","A small upright fox-like creature with a living candle on its head, the Ember starter.",
  "a candle-flame on top of its head, with cream wax-drips over the brow","ears, flame, tail (a bushy tail with a flame-shaped tip)","ember orange / cream / charcoal","curious",""),
 ("cinderpip","Cinderpip","Ember",0.85,"biped","A tiny hot-headed imp-like critter of glowing coal, small but explosive.",
  "a tall, flickering flame crest swept back over its head, drawn as solid flat pixel shapes","ears (long pointed ears), flame","ember orange / coal grey / bright yellow","mischievous",""),
 ("kilnback","Kilnback","Ember",1.22,"quadruped","A heavy, slow tortoise-like beast whose back is a brick kiln with a fire inside.",
  "a domed brick-kiln shell on its back with an arched fire opening and a short chimney","horns (two blunt ram-like horns), spikes (stubby spikes around the shell rim), flame (a small flame from the chimney)","ember orange / brick red-brown / soot grey","proud",""),
 ("bellspring","Bellspring","Tide",0.95,"quadruped","A graceful axolotl-like amphibian with a bell-shaped head and a lantern lure, the Tide starter.",
  "a bell-shaped head with a small lantern lure hanging from a stalk on its brow","fin (frilly fins along its back), tail (a long finned tail), whiskers","tide blue / pearl white / lantern yellow","curious",""),
 ("truffmole","Truffmole","Thorn",1.0,"biped","A plump mole sitting up on its hind legs, with a mushroom cap growing on its head, the Thorn starter.",
  "a wide mushroom cap on its head and big shovel-like front claws","leaf (two sprouting leaves on the cap), ears (small round ears)","thorn green / earth brown / mushroom cream","sleepy",""),
 ("mossling","Mossling","Thorn",1.1,"quadruped","A round, mossy hedgehog-like creature whose back is a cushion of moss and thorns.",
  "a big round mound of moss on its back, studded with thorn spikes and two broad leaves","spikes, leaf","thorn green / bark brown / flower white","curious",""),
 ("skiray","Skiray","Volt",0.9,"winged","A small manta-ray-like sky creature that rides the wind.",
  "wide diamond-shaped ray wings and a long thin whip tail ending in a lightning-bolt tip","antenna (two short antennae), ears (small fin-like ears), tail","volt yellow / slate blue / white","mischievous",""),
 ("sparkit","Sparkit","Volt",0.85,"biped","A tiny, twitchy squirrel-like spark creature standing on its hind legs.",
  "a huge zig-zag lightning-bolt tail curling up behind it","antenna (two antennae ending in round tips), tail","volt yellow / charcoal / white","fierce",""),
 ("coilsnail","Coilsnail","Volt",1.12,"shell","A big, sturdy snail whose shell is a spiral of copper coil.",
  "a large spiral shell wound like a copper coil, with two stubby wing-fins on top","horns (two short horns on the head), antenna (eye stalks ending in yellow bulbs), wings (stubby wing-fins)","volt yellow / copper / slate grey","sleepy",""),
 ("warden","Gravewood","Thorn",1.45,"quadruped","A huge ancient forest stag-beast, part tree, the Warden of the forest ruins.",
  "towering antlers of gnarled branches with hanging moss","horns, spikes (bark spikes on the shoulders), leaf, tail","deep moss green / dark bark brown / bone white, with ember-orange eyes","fierce",
  "Manifest key `warden`. Set `recolor` to null and drop its current wash."),
 ("noctyrm","Noctyrm","Ember",1.5,"quadruped","A regal night dragon, the final boss, whose element shifts in battle.",
  "a crown of horns and wide bat-like wings held high","wings, tail, spikes, horns, crown","night violet / near-black indigo / ember orange (eyes, crown gems, wing membranes, chest)","proud",
  "Noctyrm changes element in battle, so the game recolours it. Keep its body night violet and indigo (the recolour leaves those alone) and put all the element colour in the **ember-orange** accents, which `recolor.gd` remaps to the current element. Keep a `recolor` entry in the manifest (not null), without the night wash."),
]


REF = ("Use the attached image as the style reference. Match its pixel size, palette, outline, shading and lighting exactly. "
  "Do not copy its design, pose details or colours beyond the palette. Make a new creature described in SUBJECT.")
# Anchor prompts attach quadruped.png, a different body type: say so, or the result drifts toward a four-legged dragon.
REF_ANCHOR = ("Use the attached image as the style reference only. Match its pixel size, palette, outline, shading and lighting exactly. "
  "The attached creature has a different body type: do not copy its body shape, legs, wings, pose or design. "
  "Make a new creature described in SUBJECT, built as its Body plan says.")

def prompt(c, ref=REF):
    key,name,el,size,plan,pitch,hook,feats,cols,expr,_ = c
    p = PLANS[plan]; h = round(100*size)
    style = STYLE.format(h=h, span=p["span"], body=p["body"], ground=p["ground"])
    elline = (f"{el} accents only ({EL[el]}); the body itself is night violet" if key == "noctyrm"
              else f"{el}, main body colour {EL[el]}")
    return (f"{ref}\n\nSTYLE (fixed, do not reinterpret):\n{style}\n\nSUBJECT:\n{pitch}\nName: {name}\nElement: {elline}\n"
      f"Size: {size}\nBody plan: {plan}\nSilhouette hook: {hook}\nFeatures: {feats}\nColours: {cols}\nExpression: {expr}")

def norm(c, out, scale=""):
    return f"python3 scripts/hd2d-sprite.py raw.png {out} --kind monster --size {c[3]}{scale}"

ANCH = {"brinecrab": ("shell", "Brinecrab, Coilsnail"), "puddlet": ("blob", "Puddlet"), "brambat": ("winged", "Brambat, Skiray")}
out = ["""# HD-2D roster prompts (ChatGPT)

Ready-to-paste prompts for every creature, the Warden and the boss. **Generated by `scripts/hd2d-prompts.py`; edit designs there and rerun it, not here.** One Style Block feeds every prompt so the wording never drifts. The method, locked constants and checklist are in [HD2D.md](../HD2D.md).

There are two parts, done in this order:
1. **[Part A: make the missing anchors](#part-a-make-the-missing-anchors)** (shell, blob, winged). Every later prompt attaches an anchor, so these come first.
2. **[Part B: the roster](#part-b-the-roster)**, one prompt per creature.

## Anchors you already have

| File | Body type |
|---|---|
| `docs/hd2d/anchors/humanoid.png` | humanoid (Sable), the first anchor, made with [HD2D.md prompt A](../HD2D.md#a-first-humanoid-anchor-no-attachments) and no attachment |
| `docs/hd2d/anchors/biped.png` | biped (Ember fox) |
| `docs/hd2d/anchors/quadruped.png` | quadruped (Emberwing dragon) |

These are approved and stay as they are. Part A built three more from them.

# Part A: make the missing anchors

**Status (2026-10-08): all three exist** (`shell.png`, `blob.png`, `winged.png`). This part is kept for remaking one; `scripts/hd2d-codex.py` attaches the new anchor once it exists.

An anchor is the approved sprite that every later prompt of that body type attaches as its style reference. The roster uses five monster body types. Biped and quadruped have anchors; shell, blob and winged don't, and a mismatched reference pulls a creature toward the wrong body (that is how the Ember fox got its scarf and boots from the humanoid anchor). Each new anchor below is a real roster creature, so making the anchor also makes that creature's sprite.

| Anchor to make | Creature | Later used for |
|---|---|---|
"""]
for k,(a,used) in ANCH.items():
    out.append(f"| `docs/hd2d/anchors/{a}.png` | {[c for c in C if c[0]==k][0][1]} | {used} |\n")
out.append("""
**For each anchor:**
1. Open a **new chat** in ChatGPT. Attach **`docs/hd2d/anchors/quadruped.png`** (the dragon). It is the closest existing style, and the prompt tells ChatGPT to take only its style, not its body.
2. Paste the prompt below as is.
3. Regenerate until one passes the [checklist](../HD2D.md#checklist) **and** the anchor checks below. Expect 5–10 tries; this is the one place to be picky, because every later creature of this body type copies it. For a near miss, fix one thing in the same chat (`Same creature, same pose, same palette, same pixel size. Change only: ...`); after two edits that don't land, start a new chat.
4. Download the image and run both normalize commands under the prompt. The first writes the anchor (upscaled for viewing and attaching, like the other anchors); the second writes the creature's game sprite at its true pixel grid (`--scale 1`, how game sprites are stored).
5. Check the anchor at full size: the normalizer's reported source grid should be 8–11 px, like the other anchors, so the pixels match the cast's.
6. Add the creature's manifest entry (see [Adding to the game](#adding-to-the-game)) and add a row for the anchor to the table in [HD2D.md Step 1](../HD2D.md#step-1-anchors-one-per-body-type).

**Anchor checks** (on top of the checklist):
- The body type reads at a glance: shelled is low and wide with the shell dominating; blob has no legs and sits flat; winged hovers with both wings fully visible and spread.
- Nothing dragon-like leaked in from the reference: no dragon wings, horns, scales or four-legged stance unless the SUBJECT asks for them.
- Pixel size, outline and light look like they belong next to the three existing anchors. Put them side by side to compare.

""")
for c in C:
    if c[0] not in ANCH: continue
    a = ANCH[c[0]][0]
    out.append(f"## Anchor: {a} ({c[1]})\n\nAttach `quadruped.png`.\n\n```\n{prompt(c, REF_ANCHOR)}\n```\n\n")
    out.append(f"```bash\n{norm(c, f'docs/hd2d/anchors/{a}.png')}\n{norm(c, f'godot/art/hd2d/{c[0]}.png', ' --scale 1')}\n```\n\n")

out.append("""# Part B: the roster

**For each creature:** new chat, attach the anchor named in its heading, paste the prompt, regenerate until it passes the [checklist](../HD2D.md#checklist), normalize with the command under it, then add it to the manifest ([Adding to the game](#adding-to-the-game)). One creature per chat.

Within a body type, only the SUBJECT differs between prompts (the height, body sentence and baseline sentence change per body type). To change a design, edit only the SUBJECT.

| Creature | Element | Size → px | Body plan | Attach |
|---|---|---|---|---|
""")
for c in C:
    h = round(100*c[3])
    att = "made in Part A" if c[0] in ANCH else f"`{PLANS[c[4]]['anchor']}`"
    out.append(f"| {c[1]} | {c[2]} | {c[3]} → {h} | {c[4]} | {att} |\n")
out.append("\n")
i = 0
for c in C:
    if c[0] in ANCH: continue
    i += 1
    key,name,el,size,plan = c[:5]; note = c[10]
    out.append(f"## {i}. {name} (attach `{PLANS[plan]['anchor']}`)\n\n")
    if plan in ("shell","winged"): out.append(f"Needs the `{plan}` anchor from Part A first.\n\n")
    if note: out.append(note + "\n\n")
    out.append("```\n" + prompt(c) + "\n```\n\n")
    out.append(f"```bash\n{norm(c, f'godot/art/hd2d/{key}.png', ' --scale 1')}\n```\n\n")

out.append("""# Adding to the game

The normalizer prints `anchor`, `height` and `head` numbers. In `godot/art/hd2d/manifest.gd`, replace the creature's placeholder in `creatures()` with its own entry:

```gdscript
"kilnback": {"image": "kilnback", "anchor": Vector2(0.5, 0.9), "height": 140.0, "head": Vector2(0.6, 0.3),
	"emitters": [], "recolor": null},
```

Paste the printed numbers in place of the example ones. `recolor: null` keeps the painted colours (every creature except Noctyrm). `head` is an estimate; nudge it after a look in game (`--shot=battle`, see CLAUDE.md Commands).
""")
open(ROOT / "docs/hd2d/prompts.md", "w").write("".join(out).rstrip()+"\n")

# Machine-readable copy for scripts/hd2d-codex.py: per species, the prompt, the anchor to attach,
# and (for Part A creatures) the anchor file the result also becomes.
import json
data = {}
for c in C:
    a = ANCH.get(c[0])
    data[c[0]] = {"name": c[1], "size": c[3], "plan": c[4], "notes": c[10],
                  "attach": "quadruped.png" if a else PLANS[c[4]]["anchor"],
                  "makes_anchor": f"{a[0]}.png" if a else None,
                  "prompt": prompt(c, REF_ANCHOR if a else REF),
                  # once its own anchor exists, a regeneration attaches that and uses the plain reference line
                  "prompt_own_anchor": prompt(c) if a else None}
(ROOT / "docs/hd2d/prompts.json").write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
