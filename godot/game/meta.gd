# Persistent progress outside a run: owned creatures, shinies, packs, records, loot, upgrades, Essence.
# Port of game/src/game/meta.ts. Everything goes through Platform.store_get/store_set.
extends Node

func _uniq(a: Array) -> Array:
	var out: Array = []
	for k in a:
		if k in Data.ROSTER and not (k in out):
			out.append(k)
	return out

func owned() -> Array:
	return _uniq(Array(Platform.store_get("owned", Data.STARTERS.duplicate())) + Array(Data.STARTERS))

func is_owned(k) -> bool:
	return k in owned()

func shinies() -> Array:
	return _uniq(Platform.store_get("shiny", []))

func is_shiny(k) -> bool:
	return k in shinies()

## Add species to the collection. Returns the ones that were new.
func add_owned(keys: Array) -> Array:
	var have := owned()
	var fresh := _uniq(keys).filter(func(k): return not (k in have))
	if fresh.size():
		Platform.store_set("owned", have + fresh)
	return fresh

## Device-local time as unix seconds (the pack day uses wall-clock local time).
func _local_unix() -> int:
	return int(Time.get_unix_time_from_system()) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60

## The pack "day" rolls over at 04:00 device-local time.
func _pack_day() -> String:
	var d := Time.get_datetime_dict_from_unix_time(_local_unix() - int(Data.BAL.pack_reset_hour) * 3600)
	return "%d-%d-%d" % [d.year, d.month, d.day]

func pack_ready() -> bool:
	return Platform.store_get("packDay", "") != _pack_day()

## Time until the next pack, as "5h 12m".
func next_pack_in() -> String:
	var sod := posmod(_local_unix(), 86400)
	var diff := int(Data.BAL.pack_reset_hour) * 3600 - sod
	if diff <= 0:
		diff += 86400
	var m := ceili(diff / 60.0)
	return "%dh %dm" % [m / 60, m % 60]

## True once every creature is owned and shiny: a pack would have nothing to give.
func pack_empty() -> bool:
	for k in Data.ROSTER:
		if not is_owned(k) or not is_shiny(k):
			return false
	return true

## A pack's contents: a creature you don't own, else a shiny of one you do. {key: String or null, shiny: bool}.
func _roll_pack() -> Dictionary:
	var have := owned()
	var missing := Data.ROSTER.filter(func(k): return not (k in have) and not (k in Data.STARTERS))
	if missing.size():
		var key: String = Util.pick(missing)
		add_owned([key])
		return {"key": key, "shiny": false}
	var plain := have.filter(func(k): return not is_shiny(k))
	if plain.is_empty():
		return {"key": null, "shiny": false}
	var key: String = Util.pick(plain)
	Platform.store_set("shiny", shinies() + [key])
	return {"key": key, "shiny": true}

## Open today's free pack. Null if it's already been opened today.
func open_pack():
	if not pack_ready():
		return null
	Platform.store_set("packDay", _pack_day())
	return _roll_pack()

## Buy a pack in the shop. Null if too poor or there is nothing left to find (nothing is charged).
func buy_pack():
	if pack_empty() or not spend_loot({"gold": Data.BAL.shop_pack}):
		return null
	return _roll_pack()

func record_run(won: bool, floor_n: int) -> void:
	Platform.store_set("best", maxi(int(Platform.store_get("best", 0)), floor_n))
	if won:
		Platform.store_set("wins", int(Platform.store_get("wins", 0)) + 1)

func best() -> int:
	return int(Platform.store_get("best", 0))

func wins() -> int:
	return int(Platform.store_get("wins", 0))

## The last lineup taken on a run (owned species only, ≤3, first = lead).
func last_lineup() -> Array:
	var legacy = Platform.store_get("starter", Data.STARTERS[0])
	var l: Array = _dedupe(Platform.store_get("lineup", [legacy])).filter(func(k): return is_owned(k))
	l = l.slice(0, Data.BAL.lineup)
	return l if l.size() else [Data.STARTERS[0]]

func _dedupe(a: Array) -> Array:
	var out: Array = []
	for k in a:
		if not (k in out):
			out.append(k)
	return out

func save_lineup(keys: Array) -> void:
	Platform.store_set("lineup", keys.slice(0, Data.BAL.lineup))

# ================= loot, upgrades, shop (§5) =================
## Banked gold and materials: {gold, sword, orb, jewel}.
func wallet() -> Dictionary:
	var w := Data.NO_LOOT()
	w.merge(Platform.store_get("loot", {}), true)
	return w

## Bank loot (kept whether the run is won or lost). Returns the new totals.
func add_loot(l: Dictionary) -> Dictionary:
	var w := wallet()
	for k in l:
		w[k] = w.get(k, 0) + l[k]
	Platform.store_set("loot", w)
	return w

## Pay for something. False (and nothing spent) if any part is short.
func spend_loot(l: Dictionary) -> bool:
	var w := wallet()
	for k in l:
		if w.get(k, 0) < l[k]:
			return false
	for k in l:
		w[k] -= l[k]
	Platform.store_set("loot", w)
	return true

func buy_mat(m: String) -> bool:
	if not spend_loot({"gold": Data.BAL.shop_mat}):
		return false
	add_loot({m: 1})
	return true

func sell_mat(m: String) -> bool:
	if not spend_loot({m: 1}):
		return false
	add_loot({"gold": Data.BAL.shop_sell})
	return true

## Upgrade levels per species, one track per material (sword = Power, orb = Spirit, jewel = Vitality).
func upgrades(k: String) -> Dictionary:
	var u := {"sword": 0, "orb": 0, "jewel": 0}
	u.merge(Platform.store_get("upgrades", {}).get(k, {}), true)
	return u

## Cost of the next level on a track, or null at max.
func upgrade_cost(k: String, m: String):
	var n: int = upgrades(k)[m]
	if n >= Data.BAL.up_max:
		return null
	var c := Data.NO_LOOT()
	c[m] = n + 1
	c.gold = Data.BAL.up_gold * (n + 1)
	return c

func buy_upgrade(k: String, m: String) -> bool:
	var c = upgrade_cost(k, m)
	if not is_owned(k) or c == null or not spend_loot(c):
		return false
	var all: Dictionary = Platform.store_get("upgrades", {})
	var u := upgrades(k)
	u[m] += 1
	all[k] = u
	Platform.store_set("upgrades", all)
	return true

## Multipliers a creature's upgrades give: card/auto damage, shield/heal amounts, max HP.
func boosts(k: String) -> Dictionary:
	var u := upgrades(k)
	return {"power": 1 + Data.BAL.up_dmg * u.sword, "spirit": 1 + Data.BAL.up_spirit * u.orb, "vital": 1 + Data.BAL.up_hp * u.jewel}

func random_mat() -> String:
	return Util.pick(Data.MATS)

# ================= essence, unlocks, loadouts (§16) =================
func essence() -> Dictionary:
	var e := EMPTY_ESSENCE()
	e.merge(Platform.store_get("essence", {}), true)
	return e

## Add essence. Returns the new totals.
func earn(el: String, n: int) -> Dictionary:
	var e := essence()
	e[el] += n
	Platform.store_set("essence", e)
	return e

func _spend(el: String, n: int) -> bool:
	var e := essence()
	if e[el] < n:
		return false
	e[el] -= n
	Platform.store_set("essence", e)
	return true

func EMPTY_ESSENCE() -> Dictionary:
	return {"ember": 0, "tide": 0, "thorn": 0, "volt": 0}
func empty_essence() -> Dictionary:
	return EMPTY_ESSENCE()

func _learned() -> Array:
	return Platform.store_get("learned", [])

func _learn(id: String) -> void:
	Platform.store_set("learned", _dedupe(_learned() + [id]))

func _move_id(k: String, slot: String, i: int) -> String:
	return "%s.%s.%d" % [k, slot, i]

## Index 0 (the default card) is always unlocked.
func move_unlocked(k: String, slot: String, i: int) -> bool:
	return i == 0 or _move_id(k, slot, i) in _learned()

## A creature's built-in Trait is always usable by it; others must be learned (and their source owned).
func trait_unlocked(t: String) -> bool:
	return ("trait." + t) in _learned() and is_owned(Data.TRAITS[t].from)

func trait_usable(k: String, t: String) -> bool:
	return Data.SPECIES[k].get("trait") == t or trait_unlocked(t)

func move_cost(k: String) -> Dictionary:
	return {"el": Data.SPECIES[k].el, "n": Data.BAL.move_cost}

func trait_cost(t: String) -> Dictionary:
	return {"el": Data.SPECIES[Data.TRAITS[t].from].el, "n": Data.BAL.trait_cost}

func _has_card(k: String, slot: String, i: int) -> bool:
	var cards = Data.SPECIES[k].get("cards")
	return cards != null and i >= 0 and i < cards[slot].size()

## Spend essence to unlock an alternate card. False if locked behind ownership, already unlocked, or too poor.
func unlock_move(k: String, slot: String, i: int) -> bool:
	if not is_owned(k) or move_unlocked(k, slot, i) or not _has_card(k, slot, i):
		return false
	var c := move_cost(k)
	if not _spend(c.el, c.n):
		return false
	_learn(_move_id(k, slot, i))
	return true

## Spend essence so any creature can socket this Trait. Needs its source species owned.
func unlock_trait(t: String) -> bool:
	if trait_unlocked(t) or not is_owned(Data.TRAITS[t].from):
		return false
	var c := trait_cost(t)
	if not _spend(c.el, c.n):
		return false
	_learn("trait." + t)
	return true

func _saved() -> Dictionary:
	return Platform.store_get("loadout", {})

## The equipped loadout for a species, falling back to defaults for anything locked or missing.
## {skill: int, sig: int, "trait": String or null} (read the trait with lo["trait"]).
func loadout(k: String) -> Dictionary:
	var sp: Dictionary = Data.SPECIES[k]
	var s: Dictionary = _saved().get(k, {})
	var def = sp.get("trait")
	var pick_slot := func(slot: String) -> int:
		var i: int = s.get(slot, 0)
		return i if _has_card(k, slot, i) and move_unlocked(k, slot, i) else 0
	var t = s.get("trait")
	var tr = t if t != null and trait_usable(k, t) else def
	return {"skill": pick_slot.call("skill"), "sig": pick_slot.call("sig"), "trait": tr}

func set_move(k: String, slot: String, i: int) -> bool:
	if not move_unlocked(k, slot, i):
		return false
	var all := _saved()
	var l: Dictionary = all.get(k, {})
	l[slot] = i
	all[k] = l
	Platform.store_set("loadout", all)
	return true

## Socket a Trait. A learned (non-built-in) Trait sits in one creature at a time:
## socketing it here returns any other creature holding it to its built-in Trait.
func set_trait(k: String, t: String) -> bool:
	if not trait_usable(k, t):
		return false
	var all := _saved()
	if Data.SPECIES[k].get("trait") != t:
		for o in all.keys():
			if o != k and all[o].get("trait") == t:
				all[o]["trait"] = Data.SPECIES[o].get("trait")
	var l: Dictionary = all.get(k, {})
	l["trait"] = t
	all[k] = l
	Platform.store_set("loadout", all)
	return true

## Which other species currently holds a learned Trait (for "moves it from X" hints), or null.
func trait_holder(t: String):
	var all := _saved()
	for o in all:
		if all[o].get("trait") == t and Data.SPECIES[o].get("trait") != t:
			return o
	return null
