# Run state. One mutable object, read and written by battle/run/ui. Port of game/src/game/state.ts.
extends Node

var mode: String = "title"      ## "title" "map" "intro" "battle" "anim" "end" "reward" "over" "meta"
var party: Array[Mon] = []
var lineup: Array[int] = []     ## uids (≤3)
var active: int = 0             ## uid of the lead
var draw: Array[CardRef] = []
var disc: Array[CardRef] = []
var hand: Array = []            ## CardRef or null per slot
var energy: float = 0.0
var floor: int = 1
var enemy: Enemy = null
var swap_cd: float = 0.0
var auto_t: float = 0.0
var chain: int = 0
var chain_t: float = 99.0
var discount: int = 0
var wired: bool = false         ## Live Wire already paid out for the current chain
## Bumped whenever a battle/run ends; delayed callbacks compare against it and bail if stale.
var tok: int = 0
var picks: Array = []           ## lineup chosen on the title screen (species keys, first = lead)
var stats: Dictionary = {"start": 0, "dealt": 0, "perfects": 0}
var nodes: Array = []           ## MapNode
var actors: Dictionary = {}     ## party member Actors by uid
var em = null                   ## enemy Actor
var title_actor = null
var uid: int = 1

func mon(u: int) -> Mon:
	for c in party:
		if c.uid == u:
			return c
	return null

func act() -> Mon:
	return mon(active)

func team() -> Array[Mon]:
	var out: Array[Mon] = []
	for u in lineup:
		var c := mon(u)
		if c:
			out.append(c)
	return out

func bench() -> Array:
	return team().filter(func(c): return c.uid != active)

func active_actor():
	var c := act()
	return actors.get(c.uid) if c else null

## A fresh party member. Its moves and Trait come from the saved loadout (§16), its numbers from its upgrades (§5.2).
func new_mon(key: String, shiny := false) -> Mon:
	var sp: Dictionary = Data.SPECIES[key]
	var lo: Dictionary = Meta.loadout(key)
	var b: Dictionary = Meta.boosts(key)
	var c := Mon.new()
	c.uid = uid
	uid += 1
	c.key = key
	c.name = sp.name
	c.el = sp.el
	c.max_hp = roundi(sp.hp * b.vital)
	c.hp = c.max_hp
	c.shiny = shiny
	c.power = b.power
	c.spirit = b.spirit
	c.moves = {"strike": 0, "skill": lo.skill, "sig": lo.sig}
	c.trait_key = lo["trait"]
	return c

## The base card a creature has equipped in a slot (before upgrades).
func base_card(c: Mon, slot: String) -> Dictionary:
	var l: Array = Data.SPECIES[c.key].cards[slot]
	var i: int = c.moves.get(slot, 0)
	return l[i] if i >= 0 and i < l.size() else l[0]

## The card a ref points at, with in-run and permanent upgrades applied: {def, pow, owner}.
## `pow` scales status durations and Discharge.
func card_of(r: CardRef) -> Dictionary:
	var owner := mon(r.uid)
	var base := base_card(owner, r.slot)
	var up = owner.ups.get(r.slot)
	var pow: float = Data.BAL.up_power if up == "power" else 1.0
	var def: Dictionary = Data.boost_card(Data.scale_card(base, pow), owner.power, owner.spirit).duplicate(true)
	def.cost = maxi(0, base.cost - (1 if up == "cost" else 0))
	return {"def": def, "pow": pow, "owner": owner}

func card_cost(r: CardRef) -> int:
	var co := card_of(r)
	var owner: Mon = co.owner
	if owner.trait_key == "quickfuse" and owner.played == 0:
		return 0   # Quickfuse: first card free
	return maxi(0, co.def.cost - discount)

## Why a card can't be played right now ("" = playable, "energy", "swap", "busy").
func card_block(r: CardRef) -> String:
	if mode != "battle":
		return "busy"
	if energy < card_cost(r):
		return "energy"
	if r.uid != active and swap_cd > 0:
		return "swap"
	return ""

# ---------- derived enemy state ----------
func is_heavy(e: Enemy) -> bool:
	return (e.count + 1) % int(Data.BAL.heavy_every) == 0

## Element and name of the enemy's next heavy: {el, name}.
func heavy_of(e: Enemy) -> Dictionary:
	if e.kind == "warden":
		return Data.WARDEN_HEAVIES[e.heavy_idx % Data.WARDEN_HEAVIES.size()]
	return {"el": e.el, "name": Data.SPECIES[e.key].get("heavy", Data.HEAVY_NAME[e.el])}

## True during the last moments of a heavy wind-up, when a resisting swap is Perfect.
func in_perfect_window(e: Enemy) -> bool:
	return is_heavy(e) and e.windup - e.t <= Data.BAL.perfect_win

const ACTOR_SCRIPT := "res://render/actor.gd"
## Optional override for creating Actors (tests install stubs). Default: Actor.create(key, el).
var actor_factory: Callable

## A new on-stage Actor (TS `new Actor(key, el)`).
func make_actor(key: String, el := ""):
	if actor_factory.is_valid():
		return actor_factory.call(key, el)
	return load(ACTOR_SCRIPT).create(key, el)

## The Actor for a party member, created on demand.
func actor_for(c: Mon):
	var a = actors.get(c.uid)
	if a == null or not is_instance_valid(a):
		a = make_actor(c.key, c.el)
		a.set_shiny(c.shiny)
		actors[c.uid] = a
	return a

func drop_actor(u: int) -> void:
	var a = actors.get(u)
	if a != null and is_instance_valid(a):
		a.destroy()
	actors.erase(u)

func clear_actors() -> void:
	for a in actors.values():
		if a != null and is_instance_valid(a):
			a.destroy()
	actors = {}
	if em != null and is_instance_valid(em):
		em.destroy()
	em = null
	if title_actor != null and is_instance_valid(title_actor):
		title_actor.destroy()
	title_actor = null
