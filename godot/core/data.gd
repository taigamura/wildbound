# Static game content: elements, statuses, roster, cards, balance numbers.
# Port of game/src/core/data.ts. ../CLAUDE.md (Part 1) is the spec. Change a number here, change it there too.
#
# Card defs are Dictionaries with snake_case keys (see CARD_KEYS below). An absent key means "none",
# so read optional fields with `def.get("dmg", 0)`.
# Note: `trait` is a reserved word in GDScript 4.7, so read the "trait" key of a dict with brackets: `d["trait"]`.
extends Node

const ELEM := {
	"ember": {"name": "Ember", "hex": Color("#ff6a3d"), "glow": [Color("#ff6a3d"), Color("#ffa23d"), Color("#ffe08a")]},
	"tide": {"name": "Tide", "hex": Color("#34a8ff"), "glow": [Color("#34a8ff"), Color("#8fe3ff"), Color("#e8fbff")]},
	"thorn": {"name": "Thorn", "hex": Color("#4fcf5c"), "glow": [Color("#4fcf5c"), Color("#b6f27a"), Color("#2fae55")]},
	"volt": {"name": "Volt", "hex": Color("#ffcf2e"), "glow": [Color("#ffcf2e"), Color("#ffffff"), Color("#fff3a0")]},
}
const EL_KEYS: Array[String] = ["ember", "tide", "thorn", "volt"]
## The UI's neutral colour (style.css --neutral), used where an element is missing.
const NEUTRAL := Color("#c9b8ff")

# ================= balance =================
var BAL := {
	"floors": 8,
	# elements
	"strong": 1.5, "weak": 0.66,
	# energy & hand
	"energy_rate": 1.0, "energy_max": 10.0, "energy_start": 3.0, "hand": 4,
	# swapping
	"swap_cost": 0, "swap_cd": 6.0, "shock_swap_cd": 1.0, "discard_cost": 1,
	# auto-attack
	"auto_iv": 1.5, "auto_dmg": 2,
	# enemy
	"intent": 3.0, "heavy_every": 3, "heavy_extra": 2.0, "heavy_mult": 2.5, "enemy_dmg": 5,
	"wild_hp": 90, "hp_per_floor": 0.15, "dmg_per_floor": 0.10, "biome_b_bonus": 2,
	"alpha_hp": 1.5, "alpha_dmg": 1.25,
	"warden_hp": 300, "warden_dmg": 7, "boss_dmg": 8, "boss_shift": 7.0,
	# perfect swap
	"perfect_win": 0.4, "perfect_reflect": 0.5, "perfect_refund": 2, "slow_scale": 0.3, "slow_dur": 0.5,
	# chain
	"chain_win": 1.5, "chain_step": 0.1, "chain_max": 5,
	# statuses
	"burn_dps": 2, "burn_dur": 4.0, "soak_mult": 1.25, "soak_dur": 4.0, "root_slow": 0.4, "root_dur": 3.0, "shock_immune": 6.0,
	# shields
	"shield_delay": 3.0, "shield_decay": 0.2,
	# party & run
	"lineup": 3, "heal_reward": 0.4,
	# in-run card upgrades (§7)
	"up_power": 1.3,
	# loot (§5.1): gold, and materials sword/orb/jewel
	"wild_gold": [8, 12], "gold_per_floor": 0.15, "wild_mat_chance": 0.35,
	"alpha_gold_mul": 2, "alpha_mats": 1, "warden_gold": 40, "warden_mats": 2, "boss_gold": 80, "win_gold": 50,
	# permanent creature upgrades (§5.2): +per level; level n→n+1 costs (n+1) material + up_gold×(n+1) gold
	"up_max": 5, "up_dmg": 0.08, "up_spirit": 0.10, "up_hp": 0.08, "up_gold": 20,
	# item shop (§5.3)
	"shop_mat": 30, "shop_pack": 150, "shop_sell": 15,
	# daily pack
	"pack_reset_hour": 4,
	# loadouts & essence (§16)
	"ess_wild": 1, "ess_alpha": 2, "ess_warden": 3, "ess_boss": 2, "move_cost": 5, "trait_cost": 8,
	# trait numbers
	"bulwark_delay": 3.0, "ebb_heal": 4, "deep_roots": 1.5, "thirst": 0.3, "overshade": 0.5, "livewire_chain": 3,
}

## Each element beats the next one in the loop: ember → thorn → volt → tide → ember.
const BEATS := {"ember": "thorn", "thorn": "volt", "volt": "tide", "tide": "ember"}

## Element multiplier of an attack of element `a` on a defender of element `d` (null/"" = neutral).
func adv(a, d) -> float:
	if a == null or d == null or a == "" or d == "":
		return 1.0
	if BEATS[a] == d:
		return BAL.strong
	if BEATS[d] == a:
		return BAL.weak
	return 1.0

## True if a creature of element `def` resists attacks of element `atk`.
func resists(def, atk) -> bool:
	return def != null and def != "" and BEATS.get(def) == atk

# ================= statuses =================
const STATUS_OF := {"ember": "burn", "tide": "soak", "thorn": "root", "volt": "shock"}
const STATUS_EL := {"burn": "ember", "soak": "tide", "root": "thorn", "shock": "volt"}
const STATUS_NAME := {"burn": "Burn", "soak": "Soak", "root": "Root", "shock": "Shock"}
const STATUS_PAST := {"burn": "Burned", "soak": "Soaked", "root": "Rooted", "shock": "Shocked"}
var STATUS_DUR := {}

# ================= cards =================
const SLOTS: Array[String] = ["strike", "skill", "sig"]
## Every key a card def may carry (besides name and cost):
## dmg, hits, bonus_if {status, dmg}, from_shield, status, shield, shield_team, heal, heal_team,
## lifesteal, energy, self_dmg, discount, chain, reflect, next_strike, cleanse.
const CARD_KEYS := ["dmg", "hits", "bonus_if", "from_shield", "status", "shield", "shield_team", "heal", "heal_team",
	"lifesteal", "energy", "self_dmg", "discount", "chain", "reflect", "next_strike", "cleanse"]

static func _r(v, k: float) -> int:
	return roundi(v * k)

## Scales every number a "+30% effect" upgrade touches. Returns a copy.
func scale_card(c: Dictionary, k: float) -> Dictionary:
	if k == 1.0:
		return c
	var o := c.duplicate(true)
	for key in ["dmg", "shield", "shield_team", "heal", "heal_team", "energy"]:
		if c.has(key):
			o[key] = _r(c[key], k)
	if c.has("bonus_if"):
		o.bonus_if.dmg = _r(c.bonus_if.dmg, k)
	if c.get("lifesteal", 0):
		o.lifesteal = minf(1.0, snappedf(c.lifesteal * k, 0.01))
	if c.get("reflect", 0):
		o.reflect = minf(1.0, snappedf(c.reflect * k, 0.01))
	if c.get("next_strike", 0):
		o.next_strike = snappedf(c.next_strike * k, 0.1)
	return o

## Permanent upgrades (§5.2): damage ×power, shield and heal amounts ×spirit. Returns a copy.
func boost_card(c: Dictionary, power: float, spirit: float) -> Dictionary:
	if power == 1.0 and spirit == 1.0:
		return c
	var o := c.duplicate(true)
	if c.has("dmg"):
		o.dmg = _r(c.dmg, power)
	if c.has("bonus_if"):
		o.bonus_if.dmg = _r(c.bonus_if.dmg, power)
	for key in ["shield", "shield_team", "heal", "heal_team"]:
		if c.has(key):
			o[key] = _r(c[key], spirit)
	return o

# ================= loot (§5) =================
const MATS: Array[String] = ["sword", "orb", "jewel"]
## Each material feeds one upgrade track.
var MAT_DEF := {}

func NO_LOOT() -> Dictionary:
	return {"gold": 0, "sword": 0, "orb": 0, "jewel": 0}
func no_loot() -> Dictionary:
	return NO_LOOT()

## True if "+30% effect" changes anything (otherwise only −1 cost is offered).
func scalable(c: Dictionary) -> bool:
	for key in ["dmg", "bonus_if", "from_shield", "shield", "shield_team", "heal", "heal_team", "energy", "lifesteal", "reflect", "next_strike"]:
		if c.get(key):
			return true
	return c.has("status") and c.status != "shock"

## Number formatting like JS template literals: 2 → "2", 2.6 → "2.6".
static func num(v) -> String:
	if typeof(v) == TYPE_FLOAT and v == floorf(v):
		return str(int(v))
	return str(v)

## Short rules text for a card. `pow` is the effect multiplier (status durations and Discharge scale with it).
func card_text(c: Dictionary, pow := 1.0) -> String:
	var out: Array[String] = []
	if c.get("from_shield"):
		out.append(("Dmg = shield ×%.1f" % pow) if pow > 1 else "Dmg = your shield")
	if c.get("dmg"):
		out.append(num(c.dmg) + " dmg" + ((" ×" + num(c.hits)) if c.get("hits", 1) > 1 else ""))
	if c.has("bonus_if"):
		out.append("+%s if %s" % [num(c.bonus_if.dmg), STATUS_PAST[c.bonus_if.status]])
	if c.has("status"):
		out.append(STATUS_NAME[c.status] + ((" %.1fs" % (STATUS_DUR[c.status] * pow)) if c.status != "shock" and pow > 1 else ""))
	if c.get("shield"):
		out.append("shield " + num(c.shield))
	if c.get("shield_team"):
		out.append("team shield " + num(c.shield_team))
	if c.get("heal"):
		out.append("heal " + num(c.heal))
	if c.get("heal_team"):
		out.append("team heal " + num(c.heal_team))
	if c.get("lifesteal"):
		out.append("heal %d%% of dmg" % roundi(c.lifesteal * 100))
	if c.get("energy"):
		out.append("+" + num(c.energy) + " energy")
	if c.get("self_dmg"):
		out.append("take " + num(c.self_dmg))
	if c.get("discount"):
		out.append("next card −1")
	if c.get("chain"):
		out.append("+" + num(c.chain) + " chain")
	if c.get("reflect"):
		out.append("reflect %d%% next hit" % roundi(c.reflect * 100))
	if c.get("next_strike"):
		out.append("next Strike ×" + num(c.next_strike))
	if c.get("cleanse"):
		out.append("cleanse team")
	return ", ".join(out)

# ================= traits (§16) =================
## Passive rules each creature carries in its socket. `from` is the species it's built in to.
const TRAITS := {
	"afterglow": {"name": "Afterglow", "from": "emberwick", "text": "When its Burn on the enemy ends, +1 energy"},
	"quickfuse": {"name": "Quickfuse", "from": "cinderpip", "text": "Its first card each fight costs 0"},
	"bulwark": {"name": "Bulwark", "from": "kilnback", "text": "Its shields start decaying 3s later"},
	"ebb": {"name": "Ebb", "from": "bellspring", "text": "Heals 4 when swapped out"},
	"undercurrent": {"name": "Undercurrent", "from": "puddlet", "text": "Its heals also cleanse whoever they heal"},
	"counterweave": {"name": "Counterweave", "from": "brinecrab", "text": "A Perfect Swap into it also fires its Strike for free"},
	"deeproots": {"name": "Deep Roots", "from": "truffmole", "text": "Root it applies lasts +1.5s"},
	"thirst": {"name": "Thirst", "from": "brambat", "text": "Its Strikes heal it for 30% of their damage"},
	"overshade": {"name": "Overshade", "from": "mossling", "text": "When it shields itself, the weakest teammate gets half"},
	"relay": {"name": "Relay", "from": "skiray", "text": "After you swap to it, your next card costs 1 less"},
	"livewire": {"name": "Live Wire", "from": "sparkit", "text": "The first time its card reaches chain 3+, +1 energy"},
	"grounded": {"name": "Grounded", "from": "coilsnail", "text": "Can't be Shocked; a Shock on it gives +1 energy instead"},
}

# ================= roster =================
## SPECIES[key] = {name, el, hp, size, feats, role?, atk?, spd?, cards?: {strike: [def...], skill: [...], sig: [...]},
## "trait"?, heavy?, warden?, boss?}. Card lists are [default, ...alternates] (§16).
var SPECIES := {}

static func C(name: String, cost: int, fx: Dictionary) -> Dictionary:
	var d := {"name": name, "cost": cost}
	d.merge(fx)
	return d

func _build_species() -> void:
	SPECIES = {
		# ---------- Ember
		"emberwick": {"name": "Emberwick", "el": "ember", "hp": 50, "trait": "afterglow", "size": 1.0, "feats": ["ears", "flame", "tail"], "role": "Balanced",
			"cards": {"strike": [C("Peck", 1, {"dmg": 6})], "skill": [C("Kindle", 2, {"status": "burn"}), C("Flare Step", 1, {"energy": 1, "chain": 1})], "sig": [C("Wickflare", 3, {"dmg": 14, "bonus_if": {"status": "burn", "dmg": 8}}), C("Wildfire", 3, {"dmg": 8, "status": "burn", "chain": 1})]}},
		"cinderpip": {"name": "Cinderpip", "el": "ember", "hp": 35, "trait": "quickfuse", "size": 0.85, "feats": ["ears", "flame"], "role": "Glass cannon", "atk": 1.2, "spd": 1.1,
			"cards": {"strike": [C("Scorch", 1, {"dmg": 7})], "skill": [C("Flicker", 1, {"discount": 1}), C("Flare Up", 1, {"chain": 1, "self_dmg": 2})], "sig": [C("Flashfire", 4, {"dmg": 24}), C("Ember Barrage", 3, {"dmg": 5, "hits": 3})]}},
		"kilnback": {"name": "Kilnback", "el": "ember", "hp": 75, "trait": "bulwark", "size": 1.22, "feats": ["horns", "spikes", "flame"], "role": "Tank", "atk": 0.85, "spd": 0.9,
			"cards": {"strike": [C("Bash", 1, {"dmg": 5})], "skill": [C("Hearth Shell", 2, {"shield": 12}), C("Forge", 2, {"shield": 6, "next_strike": 2})], "sig": [C("Slow Burn", 3, {"status": "burn", "shield": 8}), C("Magma Ram", 3, {"dmg": 16, "self_dmg": 4})]}},
		# ---------- Tide
		"bellspring": {"name": "Bellspring", "el": "tide", "hp": 55, "trait": "ebb", "size": 0.95, "feats": ["fin", "tail", "whisk"], "role": "Sustain",
			"cards": {"strike": [C("Splash", 1, {"dmg": 5})], "skill": [C("Drench", 2, {"status": "soak"}), C("Tidecall", 2, {"shield_team": 5})], "sig": [C("Lantern Tide", 3, {"dmg": 10, "heal_team": 8}), C("Undertide", 3, {"dmg": 14, "bonus_if": {"status": "soak", "dmg": 6}})]}},
		"puddlet": {"name": "Puddlet", "el": "tide", "hp": 40, "trait": "undercurrent", "size": 0.85, "feats": ["fin", "whisk"], "role": "Healer", "atk": 0.9,
			"cards": {"strike": [C("Drip", 1, {"dmg": 4})], "skill": [C("Mend", 2, {"heal": 15}), C("Bubble", 1, {"shield": 7})], "sig": [C("Spring Rain", 4, {"heal_team": 12, "cleanse": true}), C("Wellspring", 3, {"heal_team": 6, "energy": 2})]}},
		"brinecrab": {"name": "Brinecrab", "el": "tide", "hp": 80, "trait": "counterweave", "size": 1.18, "feats": ["horns", "fin", "whisk"], "role": "Tank", "atk": 0.9, "spd": 0.9,
			"cards": {"strike": [C("Pinch", 1, {"dmg": 6})], "skill": [C("Barnacle", 2, {"shield": 14}), C("Brace", 1, {"reflect": 0.3})], "sig": [C("Undertow", 3, {"dmg": 12, "status": "soak"}), C("Tidal Clamp", 3, {"dmg": 10, "shield": 10})]}},
		# ---------- Thorn
		"truffmole": {"name": "Truffmole", "el": "thorn", "hp": 55, "trait": "deeproots", "size": 1.0, "feats": ["leaf", "ears"], "role": "Control",
			"cards": {"strike": [C("Dig", 1, {"dmg": 6})], "skill": [C("Tangle", 2, {"status": "root"}), C("Burrow", 2, {"shield": 8, "next_strike": 2})], "sig": [C("Sporeburst", 3, {"dmg": 12, "heal": 6}), C("Rootquake", 4, {"dmg": 16, "status": "root"})]}},
		"brambat": {"name": "Brambat", "el": "thorn", "hp": 40, "trait": "thirst", "size": 0.9, "feats": ["wings", "ears", "spikes"], "role": "Drain", "atk": 1.1, "spd": 1.1,
			"cards": {"strike": [C("Nip", 1, {"dmg": 5, "heal": 2})], "skill": [C("Thornveil", 2, {"reflect": 0.5}), C("Hemlock", 2, {"status": "root", "heal": 6})], "sig": [C("Leech Dive", 3, {"dmg": 12, "lifesteal": 0.5}), C("Thorn Storm", 4, {"dmg": 8, "hits": 2, "reflect": 0.3})]}},
		"mossling": {"name": "Mossling", "el": "thorn", "hp": 50, "trait": "overshade", "size": 1.1, "feats": ["spikes", "leaf"], "role": "Support", "atk": 0.9,
			"cards": {"strike": [C("Swat", 1, {"dmg": 5})], "skill": [C("Overgrow", 2, {"status": "root", "shield": 6}), C("Photosynth", 2, {"heal_team": 5})], "sig": [C("Canopy", 3, {"shield_team": 8}), C("Strangle Vine", 3, {"dmg": 10, "bonus_if": {"status": "root", "dmg": 6}})]}},
		# ---------- Volt
		"skiray": {"name": "Skiray", "el": "volt", "hp": 45, "trait": "relay", "size": 0.9, "feats": ["antenna", "ears", "tail"], "role": "Tempo", "spd": 1.15,
			"cards": {"strike": [C("Zap", 0, {"dmg": 3})], "skill": [C("Static", 2, {"status": "shock"}), C("Tailwind", 1, {"chain": 2})], "sig": [C("Gale Strike", 3, {"dmg": 10, "chain": 1}), C("Arc Lash", 3, {"dmg": 6, "status": "shock"})]}},
		"sparkit": {"name": "Sparkit", "el": "volt", "hp": 35, "trait": "livewire", "size": 0.85, "feats": ["antenna", "tail"], "role": "Glass cannon", "atk": 1.2, "spd": 1.1,
			"cards": {"strike": [C("Jolt", 1, {"dmg": 7})], "skill": [C("Overcharge", 1, {"energy": 2, "self_dmg": 4}), C("Supercharge", 2, {"next_strike": 3})], "sig": [C("Thunderclap", 4, {"dmg": 22}), C("Ball Lightning", 3, {"dmg": 14, "chain": 1})]}},
		"coilsnail": {"name": "Coilsnail", "el": "volt", "hp": 70, "trait": "grounded", "size": 1.12, "feats": ["horns", "antenna", "wings"], "role": "Tank", "atk": 0.85, "spd": 0.9,
			"cards": {"strike": [C("Prod", 1, {"dmg": 5})], "skill": [C("Capacitor", 2, {"shield": 10, "next_strike": 2}), C("Grounding", 2, {"shield": 8, "cleanse": true})], "sig": [C("Discharge", 3, {"from_shield": true}), C("Static Field", 3, {"shield_team": 6, "status": "shock"})]}},
		# ---------- Warden & boss
		"warden": {"name": "Gravewood", "el": "thorn", "hp": 300, "size": 1.45, "feats": ["horns", "spikes", "leaf", "tail"], "warden": true},
		"noctyrm": {"name": "Noctyrm", "el": "ember", "hp": 270, "size": 1.5, "feats": ["wings", "tail", "spikes", "horns", "crown"], "boss": true, "heavy": "Eclipse Volley"},
	}

const STARTERS: Array[String] = ["emberwick", "bellspring", "truffmole"]
## The 12 collectible creatures, in collection order.
const ROSTER: Array[String] = ["emberwick", "cinderpip", "kilnback", "bellspring", "puddlet", "brinecrab", "truffmole", "brambat", "mossling", "skiray", "sparkit", "coilsnail"]
const POOL_A: Array[String] = ["cinderpip", "puddlet", "brambat", "skiray", "kilnback", "mossling"]
const POOL_B: Array[String] = ["brinecrab", "sparkit", "coilsnail"]

func biome_of(floor_n: int) -> int:
	return 0 if floor_n <= 4 else 1

## Heavy attack names by element. The Warden alternates two.
const HEAVY_NAME := {"ember": "Blaze Charge", "tide": "Riptide Slam", "thorn": "Bramble Crush", "volt": "Thunder Ram"}
const WARDEN_HEAVIES := [{"name": "Bramble Crush", "el": "thorn"}, {"name": "Wildfire Roar", "el": "ember"}]

# ================= icons =================
## SVG path data (24×24 viewBox), as in TS. The UI may draw these or use its own icons.
const GLYPH := {
	"ember": '<path d="M12 2c1 4 6 6 6 12a6 6 0 0 1-12 0c0-3 2-5 3-6 0 2 1 3 2 3 0-4 1-7 1-9z"/>',
	"tide": '<path d="M12 2C9 7 5 11 5 15a7 7 0 0 0 14 0c0-4-4-8-7-13z"/>',
	"thorn": '<path d="M20 3C10 3 4 9 4 16c0 2 1 5 1 5s2-6 7-9c-3 3-5 6-6 9 9 0 14-7 14-18z"/>',
	"volt": '<path d="M13 1L4 14h7l-2 9 10-13h-7l2-9z"/>',
	"shield": '<path d="M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5l8-3z"/>',
	"heart": '<path d="M12 21s-8-5-8-11a4.5 4.5 0 0 1 8-3 4.5 4.5 0 0 1 8 3c0 6-8 11-8 11z"/>',
	"star": '<path d="M12 2l3 7h7l-5.5 4.5L18.5 21 12 16.5 5.5 21l2-7.5L2 9h7z"/>',
	"spark": '<path d="M12 1l2.2 7.8L22 11l-7.8 2.2L12 21l-2.2-7.8L2 11l7.8-2.2z"/>',
	"claw": '<path d="M5 18L14 4M9.5 21L18.5 7M14.5 21.5L20.5 12"/>',
	"skull": '<path d="M12 2a9 9 0 0 0-9 9c0 3 1.5 5 3 6v4h12v-4c1.5-1 3-3 3-6a9 9 0 0 0-9-9zm-3.5 9a2 2 0 1 1 0 4 2 2 0 0 1 0-4zm7 0a2 2 0 1 1 0 4 2 2 0 0 1 0-4z"/>',
	"crown": '<path d="M3 7l4.5 4L12 4l4.5 7L21 7l-2 12H5z"/>',
	"moon": '<path d="M15 2a9 9 0 1 0 7 13A8 8 0 0 1 15 2z"/>',
	"chest": '<path d="M3 9a5 5 0 0 1 5-5h8a5 5 0 0 1 5 5v1H3zm0 3h7v2h4v-2h7v8H3z"/>',
	"paw": '<path d="M12 12c3 0 6 3 6 6 0 2-2 3-3.5 3-1 0-1.5-.7-2.5-.7s-1.5.7-2.5.7C8 21 6 20 6 18c0-3 3-6 6-6zM5 8a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5zm14 0a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5zM9 3a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5zm6 0a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5z"/>',
	"orb": '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 2a8 8 0 0 1 7.9 7H15a3 3 0 0 0-6 0H4.1A8 8 0 0 1 12 4z"/>',
	"swap": '<path d="M7 4L3 8l4 4V9h10V7H7zm10 8v3H7v2h10v3l4-4z"/>',
	"up": '<path d="M12 3l8 9h-5v9H9v-9H4z"/>',
	"sound": '<path d="M3 9h4l5-5v16l-5-5H3zm13.5 3a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4zM14 3.2v2.1a7 7 0 0 1 0 13.4v2.1a9 9 0 0 0 0-17.6z"/>',
	"coin": '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 4v1.1c1.6.3 2.8 1.3 2.9 2.9h-2c-.1-.7-.7-1.1-1.9-1.1-1.1 0-1.7.4-1.7 1s.5.9 2.1 1.3c2.2.5 3.6 1.2 3.6 3.1 0 1.6-1.2 2.6-3 2.9V18h-2v-1.1c-1.8-.3-3.1-1.4-3.1-3.1h2c.1.8.8 1.3 2.1 1.3 1.2 0 1.9-.4 1.9-1.1 0-.6-.5-1-2.2-1.4-2-.4-3.5-1.1-3.5-3 0-1.5 1.1-2.5 2.8-2.8V6z"/>',
	"sword": '<path d="M20 2l-1 5-9 9-2-2 9-9zM7 15l2 2-2 2 1.5 1.5-1.5 1.5L5.5 20.5 4 22l-2-2 1.5-1.5L2 17l1.5-1.5L5 17z"/>',
	"jewel": '<path d="M7 3h10l5 6-10 13L2 9zm1.2 2L5.4 8.4h4.1L11 5zm7.6 0H13l1.5 3.4h4.1zM12 6.2l-1.3 2.2h2.6zM5.6 10.4l5.4 7.1-2.5-7.1zm5 0L12 15l1.4-4.6zm4.9 0L13 17.5l5.4-7.1z"/>',
	"mute": '<path d="M3 9h4l5-5v16l-5-5H3zm13.6-.6L19 10.8l2.4-2.4 1.4 1.4-2.4 2.4 2.4 2.4-1.4 1.4-2.4-2.4-2.4 2.4-1.4-1.4 2.4-2.4-2.4-2.4z"/>',
}
## A full SVG document for a glyph (e.g. for Image.load_svg_from_string). `fill` is the path colour.
func svg(k: String, fill := Color.WHITE) -> String:
	var p: String = GLYPH[k]
	var attr := ('fill="none" stroke="#%s" stroke-width="2.4" stroke-linecap="round"' % fill.to_html(false)) if k == "claw" else ('fill="#%s"' % fill.to_html(false))
	return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" %s>%s</svg>' % [attr, p]
## Element colour, or the neutral colour when there is no element (TS elCss).
func el_css(el) -> Color:
	return ELEM[el].hex if el != null and el != "" else NEUTRAL
## Element colour (TS elHexCss).
func el_hex_css(el) -> Color:
	return ELEM[el].hex

func _init() -> void:
	STATUS_DUR = {"burn": BAL.burn_dur, "soak": BAL.soak_dur, "root": BAL.root_dur, "shock": 0.0}
	MAT_DEF = {
		"sword": {"name": "Sword", "track": "Power", "color": ELEM.ember.hex, "text": "+%d%% card and auto-attack damage per level" % roundi(BAL.up_dmg * 100)},
		"orb": {"name": "Orb", "track": "Spirit", "color": ELEM.tide.hex, "text": "+%d%% shield and heal amounts per level" % roundi(BAL.up_spirit * 100)},
		"jewel": {"name": "Jewel", "track": "Vitality", "color": ELEM.thorn.hex, "text": "+%d%% max HP per level" % roundi(BAL.up_hp * 100)},
	}
	_build_species()
