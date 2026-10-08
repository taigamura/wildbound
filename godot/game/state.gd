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

## Cards belong to an element, not a creature. A ref still names its source creature (whose equipped
## card def, slot and in-run `ups` it carries); the card's element is the source's element.
func card_el(r: CardRef) -> String:
	var c := mon(r.uid)
	return c.el if c else ""

## Who fires the card: the lead when it is alive and shares the card's element, else the source
## (used for previews of cards the lead can't play).
func card_by(r: CardRef) -> Mon:
	var lead := act()
	if lead != null and lead.alive and lead.el == card_el(r):
		return lead
	return mon(r.uid)

## The card a ref points at, with in-run upgrades (the source's `ups[slot]`) and the firer's permanent
## Power/Spirit applied: {def, pow, src, by, el}. `by` defaults to card_by(r).
## `pow` scales status durations and Discharge.
func card_of(r: CardRef, by: Mon = null) -> Dictionary:
	var src := mon(r.uid)
	if by == null:
		by = card_by(r)
	var base := base_card(src, r.slot)
	var up = src.ups.get(r.slot)
	var pow: float = Data.BAL.up_power if up == "power" else 1.0
	var def: Dictionary = Data.boost_card(Data.scale_card(base, pow), by.power, by.spirit).duplicate(true)
	def.cost = maxi(0, base.cost - (1 if up == "cost" else 0))
	return {"def": def, "pow": pow, "src": src, "by": by, "el": src.el}

func card_cost(r: CardRef) -> int:
	var co := card_of(r)
	var by: Mon = co.by
	if by.trait_key == "quickfuse" and by.played == 0:
		return 0   # Quickfuse: the firer's first card free
	return maxi(0, co.def.cost - discount)

## No living lineup member has the card's element: playing it discards it for BAL.discard_cost.
func card_dead(r: CardRef) -> bool:
	var el := card_el(r)
	if el == "":
		return true
	for c in team():
		if c.alive and c.el == el:
			return false
	return true

## A living creature of the card's element is on the bench but the lead isn't of it: swap to play it.
func card_benched(r: CardRef) -> bool:
	if card_dead(r):
		return false
	var lead := act()
	return lead == null or not lead.alive or lead.el != card_el(r)

## Who the card's face window shows: every living lineup member of its element (any of them can lead
## and play it), its source first. A dead card shows just its source. Changes on a KO or a revive, never on a swap.
func card_faces(r: CardRef) -> Array[Mon]:
	var src := mon(r.uid)
	var out: Array[Mon] = []
	if src == null:
		return out
	for c in team():
		if c.alive and c.el == src.el:
			if c == src:
				out.push_front(c)
			else:
				out.append(c)
	if out.is_empty():
		out.append(src)
	return out

## Why a card can't be played right now ("" = playable, "energy", "bench", "busy").
## Only cards of the lead's element play; the rest wait for a swap to a living creature of their element.
func card_block(r: CardRef) -> String:
	if mode != "battle":
		return "busy"
	if card_dead(r):
		return "energy" if energy < Data.BAL.discard_cost else ""
	if card_benched(r):
		return "bench"
	if energy < card_cost(r):
		return "energy"
	return ""

## Living lineup member with the highest HP fraction (null if all fainted).
func healthiest() -> Mon:
	var best: Mon = null
	for c in team():
		if c.alive and (best == null or c.hp / c.max_hp > best.hp / best.max_hp):
			best = c
	return best

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
