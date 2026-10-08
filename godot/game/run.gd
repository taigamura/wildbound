extends Node
## Run flow outside combat (TS game/run.ts): title (team picker), packs, collection & upgrades, item shop,
## map, nodes, loot, rewards, lineup, end of run. Spec: ../CLAUDE.md §2, §5–§7, §11, §16.
## Screens are the frames Ui builds (Ui.el ids = index.html ids); this fills and wires them.

## UI colours of the materials (the Ember / Tide / Thorn accents).
const MAT_COL := {"sword": UiKit.EL.ember, "orb": UiKit.EL.tide, "jewel": UiKit.EL.thorn}

var run_ess := {}
var run_loot := {}
## Pack points banked this run, the meter's points when it started, and the packs this run earned (§11).
var run_pts := 0
var run_pts0 := 0
var run_packs := 0
var _pack_n := 0

func _el() -> Dictionary:
	return Ui.el

## Replace a button's click handler (TS `.onclick =`).
func _on(t: Tap, f: Callable) -> void:
	for c in t.pressed.get_connections():
		t.pressed.disconnect(c.callable)
	t.pressed.connect(f)

func _click() -> void:
	Sfx.audio()
	Sfx.pick()
	Platform.haptic("select")

## TS btn(): a button that plays the pick sound + haptic before its action.
func _btn(t: Tap, f: Callable) -> Tap:
	t.pressed.connect(func():
		_click()
		f.call())
	return t

## A list row (map node, shop item): portrait, name, sub line, optional trailing piece. Flat; the
## Rows list it sits in draws the hairlines between rows.
func _node_btn(g: String, title: String, sub: String, c: Color, f: Callable, raw := false, trail: Control = null) -> Tap:
	var t := Tap.new(UiKit.row_style())
	t.add_child(UiKit.list_row(UiKit.por(c, 40, g), title, sub, trail))
	if raw:
		t.pressed.connect(f)
	else:
		_btn(t, f)
	return t

func _later(t: float, f: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(f)

# ================= run start =================
## The title screen's picks, limited to owned species (falls back to the last saved lineup).
func _valid_picks() -> Array:
	var own := Meta.owned()
	var p: Array = []
	for k in S.picks:
		if k in own and not (k in p) and p.size() < Data.BAL.lineup:
			p.append(k)
	return p if p.size() else Meta.last_lineup()

func start_run() -> void:
	Sfx.audio()
	Platform.haptic("medium")
	S.clear_actors()
	S.tok += 1
	S.uid = 1
	S.picks = _valid_picks()
	Meta.save_lineup(S.picks)
	S.party.clear()
	S.lineup.clear()
	for k in S.picks:
		var c: Mon = S.new_mon(k, Meta.is_shiny(k))
		S.party.append(c)
		S.lineup.append(c.uid)
	S.active = S.lineup[0]
	S.floor = 1
	S.stats = {"start": Platform.ticks_msec(), "dealt": 0, "perfects": 0}
	run_ess = Meta.empty_essence()
	run_loot = Data.no_loot()
	run_pts = 0
	run_pts0 = Meta.pack_pts()
	run_packs = 0
	if _pack_tw != null and _pack_tw.is_valid():   # "Run again" mid-fill: no "Pack earned!" haptic on the map
		_pack_tw.kill()
	Stage.set_biome(0)
	place_player(true)
	Sfx.win()
	show_map()

# ================= essence (§16.3) =================
func _gain(el: String, n: int) -> void:
	Meta.earn(el, n)
	run_ess[el] = run_ess.get(el, 0) + n

func _fight_essence(e) -> void:
	if e.kind == "wild":
		_gain(Data.SPECIES[e.key].el, Data.BAL.ess_wild)
	elif e.kind == "alpha":
		_gain(Data.SPECIES[e.key].el, Data.BAL.ess_alpha)
	elif e.kind == "warden":
		_gain("thorn", Data.BAL.ess_warden)
		_gain("ember", Data.BAL.ess_warden)
	else:
		for el in Data.EL_KEYS:
			_gain(el, Data.BAL.ess_boss)

## Essence chips: totals (`plus` = false) or this run's gains, skipping zeros.
func _ess_chips(e: Dictionary, plus := false) -> Array:
	var out: Array = []
	for el in Data.EL_KEYS:
		var n: int = e.get(el, 0)
		if plus and n <= 0:
			continue
		out.append(UiKit.ess(el, UiKit.el_css(el), ("+%d %s" % [n, Data.ELEM[el].name]) if plus else str(n)))
	return out

## TS costHTML: "5<glyph>".
func _cost(c: Dictionary, color := Color(0, 0, 0, 0)) -> HBoxContainer:
	var col := color if color.a > 0 else UiKit.el_css(c.el)
	var h := UiKit.hbox(2)
	h.add_child(UiKit.lbl(str(c.n), "700", UiKit.T_S, UiKit.INK))
	h.add_child(UiKit.icon(c.el, 12, col))
	return h

# ================= pack meter (§11) =================
## Bank a won fight's pack points (kept win or lose). Returns {n: points, gained: packs this add earned}.
func _fight_pts(e) -> Dictionary:
	var n: int = Data.BAL.pts_wild
	match e.kind:
		"alpha": n = Data.BAL.pts_alpha
		"warden": n = Data.BAL.pts_warden
		"boss": n = Data.BAL.pts_boss
	var r := Meta.add_pack_pts(n)
	run_pts += n
	run_packs += int(r.gained)
	return {"n": n, "gained": int(r.gained)}

# ================= loot (§5.1) =================
## Bank loot now (kept win or lose) and count it toward this run's total.
func _bank(l: Dictionary) -> void:
	Meta.add_loot(l)
	for k in l:
		run_loot[k] = run_loot.get(k, 0) + l[k]

func _floor_gold() -> float:
	return 1.0 + Data.BAL.gold_per_floor * (S.floor - 1)

## What a won fight drops.
func _roll_loot(e) -> Dictionary:
	var l := Data.no_loot()
	var mat := func(n: int):
		for i in n:
			var m: String = Meta.random_mat()
			l[m] += 1
	if e.kind == "boss":
		l.gold = Data.BAL.boss_gold
		for m in Data.MATS:
			l[m] += 1
	elif e.kind == "warden":
		l.gold = Data.BAL.warden_gold
		mat.call(Data.BAL.warden_mats)
	else:
		var lo: int = Data.BAL.wild_gold[0]
		var hi: int = Data.BAL.wild_gold[1]
		var g := lo + randi() % (hi - lo + 1)
		if e.kind == "alpha":
			l.gold = roundi(g * _floor_gold() * Data.BAL.alpha_gold_mul)
			mat.call(Data.BAL.alpha_mats)
		else:
			l.gold = roundi(g * _floor_gold())
			if randf() < Data.BAL.wild_mat_chance:
				mat.call(1)
	return l

## Loot chips: totals (`plus` = false) or gains, skipping zeros.
func _loot_chips(l: Dictionary, plus := false) -> Array:
	var out: Array = []
	var chip := func(g: String, c: Color, n: int, name: String):
		if plus and not n:
			return
		out.append(UiKit.ess(g, c, ("+%d %s" % [n, name]) if plus else str(n)))
	chip.call("coin", UiKit.GOLD, l.get("gold", 0), "gold")
	for m in Data.MATS:
		chip.call(m, MAT_COL[m], l.get(m, 0), Data.MAT_DEF[m].name)
	return out

func _fill(box: Control, items: Array) -> void:
	UiKit.clear(box)
	for it in items:
		box.add_child(it)

## Show the lead on its pedestal and hide everyone else (except `keep`, which may be animating out).
func place_player(pop: bool, keep = null) -> void:
	for a in S.actors.values():
		if a != keep and is_instance_valid(a):
			a.visible = false
	var c = S.act()
	if c == null:
		return
	var a = S.actor_for(c)
	a.visible = true
	a.off = Vector2.ZERO
	a.squash = Vector2.ONE
	a.rot = 0.0
	if pop:
		var p: Vector2 = Layout.ppos()
		a.squash = Vector2(0.01, 0.01)
		a.create_tween().tween_property(a, "squash", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Particles.emit(p.x, p.y, {"n": 60, "color": Data.ELEM[c.el].glow, "spd": 2.5, "dir": [0, -1], "cone": 0.35, "life": 0.9, "size": 0.22, "drag": 1.5, "r": 0.4})
		Particles.ring(p.x, p.y, Data.ELEM[c.el].hex, 1.8)
		if c.shiny:
			_sparkle(p.x, p.y - Layout.U)

func _sparkle(x: float, y: float) -> void:
	Particles.emit(x, y, {"n": 24, "color": [Color("#ffffff"), Color("#ffe9a8"), Color("#c8f0ff")], "spd": 2.6, "life": 0.9, "size": 0.3, "drag": 1.5, "tex": "star", "spin": 6})

# ================= map =================
func _wild_node(f: int, pool: Array, avoid_el = null) -> MapNode:
	var p := pool
	if avoid_el != null:
		p = pool.filter(func(k): return Data.SPECIES[k].el != avoid_el)
	var sp: String = Util.pick(p if p.size() else pool)
	var lvl: int = f + (Data.BAL.biome_b_bonus if Data.biome_of(f) == 1 and sp in Data.POOL_A else 0)
	return MapNode.new("wild", sp, lvl)

func _gen_nodes(f: int) -> Array:
	if f == Data.BAL.floors:
		return [MapNode.new("boss", "noctyrm", f)]
	if f == 4:
		return [MapNode.new("warden", "warden", f)]
	if Data.biome_of(f) == 0:
		var a := _wild_node(f, Data.POOL_A)
		var out: Array = [a, _wild_node(f, Data.POOL_A, Data.SPECIES[a.sp].el)]
		if randf() < 0.5:
			if f == 1 or randf() < 0.5:
				out.append(MapNode.new("spring"))
			else:
				var al := _wild_node(f, Data.POOL_A)
				al.type = "alpha"
				out.append(al)
		return out
	var pool_b: Array = Data.POOL_B + Data.POOL_A
	var w := _wild_node(f, pool_b)
	var al2 := _wild_node(f, pool_b, Data.SPECIES[w.sp].el)
	al2.type = "alpha"
	var out2: Array = [w, al2]
	if randf() < 0.6:
		out2.append(MapNode.new("spring"))
	return out2

## What a node shows: colour, glyph, medallion label `m`, strip title `t`, element (or ""), and the
## strip's sub line `s` (§6: Wilds and Alphas show gold range and material chance; the Warden and
## the boss show only their icon and name).
func _node_view(n: MapNode) -> Dictionary:
	if n.type == "wild" or n.type == "alpha":
		var sp: Dictionary = Data.SPECIES[n.sp]
		var el: String = sp.el
		var a: float = Data.adv(S.act().el, el)
		var f: float = _floor_gold() * (Data.BAL.alpha_gold_mul if n.type == "alpha" else 1)
		var gold := "%d–%d gold" % [roundi(Data.BAL.wild_gold[0] * f), roundi(Data.BAL.wild_gold[1] * f)]
		var parts: Array = [("Tougher · 2 picks · %s · %d material" % [gold, Data.BAL.alpha_mats]) if n.type == "alpha" \
			else ("%s · %d%% material" % [gold, roundi(Data.BAL.wild_mat_chance * 100)])]
		if a > 1:
			parts.append("%s is strong here" % S.act().name)
		elif a < 1:
			parts.append("%s is weak here" % S.act().name)
		return {"c": UiKit.el_css(el), "g": "skull" if n.type == "alpha" else "paw", "m": sp.name,
			"t": ("Alpha " if n.type == "alpha" else "Wild ") + sp.name, "el": el, "s": " · ".join(parts)}
	if n.type == "spring":
		return {"c": UiKit.HP, "g": "moon", "m": "Spring", "t": "Moon Spring", "el": "", "s": "Heal the party to full"}
	if n.type == "warden":
		return {"c": UiKit.EL.thorn, "g": "crown", "m": "Gravewood", "t": "Gravewood", "el": "", "s": ""}
	return {"c": UiKit.FOE, "g": "crown", "m": "Noctyrm", "t": "Noctyrm", "el": "", "s": ""}

## The selected medallion on this floor's map (a first tap selects, a second tap travels).
var _map_sel := 0

## `reroll` = false keeps this floor's nodes and selection (coming back from the lineup screen).
func show_map(reroll := true) -> void:
	var el := _el()
	S.mode = "map"
	S.enemy = null
	if S.em != null and is_instance_valid(S.em):
		S.em.destroy()
	S.em = null
	Stage.tint_arena(Stage.ambience.neutral)
	Stage.set_biome(Data.biome_of(S.floor))
	place_player(false)
	if reroll or S.nodes.is_empty():
		S.nodes = _gen_nodes(S.floor)
		_map_sel = 0
	_map_sel = clampi(_map_sel, 0, S.nodes.size() - 1)
	var last: int = Data.BAL.floors
	el.mapEyebrow.text = ("Final floor" if S.floor == last else "Floor %d of %d" % [S.floor, last]) \
		+ (" · The Dusklands" if Data.biome_of(S.floor) else " · The Greenwood")
	var kind: String = S.nodes[0].type if S.nodes.size() == 1 else ""
	el.mapTitle.text = "Face the Warden" if kind == "warden" else ("Face Noctyrm" if kind == "boss" else "Pick a path")
	# the trail: the floors still to walk fade up toward the next boss (floor 4, then the last floor)
	var goal_f := 4 if S.floor < 4 else last
	var goal := {}
	var between: Array = []
	if goal_f > S.floor:
		goal = {"t": "Floor %d · %s" % [goal_f, "Warden" if goal_f == 4 else "Noctyrm"], "g": "crown"}
		for f in range(goal_f - 1, S.floor, -1):
			between.append("Floor %d" % f)
	var views: Array = []
	for n in S.nodes:
		var h := _node_view(n)
		views.append({"c": h.c, "g": h.g, "t": h.m})
	var trail: MapTrail = el.trail
	trail.set_trail(views, goal, " · ".join(between), _map_sel)
	for c in trail.tapped.get_connections():
		trail.tapped.disconnect(c.callable)
	trail.tapped.connect(_map_tap)
	_on(el.mapGo, func():
		_click()
		_travel())
	_map_info()
	UiKit.clear(el.mapParty)
	for i in S.lineup.size():
		var c = S.mon(S.lineup[i])
		if c != null:
			el.mapParty.add_child(UiKit.party_por(c, 30, i == 0))
	_fill(el.mapGold, [UiKit.wallet_row(Meta.wallet())])
	el.lineupBtn.visible = S.party.size() >= 2
	Ui.show("scr-map")

## A medallion tap: select it, or travel if it already is.
func _map_tap(i: int) -> void:
	if S.mode != "map" or i >= S.nodes.size():
		return
	if i == _map_sel:
		_click()
		_travel()
		return
	Sfx.audio()
	Sfx.pick()
	Platform.haptic("select")
	_map_sel = i
	_el().trail.select(i)
	_map_info()

## Fill the detail strip for the selected node.
func _map_info() -> void:
	var el := _el()
	var h := _node_view(S.nodes[_map_sel])
	var head: HBoxContainer = el.mapInfoHead
	UiKit.clear(head)
	var nm := UiKit.lbl(h.t, "display", UiKit.NAME, UiKit.INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(nm)
	if h.el != "":
		head.add_child(UiKit.elchip(h.el, Data.ELEM[h.el].name))
	elif h.s == "":   # Warden and boss: icon and name only
		head.add_child(UiKit.icon(h.g, 14, h.c))
	el.mapInfoSub.text = h.s
	el.mapInfoSub.visible = h.s != ""

func _travel() -> void:
	if S.mode != "map" or S.nodes.is_empty():
		return
	_choose_node(S.nodes[clampi(_map_sel, 0, S.nodes.size() - 1)])

func _choose_node(n: MapNode) -> void:
	if n.type == "spring":
		for c in S.party:
			c.alive = true
			c.hp = c.max_hp
		for k in 4:
			_later(k * 0.15, func():
				var p: Vector2 = Layout.ppos()
				Particles.emit(p.x, p.y, {"n": 40, "color": [Color("#6ff0a0"), Color("#c8ffd9"), Color("#8fe3ff")], "spd": 2, "dir": [0, -1], "cone": 0.5, "life": 1.3, "size": 0.24, "drag": 1, "r": 0.6, "swirl": 3})
				Particles.ring(p.x, p.y, Color("#6ff0a0"), 2))
		Sfx.heal()
		Platform.haptic("success")
		Fx.toast("Party fully healed")
		_next_floor()
		return
	Battle.start_battle(n)

func _next_floor() -> void:
	S.floor += 1
	show_map()

# ================= after a fight =================
## Tidy the party (victories don't heal: fainted creatures stay down until a Spring or Heal),
## bank the loot, then route to rewards or the end of the run.
func after_fight() -> void:
	var e = S.enemy
	for c in S.party:
		c.shield = 0.0
		c.status = null
		c.reflect = 0.0
		c.next_strike = 1.0
	if not (S.active in S.lineup):
		S.active = S.lineup[0]
	if S.act() == null or not S.act().alive:
		var h := S.healthiest()
		if h != null:
			S.active = h.uid
	var loot = null
	var before := run_ess.duplicate()
	if e != null:
		_fight_essence(e)
		loot = _roll_loot(e)
		_bank(loot)
	var pts := _fight_pts(e) if e != null else {"n": 0, "gained": 0}
	if e != null and e.kind == "boss":
		end_run(true)
		return
	if S.em != null and is_instance_valid(S.em):
		S.em.destroy()
	S.em = null
	place_player(false)
	var ess := {}
	for k in run_ess:
		if run_ess[k] - before.get(k, 0) > 0:
			ess[k] = run_ess[k] - before.get(k, 0)
	_show_reward(2 if (e != null and e.kind == "alpha") else 1, loot, ess, true, pts)

# ================= rewards =================
func _upgradable() -> bool:
	for c in S.party:
		for s in Data.SLOTS:
			if not c.ups.get(s):
				return true
	return false

## Picks this reward screen started with (Alphas give 2), for the pip row.
var _rw_total := 1

## The loot ribbon's chips: gold, each material, then each element's Essence (`ess`), skipping zeros,
## then the fight's pack points (`pts`, and "Pack earned!" when they filled the meter).
func _ribbon_chips(l: Dictionary, ess: Dictionary, pts := {}) -> Array:
	var out: Array = []
	if l.get("gold", 0):
		out.append(UiKit.loot_chip("coin", UiKit.GOLD_HI, "+%d gold" % l.gold))
	for m in Data.MATS:
		if l.get(m, 0):
			out.append(UiKit.loot_chip(m, MAT_COL[m], "+%d %s" % [l[m], Data.MAT_DEF[m].name]))
	# Essence: one chip; a single element reads "+2 Essence", several share one chip
	var pairs: Array = []
	for e in Data.EL_KEYS:
		if ess.get(e, 0):
			pairs.append([e, UiKit.el_css(e), "+%d" % ess[e]])
	if pairs.size() == 1:
		out.append(UiKit.loot_chip(pairs[0][0], pairs[0][1], "%s Essence" % pairs[0][2]))
	elif pairs.size() > 1:
		out.append(UiKit.multi_chip("Essence", pairs))
	if pts.get("n", 0):   # one chip, so a pack earned doesn't push the ribbon to another line
		out.append(UiKit.loot_chip("pack", UiKit.GOLD_HI, ("+%d pts · Pack earned!" if pts.get("gained", 0) else "+%d pack pts") % pts.n))
	return out

## `ess` = the Essence this fight earned; `fresh` = first showing (the ribbon pops in; later picks and
## coming back from the upgrade screen show it at rest). `pts` = the fight's pack points ({n, gained}).
var _rw_pts := {}
func _show_reward(picks: int, loot, ess := {}, fresh := true, pts := {}) -> void:
	var el := _el()
	S.mode = "reward"
	if picks <= 0:
		_next_floor()
		return
	if fresh:
		_rw_total = picks
		_rw_pts = pts
		if pts.get("gained", 0):
			_later(0.9, func(): if Ui.current == "scr-reward": Fx.toast("Pack earned! Open it from the title screen"))
	el.rwEyebrow.text = "Victory"
	el.rwTitle.text = "Choose a reward"
	var got: Array = _ribbon_chips(loot if loot != null else {}, ess, _rw_pts)
	_fill(el.rwSubLoot, got)
	el.rwSubLoot.visible = not got.is_empty()
	if fresh:
		Fx.reveal(got)
	UiKit.clear(el.rwPips)
	el.rwPips.add_child(UiKit.pick_pips(picks, _rw_total))
	el.rwPips.add_child(UiKit.lbl("%d pick%s" % [picks, "s" if picks > 1 else ""], "700", UiKit.T_S, UiKit.INK, {"valign": VERTICAL_ALIGNMENT_CENTER}))
	el.rwSub.text = "HP carries over. Knocked-out creatures stay down until a Spring or a Heal."
	var box: Control = el.rewards
	UiKit.clear(box)
	var next := func(): _show_reward(picks - 1, loot, ess, false)
	var opt := func(g: String, name: String, txt: String, color: Color, ok: bool, on_pick: Callable):
		var t := Tap.new()
		t.press_scale = 0.97
		t.dis_mod = Color(1, 1, 1, 0.45)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.custom_minimum_size.y = 168   # tall cards (the card face stretches to fill)
		var cv := CardView.new("reward").option(g, name, txt, color)
		# readable rules text: the body face at 12px (the card's own size is below the type scale)
		var tx = cv.get("tx")
		if tx is Label:
			tx.add_theme_font_override("font", UiKit.font("700"))
			tx.add_theme_font_size_override("font_size", UiKit.T_S)
			tx.add_theme_color_override("font_color", UiKit.INK2)
		t.add_child(cv)
		t.disabled = not ok
		t.pressed.connect(func():
			_click()
			on_pick.call())
		box.add_child(t)
		cv.pivot_offset = Vector2(0, 0)
		if fresh:
			Fx.kf(cv, 0.32, [[0.0, {"y": 60.0, "s": 0.6, "r": 8.0, "a": 0.0}], [1.0, {"y": 0.0, "s": 1.0, "r": 0.0, "a": 1.0}]],
				{"ease": [0.2, 1.4, 0.4, 1.0], "delay": 0.1 + (box.get_child_count() - 1) * 0.08})
	opt.call("up", "Upgrade", "One card: +30% effect or −1 cost", UiKit.GOLD, _upgradable(), func():
		_show_upgrade(next, func(): _show_reward(picks, loot, ess, false)))
	opt.call("heart", "Heal", "Whole party +%d%% HP, revives KOs" % roundi(Data.BAL.heal_reward * 100), UiKit.HP, true, func():
		for c in S.party:
			c.alive = true
			c.hp = minf(c.max_hp, c.hp + roundi(c.max_hp * Data.BAL.heal_reward))
		Sfx.heal()
		next.call())
	opt.call("jewel", "Scavenge", "+1 random Sword, Orb or Jewel", UiKit.NEUTRAL, true, func():
		var m: String = Meta.random_mat()
		_bank({m: 1})
		Sfx.caught()
		Fx.toast("+1 %s" % Data.MAT_DEF[m].name)
		next.call())
	_fill(el.rwDeck, [UiKit.wallet_row(Meta.wallet())])
	_on(el.skipBtn, func():
		Sfx.pick()
		next.call())
	Ui.show("scr-reward")

func _show_upgrade(on_done: Callable, on_back: Callable) -> void:
	var el := _el()
	var list: Control = el.upList
	UiKit.clear(list)
	UiKit.clear(el.upChoiceBox)
	el.upChoice.visible = false
	var cards_all: Array = []
	for c in S.party:
		var row := UiKit.vbox(8)
		var nm := UiKit.hbox(6)
		var col := UiKit.el_css(c.el)
		nm.add_child(UiKit.icon(c.el, 14, col))
		nm.add_child(UiKit.lbl(c.name, "display", 16, col))
		row.add_child(nm)
		var cards := UiKit.grid(3, 8)
		for slot in Data.SLOTS:
			var co: Dictionary = S.card_of(CardRef.new(c.uid, slot), c)   # as its owner plays it (§4.3)
			var up = c.ups.get(slot)
			var t := Tap.new()
			t.press_scale = 0.97
			t.dis_mod = Color(1, 1, 1, 0.45)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var faces := S.card_faces(CardRef.new(c.uid, slot)).map(func(m: Mon): return [m.key, m.el])
			var cv := CardView.new("mini").face(co.def, c.el, {"slot": slot, "base": S.base_card(c, slot).cost, "faces": faces, "pow": co.pow, "upgraded": up if up != null else ""})
			t.add_child(cv)
			t.disabled = up != null and up != ""
			cards_all.append(cv)
			t.pressed.connect(func():
				Sfx.pick()
				Platform.haptic("select")
				_pick_upgrade(c, slot, cv, cards_all, on_done))
			cards.add_child(t)
		var cm := MarginContainer.new()
		cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cm.add_theme_constant_override("margin_top", 6)
		cm.add_child(cards)
		row.add_child(cm)
		list.add_child(row)
	_on(el.upBack, func():
		Sfx.pick()
		on_back.call())
	Ui.show("scr-upgrade")

func _pick_upgrade(c: Mon, slot: String, cv: CardView, all: Array, on_done: Callable) -> void:
	var el := _el()
	for x in all:
		if x.sel:
			x.sel = false
			x.restyle()
	cv.sel = true
	cv.restyle()
	var def: Dictionary = S.card_of(CardRef.new(c.uid, slot), c).def
	var base: Dictionary = S.base_card(c, slot)
	var box: Control = el.upChoiceBox
	UiKit.clear(box)
	box.add_child(UiKit.eyebrow(def.name))
	var row := UiKit.hbox(8)
	var apply := func(u: String):
		c.ups[slot] = u
		Sfx.caught()
		Platform.haptic("success")
		Fx.toast("%s upgraded" % def.name)
		on_done.call()
	var p := UiScreens.big("+30% effect", true)
	p.disabled = not Data.scalable(base)
	p.pressed.connect(func(): apply.call("power"))
	var k := UiScreens.big("−1 cost", true)
	UiScreens.set_big(k, "−1 cost", "(%d → %d)" % [def.cost, maxi(0, def.cost - 1)])
	k.disabled = def.cost <= 0
	k.pressed.connect(func(): apply.call("cost"))
	row.add_child(p)
	row.add_child(k)
	box.add_child(row)
	el.upChoice.visible = true
	_scroll_to(el.upChoice)

## TS scrollIntoView({block:'nearest'}) inside the sheet.
func _scroll_to(c: Control) -> void:
	var p := c.get_parent()
	while p and not p is ScrollContainer:
		p = p.get_parent()
	if p:
		(func(): if is_instance_valid(c): p.ensure_control_visible(c)).call_deferred()

# ================= party / lineup =================
## Reorder the run's lineup: tap a creature (or ★) to make it the lead.
func show_party(on_done: Callable, sub := "Your three creatures fight together and their cards are your deck. Tap one to make it your lead.") -> void:
	var el := _el()
	S.mode = "reward"
	el.ptSub.text = sub
	_render_party()
	_on(el.ptDone, func():
		Sfx.pick()
		S.active = S.lineup[0]
		place_player(true)
		on_done.call())
	UiScreens.set_big(el.ptDone, "Done")
	el.ptDone.disabled = false
	Ui.show("scr-party")

func _render_party() -> void:
	var list: Control = _el().ptList
	UiKit.clear(list)
	for i in S.lineup.size():
		var uid: int = S.lineup[i]
		var c: Mon = S.mon(uid)
		if c == null:
			continue
		var lead := i == 0
		var col := UiKit.el_css(c.el)
		var to_lead := func():
			S.lineup.remove_at(S.lineup.find(c.uid))
			S.lineup.insert(0, c.uid)
			_render_party()
		# one row per creature in the lineup's Rows list; the lead is the selected row (gold outline)
		var main := Tap.new(UiKit.row_style(false), UiKit.row_style(true))
		main.on = lead
		var h := UiKit.hbox(12)
		main.add_child(h)
		h.add_child(UiKit.por(col, 40, c.el, lead))
		var v := UiKit.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var top := UiKit.hbox(8)
		var nm := UiKit.lbl(c.name + (" ✦" if c.shiny else ""), "display", UiKit.NAME, UiKit.INK, {"lh": -2})
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		var role = Data.SPECIES[c.key].get("role", "")
		var right: String = "★ Lead" if lead else (Data.TRAITS[c.trait_key].name if c.trait_key else role)
		top.add_child(UiKit.lbl(right, "700", UiKit.T_S, UiKit.GOLD_HI if lead else UiKit.INK2, {"valign": VERTICAL_ALIGNMENT_CENTER}))
		v.add_child(top)
		var hp := UiKit.hbox(8)
		hp.add_child(UiKit.meter(c.hp / float(c.max_hp), UiKit.HP if c.hp > 0 else UiKit.FOE))
		hp.add_child(UiKit.lbl("%d/%d" % [ceili(c.hp), c.max_hp], "500", UiKit.T_S, UiKit.INK2))
		v.add_child(hp)
		h.add_child(v)
		_btn(main, func(): if not lead: to_lead.call())
		list.add_child(main)

func quit_tap(t: Tap) -> void:
	Sfx.audio()
	if not (S.mode in ["map", "battle", "anim", "intro", "reward"]):
		return
	var now := Platform.ticks_msec()
	if t.has_meta("armed") and now - int(t.get_meta("armed")) < 2000:
		t.remove_meta("armed")
		t.modulate = Color.WHITE
		quit_run()
		return
	t.set_meta("armed", now)
	t.modulate = Color(1, 0.55, 0.6)
	if t.has_meta("lbl"):
		t.get_meta("lbl").text = "Sure?"
	Sfx.pick()
	Platform.haptic("warning")
	Fx.toast("Tap again to quit the run")
	get_tree().create_timer(2.0, true, false, true).timeout.connect(func():
		if is_instance_valid(t) and t.has_meta("armed") and Platform.ticks_msec() - int(t.get_meta("armed")) >= 1990:
			t.remove_meta("armed")
			t.modulate = Color.WHITE
			if t.has_meta("lbl"):
				t.get_meta("lbl").text = "Quit")

## End the run now as a loss. end_run bumps S.tok, so in-flight battle callbacks bail.
func quit_run() -> void:
	S.mode = "over"
	S.tok += 1
	end_run(false, true)

# ================= end of run =================
## `quit` = the player retreated with the quit button (a loss; banked loot stays).
func end_run(won: bool, quit := false) -> void:
	var el := _el()
	S.mode = "over"
	S.tok += 1
	if won:
		_bank({"gold": Data.BAL.win_gold})
	var secs := roundi((Platform.ticks_msec() - float(S.stats.start)) / 1000.0)
	var reached: int = Data.BAL.floors if won else S.floor
	Meta.record_run(won, reached)
	el.endH.text = "Expedition won" if won else ("Retreated" if quit else "Run over")
	el.endP.text = ("Noctyrm is sealed. Your party walks out of the wild (+%d gold)." % Data.BAL.win_gold) if won \
		else ("You left on floor %d. Your loot and pack points are safe." % S.floor) if quit \
		else ("Your party fell on floor %d. Your loot and pack points are safe." % S.floor)
	# floor, gold, Perfect Swaps and time as large pixel numbers
	UiKit.clear(el.endStats)
	for s in [[str(reached), "Floor"], [str(run_loot.get("gold", 0)), "Gold"], [str(S.stats.perfects), "Perfect swaps"],
			["%d:%02d" % [secs / 60, secs % 60], "Time"]]:
		var v := UiKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UiKit.disp(s[0], UiKit.D_M, UiKit.GOLD_HI if s[1] == "Gold" else UiKit.INK, {"align": "center"}))
		v.add_child(UiKit.lbl(s[1], "700", UiKit.T_S, UiKit.INK2, {"align": "center", "wrap": true, "lh": -4}))
		el.endStats.add_child(v)
	# the run's loot ribbon: everything banked this run, Essence included, popping in one by one
	var got := _ribbon_chips(run_loot, run_ess)
	if got.is_empty():
		got = [UiKit.lbl("Nothing this time", "500", UiKit.T_M, UiKit.INK2)]
	_fill(el.endLoot, got)
	Fx.reveal(got)
	_pack_meter_anim()
	UiKit.clear(el.endParty)
	for i in S.lineup.size():
		var c = S.mon(S.lineup[i])
		if c != null:
			el.endParty.add_child(UiKit.party_por(c, 40, i == 0))
	if won:
		Sfx.win()
		Platform.haptic("success")
		var vp: Vector2 = Ui.root.get_viewport_rect().size
		for k in 8:
			_later(k * 0.25, func():
				var x := randf_range(vp.x * 0.15, vp.x * 0.85)
				var y := randf_range(vp.y * 0.1, vp.y * 0.35)
				Particles.emit(x, y, {"n": 60, "color": [Color("#ffcf6b"), Color("#ff7a45"), Color("#3fb6ff"), Color("#5fd36a"), Color("#ffd23f"), Color("#f2d68c")], "spd": 5, "life": 1.6, "size": 0.2, "grav": 3, "drag": 1})
				Particles.emit(x, y, {"n": 10, "color": [Color("#ffcf6b"), Color("#ffffff")], "spd": 4, "life": 1.6, "size": 0.35, "grav": 2, "drag": 1, "tex": "star", "spin": 6})
				Particles.ring(x, y, Color("#ffcf6b"), 2.5, 0.6, false))
	else:
		Sfx.lose()
		Platform.haptic("error")
	if S.em != null and is_instance_valid(S.em):
		S.em.destroy()
	S.em = null
	var n: int = S.picks.size()
	UiScreens.set_big(el.againBtn, "Run again · %s%s" % [Data.SPECIES[S.picks[0]].name, (" +%d" % (n - 1)) if n > 1 else ""])
	Ui.show("scr-end")

## Back to the end-of-run screen (from the shop).
func _back_to_end() -> void:
	if S.title_actor != null and is_instance_valid(S.title_actor):
		S.title_actor.destroy()
	S.title_actor = null
	S.mode = "over"
	_el().endPackOpen.visible = run_packs > 0 and _packs_waiting() > 0
	Ui.show("scr-end")

# ---- the results screen's pack meter ----
var _pack_tw: Tween

func _to_go(pts: int) -> String:
	return "%d/%d · %d to go" % [pts, Data.BAL.pack_meter, Data.BAL.pack_meter - pts]

## Fill the meter from where it stood when the run began over this run's points, wrapping (with
## "Pack earned!", a heavy haptic and the Open button) each time it fills. Real time, like all UI motion.
func _pack_meter_anim() -> void:
	var el := _el()
	var meter := float(Data.BAL.pack_meter)
	var bar: Control = el.endPackBar
	var to_l: Label = el.endPackTo
	var open: Tap = el.endPackOpen
	if _pack_tw != null and _pack_tw.is_valid():
		_pack_tw.kill()
	open.visible = false
	el.endPackGain.text = ("+%d this run" % run_pts) if run_pts else "Win fights to fill it"
	to_l.text = _to_go(run_pts0)
	to_l.add_theme_color_override("font_color", UiKit.INK2)
	UiKit.set_fill(bar, run_pts0 / meter, run_pts0 / meter)
	_on(open, func():
		Sfx.pick()
		_open_next_pack(_back_to_end, false))
	if run_pts <= 0:
		return
	var tw := bar.create_tween()
	tw.set_ignore_time_scale(true)
	_pack_tw = tw
	tw.tween_interval(0.35)
	var per := clampf(0.8 / run_pts, 0.02, 0.06)   # seconds per point: the whole fill takes about 0.8s
	var cur := run_pts0
	var base := run_pts0
	var left := run_pts
	var earned := false
	while left > 0:
		var a := cur
		var b := mini(cur + left, Data.BAL.pack_meter)
		var f0 := base
		var after := earned
		tw.tween_method(func(v: float):
			UiKit.set_fill(bar, v / meter, f0 / meter)
			if not after:
				to_l.text = _to_go(int(v)), float(a), float(b), (b - a) * per)
		left -= b - a
		if b >= Data.BAL.pack_meter:
			earned = true
			tw.tween_callback(func():
				to_l.text = "Pack earned!"
				to_l.add_theme_color_override("font_color", UiKit.GOLD_HI)
				if Ui.current == "scr-end":   # left mid-fill (title, shop): no sound or haptic elsewhere
					Sfx.caught()
					Platform.haptic("heavy")
				to_l.pivot_offset = to_l.size / 2.0
				Fx.kf(to_l, 0.35, [[0.0, {"s": 1.0}], [0.5, {"s": 1.2}], [1.0, {"s": 1.0}]])
				open.visible = _packs_waiting() > 0)
			tw.tween_interval(0.15)
			cur = 0
			base = 0
		else:
			cur = b

# ================= title =================
## Home screen (idea 8): the lead alone on the stage; the team as a pill of portraits over the Start
## plaque (tap = the Team screen); Team, Daily pack, Collection and Item shop in the dock.
func _render_title() -> void:
	var el := _el()
	S.picks = _valid_picks()
	var own := Meta.owned()
	UiKit.clear(el.teamRow)
	for i in S.picks.size():
		var sp: Dictionary = Data.SPECIES[S.picks[i]]
		el.teamRow.add_child(UiKit.por(UiKit.el_css(sp.el), 30, sp.el, i == 0))
	el.pickEyebrow.text = "%s leads" % Data.SPECIES[S.picks[0]].name
	var best := Meta.best()
	var wins := Meta.wins()
	el.bestT.text = ("Won %d · best floor %d" % [wins, best]) if wins else (("Best run: floor %d" % best) if best else "Runs take about five minutes")
	UiScreens.set_dock_cell(el.dockTeam, "Team", "%d/%d" % [S.picks.size(), Data.BAL.lineup])
	var n := _packs_waiting()
	UiScreens.set_dock_cell(el.packBtn, ("Packs ×%d" % n) if n > 1 else ("Pack" if n else "Packs"),
		"Ready" if n else "%d/%d" % [Meta.pack_pts(), Data.BAL.pack_meter], n > 0, n == 0)
	el.packBtn.disabled = n == 0
	var sh := Meta.shinies().size()
	UiScreens.set_dock_cell(el.collBtn, "Collection", "%d/%d%s" % [own.size(), Data.ROSTER.size(), (" · %d ✦" % sh) if sh else ""])
	UiScreens.set_dock_cell(el.shopBtn, "Item shop", "%d gold" % Meta.wallet().gold)

# ---- team screen (§4.2) ----
## The lineup slot the next creature tap fills (0 = lead). Always visible as a pulsing ring.
var _team_cur := 0
## Lineup slot that just changed, popped after the re-render; -1 = none.
var _team_pop := -1

func show_team() -> void:
	S.mode = "title"
	S.picks = _valid_picks()
	_team_cur = _first_open_slot()
	_team_pop = -1
	_render_picks()
	Ui.show("scr-team")
	_show_title_actor(S.picks[mini(_team_cur, S.picks.size() - 1)])

## The first empty lineup slot, or the lead's when the team is full.
func _first_open_slot() -> int:
	return S.picks.size() if S.picks.size() < Data.BAL.lineup else 0

## Card-style ground for a team tile: the card's navy, an element rim; gold ring when `sel`.
func _tile_style(c: Color, sel: bool) -> StyleBoxFlat:
	if sel:
		return UiKit.glow_box(UiKit.flat(CardView.GROUND[0], 6, 2, UiKit.GOLD_HI), UiKit.alpha(UiKit.GOLD_HI, 0.25), 6)
	return UiKit.flat(CardView.GROUND[1], 6, 1.5, c.lerp(Color.BLACK, 0.3))

## Slot number tab, shared by a lineup slot and its creature in the grid: "1 ★" (lead), "2", "3".
func _slot_badge(i: int) -> Control:
	var p := UiKit.panel(UiKit.flat(UiKit.NAVY2, 3, 1, UiKit.GOLD_HI if i == 0 else UiKit.INK2, Vector4(4, 0, 4, 0)))
	var h := UiKit.hbox(2)
	h.add_child(UiKit.lbl(str(i + 1), "700", UiKit.T_S, UiKit.INK, {"align": "center"}))
	if i == 0:
		h.add_child(UiKit.lbl("★", "700", UiKit.T_S, UiKit.GOLD_HI))
	p.add_child(h)
	return p

## Border-only ring that pulses (real time) over the slot the next tap fills.
func _pulse_ring(c: Color, radius: float) -> Control:
	var r := Panel.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiKit.glow_box(UiKit.flat(Color(0, 0, 0, 0), radius, 2.5, c), UiKit.alpha(c, 0.6), 8)
	sb.draw_center = false
	r.add_theme_stylebox_override("panel", sb)
	Fx.kf(r, 0.55, [[0.0, {"a": 0.35}], [1.0, {"a": 1.0}]], {"loop": "alternate"})
	return Box.fill(r)

## Quick pop on whatever just changed (UI motion: Fx.kf runs in real time).
func _team_pop_fx(n: Control) -> void:
	if n is Tap:   # Tap keeps its pivot centred
		Fx.kf(n, 0.3, [[0.0, {"s": 0.86}], [0.45, {"s": 1.08}], [1.0, {"s": 1.0}]])

## The deck's element mix beside the title: an element chip per element ("×2").
func _render_team_mix() -> void:
	var el := _el()
	UiKit.clear(el.teamMix)
	var n := {}
	for k in S.picks:
		var e: String = Data.SPECIES[k].el
		n[e] = n.get(e, 0) + 1
	for e in Data.EL_KEYS:
		if n.has(e):
			el.teamMix.add_child(UiKit.ess(e, UiKit.el_css(e), "×%d" % n[e]))

## Put `k` into lineup slot `i` (the cursor). A creature already in the team trades places with
## whoever is there, so nobody leaves; an outsider replaces the slot's creature (or fills the empty
## slot). The cursor then moves to the next empty slot, if any.
func _team_place(k: String, i: int) -> void:
	var j: int = S.picks.find(k)
	if i >= S.picks.size():   # an empty slot (they're always at the end): add it, or move it last
		if j >= 0:
			S.picks.remove_at(j)
		S.picks.append(k)
		i = S.picks.size() - 1
	elif j >= 0:
		S.picks[j] = S.picks[i]
		S.picks[i] = k
	else:
		S.picks[i] = k
	_team_cur = i if S.picks.size() >= Data.BAL.lineup else S.picks.size()
	_team_saved(i, k)

func _team_saved(pop: int, show_k: String) -> void:
	Meta.save_lineup(S.picks)
	_team_pop = pop
	_render_picks()
	_show_title_actor(show_k)

## Team screen: three lineup slots over a grid of owned creatures, all as card-style face tiles.
## One slot is always the cursor (pulsing ring): tapping a creature puts it there; tapping a slot
## moves the cursor; × empties a slot (one creature always stays). Slot 1 leads. Saved on every change.
func _render_picks() -> void:
	var el := _el()
	var own := Meta.owned()
	S.picks = _valid_picks()
	var n: int = Data.BAL.lineup
	_team_cur = clampi(_team_cur, 0, mini(S.picks.size(), n - 1))
	var slots := {}
	UiKit.clear(el.teamOrder)
	for i in n:
		var k: String = S.picks[i] if i < S.picks.size() else ""
		var cur := i == _team_cur
		var t := Tap.new(_tile_style(UiKit.el_css(Data.SPECIES[k].el) if k != "" else UiKit.HAIR, false) if k != ""
			else UiKit.flat(Color(0, 0, 0, 0.18), 6, 1, UiKit.HAIR))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Box.new()
		var v := UiKit.vbox(3)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		if k != "":
			var sp: Dictionary = Data.SPECIES[k]
			v.add_child(UiKit.face_win(k, sp.el, Vector2(88, 60)))
			v.add_child(UiKit.lbl(sp.name + (" ✦" if Meta.is_shiny(k) else ""), "display", UiKit.T_M, UiKit.INK, {"align": "center", "lh": -2}))
		else:
			var hole := Box.new(Vector2(88, 60))
			hole.add_child(UiKit.icon("plus", 22, UiKit.INK2))
			v.add_child(hole)
			v.add_child(UiKit.lbl("Empty", "display", UiKit.T_M, UiKit.INK2, {"align": "center", "lh": -2}))
		var status := "Lead" if i == 0 else "Bench"
		if cur:
			status = "Choosing"
		v.add_child(UiKit.lbl(status, "700", UiKit.T_S, Color.WHITE if cur else (UiKit.GOLD_HI if i == 0 else UiKit.INK2), {"align": "center"}))
		var m := MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 6)
		m.add_child(v)
		b.add_child(Box.fill(m))
		if cur:
			b.add_child(_pulse_ring(Color.WHITE, 6))
		b.add_child(Box.at(_slot_badge(i), "tl", Vector2(3, 3)))
		if k != "" and S.picks.size() > 1:
			var x := Tap.new(UiKit.flat(UiKit.alpha(UiKit.NAVY2, 0.85), 11, 1, UiKit.INK2))
			x.custom_minimum_size = Vector2(22, 22)
			x.add_child(UiKit.icon("close", 12, UiKit.INK))
			_btn(x, func():
				S.picks.remove_at(i)
				_team_cur = S.picks.size()
				_team_saved(-1, S.picks[0]))
			b.add_child(Box.at(x, "tr", Vector2(3, 3)))
		t.add_child(b)
		_btn(t, func():
			_team_cur = mini(i, S.picks.size())
			_team_saved(_team_cur, S.picks[mini(_team_cur, S.picks.size() - 1)]))
		el.teamOrder.add_child(t)
		slots[i] = t
	UiKit.clear(el.starters)
	for k in Data.ROSTER:
		if not (k in own):
			continue
		var sp: Dictionary = Data.SPECIES[k]
		var i: int = S.picks.find(k)
		var t := Tap.new(_tile_style(UiKit.el_css(sp.el), i >= 0))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Box.new()
		var v := UiKit.vbox(3)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(UiKit.face_win(k, sp.el, Vector2(58, 50)))
		v.add_child(UiKit.lbl(sp.name + (" ✦" if Meta.is_shiny(k) else ""), "display", UiKit.T_S, UiKit.INK, {"align": "center", "lh": -2}))
		var m := MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 5)
		m.add_child(v)
		b.add_child(Box.fill(m))
		if i >= 0:
			b.add_child(Box.at(_slot_badge(i), "tl", Vector2(2, 2)))
		t.add_child(b)
		_btn(t, func(): _team_place(k, _team_cur))
		el.starters.add_child(t)
	_render_team_mix()
	if _team_cur >= S.picks.size():
		el.teamHint.text = "Tap a creature to add it to slot %d, or tap a slot to change it." % (_team_cur + 1)
	else:
		var was: String = Data.SPECIES[S.picks[_team_cur]].name
		el.teamHint.text = ("Tap a creature to lead instead of %s. Tap a slot to choose another." % was) if _team_cur == 0 \
			else "Tap a creature for slot %d instead of %s. Tap a slot to choose another." % [_team_cur + 1, was]
	if _team_pop >= 0:
		_team_pop_fx(slots.get(_team_pop))
	_team_pop = -1

func _show_title_actor(key: String, silhouette := false) -> void:
	if S.title_actor != null and is_instance_valid(S.title_actor):
		S.title_actor.destroy()
	var a = S.make_actor(key)
	a.extra = 1.15
	S.title_actor = a
	var shiny := not silhouette and Meta.is_shiny(key)
	a.set_shiny(shiny)
	a.set_silhouette(silhouette)
	a.squash = Vector2(0.01, 0.01)
	a.create_tween().tween_property(a, "squash", Vector2.ONE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var t: Vector2 = Layout.tpos()
	if silhouette:
		Stage.tint_arena(Color("#5a6088"))
		return
	var U: float = Layout.U
	Particles.emit(t.x, t.y - U * 0.6, {"n": 90, "color": Data.ELEM[a.el].glow, "spd": 3.5, "up": 1.3, "life": 1.1, "size": 0.26, "grav": 2, "drag": 1.2})
	Particles.emit(t.x, t.y - U * 0.6, {"n": 12, "color": [Color.WHITE, Data.ELEM[a.el].hex], "spd": 3, "up": 1, "life": 1, "size": 0.35, "grav": 1, "drag": 1.2, "tex": "star", "spin": 5})
	if shiny:
		_sparkle(t.x, t.y - U * 1.2)
	Particles.ring(t.x, t.y, Data.ELEM[a.el].hex, 2.6, 0.7)
	Stage.tint_arena(Data.ELEM[a.el].hex)

func to_title() -> void:
	S.tok += 1
	S.mode = "title"
	S.clear_actors()
	Stage.set_biome(0)
	_render_title()
	Ui.show("scr-title")
	Ui.measure(true)
	_show_title_actor(S.picks[0])

# ================= packs (§11) =================
## Packs the player can open now: a pending pick, today's free pack and the banked tokens.
func _packs_waiting() -> int:
	return Meta.packs_ready() + (1 if Meta.pack_pending().size() else 0)

## Open the next pack: a pick left pending first, else today's free pack, else a banked token.
## `join` = a new creature joins the title-screen team if there's room (not from the results screen,
## so "Run again" keeps its team).
func _open_next_pack(back: Callable, join: bool) -> void:
	var src := Meta.pending_source()
	if src == "":
		src = "daily" if Meta.pack_ready() else ("token" if Meta.pack_tokens() > 0 else "")
	var ch: Array = Meta.open_pack(src) if src != "" else []
	if ch.is_empty():
		back.call()
		return
	_show_pack(ch, Meta.pending_source(), back, join)

const PACK_TITLES := {
	"daily": ["Daily pack", "Pick one to keep. A new pack every day."],
	"token": ["Pack earned", "Your expeditions filled the meter. Pick one to keep."],
	"shop": ["Creature pack", "Fresh from the shop. Pick one to keep."],
}

## The open pack: {cards: [Tap], keys: [String], open: [bool], picked: String, join: bool}.
var _pk := {}

## Pick 1 of 3: the rolled creatures turn face up one after another; tapping one keeps it (the
## others fade) and the line under them says what it gave. Leaving needs a pick (the roll is saved).
func _show_pack(choices: Array, source: String, back: Callable, join := false) -> void:
	var el := _el()
	S.mode = "meta"
	if S.title_actor != null and is_instance_valid(S.title_actor):
		S.title_actor.destroy()
	S.title_actor = null
	_pack_n += 1
	var n := _pack_n
	var tt: Array = PACK_TITLES.get(source, PACK_TITLES.daily)
	el.packH1.text = tt[0]
	el.packP.text = tt[1]
	UiKit.clear(el.packChoices)
	_pk = {"cards": [], "keys": choices.duplicate(), "open": [], "picked": "", "join": join}
	for i in choices.size():
		var t := UiScreens.flip_card()
		_pack_face(t, choices[i])
		UiScreens.flip_open(t, false)
		t.pressed.connect(_pack_tap.bind(i))
		el.packChoices.add_child(t)
		_pk.cards.append(t)
		_pk.open.append(false)
		_later(0.3 + i * 0.22, func(): if n == _pack_n and Ui.current == "scr-pack": _pack_reveal(i, true))
	_fill(el.packTxt, [UiKit.sub("Tap a creature to keep it.", "center")])
	UiScreens.set_big(el.packOk, "Pick one")
	el.packOk.disabled = true
	_on(el.packOk, func():
		if _pk.picked == "":
			return
		Sfx.pick()
		back.call())
	Ui.show("scr-pack")
	Ui.measure(true)

## A choice's face: the creature's face, its name, NEW or the copy it would become, and what that
## copy would give (its role for a new creature, the card or shiny it unlocks, or gold when complete).
func _pack_face(t: Tap, k: String) -> void:
	var sp: Dictionary = Data.SPECIES[k]
	var col := UiKit.el_css(sp.el)
	UiScreens.flip_tint(t, col)
	var fv: VBoxContainer = t.get_meta("fv")
	UiKit.clear(fv)
	var por := UiKit.face_por(k, sp.el, 52)
	por.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	fv.add_child(por)
	fv.add_child(UiKit.lbl(sp.name, "display", UiKit.NAME, UiKit.INK, {"align": "center", "lh": -2}))
	var c := Meta.copies(k)
	var mx := Data.max_copies()
	var tag := "NEW" if c == 0 else ("Complete" if c >= mx else "Copy %d/%d" % [c + 1, mx])
	fv.add_child(UiKit.lbl(tag, "700", UiKit.T_S, UiKit.GOLD_HI if c == 0 else UiKit.mix(col, UiKit.INK, 0.55), {"align": "center"}))
	var what := ""
	var now := false
	if c == 0:
		what = str(sp.get("role", ""))
	elif c >= mx:
		what = "+%d gold" % Data.BAL.dupe_gold
		now = true
	else:
		var nt = Meta.next_tier(k)
		if nt != null:
			now = nt.n == c + 1
			if nt.get("shiny", false):
				what = "Turns shiny" if now else "Shiny at %d" % nt.n
			else:
				what = ("Unlocks " + _tier_name(k, nt)) if now else "%s at %d" % [_tier_name(k, nt), nt.n]
	var w := UiKit.lbl(what, "700" if now else "500", UiKit.T_S, UiKit.GOLD_HI if now else UiKit.INK2, {"align": "center", "wrap": true, "lh": -3})
	w.custom_minimum_size.y = 30   # two lines, so the three cards line up
	fv.add_child(w)

## What a COPY_TIERS entry unlocks for species k: the card's name, or "Shiny".
func _tier_name(k: String, t) -> String:
	if t == null:
		return ""
	if t.get("shiny", false):
		return "Shiny"
	return Data.SPECIES[k].cards[t.slot][t.i].name

func _pack_reveal(i: int, animate: bool) -> void:
	if _pk.is_empty() or i >= _pk.open.size() or _pk.open[i]:
		return
	_pk.open[i] = true
	UiScreens.flip_open(_pk.cards[i], true, animate)
	Sfx.caught()
	Platform.haptic("heavy")

## A tap on a face-down card turns them all over (no blind picks); on a face-up one it keeps it.
func _pack_tap(i: int) -> void:
	if _pk.is_empty() or _pk.picked != "":
		return
	if not _pk.open[i]:
		for j in _pk.cards.size():
			_pack_reveal(j, true)
		return
	_pack_keep(i)

func _pack_keep(i: int) -> void:
	var el := _el()
	var k: String = _pk.keys[i]
	var res := Meta.pick_pack(k)
	if res.is_empty():
		return
	_pk.picked = k
	Sfx.audio()
	Sfx.caught()
	Platform.haptic("select")
	var sp: Dictionary = Data.SPECIES[k]
	for j in _pk.cards.size():
		var t: Tap = _pk.cards[j]
		t.dis_mod = Color.WHITE
		t.disabled = true
		var card: Control = t.get_meta("card")
		if j == i:
			UiScreens.flip_tint(t, UiKit.el_css(sp.el), true)
			Fx.kf(card, 0.4, [[0.0, {"s": 1.0}], [0.45, {"s": 1.07}], [1.0, {"s": 1.0}]], {"ease": [0.3, 1.4, 0.5, 1.0]})
		else:
			Fx.kf(card, 0.3, [[0.0, {"a": 1.0}], [1.0, {"a": 0.3}]])
	var joined := false
	if _pk.join and res.fresh and not (k in S.picks) and S.picks.size() < Data.BAL.lineup:
		S.picks.append(k)
		Meta.save_lineup(S.picks)   # the team is saved on every change (§4.2)
		joined = true
	_show_title_actor(k)
	_fill(el.packTxt, [UiKit.sub(_pack_result(res, joined), "center")])
	UiScreens.set_big(el.packOk, "Nice!")
	el.packOk.disabled = false

## The line under the cards after a pick.
func _pack_result(res: Dictionary, joined: bool) -> String:
	var k: String = res.key
	var nm: String = Data.SPECIES[k].name
	if res.fresh:
		return "%s joins your collection%s." % [nm, " and your team" if joined else ""]
	if res.gold:
		return "%s is fully collected: +%d gold." % [nm, res.gold]
	if res.shiny:
		return "%s is now shiny! It sparkles in every run." % nm
	for t in res.unlocked:
		if not t.get("shiny", false):
			return "Copy %d of %s: %s unlocked and equipped." % [res.copies, nm, _tier_name(k, t)]
	var nt = Meta.next_tier(k)
	if nt == null:
		return "Copy %d of %s." % [res.copies, nm]
	return "Copy %d of %s. Next: %s at %d copies." % [res.copies, nm, _tier_name(k, nt), nt.n]

# ================= item shop (§5.3) =================
func _show_shop(back: Callable) -> void:
	var el := _el()
	S.mode = "meta"
	var w := Meta.wallet()
	var again := func(): _show_shop(back)
	_fill(el.shopWallet, _loot_chips(w))
	var buy: Control = el.shopBuy
	var sell: Control = el.shopSell
	UiKit.clear(buy)
	UiKit.clear(sell)
	# one row per trade; the price sits on the right. A trade you can't make keeps its text at full
	# strength and says why under the price, instead of dimming the row.
	var add := func(box: Control, g: String, t: String, sub: String, c: Color, price: String, why: String, fn: Callable):
		var pv := UiKit.vbox(0)
		var ph := UiKit.hbox(4, BoxContainer.ALIGNMENT_END)
		ph.add_child(UiKit.icon("coin", 13, UiKit.GOLD_HI))
		ph.add_child(UiKit.disp(price, UiKit.NAME, UiKit.GOLD_HI if why == "" else UiKit.INK))
		pv.add_child(ph)
		if why != "":
			pv.add_child(UiKit.lbl(why, "700", UiKit.T_S, UiKit.INK2, {"align": "right"}))
		var b := _node_btn(g, t, sub, c, fn, false, pv)
		b.disabled = why != ""
		b.dis_mod = Color.WHITE
		box.add_child(b)
	var short := func(n: int) -> String: return "Need %d more" % n
	var paid := func():
		Sfx.caught()
		Platform.haptic("success")
		again.call()
	for m in Data.MATS:
		var d: Dictionary = Data.MAT_DEF[m]
		add.call(buy, m, d.name, "%s upgrades · you have %d" % [d.track, w[m]], MAT_COL[m], str(Data.BAL.shop_mat),
			"" if w.gold >= Data.BAL.shop_mat else short.call(Data.BAL.shop_mat - w.gold), func(): if Meta.buy_mat(m): paid.call())
	var waiting := Meta.pack_pending().size() > 0   # a pack already rolled: tapping opens it, free
	add.call(buy, "pack", "Creature pack", "A pack is waiting: open it first" if waiting else "Pick 1 of 3 creatures",
		UiKit.GOLD_HI, str(Data.BAL.shop_pack), "" if waiting or w.gold >= Data.BAL.shop_pack else short.call(Data.BAL.shop_pack - w.gold),
		func():
			var r: Array = Meta.buy_pack()
			if r.size():
				_show_pack(r, Meta.pending_source(), again))
	for m in Data.MATS:
		var d: Dictionary = Data.MAT_DEF[m]
		add.call(sell, m, "Sell a %s" % d.name, "You have %d" % w[m], MAT_COL[m], "+%d" % Data.BAL.shop_sell,
			"" if w[m] > 0 else "None to sell", func(): if Meta.sell_mat(m): paid.call())
	_on(el.shopBack, func():
		Sfx.pick()
		back.call())
	Ui.show("scr-shop")
	Ui.measure(true)

# ================= collection & loadouts (§11, §16) =================
var _coll := {"cur": "", "pending": null, "tab": "cards"}
const COLL_TABS := ["cards", "trait", "upgrades"]

## The Collection (idea 9, a bestiary): the selected creature in the specimen window, a six-wide
## portrait grid (silhouettes for creatures not found yet), and the detail panel with three tabs:
## Cards (the loadout editor, §16.1), Trait (§16.2) and Upgrades (§5.2). `tab` opens on that tab.
func _show_collection(tab := "cards") -> void:
	var el := _el()
	S.mode = "meta"
	var own := Meta.owned()
	el.collCount.text = "%d of %d found" % [own.size(), Data.ROSTER.size()]
	_coll = {"cur": "", "pending": null, "tab": tab}
	Ui.show("scr-coll")
	Ui.measure(true)
	_coll_detail(S.picks[0] if S.picks[0] in own else own[0])

func _coll_detail(k: String) -> void:
	_coll.cur = k
	_coll.pending = null
	_show_title_actor(k, not Meta.is_owned(k))
	_fit_specimen(S.title_actor)
	_coll_grid()
	_coll_render()

## Scale the Collection's creature to fill its specimen window: once Layout has placed it, grow it until
## its head nears the top of the frame (it never leaves the stage band, so the art rule holds).
func _fit_specimen(a) -> void:
	var tok := S.tok
	for i in 4:   # Ui.measure settles the band over 2 frames, then the main loop places the actor
		await get_tree().process_frame
	if tok != S.tok or a == null or not is_instance_valid(a) or a != S.title_actor or Ui.current != "scr-coll":
		return
	var spec: Control = _el().collSpec
	var r: Rect2 = a.screen_rect()
	if not spec.visible or r.size.y < 1.0:
		return
	var room: float = Layout.tpos().y - spec.position.y - 14.0   # head clear of the frame's border and studs
	var wide := spec.size.x * 0.8
	a.extra *= clampf(minf(room / r.size.y, wide / maxf(r.size.x, 1.0)), 0.5, 2.4)

## The portrait grid: element orbs for owned creatures, dim "?" silhouettes for the rest, the selected
## one ringed in gold. Names live only in the detail panel.
func _coll_grid() -> void:
	var grid: Control = _el().collGrid
	UiKit.clear(grid)
	var own := Meta.owned()
	for k in Data.ROSTER:
		var sp: Dictionary = Data.SPECIES[k]
		var has: bool = k in own
		var sel: bool = k == _coll.cur
		var t := Tap.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b: Box
		if has:
			b = UiKit.por(UiKit.el_css(sp.el), 44, sp.el, sel)
			if Meta.is_shiny(k):
				b.add_child(Box.at(UiKit.lbl("✦", "700", UiKit.T_S, UiKit.GOLD_HI), "tr", Vector2(1, 0)))
		else:
			b = UiKit.por(Color("#3a3f55"), 44, "", sel)
			b.add_child(UiKit.disp("?", 22, Color("#8a90a8")))
			if not sel:
				t.modulate.a = 0.6
		t.add_child(b)
		_btn(t, _coll_detail.bind(k))
		grid.add_child(t)

func _unlock_box(what_bb: String, c: Dictionary, on_unlock: Callable) -> Control:
	var have: int = Meta.essence().get(c.el, 0)
	var box := UiKit.panel(UiKit.inset(Vector4(12, 10, 12, 12), true))
	var v := UiKit.vbox(8)
	box.add_child(v)
	v.add_child(UiKit.rich(what_bb, UiKit.T_M, UiKit.INK2))
	var b := UiScreens.big("Unlock", true)
	if have < c.n:
		UiScreens.set_big(b, "Unlock", "· need %d more %s" % [c.n - have, Data.ELEM[c.el].name])
	else:
		UiScreens.set_big(b, "Unlock", "· %d %s Essence" % [c.n, Data.ELEM[c.el].name])
	b.disabled = have < c.n
	b.pressed.connect(func():
		if not on_unlock.call():
			return
		Sfx.caught()
		Platform.haptic("success")
		_coll.pending = null
		_coll_render())
	v.add_child(b)
	box.set_meta("upchoice", true)
	return box

func _sec(title: String) -> VBoxContainer:
	var s := UiKit.vbox(4)
	s.add_child(UiKit.eyebrow(title))
	return s

func _coll_render() -> void:
	var el := _el()
	var k: String = _coll.cur
	var sp: Dictionary = Data.SPECIES[k]
	var has := Meta.is_owned(k)
	var lo := Meta.loadout(k)
	var bo := Meta.boosts(k)
	var col := UiKit.el_css(sp.el)
	# the header shows the currency the open tab spends: gold and materials for Upgrades, Essence for
	# Traits; the Cards tab spends nothing (cards unlock from copies), so it shows the copies
	if has and _coll.tab == "upgrades":
		_fill(el.collEss, _loot_chips(Meta.wallet()))
	elif _coll.tab == "trait":
		_fill(el.collEss, _ess_chips(Meta.essence()))
	else:
		_fill(el.collEss, [UiKit.ess("pack", UiKit.GOLD_HI, "%d/%d copies" % [Meta.copies(k), Data.max_copies()])] if has else [])
	# specimen window caption: element, role, HP (on a solid chip, it sits over the scene)
	var chip := UiKit.chip(sp.el, col, "%s · %s · %d HP" % [Data.ELEM[sp.el].name, sp.get("role", ""), roundi(sp.hp * bo.vital) if has else sp.hp])
	chip.add_theme_stylebox_override("panel", UiKit.flat(UiKit.alpha(UiKit.NAVY2, 0.88), 11, 1, UiKit.alpha(col, 0.7), Vector4(8, 3, 8, 3)))
	_fill(el.collSpecChip, [chip])
	var d: Control = el.collDetail
	UiKit.clear(d)
	# name row: the name, and the Trait it carries
	var nrow := UiKit.hbox(8)
	var nm := UiKit.disp(sp.name + (" ✦" if Meta.is_shiny(k) else ""), UiKit.D_S, UiKit.INK, {"ellipsis": true})
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(nm)
	var t_on = lo["trait"] if has else sp.get("trait")
	if t_on:
		var tl := UiKit.eyebrow("Trait: " + Data.TRAITS[t_on].name)
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nrow.add_child(tl)
	d.add_child(nrow)
	var ti := COLL_TABS.find(_coll.tab)
	d.add_child(UiKit.tabs(["Cards", "Trait", "Upgrades"], ti, func(i: int):
		Sfx.audio()
		Sfx.pick()
		Platform.haptic("select")
		_coll.tab = COLL_TABS[i]
		_coll.pending = null
		_coll_render()))
	# the tab body has one fixed height (scrolling inside), so switching tabs never moves the stage
	var body := UiKit.vbox(10)
	body.custom_minimum_size.y = _coll_body_h()
	if not has:
		_coll_unknown(body, k)
	else:
		match _coll.tab:
			"trait": _coll_trait(body, k)
			"upgrades": _coll_upgrades(body, k)
			_: _coll_cards(body, k)
	d.add_child(CapScroll.new(body, 0.0, -_coll_body_h()))
	for x in d.find_children("*", "PanelContainer", true, false):
		if x.has_meta("upchoice"):
			_scroll_to(x)
			break

## Tab body for a creature not found yet: its default cards, its built-in Trait, how to find it.
func _coll_unknown(body: Control, k: String) -> void:
	var sp: Dictionary = Data.SPECIES[k]
	var find := "Not found yet. Open packs: one a day, one per full pack meter, or buy one in the item shop."
	match _coll.tab:
		"trait":
			var x = sp.get("trait")
			var tp := UiKit.panel(UiKit.inset())
			var tv := UiKit.vbox(4)
			tv.add_child(UiKit.lbl(Data.TRAITS[x].name, "display", UiKit.NAME, UiKit.INK, {"lh": -2}))
			tv.add_child(UiKit.lbl(Data.TRAITS[x].text, "500", UiKit.T_M, UiKit.INK2, {"wrap": true, "lh": -2}))
			tp.add_child(tv)
			body.add_child(tp)
			body.add_child(UiKit.note("Its built-in Trait. " + find))
		"upgrades":
			body.add_child(UiKit.sub(find))
		_:
			body.add_child(UiKit.note(find))
			var cards := UiKit.hbox(8)
			for slot in Data.SLOTS:
				var cv := CardView.new("coll").face(sp.cards[slot][0], sp.el, {"slot": slot})   # not found yet: a glyph, no face
				cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				cards.add_child(cv)
			body.add_child(cards)

## Height of the Collection's tab body: about a quarter of the screen.
func _coll_body_h() -> float:
	return clampf(roundf(Layout.size.y * 0.25), 192.0, 212.0)

## Cards tab: the copies line (how many, what the next copy unlocks), then a column per slot (Strike,
## Skill, Signature) with the default card over its alternates. The equipped card is lit; tapping an
## unlocked one equips it. A locked one says how many copies it needs (copies come from packs).
func _coll_cards(body: Control, k: String) -> void:
	var sp: Dictionary = Data.SPECIES[k]
	var lo := Meta.loadout(k)
	var bo := Meta.boosts(k)
	var c := Meta.copies(k)
	var mx := Data.max_copies()
	var cl := UiKit.hbox(8)
	var ce := UiKit.eyebrow("Copies %d/%d" % [c, mx])
	ce.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cl.add_child(ce)
	var pp := UiKit.pips(c, mx, UiKit.GOLD_HI, 8.0, 6.0, 3.0)
	pp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cl.add_child(pp)
	body.add_child(cl)
	var nt = Meta.next_tier(k)
	var nxt := "Fully collected. More copies turn into %d gold." % Data.BAL.dupe_gold
	if nt != null:
		nxt = ("Shiny at %d copies." % nt.n) if nt.get("shiny", false) \
			else ("Next: %s (%s) at %d copies." % [_tier_name(k, nt), "Skill" if nt.slot == "skill" else "Signature", nt.n])
	body.add_child(UiKit.note(nxt + " Copies come from packs."))
	var cols := UiKit.hbox(8)
	for slot in Data.SLOTS:
		var cv_col := UiKit.vbox(6)
		cv_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv_col.add_child(UiKit.eyebrow("Strike" if slot == "strike" else ("Skill" if slot == "skill" else "Signature")))
		var list: Array = sp.cards[slot]
		for i in list.size():
			var def: Dictionary = list[i]
			var on: bool = slot == "strike" or lo.get(slot, 0) == i
			var open := Meta.move_unlocked(k, slot, i)
			var need := Data.copies_for(slot, i)
			var t := Tap.new()
			t.press_scale = 0.97
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cv := CardView.new("lo").face(Data.boost_card(def, bo.power, bo.spirit), sp.el, {"slot": slot, "faces": [[k, sp.el]]})
			cv.pressed_state = 1 if on else -1
			if not open:   # the strip's lock tag: copies, not Essence (long and short forms)
				cv._tags.push_front(["Needs %d copies" % need, "%d copies" % need, "lock"])
				cv._build_tags()
			cv.restyle()
			t.add_child(cv)
			t.pressed.connect(func():
				if slot == "strike" or on:
					return
				Sfx.audio()
				Sfx.pick()
				Platform.haptic("select")
				if open:
					Meta.set_move(k, slot, i)
					_coll_render()
				else:
					Fx.toast("%s needs %d copies of %s" % [def.name, need, sp.name]))
			cv_col.add_child(t)
		if list.size() < 2:
			cv_col.add_child(UiKit.lbl("One option", "500", UiKit.T_S, UiKit.MUTE, {"align": "center"}))
		cols.add_child(cv_col)
	body.add_child(cols)

## Trait tab: the socketed Trait, then every usable Trait (built-in first) and the learnable ones with
## their Essence cost. Tapping a usable one sockets it; a learnable one opens the Learn offer.
func _coll_trait(body: Control, k: String) -> void:
	var sp: Dictionary = Data.SPECIES[k]
	var own := Meta.owned()
	var lo := Meta.loadout(k)
	var pending = _coll.pending
	var t_on = lo["trait"]
	if t_on:
		var tc := UiKit.el_css(Data.SPECIES[Data.TRAITS[t_on]["from"]].el)
		var tp := UiKit.panel(UiKit.inset())
		var tv := UiKit.vbox(4)
		var th := UiKit.hbox(6)
		th.add_child(UiKit.icon(Data.SPECIES[Data.TRAITS[t_on]["from"]].el, 14, tc))
		th.add_child(UiKit.lbl(Data.TRAITS[t_on].name, "display", UiKit.NAME, UiKit.INK, {"lh": -2}))
		tv.add_child(th)
		tv.add_child(UiKit.lbl(Data.TRAITS[t_on].text, "500", UiKit.T_M, UiKit.INK2, {"wrap": true, "lh": -2}))
		tp.add_child(tv)
		body.add_child(tp)
	var opts := UiKit.grid(3, 6)
	var keys: Array = Data.TRAITS.keys()
	var builtin = sp.get("trait")
	var usable: Array = keys.filter(func(x): return Meta.trait_usable(k, x))
	usable.sort_custom(func(a, b): return a == builtin and b != builtin)
	var learnable: Array = keys.filter(func(x): return not Meta.trait_usable(k, x) and not Meta.trait_unlocked(x) and Data.TRAITS[x]["from"] in own)
	for x in usable + learnable:
		var def: Dictionary = Data.TRAITS[x]
		var open: bool = x in usable
		var holder = Meta.trait_holder(x)
		var c := UiKit.el_css(Data.SPECIES[def["from"]].el)
		var st := UiKit.flat(Color(0, 0, 0, 0.18), 4, 1, UiKit.HAIR, Vector4(4, 7, 4, 7))
		if x == t_on:   # socketed: selected
			st = UiKit.row_style(true, Vector4(4, 7, 4, 7))
		if pending != null and pending.has("trait") and pending["trait"] == x:   # the offer below is for this one
			st = UiKit.flat(UiKit.alpha(c, 0.10), 4, 1.5, c, Vector4(4, 7, 4, 7))
		var b := Tap.new(st)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UiKit.vbox(3)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(UiKit.lbl(def.name, "700", 13, UiKit.mix(c, UiKit.INK, 0.45), {"align": "center", "lh": -4}))
		if not open:
			var cost := _cost(Meta.trait_cost(x), c)
			cost.alignment = BoxContainer.ALIGNMENT_CENTER
			v.add_child(cost)
		else:
			var tag: String = "Built-in" if x == builtin else (("moves from " + Data.SPECIES[holder].name) if (holder != null and holder != k and x != t_on) else ("from " + Data.SPECIES[def["from"]].name))
			v.add_child(UiKit.lbl(tag, "500", UiKit.T_S, UiKit.INK2, {"align": "center", "ellipsis": true}))
		b.add_child(v)
		b.pressed.connect(func():
			if x == t_on:
				return
			Sfx.audio()
			Sfx.pick()
			Platform.haptic("select")
			if open:
				Meta.set_trait(k, x)
				_coll.pending = null
			else:
				_coll.pending = {"trait": x}
			_coll_render())
		opts.add_child(b)
	body.add_child(opts)
	var hidden := keys.filter(func(x): return not (Data.TRAITS[x]["from"] in own)).size()
	if hidden:
		body.add_child(UiKit.note("%d more Trait%s: own the creature to learn %s." % [hidden, "" if hidden == 1 else "s", "it" if hidden == 1 else "them"]))
	if pending != null and pending.has("trait"):
		var x2: String = pending["trait"]
		var def2: Dictionary = Data.TRAITS[x2]
		body.add_child(_unlock_box("Learn [b]%s[/b]: %s. Any one creature can socket it besides %s." % [def2.name, def2.text, Data.SPECIES[def2["from"]].name],
			Meta.trait_cost(x2), func(): return Meta.unlock_trait(x2) and Meta.set_trait(k, x2)))

## What each upgrade track adds per level: the BAL key and the words after "+N%".
const UP_EFFECT := {"sword": ["up_dmg", "damage"], "orb": ["up_spirit", "shields and heals"], "jewel": ["up_hp", "max HP"]}

## Upgrades tab (§5.2): one track per material (the header shows gold and materials): five pips, what it adds so far, and a
## button with the next level and its cost (or what is missing).
func _coll_upgrades(body: Control, k: String) -> void:
	var w := Meta.wallet()   # shown in the header while this tab is open
	var list := UiKit.rows()
	var lv := Meta.upgrades(k)
	for m in Data.MATS:
		var def: Dictionary = Data.MAT_DEF[m]
		var c: Color = MAT_COL[m]
		var n: int = lv.get(m, 0)
		var cost = Meta.upgrade_cost(k, m)
		var row := UiKit.panel(UiKit.row_style(false, Vector4(0, 6, 0, 6)))
		var h := UiKit.hbox(10)
		row.add_child(h)
		var v := UiKit.vbox(5)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pr := UiKit.hbox(6)
		pr.add_child(UiKit.icon(m, 16, c))
		pr.add_child(UiKit.disp(def.track, UiKit.NAME, UiKit.INK))
		v.add_child(pr)
		v.add_child(UiKit.pips(n, Data.BAL.up_max))
		var fx: Array = UP_EFFECT[m]
		var pct := roundi(Data.BAL[fx[0]] * 100)
		v.add_child(UiKit.note(("+%d%% %s" % [pct * n, fx[1]]) if n else ("+%d%% %s per level" % [pct, fx[1]])))
		h.add_child(v)
		h.add_child(_up_btn(k, m, n, cost, w))
		list.add_child(row)
	body.add_child(list)

## The upgrade button: a quiet two-line button, gold-rimmed when affordable. Line 1 is the next level
## (or what is missing), line 2 its cost.
func _up_btn(k: String, m: String, n: int, cost, w: Dictionary) -> Tap:
	var can: bool = cost != null and w.gold >= cost.gold and w[m] >= cost[m]
	var t := Tap.new(UiKit.flat(Color(0, 0, 0, 0.18), 5, 1, UiKit.GOLD_HI if can else UiKit.LINE, Vector4(10, 6, 10, 6)))
	t.dis_mod = Color.WHITE   # it says why it can't be bought instead of dimming
	t.custom_minimum_size = Vector2(112, 44)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := UiKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	t.add_child(v)
	if cost == null:
		v.add_child(UiKit.lbl("Max level", "700", UiKit.T_S, UiKit.INK2, {"align": "center"}))
		t.disabled = true
		return t
	var mname: String = Data.MAT_DEF[m].name
	var line1 := "Level %d" % (n + 1)
	if not can:
		line1 = ("Need %d %s" % [cost[m] - w[m], mname]) if w[m] < cost[m] else ("Need %d gold" % (cost.gold - w.gold))
	v.add_child(UiKit.lbl(line1, "700", UiKit.T_S, UiKit.GOLD_HI if can else UiKit.INK2, {"align": "center"}))
	v.add_child(UiKit.lbl("%d %s · %d gold" % [cost[m], mname, cost.gold], "500", UiKit.T_S, UiKit.INK2, {"align": "center"}))
	t.disabled = not can
	t.pressed.connect(func():
		if not Meta.buy_upgrade(k, m):
			return
		Sfx.audio()
		Sfx.caught()
		Platform.haptic("success")
		_coll_render())
	return t

func _pad_top(c: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_top", px)
	m.add_child(c)
	return m

func init_run_ui() -> void:
	var el := _el()
	el.startBtn.pressed.connect(start_run)
	el.againBtn.pressed.connect(func():
		Sfx.pick()
		start_run())
	el.titleBtn.pressed.connect(func():
		Sfx.pick()
		to_title())
	el.lineupBtn.pressed.connect(func():
		Sfx.pick()
		show_party(func(): show_map(false)))
	el.packBtn.pressed.connect(func():
		Sfx.audio()
		Sfx.pick()
		_open_next_pack(to_title, true))
	el.collBtn.pressed.connect(func():
		Sfx.audio()
		Sfx.pick()
		_show_collection())
	el.collBack.pressed.connect(func():
		Sfx.pick()
		to_title())
	el.shopBtn.pressed.connect(func():
		Sfx.audio()
		Sfx.pick()
		_show_shop(to_title))
	el.endShopBtn.pressed.connect(func():
		Sfx.pick()
		_show_shop(_back_to_end))
	for b in [el.teamBtn, el.dockTeam]:
		b.pressed.connect(func():
			Sfx.audio()
			Sfx.pick()
			show_team())
	el.teamDone.pressed.connect(func():
		Sfx.pick()
		to_title())
	el.mapQuit.pressed.connect(func(): quit_tap(el.mapQuit))
	S.picks = Meta.last_lineup()

## Debug/screenshot helpers: open a screen directly.
func debug_show(id: String) -> void:
	match id:
		"title": to_title()
		"team": show_team()
		"team-swap":   # every creature owned, team full, the cursor on slot 2 (scratch save, not user://save.cfg)
			Platform.use_save_path("user://shot-team-swap.cfg")
			Platform.store_set("owned", Array(Data.ROSTER))
			Platform.store_set("lineup", ["emberwick", "bellspring", "truffmole"])
			S.picks = Meta.last_lineup()
			show_team()
			_team_cur = 1
			_render_picks()
		"coll": _show_collection()
		"coll-trait": _show_collection("trait")
		"coll-up":
			if Platform.ui_check:   # scratch save: one Power level bought, so the shot shows a pip and a "Need" button
				Meta.buy_upgrade(S.picks[0], "sword")
			_show_collection("upgrades")
		"shop": _show_shop(to_title)
		"pack", "pack-pick":   # three choices: new, a copy that unlocks a card, a copy that turns shiny (scratch save)
			Platform.use_save_path("user://shot-pack.cfg")
			Platform.store_set("copies", {"emberwick": 1, "bellspring": 2, "truffmole": 1, "sparkit": 9})
			Platform.store_set("packPending", ["cinderpip", "bellspring", "sparkit"])
			Platform.store_set("packSource", "daily")
			Platform.store_set("packDay", Meta._pack_day())
			Platform.store_set("packPts", 32)
			S.picks = Meta.last_lineup()
			_open_next_pack(to_title, true)
			if id == "pack-pick":   # every card face up, Bellspring kept (its third copy unlocks Undertide)
				for i in _pk.cards.size():
					_pack_reveal(i, false)
				_pack_keep(1)
		"map":
			start_run()
		"map-sel":   # the second medallion selected
			start_run()
			_map_tap(1)
		"map-warden":   # floor 4: one medallion, the trail fades up toward Noctyrm
			start_run()
			S.floor = 4
			show_map()
		"map-late":   # floor 6 in the Dusklands, with an Alpha and a hurt, knocked-out party
			start_run()
			S.floor = 6
			S.party[1].hp = 0.0
			S.party[1].alive = false
			S.party[2].hp = S.party[2].max_hp * 0.25
			show_map()
		"party":
			start_run()
			show_party(func(): show_map(false))
		"reward":
			start_run()
			_show_reward(2, {"gold": 11, "sword": 1, "orb": 0, "jewel": 0}, {"thorn": 2}, true, {"n": 3, "gained": 0})
		"reward-warden":   # the Warden's haul: five chips on the ribbon, one pick
			start_run()
			S.floor = 4
			_show_reward(1, {"gold": 40, "sword": 1, "orb": 1, "jewel": 0}, {"thorn": 3, "ember": 3}, true, {"n": 5, "gained": 1})
		"upgrade":
			start_run()
			_show_upgrade(func(): show_map(), func(): show_map())
		"end":
			start_run()
			S.floor = 3
			run_loot = {"gold": 31, "sword": 1, "orb": 0, "jewel": 1}
			run_ess = {"ember": 0, "tide": 1, "thorn": 2, "volt": 0}
			S.stats.perfects = 2
			S.party[2].hp = 0.0
			S.party[2].alive = false
			run_pts0 = 38   # the meter wraps: a pack earned, 10 points into the next
			run_pts = 22
			run_packs = 1
			if Platform.ui_check:   # scratch save: bank the token so Open shows
				Meta.add_pack_pts(50)
			end_run(false)
		"end-win":
			start_run()
			S.floor = 8
			run_loot = {"gold": 312, "sword": 3, "orb": 2, "jewel": 4}
			run_ess = {"ember": 9, "tide": 4, "thorn": 7, "volt": 3}
			S.stats.perfects = 11
			S.stats.start = Platform.ticks_msec() - 754000
			run_pts0 = 12
			run_pts = 31
			end_run(true)
