# Persistent progress outside a run: copies (collection), packs and the pack meter, records, loot,
# upgrades, Essence. Port of game/src/game/meta.ts. Everything goes through Platform.store_get/store_set.
extends Node

func _uniq(a: Array) -> Array:
	var out: Array = []
	for k in a:
		if k in Data.ROSTER and not (k in out):
			out.append(k)
	return out

# ================= copies (§11, §16.1) =================
## Copies per roster species, stored as "copies". Species missing from it are migrated from the
## pre-copies keys: a legacy shiny counts as max copies, a legacy owned species (or a starter) as 1.
func _all_copies() -> Dictionary:
	var stored: Dictionary = Platform.store_get("copies", {})
	var legacy_owned := Array(Platform.store_get("owned", [])) + Array(Data.STARTERS)
	var legacy_shiny: Array = Platform.store_get("shiny", [])
	var out := {}
	for k in Data.ROSTER:
		if stored.has(k):
			out[k] = int(stored[k])
		elif k in legacy_shiny:
			out[k] = Data.max_copies()
		elif k in legacy_owned:
			out[k] = 1
		else:
			out[k] = 0
	return out

func copies(k: String) -> int:
	return int(_all_copies().get(k, 0))

func _set_copies(k: String, n: int) -> void:
	var all := _all_copies()   # writes the migrated counts back too
	all[k] = n
	Platform.store_set("copies", all)

func owned() -> Array:
	return Data.ROSTER.filter(func(k): return copies(k) >= 1)

func is_owned(k) -> bool:
	return k in Data.ROSTER and copies(k) >= 1

func shinies() -> Array:
	return Data.ROSTER.filter(func(k): return is_shiny(k))

func is_shiny(k) -> bool:
	return k in Data.ROSTER and copies(k) >= Data.max_copies()

## A COPY_TIERS entry counts only if it is the shiny tier or names a card the species has.
func _tier_real(k: String, t: Dictionary) -> bool:
	return t.get("shiny", false) or _has_card(k, t.slot, t.i)

## The next tier a species hasn't reached yet (a COPY_TIERS dict), or null when it is maxed.
func next_tier(k: String) -> Variant:
	var c := copies(k)
	for t in Data.COPY_TIERS:
		if t.n > c and _tier_real(k, t):
			return t
	return null

## Add one copy. Unowned → owned (1 copy). A newly reached card tier unlocks and equips that card;
## the last tier makes it shiny. A copy beyond max_copies converts to BAL.dupe_gold gold.
## {key, copies, fresh, unlocked: Array of tier dicts, shiny: bool (newly), gold: int}; {} if k is bad.
func add_copy(k: String) -> Dictionary:
	if not (k in Data.ROSTER):
		return {}
	var c := copies(k)
	var res := {"key": k, "copies": c, "fresh": c == 0, "unlocked": [], "shiny": false, "gold": 0}
	if c >= Data.max_copies():
		res.gold = int(Data.BAL.dupe_gold)
		add_loot({"gold": res.gold})
		return res
	c += 1
	_set_copies(k, c)
	res.copies = c
	for t in Data.COPY_TIERS:
		if t.n != c or not _tier_real(k, t):
			continue
		res.unlocked.append(t)
		if t.get("shiny", false):
			res.shiny = true
		else:
			set_move(k, t.slot, t.i)
	return res

## Add species to the collection (1 copy each if unowned). Returns the ones that were new.
func add_owned(keys: Array) -> Array:
	var fresh: Array = []
	for k in _uniq(keys):
		if not is_owned(k):
			_set_copies(k, 1)
			fresh.append(k)
	return fresh

# ================= packs and the pack meter (§11) =================
## Device-local time as unix seconds (the pack day uses wall-clock local time).
func _local_unix() -> int:
	return int(Time.get_unix_time_from_system()) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60

## The pack "day" rolls over at 04:00 device-local time.
func _pack_day() -> String:
	var d := Time.get_datetime_dict_from_unix_time(_local_unix() - int(Data.BAL.pack_reset_hour) * 3600)
	return "%d-%d-%d" % [d.year, d.month, d.day]

## Today's free pack hasn't been opened yet.
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

## Points toward the next pack token (0..pack_meter-1).
func pack_pts() -> int:
	return int(Platform.store_get("packPts", 0))

## Banked, unopened packs earned from the meter.
func pack_tokens() -> int:
	return int(Platform.store_get("packTokens", 0))

## Bank pack points (per fight won; kept on a loss). Every full meter becomes a token; overflow carries.
## {pts, tokens, gained: new tokens from this add}.
func add_pack_pts(n: int) -> Dictionary:
	var meter := int(Data.BAL.pack_meter)
	var total := pack_pts() + maxi(n, 0)
	var gained := total / meter
	var tokens := pack_tokens() + gained
	Platform.store_set("packPts", total % meter)
	Platform.store_set("packTokens", tokens)
	return {"pts": total % meter, "tokens": tokens, "gained": gained}

## Packs the player can open right now: tokens plus today's free pack.
func packs_ready() -> int:
	return pack_tokens() + (1 if pack_ready() else 0)

## The rolled choices waiting to be picked ([] if none). Persisted, so closing the app doesn't reroll.
func pack_pending() -> Array:
	return Array(Platform.store_get("packPending", []))

## Where the pending pack came from: "daily", "token", "shop", or "" if nothing is pending.
func pending_source() -> String:
	return str(Platform.store_get("packSource", "")) if pack_pending().size() else ""

## Draw BAL.pack_choices distinct species, without replacement; unowned weigh pack_new_weight, owned 1.
func _roll_choices() -> Array:
	var pool: Array = Data.ROSTER.duplicate()
	var out: Array = []
	var new_w := float(Data.BAL.pack_new_weight)
	while out.size() < int(Data.BAL.pack_choices) and pool.size():
		var total := 0.0
		for k in pool:
			total += 1.0 if is_owned(k) else new_w
		var r := Util.rand(0, total)
		var pick: String = pool[-1]
		for k in pool:
			r -= 1.0 if is_owned(k) else new_w
			if r < 0:
				pick = k
				break
		out.append(pick)
		pool.erase(pick)
	return out

func _start_pack(source: String) -> Array:
	var ch := _roll_choices()
	Platform.store_set("packPending", ch)
	Platform.store_set("packSource", source)
	return ch

## Open a pack: "daily" (today's free one) or "token" (from the meter). Rolls and persists the choices.
## If a pack is already pending, returns its choices without consuming anything. [] if nothing to open.
func open_pack(source: String = "daily") -> Array:
	var pend := pack_pending()
	if pend.size():
		return pend
	match source:
		"daily":
			if not pack_ready():
				return []
			Platform.store_set("packDay", _pack_day())
		"token":
			var t := pack_tokens()
			if t <= 0:
				return []
			Platform.store_set("packTokens", t - 1)
		_:
			return []
	return _start_pack(source)

## Buy a pack in the shop (BAL.shop_pack gold). A pending pack is returned instead, uncharged. [] if too poor.
func buy_pack() -> Array:
	var pend := pack_pending()
	if pend.size():
		return pend
	if not spend_loot({"gold": Data.BAL.shop_pack}):
		return []
	return _start_pack("shop")

## Keep one of the pending choices. Clears the pending pack and returns add_copy(k), or {} if k isn't offered.
func pick_pack(k: String) -> Dictionary:
	if not (k in pack_pending()):
		return {}
	Platform.store_set("packPending", null)
	Platform.store_set("packSource", null)
	return add_copy(k)

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

# ================= essence (Traits only), unlocks, loadouts (§16) =================
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

## Index 0 (the default card) is always unlocked; alternates unlock from copies (COPY_TIERS).
## Cards learned with Essence before the copies rewrite (ids in "learned") stay unlocked.
func move_unlocked(k: String, slot: String, i: int) -> bool:
	if i == 0:
		return true
	var need := Data.copies_for(slot, i)
	return (need != -1 and copies(k) >= need) or _move_id(k, slot, i) in _learned()

## A creature's built-in Trait is always usable by it; others must be learned (and their source owned).
func trait_unlocked(t: String) -> bool:
	return ("trait." + t) in _learned() and is_owned(Data.TRAITS[t].from)

func trait_usable(k: String, t: String) -> bool:
	return Data.SPECIES[k].get("trait") == t or trait_unlocked(t)

func trait_cost(t: String) -> Dictionary:
	return {"el": Data.SPECIES[Data.TRAITS[t].from].el, "n": Data.BAL.trait_cost}

func _has_card(k: String, slot: String, i: int) -> bool:
	var cards = Data.SPECIES[k].get("cards")
	return cards != null and i >= 0 and i < cards[slot].size()

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
