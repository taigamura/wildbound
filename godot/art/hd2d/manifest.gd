# HD-2D cast and ambience. Port of game/src/art/packs/hd2d/manifest.ts.
#
# Sprites are stored at their true pixel grid (scripts/hd2d-sprite.py --scale 1; prompts in
# docs/hd2d/prompts.md). Species without their own sprite yet reuse a placeholder anchor,
# recoloured per element (recolor.gd). Within each element: 1st -> fox (biped),
# 2nd -> Sable (humanoid), 3rd, the tank -> dragon (quadruped).
# To add a real sprite: drop `<species>.png` into this folder and give it a `painted` entry.
#
# Fields (fractions of the image): anchor = feet, head = projectile target, emitters = ambient
# element particles. height = drawn canvas height in art units (56 art units = 1 world unit U).
# recolor: {} = defaults, a Dictionary = options (see recolor.gd), null = keep the painted colours.
extends RefCounted

## Sable keeps her skin and gold trim: only the hair, coat lining and lantern glass shift.
const HUMAN := {"max_hue": 10.0, "min_sat": 0.55}


static func fox() -> Dictionary:
	return {"image": "fox", "anchor": Vector2(0.606, 0.904), "height": 124.0, "head": Vector2(0.64, 0.34),
		"emitters": [Vector2(0.52, 0.1), Vector2(0.23, 0.55)], "recolor": {}}


static func sable() -> Dictionary:
	return {"image": "sable", "anchor": Vector2(0.469, 0.905), "height": 158.0, "head": Vector2(0.57, 0.25),
		"emitters": [Vector2(0.38, 0.69)], "recolor": HUMAN}


## The anchor script puts the dragon's feet at its front claws (0.762); 0.6 centres the body on the pedestal.
static func dragon(recolor: Dictionary = {}, height := 124.0) -> Dictionary:
	return {"image": "dragon", "anchor": Vector2(0.6, 0.904), "height": height, "head": Vector2(0.77, 0.33),
		"emitters": [], "recolor": recolor}


## A species' own sprite, painted in its colours. Numbers come from the normalizer's output.
static func painted(image: String, anchor: Vector2, height: float, head: Vector2) -> Dictionary:
	return {"image": image, "anchor": anchor, "height": height, "head": head, "emitters": [], "recolor": null}


static var _creatures: Dictionary = {}


static func creatures() -> Dictionary:
	if _creatures.is_empty():
		_creatures = {
			"emberwick": fox(), "cinderpip": sable(), "kilnback": dragon(),
			# Anchor x is the body's centre, not the normalizer's lowest-row guess (claw or tail tips).
			"bellspring": painted("bellspring", Vector2(0.56, 0.901), 119.0, Vector2(0.678, 0.3)),
			"puddlet": painted("puddlet", Vector2(0.48, 0.901), 106.0, Vector2(0.55, 0.45)),
			"brinecrab": painted("brinecrab", Vector2(0.5, 0.903), 146.0, Vector2(0.55, 0.35)),
			"truffmole": fox(),
			"brambat": painted("brambat", Vector2(0.51, 0.906), 111.0, Vector2(0.6, 0.4)),
			"mossling": dragon(),
			"skiray": fox(), "sparkit": sable(), "coilsnail": dragon(),
			# Gravewood: deeper, mossier green than Mossling, and 8% larger on top of its species size.
			"warden": dragon({"ramps": {"thorn": [195.0, 168.0, 142.0, 104.0]}, "light": 0.66, "sat": 0.85, "wash": [0.8, 0.9, 0.74]}, 134.0),
			# Noctyrm: a night-washed version of whichever element it currently holds.
			"noctyrm": dragon({"light": 0.74, "sat": 1.1, "wash": [0.8, 0.7, 1.0]}),
		}
	return _creatures


static func entry(key: String) -> Dictionary:
	var c := creatures()
	return c.get(key, fox())


const AMBIENCE := {
	"fireflies": [Color("#ffe6a8"), Color("#ffd27a"), Color("#fff6dc")],
	"leaves": [Color("#8fbf5a"), Color("#d9a441"), Color("#6e9e48")],
	"neutral": Color("#ffd9a0"),
}
