# Core logic tests: data helpers, util, persistence, meta (loot, packs, essence, loadouts, Traits),
# state helpers, enemy numbers, card resolution, statuses, shields, Perfect Swap, chain, and a
# simulated fight. Run: godot --headless --path godot --script res://tests/test_core.gd
#
# The visual modules (Layout, Feel, Particles, Stage, Fx, Ui, Run) are swapped for
# tests/core_stubs/module_stub.gd and Actors for actor_stub.gd, so this runs headless and
# independent of their implementations. Saves go to a scratch file.
extends SceneTree

const STUB := preload("res://tests/core_stubs/module_stub.gd")
const ACTOR := preload("res://tests/core_stubs/actor_stub.gd")
const SAVE := "user://test_core_save.cfg"
const VISUAL := ["Layout", "Feel", "Particles", "Stage", "Fx", "Ui", "Run"]

var passed := 0
var failed := 0
var section := ""
var Dt: Node; var Ut: Node; var Pf: Node; var Sx: Node; var St: Node; var Mt: Node; var Bt: Node
var stub: Node   # any of the swapped modules (they share counters per node, so read the one you need)

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		printerr("FAIL [%s] %s" % [section, msg])

func eq(a, b, msg: String) -> void:
	check(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])

func near(a: float, b: float, msg: String, eps := 0.01) -> void:
	check(absf(a - b) <= eps, "%s (got %s, want %s)" % [msg, str(a), str(b)])

func mod(n: String) -> Node:
	return root.get_node(n)

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	for n in ["Data", "Util", "Platform", "Sfx", "S", "Meta", "Battle"] + VISUAL:
		if root.get_node_or_null(n) == null:
			printerr("autoload %s failed to load; fix its script first" % n)
			quit(2)
			return
	for n in VISUAL:
		mod(n).set_script(STUB)
	Dt = mod("Data"); Ut = mod("Util"); Pf = mod("Platform"); Sx = mod("Sfx"); St = mod("S"); Mt = mod("Meta"); Bt = mod("Battle")
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Pf.use_save_path(SAVE)
	St.actor_factory = func(k, e):
		var a = ACTOR.make(k, e)
		root.add_child(a)
		return a

	test_data()
	test_util()
	test_platform()
	test_audio()
	test_meta()
	test_state()
	test_enemy_numbers()
	test_cards()
	test_element_cards()
	test_statuses()
	test_shields()
	test_traits()
	await test_perfect_swap()
	await test_sim_fight()

	St.clear_actors()
	St.party.clear()
	St.enemy = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("test_core: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

# ---------------------------------------------------------------- data
func test_data() -> void:
	section = "data"
	eq(Dt.adv("ember", "thorn"), 1.5, "ember beats thorn")
	eq(Dt.adv("thorn", "ember"), 0.66, "thorn resisted by ember")
	eq(Dt.adv("ember", "volt"), 1.0, "non-adjacent")
	eq(Dt.adv(null, "volt"), 1.0, "null attacker")
	check(Dt.resists("tide", "ember"), "tide resists ember")
	check(not Dt.resists("ember", "tide"), "ember doesn't resist tide")
	eq(Dt.STATUS_DUR.burn, 4.0, "burn dur")
	eq(Dt.SPECIES.size(), 14, "14 species")
	eq(Dt.ROSTER.size(), 12, "12 roster")
	for k in Dt.ROSTER:
		var sp: Dictionary = Dt.SPECIES[k]
		check(sp.cards.strike.size() == 1 and sp.cards.skill.size() == 3 and sp.cards.sig.size() == 3, k + " card slots")
		for slot in ["skill", "sig"]:
			check(Dt.scalable(sp.cards[slot][2]), k + " " + slot + " option 3 scales with +30%")
		check(Dt.TRAITS.has(sp["trait"]) and Dt.TRAITS[sp["trait"]].from == k, k + " trait")
	var card_names := {}
	for k in Dt.ROSTER:
		for slot in Dt.SLOTS:
			for c in Dt.SPECIES[k].cards[slot]:
				check(not card_names.has(c.name), "card name unique: " + c.name)
				card_names[c.name] = true
	eq(card_names.size(), 84, "84 cards in the roster (12 × 7)")
	var wick: Dictionary = Dt.SPECIES.emberwick.cards.sig[0]
	eq(Dt.card_text(wick), "14 dmg, +8 if Burned", "Wickflare text")
	var up: Dictionary = Dt.scale_card(wick, 1.3)
	eq(up.dmg, 18, "Wickflare +30% dmg")
	eq(up.bonus_if.dmg, 10, "Wickflare +30% bonus")
	eq(wick.dmg, 14, "scale_card doesn't mutate")
	eq(Dt.card_text(Dt.SPECIES.emberwick.cards.skill[0], 1.3), "Burn 5.2s", "Kindle upgraded text")
	eq(Dt.card_text(Dt.SPECIES.coilsnail.cards.sig[0], 1.3), "Dmg = shield ×1.3", "Discharge upgraded text")
	eq(Dt.card_text(Dt.SPECIES.brambat.cards.sig[1]), "8 dmg ×2, reflect 30% next hit", "Thorn Storm text")
	eq(Dt.card_text(Dt.SPECIES.puddlet.cards.sig[0]), "team heal 12, cleanse team", "Spring Rain text")
	var ls: Dictionary = Dt.scale_card(Dt.SPECIES.brambat.cards.sig[0], 1.3)
	near(ls.lifesteal, 0.65, "lifesteal scaled")
	var ns: Dictionary = Dt.scale_card(Dt.SPECIES.kilnback.cards.skill[1], 1.3)
	near(ns.next_strike, 2.6, "next_strike scaled")
	eq(Dt.card_text(ns), "shield 8, next Strike ×2.6", "Forge upgraded text")
	check(not Dt.scalable(Dt.SPECIES.cinderpip.cards.skill[0]), "Flicker not scalable")
	check(not Dt.scalable(Dt.SPECIES.skiray.cards.skill[0]), "Static not scalable")
	check(Dt.scalable(Dt.SPECIES.emberwick.cards.skill[0]), "Kindle scalable")
	var b: Dictionary = Dt.boost_card(Dt.SPECIES.truffmole.cards.sig[0], 1.16, 1.2)
	eq(b.dmg, 14, "boost dmg 12×1.16")
	eq(b.heal, 7, "boost heal 6×1.2")
	eq(Dt.biome_of(4), 0, "floor 4 biome A")
	eq(Dt.biome_of(5), 1, "floor 5 biome B")
	eq(Dt.MAT_DEF.sword.text, "+8% card and auto-attack damage per level", "mat text")
	check(Dt.svg("ember").begins_with("<svg"), "svg")

# ---------------------------------------------------------------- util
func test_util() -> void:
	section = "util"
	var a := [1, 2, 3, 4, 5, 6]
	var s: Array = Ut.shuffle(a.duplicate())
	s.sort()
	eq(s, a, "shuffle keeps elements")
	for i in 50:
		var r: float = Ut.rand(2, 3)
		check(r >= 2 and r <= 3, "rand range")
	check(Ut.pick(["x"]) == "x", "pick")
	eq(Ut.clamp(5, 0, 3), 3.0, "clamp")

# ---------------------------------------------------------------- platform
func test_platform() -> void:
	section = "platform"
	eq(Pf.store_get("nope", 7), 7, "fallback")
	Pf.store_set("arr", ["a"])
	var got: Array = Pf.store_get("arr", [])
	got.append("b")
	eq(Pf.store_get("arr", []), ["a"], "returns copies")
	Pf.use_save_path(SAVE)   # reload from disk
	eq(Pf.store_get("arr", []), ["a"], "persisted to disk")
	Pf.store_set("arr", null)
	eq(Pf.store_get("arr", "gone"), "gone", "null erases")
	Pf.haptic("light")   # no-op on desktop

# ---------------------------------------------------------------- audio
func test_audio() -> void:
	section = "audio"
	for n in Sx.NAMES:
		var w: AudioStreamWAV = Sx.stream(n)
		check(w != null and w.data.size() > 1000, n + " rendered")
		var peak := 0
		for i in range(0, w.data.size(), 2):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		check(peak > 300 and peak < 32767, "%s peak %d" % [n, peak])
	Sx.set_muted(true)
	check(Sx.is_muted() and Pf.store_get("muted", false), "mute persisted")
	Sx.hit("volt")
	Sx.set_muted(false)
	Sx.caught()

# ---------------------------------------------------------------- meta
func test_meta() -> void:
	section = "meta"
	var mx: int = Dt.max_copies()
	eq(Mt.owned(), ["emberwick", "bellspring", "truffmole"], "starters owned")
	eq(Mt.copies("emberwick"), 1, "starter has 1 copy")
	eq(Mt.copies("skiray"), 0, "unowned has 0 copies")
	eq(Mt.add_owned(["skiray", "emberwick", "bogus"]), ["skiray"], "add_owned returns new")
	check(Mt.is_owned("skiray"), "skiray owned")
	eq(Mt.copies("skiray"), 1, "add_owned gives 1 copy")
	check(Mt.next_pack_in().contains("h "), "next_pack_in format")
	_test_copies()
	_test_migration()
	_test_pack_meter()
	_test_packs()
	# loot
	Pf.store_set("loot", null)
	Mt.add_loot({"gold": 50})
	check(not Mt.spend_loot({"gold": 999}), "spend fails when short")
	eq(Mt.wallet().gold, 50, "nothing spent on failure")
	check(Mt.buy_mat("sword"), "buy mat")
	eq(Mt.wallet(), {"gold": 20, "sword": 1, "orb": 0, "jewel": 0}, "wallet after buy")
	check(Mt.sell_mat("sword"), "sell mat")
	eq(Mt.wallet().gold, 35, "sell gives 15")
	eq(Mt.upgrade_cost("emberwick", "sword"), {"gold": 20, "sword": 1, "orb": 0, "jewel": 0}, "lvl1 cost")
	check(not Mt.buy_upgrade("emberwick", "sword"), "can't upgrade without sword")
	Mt.add_loot({"gold": 100, "sword": 3, "jewel": 1})
	check(Mt.buy_upgrade("emberwick", "sword"), "upgrade lvl1")
	check(Mt.buy_upgrade("emberwick", "sword"), "upgrade lvl2")
	eq(Mt.upgrades("emberwick").sword, 2, "two levels")
	near(Mt.boosts("emberwick").power, 1.16, "power boost")
	check(Mt.buy_upgrade("bellspring", "jewel"), "jewel upgrade")
	# records
	Mt.record_run(false, 3)
	Mt.record_run(true, 8)
	Mt.record_run(false, 2)
	eq(Mt.best(), 8, "best floor")
	eq(Mt.wins(), 1, "wins")
	eq(Mt.last_lineup(), ["emberwick"], "default lineup")
	Mt.save_lineup(["truffmole", "skiray", "bogus", "x"])
	eq(Mt.last_lineup(), ["truffmole", "skiray"], "saved lineup filtered")
	# loadouts: alternates unlock from copies, not Essence
	eq(Mt.essence(), {"ember": 0, "tide": 0, "thorn": 0, "volt": 0}, "no essence")
	check(not Mt.move_unlocked("truffmole", "skill", 1), "1 copy: alt skill locked")
	check(not Mt.set_move("truffmole", "skill", 1), "locked skill can't be equipped")
	Mt.earn("thorn", 20)
	check(not Mt.has_method("unlock_move"), "essence no longer unlocks cards")
	eq(Mt.essence().thorn, 20, "no essence spent on cards")
	Mt.add_copy("truffmole")
	check(Mt.move_unlocked("truffmole", "skill", 1), "2 copies: alt skill unlocked")
	eq(Mt.loadout("truffmole").skill, 1, "tier unlock equips the card")
	check(Mt.set_move("truffmole", "skill", 0), "re-equip default")
	eq(Mt.loadout("truffmole").skill, 0, "default back")
	check(not Mt.set_move("truffmole", "sig", 1), "sig needs 3 copies")
	eq(Mt.loadout("emberwick")["trait"], "afterglow", "built-in trait")
	eq(Mt.add_copy("emberwick").unlocked.size(), 1, "emberwick 2nd copy")
	eq(Mt.loadout("emberwick").skill, 1, "Flare Step equipped (test_state relies on this)")
	# traits (still Essence)
	Mt.earn("ember", 7)
	check(not Mt.unlock_trait("afterglow"), "trait needs 8 essence")
	Mt.earn("ember", 1)
	check(Mt.unlock_trait("afterglow"), "learn Afterglow")
	eq(Mt.essence().ember, 0, "trait cost 8")
	check(Mt.trait_unlocked("afterglow"), "afterglow learned")
	check(not Mt.unlock_trait("afterglow"), "already learned")
	check(not Mt.unlock_trait("quickfuse") or Mt.is_owned("cinderpip"), "trait source must be owned")
	check(Mt.set_trait("truffmole", "afterglow"), "socket on truffmole")
	eq(Mt.loadout("truffmole")["trait"], "afterglow", "truffmole has afterglow")
	eq(Mt.trait_holder("afterglow"), "truffmole", "holder")
	check(Mt.set_trait("skiray", "afterglow"), "socket on skiray")
	eq(Mt.loadout("truffmole")["trait"], "deeproots", "truffmole back to built-in")
	eq(Mt.trait_holder("afterglow"), "skiray", "holder moved")
	check(not Mt.set_trait("skiray", "bulwark"), "unlearned trait")
	check(Mt.set_trait("emberwick", "afterglow"), "own built-in always ok")
	eq(Mt.loadout("skiray")["trait"], "afterglow", "built-in socketing doesn't evict others")
	Mt.set_trait("skiray", "relay")
	eq(Mt.trait_holder("afterglow"), null, "no holder")
	eq(Mt.trait_cost("relay"), {"el": "volt", "n": 8}, "trait cost")
	check(not Dt.BAL.has("move_cost"), "move_cost gone from BAL")

## Copies and COPY_TIERS: skill alt at 2, sig alt at 3, shiny at max, overflow → gold.
func _test_copies() -> void:
	section = "meta/copies"
	eq(Dt.copies_for("skill", 0), 0, "default needs 0")
	eq(Dt.copies_for("skill", 1), 2, "alt skill at 2")
	eq(Dt.copies_for("sig", 1), 3, "alt sig at 3")
	eq(Dt.copies_for("strike", 1), -1, "no strike tier")
	var r: Dictionary = Mt.add_copy("mossling")
	eq([r.key, r.copies, r.fresh, r.unlocked, r.shiny, r.gold], ["mossling", 1, true, [], false, 0], "first copy owns it")
	check(Mt.is_owned("mossling"), "mossling owned")
	eq(Mt.next_tier("mossling").n, 2, "next tier: 2 copies")
	r = Mt.add_copy("mossling")
	check(not r.fresh and r.copies == 2, "second copy")
	eq(r.unlocked.size(), 1, "one tier reached")
	eq([r.unlocked[0].slot, r.unlocked[0].i], ["skill", 1], "skill alt tier")
	check(Mt.move_unlocked("mossling", "skill", 1) and not Mt.move_unlocked("mossling", "sig", 1), "skill alt only")
	eq(Mt.loadout("mossling").skill, 1, "alt skill equipped on unlock")
	r = Mt.add_copy("mossling")
	eq([r.unlocked[0].slot, r.unlocked[0].i], ["sig", 1], "sig alt tier")
	eq(Mt.loadout("mossling").sig, 1, "alt sig equipped on unlock")
	eq(Mt.add_copy("bogus"), {}, "bogus key")
	var shiny_seen := false
	for i in range(3, Dt.max_copies()):
		r = Mt.add_copy("mossling")
		for t in r.unlocked:
			check(t.get("shiny", false) or Mt._has_card("mossling", t.slot, t.i), "only real card tiers reported")
		shiny_seen = shiny_seen or r.shiny
	eq(Mt.copies("mossling"), Dt.max_copies(), "maxed")
	check(shiny_seen and Mt.is_shiny("mossling"), "shiny at max copies")
	eq(Mt.next_tier("mossling"), null, "no next tier when maxed")
	check("mossling" in Mt.shinies(), "listed in shinies")
	var g0: int = Mt.wallet().gold
	r = Mt.add_copy("mossling")
	eq([r.copies, r.gold, r.shiny, r.unlocked], [Dt.max_copies(), Dt.BAL.dupe_gold, false, []], "overflow copy → gold")
	eq(Mt.wallet().gold, g0 + Dt.BAL.dupe_gold, "overflow gold banked")
	eq(Mt.copies("mossling"), Dt.max_copies(), "copies capped")

## Old saves: "owned"/"shiny"/"learned" without a "copies" entry.
func _test_migration() -> void:
	section = "meta/migration"
	var keep_copies = Pf.store_get("copies", null)
	var keep_learned = Pf.store_get("learned", null)
	var keep_lo = Pf.store_get("loadout", null)
	Pf.store_set("copies", null)
	Pf.store_set("owned", ["emberwick", "bellspring", "truffmole", "sparkit", "kilnback"])
	Pf.store_set("shiny", ["kilnback"])
	Pf.store_set("learned", ["sparkit.sig.1", "trait.livewire"])
	eq(Mt.copies("sparkit"), 1, "legacy owned → 1 copy")
	eq(Mt.copies("emberwick"), 1, "starter → 1 copy")
	eq(Mt.copies("kilnback"), Dt.max_copies(), "legacy shiny → max copies")
	check(Mt.is_shiny("kilnback") and not Mt.is_shiny("sparkit"), "shiny derived from copies")
	eq(Mt.copies("puddlet"), 0, "legacy unowned → 0")
	check(Mt.move_unlocked("sparkit", "sig", 1), "essence-learned card stays unlocked")
	check(not Mt.move_unlocked("sparkit", "skill", 1), "unlearned alt still locked")
	check(Mt.move_unlocked("kilnback", "skill", 1) and Mt.move_unlocked("kilnback", "sig", 1), "shiny migrant has every card")
	check(Mt.trait_unlocked("livewire"), "learned trait kept")
	Mt.add_copy("sparkit")
	eq(Pf.store_get("copies", {}).get("sparkit"), 2, "copies written on first change")
	eq(Pf.store_get("copies", {}).get("kilnback"), Dt.max_copies(), "migrated counts written back")
	eq(Mt.copies("emberwick"), 1, "migrated starter kept")
	# restore
	Pf.store_set("copies", keep_copies)
	Pf.store_set("learned", keep_learned)
	Pf.store_set("loadout", keep_lo)
	Pf.store_set("owned", null)
	Pf.store_set("shiny", null)

## Pack points bank per fight; every pack_meter points becomes a token, overflow carries.
func _test_pack_meter() -> void:
	section = "meta/meter"
	eq([Mt.pack_pts(), Mt.pack_tokens()], [0, 0], "empty meter")
	var r: Dictionary = Mt.add_pack_pts(Dt.BAL.pts_wild)
	eq(r, {"pts": 2, "tokens": 0, "gained": 0}, "wild points")
	r = Mt.add_pack_pts(Dt.BAL.pack_meter - 1)
	eq(r, {"pts": 1, "tokens": 1, "gained": 1}, "token earned, overflow carries")
	r = Mt.add_pack_pts(Dt.BAL.pack_meter * 2)
	eq([r.pts, r.tokens, r.gained], [1, 3, 2], "two tokens at once")
	eq([Mt.pack_pts(), Mt.pack_tokens()], [1, 3], "meter persisted")
	Pf.use_save_path(SAVE)   # reload from disk
	eq([Mt.pack_pts(), Mt.pack_tokens()], [1, 3], "meter survives reload")
	eq(Mt.add_pack_pts(0).gained, 0, "zero points")

## Pick-1-of-3 packs: distinct choices, persisted pending, daily/token/shop consumption.
func _test_packs() -> void:
	section = "meta/packs"
	# picks are random: restore copies and loadouts afterwards so later sections see a fixed collection
	var keep_all = Pf.store_get("copies", null)
	var keep_lo = Pf.store_get("loadout", null)
	check(Mt.pack_ready(), "daily ready")
	eq(Mt.packs_ready(), Mt.pack_tokens() + 1, "packs_ready = tokens + daily")
	eq(Mt.pack_pending(), [], "nothing pending")
	eq(Mt.pending_source(), "", "no source")
	eq(Mt.open_pack("bogus"), [], "bad source opens nothing")
	var ch: Array = Mt.open_pack("daily")
	eq(ch.size(), Dt.BAL.pack_choices, "3 choices")
	var u := {}
	for k in ch:
		check(k in Dt.ROSTER, "choice in roster")
		u[k] = true
	eq(u.size(), ch.size(), "choices distinct")
	check(not Mt.pack_ready(), "daily consumed")
	eq(Mt.pending_source(), "daily", "source daily")
	Pf.use_save_path(SAVE)   # "close the app"
	eq(Mt.pack_pending(), ch, "pending persists across reload")
	var tok: int = Mt.pack_tokens()
	eq(Mt.open_pack("token"), ch, "pending returned, no reroll")
	eq(Mt.pack_tokens(), tok, "pending doesn't consume a token")
	eq(Mt.open_pack("daily"), ch, "pending returned for daily too")
	var g0: int = Mt.wallet().gold
	eq(Mt.buy_pack(), ch, "buying while pending returns pending")
	eq(Mt.wallet().gold, g0, "uncharged while pending")
	eq(Mt.pick_pack("bogus"), {}, "can't pick something not offered")
	var notoff: Array = Dt.ROSTER.filter(func(k): return not (k in ch))
	eq(Mt.pick_pack(notoff[0]), {}, "can't pick a roster species not offered")
	var c0: int = Mt.copies(ch[0])
	var r: Dictionary = Mt.pick_pack(ch[0])
	var maxed: bool = c0 >= Dt.max_copies()
	eq([r.key, r.copies, r.fresh, r.gold], [ch[0], c0 if maxed else c0 + 1, c0 == 0, Dt.BAL.dupe_gold if maxed else 0], "picked adds a copy (or gold when maxed)")
	eq(Mt.pack_pending(), [], "pending cleared")
	eq(Mt.pending_source(), "", "source cleared")
	eq(Mt.pick_pack(ch[1]), {}, "can't pick twice")
	eq(Mt.open_pack("daily"), [], "daily can't be opened twice")
	# token
	if tok == 0:
		Mt.add_pack_pts(Dt.BAL.pack_meter)
		tok = 1
	var ch2: Array = Mt.open_pack("token")
	eq(ch2.size(), Dt.BAL.pack_choices, "token pack")
	eq(Mt.pack_tokens(), tok - 1, "token consumed")
	eq(Mt.pending_source(), "token", "source token")
	Mt.pick_pack(ch2[2])
	Pf.store_set("packTokens", 0)
	eq(Mt.open_pack("token"), [], "no tokens, nothing to open")
	eq(Mt.packs_ready(), 0, "nothing ready")
	# shop
	Pf.store_set("loot", null)
	eq(Mt.buy_pack(), [], "can't buy when poor")
	Mt.add_loot({"gold": 200})
	var ch3: Array = Mt.buy_pack()
	eq(ch3.size(), Dt.BAL.pack_choices, "bought a pack")
	eq(Mt.wallet().gold, 50, "pack cost 150")
	eq(Mt.pending_source(), "shop", "source shop")
	Mt.pick_pack(ch3[0])
	# weighting: unowned are drawn more than their share
	var unowned_n := 0
	var total := 0
	var owned_now: Array = Mt.owned()
	for i in 300:
		var c: Array = Mt._roll_choices()
		if i < 5:
			check(c.size() == 3 and c[0] != c[1] and c[1] != c[2] and c[0] != c[2], "distinct roll")
		for k in c:
			total += 1
			if not (k in owned_now):
				unowned_n += 1
	var share: float = float(Dt.ROSTER.size() - owned_now.size()) / Dt.ROSTER.size()
	check(float(unowned_n) / total > share + 0.05, "unowned weighted up (%d/%d vs share %.2f)" % [unowned_n, total, share])
	# never empty: everything maxed still rolls, picks pay gold
	var all := {}
	for k in Dt.ROSTER:
		all[k] = Dt.max_copies()
	Pf.store_set("copies", all)
	var c4: Array = Mt._start_pack("shop")
	eq(c4.size(), 3, "maxed collection still rolls 3")
	eq(Mt.pick_pack(c4[0]).gold, Dt.BAL.dupe_gold, "maxed pick → gold")
	Pf.store_set("copies", keep_all)
	Pf.store_set("loadout", keep_lo)

# ---------------------------------------------------------------- state
func _fresh_party(keys: Array) -> void:
	St.clear_actors()
	St.party.clear()
	St.lineup.clear()
	for k in keys:
		var c: Mon = St.new_mon(k)
		St.party.append(c)
		if St.lineup.size() < 3:
			St.lineup.append(c.uid)
	St.active = St.lineup[0]
	St.floor = 1

func test_state() -> void:
	section = "state"
	_fresh_party(["emberwick", "bellspring", "truffmole"])
	var c: Mon = St.act()
	eq(c.key, "emberwick", "lead")
	eq(c.max_hp, 50, "hp")
	near(c.power, 1.16, "power from upgrades")
	eq(c.moves.skill, 1, "loadout skill applied")
	eq(c.trait_key, "afterglow", "trait applied")
	eq(St.mon(St.lineup[1]).max_hp, 59, "bellspring 55×1.08")
	eq(St.team().size(), 3, "team")
	eq(St.bench().size(), 2, "bench")
	var r := CardRef.new(c.uid, "strike")
	var co: Dictionary = St.card_of(r)
	eq(co.def.name, "Peck", "Peck")
	eq(co.def.dmg, 7, "Peck 6×1.16")
	eq(St.card_of(CardRef.new(c.uid, "skill")).def.name, "Flare Step", "equipped alternate")
	c.ups["sig"] = "power"
	var sig: Dictionary = St.card_of(CardRef.new(c.uid, "sig"))
	eq(sig.pow, 1.3, "power upgrade pow")
	eq(sig.def.dmg, 21, "Wickflare 14×1.3=18 ×1.16=21")
	c.ups["sig"] = "cost"
	eq(St.card_of(CardRef.new(c.uid, "sig")).def.cost, 2, "cost upgrade")
	St.mode = "map"
	eq(St.card_block(r), "busy", "busy outside battle")
	St.mode = "battle"
	St.energy = 0
	eq(St.card_block(r), "energy", "no energy")
	St.energy = 5
	eq(St.card_block(r), "", "playable")
	var bref := CardRef.new(St.lineup[1], "strike")
	eq(St.card_block(bref), "bench", "other-element card never playable")
	St.swap_cd = 1
	eq(St.card_block(r), "", "lead card fine on cooldown")
	St.swap_cd = 0
	St.mon(St.lineup[1]).alive = false
	check(St.card_dead(bref), "only Tide creature fainted → dead card")
	eq(St.card_block(bref), "", "dead card can be discarded")
	St.energy = 0
	eq(St.card_block(bref), "energy", "discard needs energy")
	St.energy = 5
	St.mon(St.lineup[1]).alive = true
	St.discount = 1
	eq(St.card_cost(r), 0, "discount")
	St.discount = 0
	c.ups.clear()
	# quickfuse
	c.trait_key = "quickfuse"
	eq(St.card_cost(CardRef.new(c.uid, "sig")), 0, "quickfuse first card free")
	c.played = 1
	eq(St.card_cost(CardRef.new(c.uid, "sig")), 3, "quickfuse only first")
	c.played = 0
	c.trait_key = "afterglow"
	# heavy helpers
	var e := Enemy.new()
	e.key = "warden"; e.el = "thorn"; e.kind = "warden"
	check(not St.is_heavy(e), "attack 1 normal")
	e.count = 2
	check(St.is_heavy(e), "attack 3 heavy")
	eq(St.heavy_of(e), {"name": "Bramble Crush", "el": "thorn"}, "warden heavy 1")
	e.heavy_idx = 1
	eq(St.heavy_of(e), {"name": "Wildfire Roar", "el": "ember"}, "warden heavy 2")
	var b := Enemy.new()
	b.key = "noctyrm"; b.el = "volt"; b.kind = "boss"
	eq(St.heavy_of(b), {"el": "volt", "name": "Eclipse Volley"}, "boss heavy")
	var w := Enemy.new()
	w.key = "skiray"; w.el = "volt"
	eq(St.heavy_of(w).name, "Thunder Ram", "wild heavy name")
	e.windup = 5; e.t = 4.7
	check(St.in_perfect_window(e), "in window")
	e.t = 4.5
	check(not St.in_perfect_window(e), "not yet")
	var a = St.actor_for(c)
	check(a != null and St.actor_for(c) == a, "actor_for caches")
	St.drop_actor(c.uid)
	check(not St.actors.has(c.uid), "drop_actor")

# ---------------------------------------------------------------- battles
func _battle(keys: Array, foe: String, type := "wild", lvl := 1) -> Enemy:
	_fresh_party(keys)
	for c in St.party:
		c.trait_key = Dt.SPECIES[c.key]["trait"]
		c.moves = {"strike": 0, "skill": 0, "sig": 0}
		c.power = 1.0
		c.spirit = 1.0
		c.max_hp = Dt.SPECIES[c.key].hp
		c.hp = c.max_hp
	Bt.start_battle(MapNode.new(type, foe, lvl))
	St.mode = "battle"
	St.energy = 10
	return St.enemy

func _hand(i: int, uid: int, slot: String) -> void:
	St.hand[i] = CardRef.new(uid, slot)

func test_enemy_numbers() -> void:
	section = "enemy"
	var e := _battle(["emberwick"], "cinderpip")
	eq(e.max, 77.0, "cinderpip f1 hp = round(90×(0.6+0.4×35/55))")
	near(e.dmg, 6.0, "cinderpip dmg 5×1.2")
	near(e.iv, 3 / 1.1, "cinderpip wind-up 3/1.1")
	eq(e.name, "Cinderpip", "name")
	eq(St.hand.size(), 4, "hand of 4")
	eq(St.draw.size() + St.hand.filter(func(x): return x != null).size(), 3, "solo deck has 3 cards")
	eq(St.energy, 10.0, "energy set by test")
	e = _battle(["emberwick"], "mossling", "alpha", 3)
	eq(e.max, roundf(90 * (0.6 + 0.4 * 50 / 55.0) * 1.3 * 1.5), "alpha f3 hp")
	near(e.dmg, 5 * 0.9 * 1.2 * 1.25, "alpha f3 dmg")
	eq(e.name, "Alpha Mossling", "alpha name")
	e = _battle(["emberwick"], "warden", "warden", 4)
	eq(e.max, 300.0, "warden hp")
	eq(e.dmg, 7.0, "warden dmg")
	e = _battle(["emberwick"], "noctyrm", "boss", 8)
	eq(e.max, 270.0, "boss hp")
	eq(e.dmg, 8.0, "boss dmg")
	check(e.el in Dt.EL_KEYS, "boss element")
	var el0 := e.el
	for i in 8 * 60:
		e.t = 0   # keep it from attacking
		Bt.tick_battle(1.0 / 60, 0)
	check(e.el != el0, "boss shifted element after 7s")
	e = _battle(["emberwick", "bellspring", "truffmole"], "skiray")
	eq(St.draw.size(), 5, "3 creatures → 9 cards, 4 in hand")

func test_cards() -> void:
	section = "cards"
	var e := _battle(["emberwick", "bellspring", "truffmole"], "mossling")
	var wick: Mon = St.party[0]
	var bell: Mon = St.party[1]
	# element multiplier: Peck 6 ember vs thorn → 9
	_hand(0, wick.uid, "strike")
	var hp0 := e.hp
	Bt.play_card(0)
	eq(hp0 - e.hp, 9.0, "Peck super-effective 6×1.5")
	eq(St.energy, 9.0, "Peck costs 1")
	eq(St.chain, 0, "first card: chain 0")
	check(St.hand[0] != null or St.draw.is_empty(), "slot refilled")
	# chain: next card within 1.5s → +1 step = +10%
	_hand(1, wick.uid, "sig")
	hp0 = e.hp
	Bt.play_card(1)
	eq(St.chain, 1, "chain 1")
	eq(hp0 - e.hp, roundf(14 * 1.1 * 1.5), "Wickflare with chain")
	# bench cards don't play and don't swap
	var ui = mod("Ui")
	var denied := []
	var on_denied := func(i, why): denied.append(why)
	Bt.card_denied.connect(on_denied)
	_hand(2, bell.uid, "skill")   # Drench: soak
	var en0: float = St.energy
	Bt.play_card(2)
	eq(denied, ["bench"], "bench card denied")
	eq(St.active, wick.uid, "bench card didn't swap")
	eq(St.energy, en0, "bench card cost nothing")
	# swap by portrait: free, 6s cooldown
	Bt.swap_tap(bell.uid)
	eq(St.active, bell.uid, "swap tap")
	eq(St.energy, en0, "swap is free")
	eq(St.swap_cd, 6.0, "swap cooldown 6s")
	St.chain_t = 99
	Bt.play_card(2)
	eq(e.status.k, "soak", "Drench soaked")
	# soak: Splash 5 tide vs thorn (resisted 0.66) ×1.25 → 4
	_hand(3, bell.uid, "strike")
	hp0 = e.hp
	Bt.play_card(3)
	eq(hp0 - e.hp, float(roundi(5 * 1.1 * 1.25)), "soaked: tide vs thorn neutral ×1.1 chain ×1.25")
	Bt.swap_tap(wick.uid)
	eq(St.active, bell.uid, "swap tap blocked by cooldown")
	_hand(0, bell.uid, "strike")
	St.energy = 0
	Bt.play_card(0)
	eq(denied, ["bench", "energy"], "denied without energy")
	Bt.card_denied.disconnect(on_denied)
	check(ui.calls.get("refresh_hand", 0) > 0, "UI refreshed")
	# a fainted creature's cards stay and are discarded for 1 energy
	wick.alive = false
	wick.hp = 0
	_hand(1, wick.uid, "sig")
	var dead = St.hand[1]
	St.energy = 3
	St.chain = 2
	St.chain_t = 0
	var hp1: float = e.hp
	var disc := []
	var on_disc := func(i): disc.append(i)
	Bt.card_discarded.connect(on_disc)
	Bt.play_card(1)
	Bt.card_discarded.disconnect(on_disc)
	eq(disc, [1], "dead card discarded")
	eq(St.energy, 2.0, "discard costs 1")
	eq(e.hp, hp1, "discard does no damage")
	eq(St.chain, 2, "discard leaves the chain")
	check(dead in St.disc, "dead card in the discard pile")
	check(St.hand[1] != dead, "slot redrawn")
	St.swap_cd = 0
	Bt.swap_tap(wick.uid)
	eq(St.active, bell.uid, "can't swap to a fainted creature")
	wick.alive = true
	wick.hp = wick.max_hp
	# multi-hit lands extra hits later; from_shield; next_strike
	e = _battle(["coilsnail", "kilnback"], "brinecrab")
	var coil: Mon = St.party[0]
	_hand(0, coil.uid, "skill")   # Capacitor: shield 10, next strike ×2
	Bt.play_card(0)
	eq(coil.shield, 10.0, "Capacitor shield")
	eq(coil.next_strike, 2.0, "Capacitor next strike")
	_hand(1, coil.uid, "strike")   # Prod 5 volt vs tide ×1.5, ×2 → 15 (+chain 10%)
	St.chain_t = 99
	hp0 = e.hp
	Bt.play_card(1)
	eq(hp0 - e.hp, roundf(5 * 2 * 1.5), "next strike doubled")
	eq(coil.next_strike, 1.0, "next strike consumed")
	_hand(2, coil.uid, "sig")   # Discharge: dmg = shield
	St.chain_t = 99
	hp0 = e.hp
	Bt.play_card(2)
	eq(hp0 - e.hp, roundf(10 * 1.5), "Discharge = shield")
	eq(coil.shield, 0.0, "shield consumed")

## The owner rule: the owning lead plays a card in full; a same-element lead plays it as a basic hit;
## another element can't play it; with no living creature of its element it is dead.
func test_element_cards() -> void:
	section = "owner cards"
	var e := _battle(["emberwick", "cinderpip", "bellspring"], "mossling")
	var wick: Mon = St.party[0]
	var pip: Mon = St.party[1]
	var bell: Mon = St.party[2]
	var scorch := CardRef.new(pip.uid, "strike")   # Scorch (1): 7 dmg
	var peck := CardRef.new(wick.uid, "strike")     # Peck (1): 6 dmg
	var wsig := CardRef.new(wick.uid, "sig")        # Wickflare (3): 14 dmg
	eq(St.card_el(scorch), "ember", "card element = owner element")
	# owner leading: full card
	check(not St.card_basic(peck), "owner leading: not basic")
	eq(St.card_by(peck), wick, "owner fires its card")
	eq(St.card_waiting_for(peck), null, "owner leads: waiting for nobody")
	# same element, not the owner: basic hit
	check(St.card_basic(scorch), "same-element non-owner: basic")
	eq(St.card_block(scorch), "", "basic card playable")
	check(not St.card_benched(scorch), "basic card isn't benched")
	eq(St.card_waiting_for(scorch), pip, "basic card waits for its owner")
	eq(St.card_cost(scorch), Dt.BAL.basic_cost, "basic costs BAL.basic_cost")
	eq(St.card_cost(wsig), 3, "the owner's own card keeps its cost")
	St.active = pip.uid
	eq(St.card_cost(wsig), Dt.BAL.basic_cost, "a 3-cost card plays basic for 1")
	St.active = wick.uid
	wick.power = 2.0
	pip.power = 1.0
	eq(St.basic_dmg(scorch), 8, "basic damage = 4 × the lead's Power")
	eq(St.card_by(scorch), wick, "basic fires as the lead (Power)")
	# other element: blocked
	var splash := CardRef.new(bell.uid, "strike")
	eq(St.card_block(splash), "bench", "other element waits for a swap")
	check(St.card_benched(splash), "other element benched")
	check(not St.card_basic(splash), "other element isn't basic")
	eq(St.card_by(splash), bell, "preview by the owner")
	# faces: only the owner
	eq(St.card_faces(scorch), [pip], "faces: owner only")
	eq(St.card_faces(wsig), [wick], "faces: owner only (2)")
	# play the basic: 1 energy, 4×Power in the lead's element (ember vs thorn ×1.5), +1 chain, no discount use
	St.discount = 1
	St.chain = 1
	St.chain_t = 0
	_hand(0, scorch.uid, scorch.slot)
	var hp0 := e.hp
	var en0: float = St.energy
	var played := []
	var on_played := func(i): played.append(i)
	Bt.card_played.connect(on_played)
	Bt.play_card(0)
	Bt.card_played.disconnect(on_played)
	eq(played, [0], "basic emits card_played")
	eq(hp0 - e.hp, float(roundi(4 * 2.0 * 1.2 * 1.5)), "basic: 4×2 Power ×chain 2 ×1.5 element")
	eq(St.energy, en0 - 1, "basic costs 1")
	eq(St.chain, 2, "basic adds a chain step")
	eq(St.discount, 1, "basic leaves the discount")
	eq(wick.played, 0, "basic isn't the lead's played card")
	eq(pip.played, 0, "nor the owner's")
	eq(St.active, wick.uid, "playing never swaps")
	St.discount = 0
	# a basic doesn't trigger the lead's Quickfuse (and Quickfuse doesn't free it)
	wick.trait_key = "quickfuse"
	wick.played = 0
	eq(St.card_cost(scorch), 1, "Quickfuse doesn't free a basic")
	_hand(1, scorch.uid, scorch.slot)
	Bt.play_card(1)
	eq(wick.played, 0, "Quickfuse still armed after a basic")
	eq(St.card_cost(wsig), 0, "Quickfuse frees the owner's own card")
	wick.trait_key = "afterglow"
	# the owner's card plays in full with its effects
	St.chain_t = 99
	wick.power = 1.0
	_hand(2, wsig.uid, wsig.slot)
	hp0 = e.hp
	en0 = St.energy
	Bt.play_card(2)
	eq(hp0 - e.hp, roundf(14 * 1.5), "Wickflare in full by its owner")
	eq(St.energy, en0 - 3, "Wickflare costs 3")
	eq(wick.played, 1, "the owner counts the play")
	# off-element deny toast names the owner
	St.active = bell.uid
	var fx = mod("Fx")
	fx.log.clear()
	_hand(3, wick.uid, "skill")
	Bt.play_card(3)
	var toasts: Array = fx.log.filter(func(l): return l[0] == "toast")
	check(toasts.size() > 0 and "Emberwick" in str(toasts[-1][1]), "bench toast names the owner")
	# owner KO'd, same-element teammate leads: basic
	wick.alive = false
	wick.hp = 0
	St.active = pip.uid
	check(not St.card_dead(wsig), "Cinderpip alive: Emberwick's card lives on")
	check(St.card_basic(wsig), "owner KO'd: basic for the same-element lead")
	eq(St.card_waiting_for(wsig), null, "a KO'd owner isn't waited for")
	eq(St.card_faces(wsig), [wick], "faces: still the owner")
	St.active = bell.uid
	eq(St.card_block(wsig), "bench", "off-element lead: benched")
	# every creature of the element down: dead
	pip.alive = false
	check(St.card_dead(scorch), "all Ember down: dead")
	check(St.card_dead(wsig), "all Ember down: dead (other owner)")
	check(not St.card_basic(scorch), "dead isn't basic")
	check(not St.card_benched(scorch), "dead isn't benched")
	eq(St.card_block(scorch), "", "dead card can be discarded")
	wick.alive = true
	wick.hp = wick.max_hp
	pip.alive = true
	# Thirst: a basic Strike from a teammate doesn't heal the lead
	e = _battle(["truffmole", "brambat"], "puddlet")
	var mole: Mon = St.party[0]
	var bat: Mon = St.party[1]
	mole.trait_key = "thirst"
	mole.hp = 10
	bat.hp = 10
	_hand(0, bat.uid, "strike")   # Nip: dmg, heal self 2 (but as a basic: no effects)
	Bt.play_card(0)
	eq(mole.hp, 10.0, "basic: no Thirst, no Nip heal")
	eq(bat.hp, 10.0, "owner not healed")
	St.active = bat.uid
	St.chain_t = 99
	bat.trait_key = "thirst"
	_hand(1, bat.uid, "strike")
	Bt.play_card(1)
	check(bat.hp > 12.0, "owner leading: Nip heals and Thirst fires")

func test_statuses() -> void:
	section = "status"
	# burn on enemy: 1 dmg every 0.5s for 4s
	var e := _battle(["emberwick"], "skiray")
	var wick: Mon = St.party[0]
	wick.trait_key = null
	_hand(0, wick.uid, "skill")   # Kindle
	Bt.play_card(0)
	eq(e.status.k, "burn", "Kindle burns")
	var hp0 := e.hp
	St.auto_t = -999   # no auto-attacks
	for i in 32:
		e.t = 0
		Bt.tick_battle(0.125, 0)
	eq(hp0 - e.hp, 8.0, "burn 2/s for 4s")
	eq(e.status, null, "burn expired")
	# root slows the intent bar 40%
	e = _battle(["truffmole"], "skiray")
	var mole: Mon = St.party[0]
	_hand(0, mole.uid, "skill")   # Tangle
	Bt.play_card(0)
	near(e.status.t, 3.0 + 1.5, "root + Deep Roots")
	var t0 := e.t
	St.auto_t = -999
	Bt.tick_battle(0.5, 0)
	near(e.t - t0, 0.3, "rooted intent fills 40% slower")
	# shock resets wind-up and gives immunity
	e = _battle(["skiray"], "puddlet")
	var sky: Mon = St.party[0]
	e.t = 2.0
	_hand(0, sky.uid, "skill")   # Static
	Bt.play_card(0)
	eq(e.t, 0.0, "shock resets intent")
	eq(e.shock_cd, 6.0, "shock immunity")
	eq(e.status, null, "shock doesn't occupy the slot")
	e.t = 1.0
	_hand(1, sky.uid, "skill")
	Bt.play_card(1)
	eq(e.t, 1.0, "immune to re-shock")
	# statuses on your creature
	e = _battle(["emberwick", "bellspring"], "skiray")
	wick = St.party[0]
	St.chain = 3
	Bt._apply_mon_status(wick, "shock")
	eq(St.chain, 0, "shock resets your chain")
	eq(St.swap_cd, 1.0, "shock puts swapping on a 1s cooldown")
	Bt._apply_mon_status(wick, "root")
	St.energy = 0
	St.auto_t = -999
	e.t = 0
	Bt.tick_battle(1.0, 0)
	near(St.energy, 0.6, "rooted lead regenerates 40% slower")
	Bt._apply_mon_status(wick, "burn")
	var whp := wick.hp
	for i in 8:
		e.t = 0
		Bt.tick_battle(0.125, 0)
	eq(whp - wick.hp, 2.0, "burn on you 2/s")
	Bt._apply_mon_status(wick, "soak")
	whp = wick.hp
	Bt._hurt_mon(wick, 8, "volt", false)   # volt vs ember neutral ×1.25
	eq(whp - wick.hp, 10.0, "soaked takes +25%")

func test_shields() -> void:
	section = "shields"
	var e := _battle(["kilnback", "emberwick"], "skiray")
	var kiln: Mon = St.party[0]
	kiln.trait_key = null
	Bt._add_shield(kiln, 12)
	St.auto_t = -999
	for i in 24:
		e.t = 0
		Bt.tick_battle(0.125, 0)
	eq(kiln.shield, 12.0, "no decay for 3s")
	for i in 8:
		e.t = 0
		Bt.tick_battle(0.125, 0)
	near(kiln.shield, 12 * pow(1 - 0.2 * 0.125, 8), "decays 20%/s after 3s")
	kiln.shield = 6
	var hp0 := kiln.hp
	Bt._hurt_mon(kiln, 10, "volt", false)   # volt vs ember neutral
	eq(kiln.shield, 0.0, "shield broken")
	eq(hp0 - kiln.hp, 4.0, "rest goes through")
	kiln.trait_key = "bulwark"
	Bt._add_shield(kiln, 10)
	for i in 48:
		e.t = 0
		Bt.tick_battle(0.125, 0)
	eq(kiln.shield, 10.0, "Bulwark: no decay for 6s")

func test_traits() -> void:
	section = "traits"
	# Overshade: half the shield to the weakest teammate
	var e := _battle(["mossling", "emberwick", "bellspring"], "skiray")
	var moss: Mon = St.party[0]
	var wick: Mon = St.party[1]
	wick.hp = 10
	_hand(0, moss.uid, "skill")   # Overgrow: root + shield 6
	Bt.play_card(0)
	eq(moss.shield, 6.0, "Overgrow shield")
	eq(wick.shield, 3.0, "Overshade half to weakest")
	# Undercurrent: heals cleanse
	e = _battle(["puddlet", "emberwick"], "skiray")
	var pud: Mon = St.party[0]
	wick = St.party[1]
	wick.status = {"k": "burn", "t": 3.0, "acc": 0.0}
	wick.hp = 20
	_hand(0, pud.uid, "sig")   # Spring Rain: heal team 12, cleanse
	pud.trait_key = "undercurrent"
	pud.moves.sig = 1   # Wellspring: heal team 6, +2 energy (no cleanse of its own)
	Bt.play_card(0)
	eq(wick.status, null, "Undercurrent cleansed teammate")
	eq(wick.hp, 26.0, "Wellspring healed 6")
	# Thirst: strikes heal 30%
	e = _battle(["brambat"], "puddlet")
	var bat: Mon = St.party[0]
	bat.hp = 10
	_hand(0, bat.uid, "strike")   # Nip 5 thorn vs tide (neutral): heal 2, then Thirst round(30%×5)=2
	Bt.play_card(0)
	eq(bat.hp, 14.0, "Nip heal 2 + Thirst 2")
	# Relay + Live Wire + Quickfuse
	e = _battle(["emberwick", "skiray", "sparkit"], "puddlet")
	var sky: Mon = St.party[1]
	var spk: Mon = St.party[2]
	Bt.swap_tap(sky.uid)
	eq(St.discount, 1, "Relay: next card -1 after swapping to it")
	St.energy = 5
	St.swap_cd = 0
	St.chain = 2
	St.chain_t = 0
	St.active = spk.uid
	_hand(1, spk.uid, "strike")   # Jolt 1 - 1 relay = 0; chain → 3 → Live Wire +1
	Bt.play_card(1)
	eq(St.chain, 3, "chain 3")
	check(St.wired, "Live Wire paid")
	eq(St.energy, 6.0, "Relay discount + Live Wire energy")
	# Ebb: heals 4 when swapped out
	e = _battle(["bellspring", "emberwick"], "skiray")
	var bell: Mon = St.party[0]
	bell.hp = 30
	Bt.swap_tap(St.party[1].uid)
	eq(bell.hp, 34.0, "Ebb heal on swap out")
	# Grounded: shock gives energy
	e = _battle(["coilsnail"], "skiray")
	St.energy = 2
	St.chain = 2
	Bt._apply_mon_status(St.party[0], "shock")
	eq(St.energy, 3.0, "Grounded +1 energy")
	eq(St.chain, 2, "Grounded keeps the chain")
	# Afterglow: +1 energy when its burn ends
	e = _battle(["emberwick"], "skiray")
	_hand(0, St.party[0].uid, "skill")
	Bt.play_card(0)
	St.energy = 0
	St.auto_t = -999
	for i in 32:
		e.t = 0
		Bt.tick_battle(0.125, 0)
	near(St.energy, 4.0 + 1, "Afterglow +1 energy")

func test_perfect_swap() -> void:
	section = "perfect"
	var e := _battle(["emberwick", "bellspring", "brinecrab"], "kilnback")   # ember heavy; tide resists
	var bell: Mon = St.party[1]
	var crab: Mon = St.party[2]
	Bt._dbg_heavy()
	check(St.is_heavy(e), "next attack heavy")
	e.t = e.windup - 0.3
	St.energy = 5
	St.auto_t = -999
	var hp0 := e.hp
	var feel = mod("Feel")
	var hs0: int = feel.calls.get("slow_mo", 0)
	Bt.swap_tap(bell.uid)
	check(e.perfect, "perfect swap")
	eq(St.energy, 7.0, "refund 2 (swaps are free)")
	eq(St.stats.perfects, 1, "perfect counted")
	eq(feel.calls.get("slow_mo", 0), hs0 + 1, "slow-mo")
	Bt.tick_battle(0.31, 0)   # the heavy fires
	var bhp := bell.hp
	await create_timer(1.0).timeout
	eq(bell.hp, bhp, "perfect swap takes 0 damage")
	eq(bell.status, null, "and no status")
	eq(hp0 - e.hp, roundf(e.dmg * 2.5 * 0.5), "50% reflected (ember vs ember neutral)")
	# a heavy without a perfect swap hits and applies its status
	St.swap_cd = 0
	Bt.swap_tap(St.party[0].uid)   # emberwick, not resisting ember
	var wick: Mon = St.party[0]
	Bt._dbg_heavy()
	e.t = e.windup - 0.01
	var whp := wick.hp
	Bt.tick_battle(0.02, 0)
	await create_timer(1.0).timeout
	eq(whp - wick.hp, roundf(e.dmg * 2.5), "heavy lands 2.5×")
	eq(wick.status.k if wick.status else "", "burn", "heavy applies its status")
	# Counterweave: perfect swap into Brinecrab fires its Strike
	St.swap_cd = 0
	Bt._dbg_heavy()
	e.t = e.windup - 0.2
	hp0 = e.hp
	Bt.swap_tap(crab.uid)
	check(e.perfect, "perfect into brinecrab")
	eq(hp0 - e.hp, roundf(6 * 1.5), "Counterweave Strike (Pinch tide vs ember)")

func test_sim_fight() -> void:
	section = "sim"
	var run = mod("Run")
	var after0: int = run.calls.get("after_fight", 0)
	var e := _battle(["emberwick", "bellspring", "truffmole"], "skiray")
	St.energy = Dt.BAL.energy_start
	Engine.time_scale = 6.0
	Engine.max_fps = 60
	var t := 0.0
	var start := Time.get_ticks_msec()
	while St.mode == "battle" or St.mode == "intro":
		var dt := minf(root.get_process_delta_time(), 0.1)
		t += dt
		Bt.tick_battle(dt, t)
		for i in St.hand.size():
			if St.hand[i] != null and St.card_block(St.hand[i]) == "":
				Bt.play_card(i)
				break
		await process_frame
		if Time.get_ticks_msec() - start > 30000:
			break
	check(not e.alive, "won the fight in %.1fs of game time" % t)
	check(St.stats.dealt >= e.max, "damage dealt counted")
	await create_timer(1.6).timeout   # scaled time
	Engine.time_scale = 1.0
	Engine.max_fps = 0
	eq(run.calls.get("after_fight", 0), after0 + 1, "Run.after_fight called")
	check(St.team().all(func(c): return c.hp <= c.max_hp and c.hp >= 0), "hp in range")
