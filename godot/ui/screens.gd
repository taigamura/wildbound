class_name UiScreens
## The static parts of the out-of-battle screens (index.html <section class="screen">): a logo/header
## band at the top and a bottom sheet, each registered in Ui.el by its TS id. Plus the shared button
## looks (.big, .big.alt, .ghostbtn, .metabtn) and the pack flip card.

const LOGO_SHADER := """
shader_type canvas_item;
uniform vec4 g0 : source_color = vec4(1.0);
uniform vec4 g1 : source_color = vec4(0.784, 0.706, 1.0, 1.0);
uniform vec4 g2 : source_color = vec4(0.49, 0.36, 1.0, 1.0);
uniform float y0 = 0.0;
uniform float y1 = 60.0;
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	if (COLOR.r > 0.97 && COLOR.g > 0.97 && COLOR.b > 0.97) {
		float t = clamp((ly - y0) / max(y1 - y0, 1.0), 0.0, 1.0);
		vec3 g = t < 0.2 ? g0.rgb : (t < 0.55 ? mix(g0.rgb, g1.rgb, (t - 0.2) / 0.35) : mix(g1.rgb, g2.rgb, (t - 0.55) / 0.45));
		base.rgb = g;
	}
	COLOR = base;
}
"""
static var _logo_shader: Shader

# ------------------------------------------------------------------ buttons

## .big: the lilac primary button. `alt` = the smaller .big.alt used in rows.
static func big(text: String, alt := false) -> Tap:
	var t := Tap.new()
	t.press_scale = 0.97
	t.dis_mod = Color(0.5, 0.5, 0.55)
	var bx := Box.new()
	bx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_child(bx)
	bx.add_child(Box.fill(RRect.new({"radius": 16.0, "c0": Color("#f1eaff"), "c1": Color("#b49bff"), "angle": 180.0,
		"sh_off": Vector2(0, 5), "sh_c": Color("#5a3bc4"), "glow": 30.0, "glow_c": Color(155 / 255.0, 123 / 255.0, 1, 0.25)})))
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := Vector4(10, 13, 10, 12) if alt else Vector4(18, 15, 18, 14)
	m.add_theme_constant_override("margin_left", int(pad.x))
	m.add_theme_constant_override("margin_top", int(pad.y))
	m.add_theme_constant_override("margin_right", int(pad.z))
	m.add_theme_constant_override("margin_bottom", int(pad.w))
	bx.add_child(Box.fill(m))
	var h := UiKit.hbox(5, BoxContainer.ALIGNMENT_CENTER)
	m.add_child(h)
	t.set_meta("row", h)
	t.set_meta("alt", alt)
	if alt:
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_big(t, text)
	return t

## Button text, with the optional <small> part.
static func set_big(t: Tap, text: String, small := "") -> void:
	var h: HBoxContainer = t.get_meta("row")
	UiKit.clear(h)
	var alt: bool = t.get_meta("alt")
	var ink := Color("#1b1035")
	h.add_child(UiKit.lbl(text, "display", 17 if alt else 21, ink, {"ls": 0.02, "valign": VERTICAL_ALIGNMENT_CENTER}))
	if small != "":
		var s := UiKit.lbl(small, "700", 11, ink, {"valign": VERTICAL_ALIGNMENT_CENTER})
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(s)

## .ghostbtn: outlined quiet button.
static func ghost(text: String) -> Tap:
	var t := Tap.new(UiKit.flat(Color(0, 0, 0, 0), 12, 1, UiKit.LINE, Vector4(14, 10, 14, 10)))
	var l := UiKit.lbl(text, "700", 13, UiKit.MUTE, {"upper": true, "ls": 0.06, "align": "center"})
	t.add_child(l)
	t.set_meta("lbl", l)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t

## .metabtn: title-screen tile (title + sub line). `ready` = the gold "pack ready" state.
static func meta_btn() -> Tap:
	var t := Tap.new()
	t.dis_mod = Color(1, 1, 1, 0.7)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(3)
	t.add_child(v)
	t.set_meta("v", v)
	set_meta_btn(t, "", "", false)
	return t

static func set_meta_btn(t: Tap, title: String, sub: String, ready := false) -> void:
	var st := UiKit.flat(Color(1, 1, 1, 0.04), 14, 1.5, UiKit.LINE, Vector4(12, 10, 12, 10))
	if ready:
		st = UiKit.glow_box(UiKit.flat(Color(1, 207 / 255.0, 107 / 255.0, 0.12), 14, 1.5, UiKit.GOLD, Vector4(12, 10, 12, 10)),
			Color(1, 207 / 255.0, 107 / 255.0, 0.25), 9)
	t.style = st
	t.disabled = t.disabled
	var v: VBoxContainer = t.get_meta("v")
	UiKit.clear(v)
	v.add_child(UiKit.lbl(title, "display", 16, UiKit.INK, {"lh": -4}))
	v.add_child(UiKit.lbl(sub, "700", 11, UiKit.GOLD if ready else UiKit.MUTE, {"wrap": true, "lh": -2}))

static func row(a: Control, b: Control) -> HBoxContainer:
	var r := UiKit.hbox(8)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(a)
	r.add_child(b)
	return r

# ------------------------------------------------------------------ logo

static func logo(ui, title_key: String, title: String, size: float, p_key: String, p_text: String) -> VBoxContainer:
	var v := UiKit.vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var h1 := UiKit.lbl(title, "display", int(size), Color.WHITE, {"align": "center", "shadow": Color("#24154f"),
		"shadow_off": Vector2(0, 5), "lh": int(-size * 0.25)})
	if not _logo_shader:
		_logo_shader = Shader.new()
		_logo_shader.code = LOGO_SHADER
	var m := ShaderMaterial.new()
	m.shader = _logo_shader
	h1.material = m
	h1.resized.connect(func():
		var f: Font = h1.get_theme_font("font")
		var asc := f.get_ascent(int(size))
		m.set_shader_parameter("y0", (h1.size.y - f.get_height(int(size))) / 2.0 + asc * 0.12)
		m.set_shader_parameter("y1", (h1.size.y - f.get_height(int(size))) / 2.0 + asc * 1.0))
	var glow := RRect.new({"radius": 999.0, "mode": "radial", "rc": Vector2(0.5, 0.5), "c0": Color(125 / 255.0, 92 / 255.0, 1, 0.32),
		"c1": Color(125 / 255.0, 92 / 255.0, 1, 0.0)})
	var stack := Box.new()
	stack.add_child(Box.fill(glow))
	stack.add_child(h1)
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(stack)
	ui.el[title_key] = h1
	if p_key != "" or p_text != "":
		var p := UiKit.lbl(p_text, "700", 13, UiKit.MUTE, {"upper": true, "ls": 0.16, "align": "center", "wrap": true, "lh": 0})
		v.add_child(p)
		if p_key != "":
			ui.el[p_key] = p
	return v

# ------------------------------------------------------------------ screens

static func _screen(ui, id: String, top: Control, items: Array, frac := 0.68) -> void:
	var scr := Control.new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.root.add_child(scr)
	ui.screens[id] = scr
	if top:
		top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		scr.add_child(top)
	var outer := MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	outer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	scr.add_child(outer)
	var inner := UiKit.panel(UiKit.flat(UiKit.PANEL, 22, 1, UiKit.LINE, Vector4(16, 18, 16, 16)))
	inner.mouse_filter = Control.MOUSE_FILTER_STOP
	outer.add_child(inner)
	var vb := UiKit.vbox(14)
	for it in items:
		vb.add_child(it)
	inner.add_child(CapScroll.new(vb, frac, 36))
	scr.set_meta("top", top)
	scr.set_meta("outer", outer)
	scr.set_meta("inner", inner)
	ui.band[id] = {"top": top, "bottom": outer}

## Re-apply safe-area padding and the 460px max width (on resize).
static func frame(ui, s: Dictionary) -> void:
	var side: float = s.side + 16.0
	for id in ui.screens:
		var scr: Control = ui.screens[id]
		var top = scr.get_meta("top") if scr.has_meta("top") else null
		if top:
			top.offset_left = side
			top.offset_right = -side
			top.offset_top = 18.0 + s.top
		var outer: Control = scr.get_meta("outer")
		outer.offset_left = side
		outer.offset_right = -side
		outer.offset_bottom = -(16.0 + s.bottom)

## sheetIn: .4s cubic-bezier(.2,1.2,.4,1) from 40px down and transparent.
static func sheet_in(ui, id: String) -> void:
	var inner: Control = ui.screens[id].get_meta("inner")
	Fx.kf(inner, 0.4, [[0.0, {"y": 40.0, "a": 0.0}], [1.0, {"y": 0.0, "a": 1.0}]], {"ease": [0.2, 1.2, 0.4, 1.0]})

static func _vbox_with(sep: int, items: Array) -> VBoxContainer:
	var v := UiKit.vbox(sep)
	for it in items:
		v.add_child(it)
	return v

static func _named(ui, key: String, c: Control) -> Control:
	ui.el[key] = c
	return c

static func build(ui) -> void:
	var el: Dictionary = ui.el
	# ---- title
	var t_logo := logo(ui, "titleH1", "Wildbound", 62, "", "Collect · Deal · Survive")
	# the current team (summary only; editing is on scr-team)
	el.teamRow = UiKit.hbox(6)
	el.teamRow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	el.teamBtn = ghost("Team")
	var head := _vbox_with(8, [_named(ui, "pickEyebrow", UiKit.eyebrow("Your team")), row(el.teamRow, el.teamBtn)])
	var metarow := UiKit.grid(3, 8)
	for k in ["packBtn", "collBtn", "shopBtn"]:
		el[k] = meta_btn()
		metarow.add_child(el[k])
	el.startBtn = big("Start expedition")
	el.bestT = UiKit.best("")
	_screen(ui, "scr-title", t_logo, [head, metarow, el.startBtn, el.bestT])

	# ---- team
	# (no intro paragraph: the hint under the lineup says what a tap does, which keeps Done on screen)
	var tm_head := _vbox_with(6, [_named(ui, "teamEyebrow", UiKit.eyebrow("Team")), UiKit.h2("Build your team")])
	el.teamOrder = UiKit.grid(3, 8)
	# under the lineup: the deck's element mix and a two-line hint (what a tap does / the replace prompt)
	el.teamMix = UiKit.hbox(6)
	el.teamMix.custom_minimum_size.y = 22
	el.teamHint = UiKit.lbl("", "700", 12, UiKit.MUTE, {"wrap": true, "lh": -1})
	el.teamHint.custom_minimum_size.y = 32
	var tm_info := _vbox_with(6, [el.teamMix, el.teamHint])
	var starters := UiKit.grid(3, 8)
	el.starters = starters
	var st_m := MarginContainer.new()
	st_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["left", "right"]:
		st_m.add_theme_constant_override("margin_" + k, 2)
	st_m.add_theme_constant_override("margin_top", 6)
	st_m.add_theme_constant_override("margin_bottom", 4)
	st_m.add_child(starters)
	el.teamDone = big("Done")
	_screen(ui, "scr-team", null, [tm_head, el.teamOrder, tm_info, CapScroll.new(st_m, 0.31), el.teamDone], 0.74)

	# ---- map
	el.trail = UiKit.hbox(5)
	var mhead := _vbox_with(6, [_named(ui, "mapEyebrow", UiKit.eyebrow("Floor 1 of 8")), UiKit.h2("Pick a path")])
	el.nodes = UiKit.vbox(8)
	el.mapParty = UiKit.hbox(8)
	var gold := UiKit.hbox(5)
	gold.add_child(UiKit.icon("coin", 13, UiKit.MUTE))
	el.mapGold = UiKit.lbl("", "700", 12, UiKit.MUTE, {"ls": 0.06, "wrap": true})
	el.mapGold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold.add_child(el.mapGold)
	el.lineupBtn = ghost("Lineup")
	el.mapQuit = ghost("Quit")
	var mrow := row(gold, el.lineupBtn)
	mrow.add_child(el.mapQuit)
	_screen(ui, "scr-map", null, [el.trail, mhead, el.nodes, el.mapParty, mrow])

	# ---- reward
	el.rwSubLoot = UiKit.flow(6)
	var rhead := _vbox_with(6, [_named(ui, "rwEyebrow", UiKit.eyebrow("Victory")), _named(ui, "rwTitle", UiKit.h2("Take a card")),
		el.rwSubLoot, _named(ui, "rwSub", UiKit.sub(""))])
	el.rewards = UiKit.grid(3, 10)
	var rw_m := MarginContainer.new()
	rw_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rw_m.add_theme_constant_override("margin_top", 14)
	rw_m.add_child(el.rewards)
	el.rwDeck = UiKit.lbl("", "700", 12, UiKit.MUTE, {"ls": 0.06, "wrap": true})
	el.skipBtn = ghost("Skip")
	_screen(ui, "scr-reward", null, [rhead, rw_m, row(el.rwDeck, el.skipBtn)])

	# ---- upgrade
	var uhead := _vbox_with(6, [UiKit.eyebrow("Upgrade a card"), UiKit.h2("Pick a card"),
		UiKit.sub("Each card can be upgraded once. Card upgrades last for this run.")])
	el.upList = UiKit.vbox(12)
	el.upChoice = UiKit.panel(UiKit.flat(Color(1, 207 / 255.0, 107 / 255.0, 0.08), 14, 1, Color(1, 207 / 255.0, 107 / 255.0, 0.3), Vector4(10, 10, 10, 10)))
	el.upChoiceBox = UiKit.vbox(8)
	el.upChoice.add_child(el.upChoiceBox)
	el.upChoice.visible = false
	el.upBack = ghost("Back")
	_screen(ui, "scr-upgrade", null, [uhead, el.upList, el.upChoice, row(UiKit.spacer(), el.upBack)], 0.82)

	# ---- party
	var phead := _vbox_with(6, [UiKit.eyebrow("Party"), UiKit.h2("Set your lineup"), _named(ui, "ptSub", UiKit.sub(""))])
	el.ptList = UiKit.vbox(8)
	el.ptDone = big("Done")
	_screen(ui, "scr-party", null, [phead, el.ptList, el.ptDone], 0.82)

	# ---- pack
	var pk_logo := logo(ui, "packH1", "Daily pack", 47, "packP", "One new friend a day")
	el.packCard = _flip(ui)
	el.packTxt = UiKit.vbox(6)
	el.packOk = big("Nice!")
	_screen(ui, "scr-pack", pk_logo, [el.packCard, el.packTxt, el.packOk])

	# ---- collection
	var c_logo := logo(ui, "collH1", "Collection", 43, "collCount", "")
	el.collEss = UiKit.flow(6, true)
	c_logo.add_child(el.collEss)
	el.collGrid = UiKit.grid(4, 6)
	el.collDetail = UiKit.vbox(8)
	el.collBack = ghost("Back")
	_screen(ui, "scr-coll", c_logo, [el.collGrid, el.collDetail, el.collBack], 0.62)

	# ---- shop
	var s_logo := logo(ui, "shopH1", "Item shop", 43, "", "Spend your loot")
	el.shopWallet = UiKit.flow(6, true)
	s_logo.add_child(el.shopWallet)
	el.shopBuy = UiKit.vbox(8)
	el.shopSell = UiKit.vbox(8)
	el.shopBack = ghost("Back")
	_screen(ui, "scr-shop", s_logo, [UiKit.eyebrow("Buy"), el.shopBuy, UiKit.eyebrow("Sell"), el.shopSell, el.shopBack], 0.70)

	# ---- end
	var e_logo := logo(ui, "endH", "Run over", 51, "endP", "")
	el.endStats = UiKit.grid(4, 8)
	el.endEss = UiKit.flow(6, true)
	el.endLoot = UiKit.flow(6, true)
	el.endParty = UiKit.hbox(8)
	el.againBtn = big("Run again")
	el.endShopBtn = ghost("Item shop")
	el.titleBtn = ghost("Title")
	var r2 := UiKit.hbox(8)
	for b in [el.endShopBtn, el.titleBtn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(b)
	_screen(ui, "scr-end", e_logo, [el.endStats, el.endEss, el.endLoot, el.endParty, el.againBtn, r2])

# ------------------------------------------------------------------ pack flip card

static func _flip(ui) -> Control:
	var card := Tap.new()
	card.press_scale = 1.0
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bx := Box.new(Vector2(150, 200))
	card.add_child(bx)
	# back: purple, "W", wiggling
	var back := Box.new(Vector2(150, 200))
	back.add_child(Box.fill(RRect.new({"radius": 16.0, "c0": Color("#7d5cff"), "c1": Color("#2a1a5e"), "angle": 160.0,
		"border_w": 2.0, "border_c": Color("#c8b4ff"), "glow": 30.0, "glow_c": Color(155 / 255.0, 123 / 255.0, 1, 0.5)})))
	var bv := UiKit.vbox(8)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_child(UiKit.lbl("W", "display", 56, Color.WHITE, {"align": "center", "shadow": Color("#24154f"), "shadow_off": Vector2(0, 3), "lh": -14}))
	bv.add_child(UiKit.lbl("Wildbound", "display", 16, Color("#e3d6ff"), {"align": "center"}))
	back.add_child(bv)
	back.pivot_offset = Vector2(75, 100)
	bx.add_child(Box.fill(back))
	# front: element card
	var front := Box.new(Vector2(150, 200))
	var fbg := RRect.new({"radius": 16.0, "angle": 170.0, "border_w": 2.0, "glow": 34.0})
	front.add_child(Box.fill(fbg))
	var fm := MarginContainer.new()
	fm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["left", "top", "right", "bottom"]:
		fm.add_theme_constant_override("margin_" + k, 12)
	var fv := UiKit.vbox(8)
	fv.alignment = BoxContainer.ALIGNMENT_CENTER
	fm.add_child(fv)
	front.add_child(Box.fill(fm))
	front.pivot_offset = Vector2(75, 100)
	bx.add_child(Box.fill(front))
	ui.el.packBack = back
	ui.el.packFrontFace = front
	ui.el.packFrontBg = fbg
	ui.el.packFront = fv
	return card

## Colour the front face (.flip --c).
static func flip_color(ui, c: Color) -> void:
	ui.el.packFrontBg.look({"c0": UiKit.mix(c, UiKit.DEEP2, 0.45), "c1": UiKit.DEEP, "border_c": c, "glow_c": UiKit.alpha(c, 0.8)})

## Closed (back showing, wiggling) or open (rotateY .6s cubic-bezier(.3,1.4,.5,1), as a 2D scale-x flip).
static func flip_set(ui, open: bool) -> void:
	var back: Control = ui.el.packBack
	var front: Control = ui.el.packFrontFace
	Fx.stop(back)
	Fx.stop(front)
	if not open:
		front.visible = false
		back.visible = true
		back.scale = Vector2.ONE
		back.modulate.a = 1.0
		Fx.kf(back, 1.2, [[0.0, {"r": 0.0, "s": 1.0}], [0.5, {"r": -2.0, "s": 1.03}], [1.0, {"r": 0.0, "s": 1.0}]],
			{"loop": "loop", "ease": [0.42, 0, 0.58, 1]})
		return
	back.rotation = 0
	Fx.kf(back, 0.22, [[0.0, {"sx": 1.0, "sy": 1.0}], [1.0, {"sx": 0.0, "sy": 1.0}]], {"ease": [0.4, 0.0, 1.0, 1.0],
		"done": func():
			back.visible = false
			front.visible = true
			Fx.kf(front, 0.45, [[0.0, {"sx": 0.0, "sy": 1.0}], [1.0, {"sx": 1.0, "sy": 1.0}]], {"ease": [0.3, 1.4, 0.5, 1.0]})})
