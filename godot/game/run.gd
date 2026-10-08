extends Node
## Run flow outside combat (TS game/run.ts): title (team picker), packs, collection & upgrades, item shop,
## map, nodes, loot, rewards, lineup, end of run. Spec: ../CLAUDE.md §2, §5–§7, §11, §16.
## Screens are the frames Ui builds (Ui.el ids = index.html ids); this fills and wires them.

## UI colours of the materials (the Ember / Tide / Thorn accents).
const MAT_COL := {"sword": UiKit.EL.ember, "orb": UiKit.EL.tide, "jewel": UiKit.EL.thorn}

var run_ess := {}
var run_loot := {}
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
	_show_reward(2 if (e != null and e.kind == "alpha") else 1, loot, ess)

# ================= rewards =================
func _upgradable() -> bool:
	for c in S.party:
		for s in Data.SLOTS:
			if not c.ups.get(s):
				return true
	return false

## Picks this reward screen started with (Alphas give 2), for the pip row.
var _rw_total := 1

## The loot ribbon's chips: gold, each material, then each element's Essence (`ess`), skipping zeros.
func _ribbon_chips(l: Dictionary, ess: Dictionary) -> Array:
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
	return out

## `ess` = the Essence this fight earned; `fresh` = first showing (the ribbon pops in; later picks and
## coming back from the upgrade screen show it at rest).
func _show_reward(picks: int, loot, ess := {}, fresh := true) -> void:
	var el := _el()
	S.mode = "reward"
	if picks <= 0:
		_next_floor()
		return
	if fresh:
		_rw_total = picks
	el.rwEyebrow.text = "Victory"
	el.rwTitle.text = "Choose a reward"
	var got: Array = _ribbon_chips(loot if loot != null else {}, ess)
	_fill(el.rwSubLoot, got)
	el.rwSubLoot.visible = not got.is_empty()
	if fresh:
		Fx.reveal(got)
	UiKit.clear(el.rwPips)
	el.rwPips.add_child(UiKit.pips(picks, _rw_total))
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
			var co: Dictionary = S.card_of(CardRef.new(c.uid, slot))
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
	var def: Dictionary = S.card_of(CardRef.new(c.uid, slot)).def
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
		else ("You left on floor %d. Your loot is safe." % S.floor) if quit \
		else ("Your party fell on floor %d. Your loot is safe." % S.floor)
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
				Particles.emit(x, y, {"n": 60, "color": [Color("#ffcf6b"), Color("#ff7a45"), Color("#3fb6ff"), Color("#5fd36a"), Color("#ffd23f"), Color("#c8b4ff")], "spd": 5, "life": 1.6, "size": 0.2, "grav": 3, "drag": 1})
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
	Ui.show("scr-end")

# ================= title =================
## Home screen: the current team as a summary, Start, and the meta buttons. The team is edited on scr-team.
func _render_title() -> void:
	var el := _el()
	S.picks = _valid_picks()
	var own := Meta.owned()
	UiKit.clear(el.teamRow)
	for i in S.picks.size():
		el.teamRow.add_child(_team_chip(S.picks[i], i == 0))
	el.pickEyebrow.text = "Your team · %d/%d" % [S.picks.size(), Data.BAL.lineup]
	var best := Meta.best()
	var wins := Meta.wins()
	el.bestT.text = ("Expeditions won: %d · best floor %d" % [wins, best]) if wins else (("Best run: floor %d" % best) if best else "Runs take about five minutes")
	var ready := Meta.pack_ready()
	UiScreens.set_meta_btn(el.packBtn, "Daily pack", "Ready to open" if ready else "Next in " + Meta.next_pack_in(), ready)
	el.packBtn.disabled = not ready
	var sh := Meta.shinies().size()
	UiScreens.set_meta_btn(el.collBtn, "Collection", "%d / %d%s" % [own.size(), Data.ROSTER.size(), (" · %d ✦" % sh) if sh else ""])
	UiScreens.set_meta_btn(el.shopBtn, "Item shop", "%d gold" % Meta.wallet().gold)

## A compact team member: element orb, name, "Lead" marked in gold. `replace_c` set (team screen,
## a pending pick): the status line reads "Tap to replace" in the incoming creature's colour.
func _team_chip(k: String, lead: bool, replace_c := Color(0, 0, 0, 0)) -> Control:
	var sp: Dictionary = Data.SPECIES[k]
	var c := UiKit.el_css(sp.el)
	# the lead is the selected one: gold outline and wash; the others sit in a brass hairline
	var p := UiKit.panel(UiKit.row_style(true, Vector4(6, 8, 6, 8)) if lead else UiKit.flat(Color(0, 0, 0, 0.18), 4, 1, UiKit.HAIR, Vector4(6, 8, 6, 8)))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UiKit.por(c, 32, sp.el, lead))
	v.add_child(UiKit.lbl(sp.name + (" ✦" if Meta.is_shiny(k) else ""), "display", UiKit.NAME, UiKit.INK, {"align": "center", "lh": -2}))
	if replace_c.a > 0:
		v.add_child(UiKit.lbl("Tap to replace", "700", UiKit.T_S, UiKit.mix(replace_c, UiKit.INK, 0.6), {"align": "center"}))
	else:
		v.add_child(UiKit.lbl("★ Lead" if lead else "Bench", "700", UiKit.T_S, UiKit.GOLD_HI if lead else UiKit.INK2, {"align": "center"}))
	p.add_child(v)
	return p

# ---- team screen (§4.2) ----
## Owned creature waiting for a lineup slot (team full, tapped an unpicked one); "" = none.
var _team_pending := ""
## What changed on the last edit, popped after the re-render: {slot: int, pick: String}.
var _team_pop := {}

func show_team() -> void:
	S.mode = "title"
	_team_pending = ""
	_team_pop = {}
	_render_picks()
	Ui.show("scr-team")
	_show_title_actor(S.picks[0])

## Lineup-slot badge, shared by the slot and its picker card so they read as a pair: "1 ★", "2", "3".
func _slot_badge(i: int, c: Color) -> Control:
	# mockup .num-b: a dark tab with an element rim; the lead's star is gold
	var p := UiKit.panel(UiKit.flat(UiKit.NAVY2, 3, 1, UiKit.mix(c, Color.BLACK, 0.2), Vector4(5, 1, 5, 1)))
	var h := UiKit.hbox(2)
	h.add_child(UiKit.lbl(str(i + 1), "700", UiKit.T_S, UiKit.INK, {"align": "center"}))
	if i == 0:
		h.add_child(UiKit.lbl("★", "700", UiKit.T_S, UiKit.GOLD_HI))
	p.add_child(h)
	return p

## Border-only ring that pulses (real time) over a card: the pending pick and the slots it can replace.
func _pulse_ring(c: Color, radius: float) -> Control:
	var r := Panel.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiKit.glow_box(UiKit.flat(Color(0, 0, 0, 0), radius, 2.5, c), UiKit.alpha(c, 0.6), 8)
	sb.draw_center = false
	r.add_theme_stylebox_override("panel", sb)
	Fx.kf(r, 0.55, [[0.0, {"a": 0.2}], [1.0, {"a": 1.0}]], {"loop": "alternate"})
	return Box.fill(r)

## Quick pop on whatever just changed (UI motion: Fx.kf runs in real time).
func _team_pop_fx(n: Control) -> void:
	if n is Tap:   # Tap keeps its pivot centred
		Fx.kf(n, 0.3, [[0.0, {"s": 0.86}], [0.45, {"s": 1.08}], [1.0, {"s": 1.0}]])

## The deck's element mix under the lineup: "Ember ×2 · Tide ×1" as element chips.
func _render_team_mix() -> void:
	var el := _el()
	UiKit.clear(el.teamMix)
	var n := {}
	for k in S.picks:
		var e: String = Data.SPECIES[k].el
		n[e] = n.get(e, 0) + 1
	var lab := UiKit.eyebrow("Deck")
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	el.teamMix.add_child(lab)
	for e in Data.EL_KEYS:
		if n.has(e):
			el.teamMix.add_child(UiKit.ess(e, UiKit.el_css(e), "%s ×%d" % [Data.ELEM[e].name, n[e]]))

## Team screen: the lineup slots and the owned-creature picker. Slot n and its picker card share a
## numbered badge ("1 ★" = lead). Tap a slot to make it lead; tap a creature to add it (team not full)
## or remove it (min 1). With the team full, tapping an unpicked creature makes it the pending pick and
## the next slot (or in-team card) tapped is replaced by it, keeping order; nothing is replaced silently.
## Saved on every change.
func _render_picks() -> void:
	var el := _el()
	var box: Control = el.starters
	UiKit.clear(box)
	var own := Meta.owned()
	S.picks = _valid_picks()
	var full: bool = S.picks.size() >= Data.BAL.lineup
	if not full or not (_team_pending in own) or _team_pending in S.picks:
		_team_pending = ""
	var pend := _team_pending
	var pc: Color = UiKit.el_css(Data.SPECIES[pend].el) if pend != "" else UiKit.MUTE
	var changed := func(show_k: String, pop: Dictionary):
		Meta.save_lineup(S.picks)
		_team_pop = pop
		_render_picks()
		_show_title_actor(show_k)
	var replace := func(i: int):
		var nk := _team_pending
		S.picks[i] = nk
		_team_pending = ""
		changed.call(nk, {"slot": i, "pick": nk})
	var slots := {}
	var cards := {}
	UiKit.clear(el.teamOrder)
	for i in Data.BAL.lineup:
		if i >= S.picks.size():
			var empty := UiKit.panel(UiKit.flat(Color(0, 0, 0, 0.18), 4, 1, UiKit.HAIR, Vector4(6, 6, 6, 6)))
			empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			empty.add_child(UiKit.lbl("Empty", "500", UiKit.T_S, UiKit.INK2, {"align": "center", "valign": VERTICAL_ALIGNMENT_CENTER}))
			el.teamOrder.add_child(empty)
			slots[i] = empty
			continue
		var k: String = S.picks[i]
		var c := UiKit.el_css(Data.SPECIES[k].el)
		var t := Tap.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Box.new()
		b.add_child(Box.fill(_team_chip(k, i == 0, pc if pend != "" else Color(0, 0, 0, 0))))
		if pend != "":   # replace mode: every slot is a target, outlined in the incoming creature's colour
			b.add_child(_pulse_ring(pc, 4))
		b.add_child(Box.at(_slot_badge(i, c), "tr", Vector2(4, 4)))
		t.add_child(b)
		_btn(t, func():
			if _team_pending != "":
				replace.call(i)
				return
			if S.picks[0] != k:
				S.picks.erase(k)
				S.picks.insert(0, k)
			changed.call(k, {"slot": 0, "pick": k}))
		el.teamOrder.add_child(t)
		slots[i] = t
	for k in Data.ROSTER:
		if not (k in own):
			continue
		var sp: Dictionary = Data.SPECIES[k]
		var shiny := Meta.is_shiny(k)
		var i: int = S.picks.find(k)
		var is_pend: bool = k == pend
		var c := UiKit.el_css(sp.el)
		var pad := Vector4.ZERO   # content padding lives in a MarginContainer so the pulse ring can hug the border
		var st: StyleBoxFlat
		if i >= 0:   # in the team: selected, a gold outline with a soft gold glow (the only glow here)
			st = UiKit.glow_box(UiKit.flat(UiKit.SEL_BG, 5, 1.5, UiKit.GOLD_HI, pad), UiKit.alpha(UiKit.GOLD_HI, 0.25), 6)
		elif is_pend:   # waiting for a slot: an element outline (the pulse ring marks it too)
			st = UiKit.flat(UiKit.alpha(c, 0.10), 5, 1.5, UiKit.mix(c, Color.WHITE, 0.3), pad)
		else:   # owned but not picked: flat in a hairline, dimmed below
			st = UiKit.flat(Color(0, 0, 0, 0.18), 5, 1, UiKit.HAIR, pad)
		var t := Tap.new(st)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Box.new()
		var v := UiKit.vbox(6)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(UiKit.por(c, 40, sp.el, i >= 0))
		v.add_child(UiKit.lbl(sp.name + (" ✦" if shiny else ""), "display", UiKit.NAME, UiKit.INK, {"align": "center", "lh": -2}))
		var status: String = "Lead" if i == 0 else ("Bench" if i > 0 else ("Pick a slot" if is_pend else sp.get("role", "")))
		var status_c: Color = UiKit.GOLD_HI if i == 0 else (UiKit.INK2 if i > 0 else (UiKit.INK if is_pend else UiKit.INK2))
		v.add_child(UiKit.lbl(status, "700", UiKit.T_S, status_c, {"align": "center"}))
		if i < 0 and not is_pend:
			v.modulate = Color(1, 1, 1, 0.55)
		var m := MarginContainer.new()
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mg := {"left": 6, "top": 12, "right": 6, "bottom": 10}
		for side in mg:
			m.add_theme_constant_override("margin_" + side, mg[side])
		m.add_child(v)
		b.add_child(Box.fill(m))
		if is_pend:
			b.add_child(_pulse_ring(Color.WHITE, 5))
		if i >= 0:
			b.add_child(Box.at(_slot_badge(i, c), "tr", Vector2(6, 6)))
		t.add_child(b)
		_btn(t, func():
			var j: int = S.picks.find(k)
			if _team_pending != "":
				if k == _team_pending:   # tap again: cancel
					_team_pending = ""
					_team_pop = {}
					_render_picks()
					_show_title_actor(S.picks[0])
				elif j >= 0:   # an in-team card is a target too
					replace.call(j)
				else:   # change the pending pick
					_team_pending = k
					_team_pop = {"pick": k}
					_render_picks()
					_show_title_actor(k)
			elif j >= 0:
				if S.picks.size() > 1:
					S.picks.remove_at(j)
					changed.call(S.picks[0], {"slot": j})
				else:
					Fx.toast("Your team needs at least one creature")
			elif S.picks.size() < Data.BAL.lineup:
				S.picks.append(k)
				changed.call(k, {"slot": S.picks.size() - 1, "pick": k})
			else:   # full: hold it as the pending pick; the player chooses which slot it replaces
				_team_pending = k
				_team_pop = {"pick": k}
				_render_picks()
				_show_title_actor(k))
		box.add_child(t)
		cards[k] = t
	el.teamEyebrow.text = "Team · %d/%d" % [S.picks.size(), Data.BAL.lineup]
	_render_team_mix()
	if pend != "":
		el.teamHint.text = "Swap in %s: tap a slot to replace. Tap %s again to cancel." % [Data.SPECIES[pend].name, Data.SPECIES[pend].name]
		el.teamHint.add_theme_color_override("font_color", pc)
	else:
		var spare: bool = own.any(func(o): return not (o in S.picks))
		el.teamHint.text = "Tap a slot to make it lead. Tap a creature to %s." % (("swap it in" if spare else "remove it") if full else "add or remove it")
		el.teamHint.add_theme_color_override("font_color", UiKit.INK2)
	if _team_pop.has("slot"):
		_team_pop_fx(slots.get(_team_pop.slot))
	if _team_pop.has("pick"):
		_team_pop_fx(cards.get(_team_pop.pick))
	_team_pop = {}

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
func _show_daily_pack() -> void:
	var res = Meta.open_pack()
	if res == null:
		to_title()
		return
	_show_pack(res, "Daily pack", "One new friend a day", to_title, true)

## The card-flip reveal for any pack (daily or bought). `join` = true adds a new creature to the
## title-screen team if there's room (the daily pack only, so "Run again" keeps its team).
func _show_pack(res: Dictionary, title: String, blurb: String, back: Callable, join := false) -> void:
	var el := _el()
	S.mode = "meta"
	if S.title_actor != null and is_instance_valid(S.title_actor):
		S.title_actor.destroy()
	S.title_actor = null
	_pack_n += 1
	var n := _pack_n
	el.packH1.text = title
	el.packP.text = blurb
	UiScreens.flip_set(Ui, false)
	_fill(el.packTxt, [UiKit.sub("Tap the card", "center")])
	var k = res.get("key")
	var sp = Data.SPECIES[k] if k != null else null
	UiScreens.flip_color(Ui, UiKit.el_css(sp.el) if sp else UiKit.GOLD)
	var f: Control = el.packFront
	UiKit.clear(f)
	if sp:
		f.add_child(UiKit.orb(UiKit.el_css(sp.el), 56, sp.el, 26))
		f.add_child(UiKit.lbl(sp.name + (" ✦" if res.shiny else ""), "display", 22, UiKit.INK, {"align": "center"}))
		f.add_child(UiKit.lbl("Shiny!" if res.shiny else "New creature", "700", 12, UiKit.MUTE, {"align": "center", "wrap": true}))
	else:
		f.add_child(UiKit.lbl("All shiny!", "display", 22, UiKit.INK, {"align": "center"}))
		f.add_child(UiKit.lbl("You have every shiny. Nothing left to find… for now.", "700", 12, UiKit.MUTE, {"align": "center", "wrap": true}))
	var state := {"opened": false}
	var reveal := func():
		if state.opened or n != _pack_n or Ui.current != "scr-pack":
			return
		state.opened = true
		UiScreens.flip_set(Ui, true)
		Sfx.caught()
		Platform.haptic("heavy")
		if k != null and sp:
			_show_title_actor(k)
			_fill(el.packTxt, [UiKit.sub(("%s now shines in every run." % sp.name) if res.shiny else ("%s joins your collection. Add it to your team on the title screen." % sp.name), "center")])
		else:
			UiKit.clear(el.packTxt)
	_on(el.packCard, reveal)
	_later(1.2, reveal)
	_on(el.packOk, func():
		Sfx.pick()
		if join and k != null and not res.shiny and not (k in S.picks) and S.picks.size() < Data.BAL.lineup:
			S.picks.append(k)
		back.call())
	Ui.show("scr-pack")
	Ui.measure(true)

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
	var empty := Meta.pack_empty()
	add.call(buy, "star", "Creature pack", "You own every creature and every shiny" if empty else "A creature you don’t own, else a shiny",
		UiKit.GOLD_HI, str(Data.BAL.shop_pack), "All collected" if empty else ("" if w.gold >= Data.BAL.shop_pack else short.call(Data.BAL.shop_pack - w.gold)),
		func():
			var r = Meta.buy_pack()
			if r != null:
				_show_pack(r, "Creature pack", "Fresh from the shop", again))
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
var _coll := {"cur": "", "pending": null}

func _show_collection() -> void:
	var el := _el()
	S.mode = "meta"
	var own := Meta.owned()
	var grid: Control = el.collGrid
	UiKit.clear(grid)
	el.collCount.text = "%d / %d" % [own.size(), Data.ROSTER.size()]
	_coll = {"cur": "", "pending": null}
	for k in Data.ROSTER:
		var sp: Dictionary = Data.SPECIES[k]
		var has: bool = k in own
		var c := UiKit.el_css(sp.el) if has else UiKit.MUTE
		var st := UiKit.flat(Color(0, 0, 0, 0.18), 4, 1, UiKit.HAIR, Vector4(2, 6, 2, 6))
		var st_on := UiKit.row_style(true, Vector4(2, 6, 2, 6))
		var t := Tap.new(st, st_on)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UiKit.vbox(4)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		if has:
			v.add_child(UiKit.por(c, 30, sp.el))
		else:
			var q := UiKit.boxed(UiKit.lbl("?", "display", UiKit.NAME, UiKit.MUTE, {"align": "center"}), Vector2(30, 30),
				RRect.new({"radius": 15.0, "border_w": 1.0, "border_c": UiKit.HAIR}).solid(UiKit.NAVY2))
			v.add_child(q)
		v.add_child(UiKit.lbl((sp.name if has else "???") + (" ✦" if Meta.is_shiny(k) else ""), "700", UiKit.T_S, UiKit.INK, {"align": "center", "ellipsis": true}))
		t.add_child(v)
		if not has:
			t.modulate.a = 0.7
		t.set_meta("k", k)
		_btn(t, _coll_detail.bind(k))
		grid.add_child(t)
	Ui.show("scr-coll")
	Ui.measure(true)
	_coll_detail(S.picks[0] if S.picks[0] in own else own[0])

func _coll_detail(k: String) -> void:
	_coll.cur = k
	_coll.pending = null
	_show_title_actor(k, not Meta.is_owned(k))
	for b in _el().collGrid.get_children():
		b.on = b.get_meta("k") == k
	_coll_render()

## The unlock panel for a locked option: what it costs and an Unlock button (disabled if too poor).
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
	var pending = _coll.pending
	var sp: Dictionary = Data.SPECIES[k]
	var own := Meta.owned()
	var has: bool = k in own
	var lo := Meta.loadout(k)
	var bo := Meta.boosts(k)
	var col := UiKit.el_css(sp.el)
	_fill(el.collEss, _ess_chips(Meta.essence()) + _loot_chips(Meta.wallet()))
	var d: Control = el.collDetail
	UiKit.clear(d)
	var prow := UiKit.hbox(8)
	prow.add_child(UiKit.elchip(sp.el, Data.ELEM[sp.el].name))
	var nm := UiKit.lbl(sp.name + (" ✦" if Meta.is_shiny(k) else ""), "display", UiKit.D_S, UiKit.INK, {"ellipsis": true})
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(nm)
	prow.add_child(UiKit.lbl("%s · %d HP" % [sp.get("role", ""), roundi(sp.hp * bo.vital) if has else sp.hp], "500", UiKit.T_S, UiKit.INK2))
	d.add_child(prow)
	if not has:
		d.add_child(UiKit.sub("Not found yet. Open a daily pack, or buy one in the item shop."))
		var cards := UiKit.grid(3, 8)
		for slot in Data.SLOTS:
			var cv := CardView.new("coll").face(sp.cards[slot][0], sp.el, {"slot": slot})   # not found yet: a glyph, no face
			cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cards.add_child(cv)
		d.add_child(_pad_top(cards, 6))
		return
	# card slots: one row each, options in columns
	for slot in Data.SLOTS:
		var sec := _sec("Strike" if slot == "strike" else ("Skill" if slot == "skill" else "Signature"))
		var cards := UiKit.grid(3, 8)
		var list: Array = sp.cards[slot]
		for i in list.size():
			var def: Dictionary = list[i]
			var on: bool = slot == "strike" or lo.get(slot, 0) == i
			var open := Meta.move_unlocked(k, slot, i)
			var t := Tap.new()
			t.press_scale = 0.97
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cv := CardView.new("lo").face(Data.boost_card(def, bo.power, bo.spirit), sp.el, {"slot": slot, "faces": [[k, sp.el]]})
			cv.pressed_state = 1 if on else -1
			cv.sel = pending != null and pending.has("slot") and pending.slot == slot and pending.i == i
			if not open:
				var mc := Meta.move_cost(k)
				cv.add_lock(mc.n, mc.el)
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
					_coll.pending = null
				else:
					_coll.pending = {"slot": slot, "i": i}
				_coll_render())
			cards.add_child(t)
		for i in range(list.size(), 3):
			cards.add_child(UiKit.spacer())
		sec.add_child(_pad_top(cards, 6))
		if pending != null and pending.has("slot") and pending.slot == slot:
			var p: Dictionary = pending
			var pdef: Dictionary = list[p.i]
			sec.add_child(_unlock_box("Unlock [b]%s[/b] for %s's %s slot." % [pdef.name, sp.name, "Skill" if slot == "skill" else "Signature"], Meta.move_cost(k),
				func(): return Meta.unlock_move(k, p.slot, p.i) and Meta.set_move(k, p.slot, p.i)))
		d.add_child(sec)
	# Trait socket: built-in + learned Traits, then learnable ones (source owned) with their cost
	var tsec := _sec("Trait")
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
		tsec.add_child(tp)
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
			if not (pending != null and pending.has("trait") and pending["trait"] == x):
				b.modulate.a = 0.7
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
	tsec.add_child(_pad_top(opts, 2))
	var hidden := keys.filter(func(x): return not (Data.TRAITS[x]["from"] in own)).size()
	if hidden:
		tsec.add_child(_pad_top(UiKit.note("%d more Trait%s: own the creature to learn %s." % [hidden, "" if hidden == 1 else "s", "it" if hidden == 1 else "them"]), 6))
	if pending != null and pending.has("trait"):
		var x2: String = pending["trait"]
		var def2: Dictionary = Data.TRAITS[x2]
		tsec.add_child(_unlock_box("Learn [b]%s[/b]: %s. Any one creature can socket it besides %s." % [def2.name, def2.text, Data.SPECIES[def2["from"]].name],
			Meta.trait_cost(x2), func(): return Meta.unlock_trait(x2) and Meta.set_trait(k, x2)))
	d.add_child(tsec)
	# permanent upgrades (§5.2): one track per material
	var ups := _sec("Upgrades")
	var lv := Meta.upgrades(k)
	var w := Meta.wallet()
	for m in Data.MATS:
		var def: Dictionary = Data.MAT_DEF[m]
		var c: Color = MAT_COL[m]
		var n: int = lv.get(m, 0)
		var cost = Meta.upgrade_cost(k, m)
		var row := UiKit.panel(UiKit.inset())
		var v := UiKit.vbox(6)
		row.add_child(v)
		var pr := UiKit.hbox(8)
		pr.add_child(UiKit.icon(m, 20, c))
		var tl := UiKit.lbl(def.track, "display", UiKit.NAME, UiKit.INK)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(tl)
		pr.add_child(UiKit.lbl("Lv %d / %d" % [n, Data.BAL.up_max], "700", UiKit.T_S, UiKit.INK2))
		v.add_child(pr)
		var pips := UiKit.hbox(4)
		for i in Data.BAL.up_max:
			var pip := Panel.new()
			pip.add_theme_stylebox_override("panel", UiKit.flat(c if i < n else Color(1, 1, 1, 0.1), 3))
			pip.custom_minimum_size.y = 6
			pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pips.add_child(pip)
		v.add_child(pips)
		v.add_child(UiKit.note(def.text))
		var b := UiScreens.big("Upgrade", true)
		if cost == null:
			b.disabled = true
			UiScreens.set_big(b, "Max level")
		else:
			b.disabled = w.gold < cost.gold or w[m] < cost[m]
			UiScreens.set_big(b, "Upgrade", "· %d %s%s + %d gold" % [cost[m], def.name, "s" if cost[m] > 1 else "", cost.gold])
			b.pressed.connect(func():
				if not Meta.buy_upgrade(k, m):
					return
				Sfx.audio()
				Sfx.caught()
				Platform.haptic("success")
				_coll_render())
		v.add_child(b)
		ups.add_child(row)
	d.add_child(ups)
	for x in d.find_children("*", "PanelContainer", true, false):
		if x.has_meta("upchoice"):
			_scroll_to(x)
			break

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
		_show_daily_pack())
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
	el.teamBtn.pressed.connect(func():
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
		"team-swap":   # every creature owned, team full, Cinderpip pending (scratch save, not user://save.cfg)
			Platform.use_save_path("user://shot-team-swap.cfg")
			Platform.store_set("owned", Array(Data.ROSTER))
			Platform.store_set("lineup", ["emberwick", "bellspring", "truffmole"])
			S.picks = Meta.last_lineup()
			show_team()
			_team_pending = "cinderpip"
			_render_picks()
			_show_title_actor("cinderpip")
		"coll": _show_collection()
		"shop": _show_shop(to_title)
		"pack": _show_pack({"key": "sparkit", "shiny": false}, "Daily pack", "One new friend a day", to_title)
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
			_show_reward(2, {"gold": 11, "sword": 1, "orb": 0, "jewel": 0}, {"thorn": 2})
		"reward-warden":   # the Warden's haul: five chips on the ribbon, one pick
			start_run()
			S.floor = 4
			_show_reward(1, {"gold": 40, "sword": 1, "orb": 1, "jewel": 0}, {"thorn": 3, "ember": 3})
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
			end_run(false)
		"end-win":
			start_run()
			S.floor = 8
			run_loot = {"gold": 312, "sword": 3, "orb": 2, "jewel": 4}
			run_ess = {"ember": 9, "tide": 4, "thorn": 7, "volt": 3}
			S.stats.perfects = 11
			S.stats.start = Platform.ticks_msec() - 754000
			end_run(true)
