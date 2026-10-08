class_name UiScreens
## The static parts of the out-of-battle screens (index.html <section class="screen">): a logo/header
## band at the top and a bottom sheet, each registered in Ui.el by its TS id. Plus the shared button
## looks (.big, .big.alt, .ghostbtn, .metabtn) and the pack flip card.

const LOGO_SHADER := """
shader_type canvas_item;
uniform vec4 g0 : source_color = vec4(1.0, 0.973, 0.894, 1.0);
uniform vec4 g1 : source_color = vec4(0.949, 0.839, 0.549, 1.0);
uniform vec4 g2 : source_color = vec4(0.788, 0.635, 0.29, 1.0);
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

## .plaque: the primary action, a brass plaque with a pressed bottom edge. It is the only gold-filled
## shape on a screen, so use one per screen. `alt` = the smaller plaque used in rows and panels.
static func big(text: String, alt := false) -> Tap:
	var t := Tap.new()
	t.press_scale = 0.97
	t.dis_mod = Color(0.55, 0.55, 0.58)
	var bx := Box.new()
	bx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bx.custom_minimum_size.y = 40 if alt else 54
	t.add_child(bx)
	bx.add_child(Box.fill(RRect.new({"radius": 6.0, "c0": Color("#f6dc95"), "c1": Color("#d6a849"), "s1": 0.52, "c2": Color("#b0822c"),
		"angle": 180.0, "border_w": 1.0, "border_c": Color("#4d340c"), "sh_off": Vector2(0, 3), "sh_c": Color("#3c2908")})))
	# inset bevel: a light line under the top edge, a darker one above the bottom edge
	var bevel := Control.new()
	bevel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bevel.draw.connect(func():
		bevel.draw_rect(Rect2(3, 1, bevel.size.x - 6, 1), Color("#fff4cf"))
		bevel.draw_rect(Rect2(2, bevel.size.y - 3, bevel.size.x - 4, 2), Color("#8a6220")))
	bevel.resized.connect(bevel.queue_redraw)
	bx.add_child(Box.fill(bevel))
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := Vector4(10, 6, 10, 8) if alt else Vector4(16, 8, 16, 10)
	m.add_theme_constant_override("margin_left", int(pad.x))
	m.add_theme_constant_override("margin_top", int(pad.y))
	m.add_theme_constant_override("margin_right", int(pad.z))
	m.add_theme_constant_override("margin_bottom", int(pad.w))
	bx.add_child(Box.fill(m))
	var h := UiKit.hbox(6, BoxContainer.ALIGNMENT_CENTER)
	m.add_child(h)
	t.set_meta("row", h)
	t.set_meta("alt", alt)
	if alt:
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_big(t, text)
	return t

## Plaque text, with the optional small part (a cost, or why it is disabled).
static func set_big(t: Tap, text: String, small := "") -> void:
	var h: HBoxContainer = t.get_meta("row")
	UiKit.clear(h)
	var alt: bool = t.get_meta("alt")
	var ink := UiKit.PLAQUE_INK
	var l := UiKit.lbl(text, "display", UiKit.NAME if alt else UiKit.D_S, ink, {"valign": VERTICAL_ALIGNMENT_CENTER})
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	if small != "":
		var s := UiKit.lbl(small, "700", UiKit.T_S, ink, {"valign": VERTICAL_ALIGNMENT_CENTER})
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(s)

## .quiet: the secondary button, a brass hairline box with ink2 text (no caps, no tracking).
static func quiet(text: String) -> Tap:
	var t := Tap.new(UiKit.flat(Color(0, 0, 0, 0), 5, 1, UiKit.LINE, Vector4(14, 8, 14, 8)))
	t.custom_minimum_size.y = 40
	var l := UiKit.lbl(text, "700", UiKit.T_M, UiKit.INK2, {"align": "center", "valign": VERTICAL_ALIGNMENT_CENTER})
	t.add_child(l)
	t.set_meta("lbl", l)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t

## Old name for quiet().
static func ghost(text: String) -> Tap:
	return quiet(text)

## Title-screen tile (title + sub line), quiet-styled. `ready` = act now (pack ready): gold outline and glow.
static func meta_btn() -> Tap:
	var t := Tap.new()
	t.dis_mod = Color(1, 1, 1, 1)   # a waiting pack stays readable; its sub line says when
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(2)
	t.add_child(v)
	t.set_meta("v", v)
	set_meta_btn(t, "", "", false)
	return t

static func set_meta_btn(t: Tap, title: String, sub: String, ready := false) -> void:
	var pad := Vector4(10, 8, 10, 8)
	t.style = UiKit.act_style(pad) if ready else UiKit.flat(Color(0, 0, 0, 0.18), 5, 1, UiKit.LINE, pad)
	t.disabled = t.disabled
	var v: VBoxContainer = t.get_meta("v")
	UiKit.clear(v)
	v.add_child(UiKit.lbl(title, "display", UiKit.NAME, UiKit.INK, {"lh": -2}))
	v.add_child(UiKit.lbl(sub, "700", UiKit.T_S, UiKit.GOLD_HI if ready else UiKit.INK2, {"wrap": true, "lh": -3}))

static func row(a: Control, b: Control) -> HBoxContainer:
	var r := UiKit.hbox(8)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(a)
	r.add_child(b)
	return r

# ------------------------------------------------------------------ logo

## Screen title over the scene: the display face filled with a parchment-to-gold gradient and a dark
## brown drop shadow, with an optional sentence-case tagline in ink.
static func logo(ui, title_key: String, title: String, size: float, p_key: String, p_text: String) -> VBoxContainer:
	var v := UiKit.vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var h1 := UiKit.lbl(title, "display", int(size), Color.WHITE, {"align": "center", "shadow": UiKit.PLAQUE_INK,
		"shadow_off": Vector2(0, maxf(2.0, roundf(size / 14.0))), "outline": 2, "outline_c": UiKit.PLAQUE_INK, "lh": int(-size * 0.2)})
	if not _logo_shader:
		_logo_shader = Shader.new()
		_logo_shader.code = LOGO_SHADER
	var m := ShaderMaterial.new()
	m.shader = _logo_shader
	h1.material = m
	h1.resized.connect(func():
		var f: Font = h1.get_theme_font("font")
		var asc := f.get_ascent(int(size))
		m.set_shader_parameter("y0", (h1.size.y - f.get_height(int(size))) / 2.0 + asc * 0.2)
		m.set_shader_parameter("y1", (h1.size.y - f.get_height(int(size))) / 2.0 + asc * 1.0))
	h1.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(h1)
	ui.el[title_key] = h1
	if p_key != "" or p_text != "":
		var p := UiKit.lbl(p_text, "500", UiKit.T_L, UiKit.INK, {"align": "center", "wrap": true, "lh": -2})
		v.add_child(p)
		if p_key != "":
			ui.el[p_key] = p
	return v

# ------------------------------------------------------------------ screens

## Space between groups in a sheet (8 between related items, 16 inside windows, 24 between groups;
## sheets use 16 so the 375x667 phone keeps its stage).
const SHEET_GAP := 16
## Side gutter between the screen edge and a sheet or header.
const GUTTER := 12.0

## A screen in three zones: header (`top`, on a scrim), stage (the creature, between them; Layout keeps
## art out of the other two), sheet (`items` in one window at the bottom, scrolling past `frac` of the screen).
static func _screen(ui, id: String, top: Control, items: Array, frac := 0.68) -> void:
	var scr := Control.new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.root.add_child(scr)
	ui.screens[id] = scr
	if top:
		# header zone: a navy scrim behind the title so it reads over the bright diorama
		var scrim := UiKit.scrim()
		scrim.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		scr.add_child(scrim)
		top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		scr.add_child(top)
		top.item_rect_changed.connect(func():   # full strength down to the header's last line, then fade
			var hb := top.get_rect().end.y
			scrim.offset_bottom = hb + 44.0
			scrim.look({"s1": hb / (hb + 44.0)}))
	var outer := MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	outer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	scr.add_child(outer)
	# sheet zone: one window holds every control; groups inside it sit SHEET_GAP apart
	var inner := UiKit.win(16)
	inner.mouse_filter = Control.MOUSE_FILTER_STOP
	outer.add_child(inner)
	var vb := UiKit.vbox(SHEET_GAP)
	for it in items:
		vb.add_child(it)
	inner.add_child(CapScroll.new(vb, frac, 36))
	scr.set_meta("top", top)
	scr.set_meta("outer", outer)
	scr.set_meta("inner", inner)
	ui.band[id] = {"top": top, "bottom": outer}
	# content changes (a longer hint, a new row) move the band edges; keep the stage spots in step
	for n in [top, outer]:
		if n:
			n.resized.connect(func(): if ui.current == id: ui.measure())

## Re-apply safe-area padding and the 460px max width (on resize).
static func frame(ui, s: Dictionary) -> void:
	var side: float = s.side + GUTTER
	for id in ui.screens:
		var scr: Control = ui.screens[id]
		var top = scr.get_meta("top") if scr.has_meta("top") else null
		if top:
			top.offset_left = side
			top.offset_right = -side
			top.offset_top = 16.0 + s.top
		var outer: Control = scr.get_meta("outer")
		outer.offset_left = side
		outer.offset_right = -side
		outer.offset_bottom = -(12.0 + s.bottom)

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
	_title(ui)

	# ---- team
	# (no intro paragraph: the hint under the lineup says what a tap does, which keeps Done on screen)
	# header: title and the team count on one line, so the sheet stays short and the creature on the
	# stage stands near the front (a tall sheet pushes it up the screen, far back into the depth blur)
	# header: the title with the deck's element mix beside it, so the sheet stays short and the
	# creature on the stage stands near the front (a tall sheet pushes it up the screen, far back
	# into the depth blur)
	var tm_head := UiKit.hbox(6)
	var tm_h2 := UiKit.h2("Your team")
	tm_h2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tm_h2.autowrap_mode = TextServer.AUTOWRAP_OFF
	tm_head.add_child(tm_h2)
	el.teamMix = UiKit.hbox(4)
	el.teamMix.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tm_head.add_child(el.teamMix)
	el.teamOrder = UiKit.grid(3, 8)
	# under the lineup: a two-line hint (which slot the next tap fills)
	el.teamHint = UiKit.lbl("", "500", UiKit.T_S, UiKit.INK2, {"wrap": true, "lh": -2})
	el.teamHint.custom_minimum_size.y = 32
	var tm_info: Control = el.teamHint
	var starters := UiKit.grid(4, 6)
	el.starters = starters
	var st_m := MarginContainer.new()
	st_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["left", "right"]:
		st_m.add_theme_constant_override("margin_" + k, 2)
	st_m.add_theme_constant_override("margin_top", 2)
	st_m.add_theme_constant_override("margin_bottom", 2)
	st_m.add_child(starters)
	el.teamDone = big("Done")
	_screen(ui, "scr-team", null, [tm_head, el.teamOrder, tm_info, CapScroll.new(st_m, 0.2), el.teamDone], 0.74)

	# ---- map (UI-QUEUE item 8: a trail of medallions, one detail strip, party portraits, wallet row)
	var mtitle := _vbox_with(2, [_named(ui, "mapEyebrow", UiKit.eyebrow("Floor 1 of 8")),
		_named(ui, "mapTitle", UiKit.disp("Pick a path", UiKit.D_S))])
	mtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	el.lineupBtn = ghost("Lineup")
	el.mapQuit = ghost("Quit")
	var mhead := UiKit.hbox(8)
	for n in [mtitle, el.lineupBtn, el.mapQuit]:
		mhead.add_child(n)
	el.trail = MapTrail.new()
	# the detail strip: the selected medallion's name, element, what it pays, and Travel
	el.mapInfo = UiKit.panel(UiKit.inset(Vector4(12, 8, 8, 10)))
	var info := UiKit.vbox(4)
	el.mapInfoHead = UiKit.hbox(8)
	el.mapInfoSub = UiKit.lbl("", "500", 13, UiKit.INK2, {"wrap": true, "lh": -4})
	el.mapGo = big("Travel", true)
	el.mapGo.size_flags_horizontal = Control.SIZE_SHRINK_END
	var ihead := UiKit.hbox(8)
	el.mapInfoHead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ihead.add_child(el.mapInfoHead)
	ihead.add_child(el.mapGo)
	info.add_child(ihead)
	info.add_child(el.mapInfoSub)
	el.mapInfo.add_child(info)
	el.mapParty = UiKit.hbox(8)
	el.mapGold = UiKit.hbox(0)
	var mfoot := UiKit.hbox(8)
	el.mapParty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mfoot.add_child(el.mapParty)
	mfoot.add_child(el.mapGold)
	_screen(ui, "scr-map", null, [mhead, el.trail, el.mapInfo, mfoot], 0.74)

	# ---- reward (UI-QUEUE item 10): "Victory" and the loot ribbon sit on a band just above the sheet
	var rtitle := UiKit.hbox(8)
	var rt := _named(ui, "rwTitle", UiKit.disp("Choose a reward", UiKit.D_S))
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	el.rwPips = UiKit.hbox(6)
	el.rwPips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rtitle.add_child(rt)
	rtitle.add_child(el.rwPips)
	var rhead := _vbox_with(6, [rtitle, _named(ui, "rwSub", UiKit.lbl("", "500", 13, UiKit.INK2, {"wrap": true, "lh": -4}))])
	el.rewards = UiKit.grid(3, 10)
	el.rwDeck = UiKit.hbox(0)
	el.rwDeck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	el.skipBtn = ghost("Skip")
	_screen(ui, "scr-reward", null, [rhead, el.rewards, row(el.rwDeck, el.skipBtn)])
	var rw_rib := _ribbon(ui, "rwEyebrow", "rwSubLoot", "Victory")
	_above_sheet(ui, "scr-reward", rw_rib)

	# ---- upgrade
	var uhead := _vbox_with(6, [UiKit.eyebrow("Upgrade a card"), UiKit.h2("Pick a card"),
		UiKit.sub("Each card can be upgraded once. Card upgrades last for this run.")])
	el.upList = UiKit.vbox(12)
	el.upChoice = UiKit.panel(UiKit.inset(Vector4(12, 10, 12, 12), true))
	el.upChoiceBox = UiKit.vbox(8)
	el.upChoice.add_child(el.upChoiceBox)
	el.upChoice.visible = false
	el.upBack = ghost("Back")
	_screen(ui, "scr-upgrade", null, [uhead, el.upList, el.upChoice, row(UiKit.spacer(), el.upBack)], 0.82)

	# ---- party
	var phead := _vbox_with(6, [UiKit.eyebrow("Party"), UiKit.h2("Set your lineup"), _named(ui, "ptSub", UiKit.sub(""))])
	el.ptList = UiKit.rows()
	el.ptDone = big("Done")
	_screen(ui, "scr-party", null, [phead, el.ptList, el.ptDone], 0.82)

	# ---- pack (§11): three face-down cards; Run fills packChoices with flip_card()s
	var pk_logo := logo(ui, "packH1", "Daily pack", UiKit.D_L, "packP", "Pick one to keep")
	el.packChoices = UiKit.hbox(8)
	el.packChoices.custom_minimum_size.y = PACK_CARD_H
	el.packTxt = UiKit.vbox(6)
	el.packTxt.custom_minimum_size.y = 40   # one or two lines, so the sheet doesn't jump after the pick
	el.packOk = big("Nice!")
	_screen(ui, "scr-pack", pk_logo, [el.packChoices, el.packTxt, el.packOk])

	# ---- collection (idea 9: a bestiary)
	_coll(ui)

	# ---- shop
	var s_logo := logo(ui, "shopH1", "Item shop", UiKit.D_L, "", "Spend your loot")
	el.shopWallet = UiKit.flow(6, true)
	s_logo.add_child(el.shopWallet)
	el.shopBuy = UiKit.rows()
	el.shopSell = UiKit.rows()
	el.shopBack = ghost("Back")
	_screen(ui, "scr-shop", s_logo, [_vbox_with(4, [UiKit.eyebrow("Buy"), el.shopBuy]), _vbox_with(4, [UiKit.eyebrow("Sell"), el.shopSell]), el.shopBack], 0.70)

	# ---- end (UI-QUEUE item 10): big pixel numbers, the run's loot ribbon, the party, Run again
	var e_logo := logo(ui, "endH", "Run over", UiKit.D_L, "endP", "")
	el.endStats = UiKit.grid(4, 4)
	el.endEss = UiKit.flow(6, true)   # kept for callers; the ribbon (endLoot) now carries the Essence too
	el.endEss.visible = false
	var e_rib := Box.new()
	e_rib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e_rib.add_child(Box.fill(UiKit.ribbon_band()))
	var e_pad := MarginContainer.new()
	e_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	e_pad.add_theme_constant_override("margin_top", 10)
	e_pad.add_theme_constant_override("margin_bottom", 10)
	el.endLoot = UiKit.flow(8, true)
	e_pad.add_child(_vbox_with(8, [_named(ui, "endLootH", UiKit.lbl("Loot banked", "700", UiKit.T_S, UiKit.GOLD_HI, {"align": "center"})), el.endLoot]))
	e_rib.add_child(Box.fill(e_pad))
	el.endRibbon = e_rib
	# the pack meter: this run's points filling the bar (Run animates it), and Open when a pack was earned
	el.endPack = UiKit.vbox(6)
	var ph := UiKit.hbox(8)
	ph.add_child(UiKit.icon("pack", 16, UiKit.GOLD_HI))
	var pl := UiKit.lbl("Pack meter", "700", UiKit.T_S, UiKit.GOLD_HI, {"valign": VERTICAL_ALIGNMENT_CENTER})
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(pl)
	el.endPackGain = UiKit.lbl("", "700", UiKit.T_S, UiKit.INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
	el.endPackGain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	el.endPackGain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(el.endPackGain)
	# under it, the bar with "18 to go" (or "Pack earned!") at its right
	el.endPackBar = UiKit.fill_bar(10.0)
	el.endPackBar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	el.endPackTo = UiKit.lbl("", "700", UiKit.T_S, UiKit.INK2, {"valign": VERTICAL_ALIGNMENT_CENTER, "align": "right"})
	el.endPackTo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	el.endPackTo.custom_minimum_size.x = 104   # the bar keeps its width while the text changes
	var pb := UiKit.hbox(8)
	pb.add_child(el.endPackBar)
	pb.add_child(el.endPackTo)
	var pv: VBoxContainer = el.endPack
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pv.add_child(ph)
	pv.add_child(pb)
	el.endPackOpen = quiet("Open pack")
	el.endPackOpen.visible = false
	el.endPackRow = UiKit.hbox(12)
	el.endPackRow.add_child(pv)
	el.endPackRow.add_child(el.endPackOpen)
	el.endParty = UiKit.hbox(12, BoxContainer.ALIGNMENT_CENTER)
	el.againBtn = big("Run again")
	el.endShopBtn = ghost("Item shop")
	el.titleBtn = ghost("Title")
	var r2 := UiKit.hbox(8)
	for b in [el.endShopBtn, el.titleBtn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(b)
	_screen(ui, "scr-end", e_logo, [el.endStats, e_rib, el.endPackRow, el.endParty, el.againBtn, r2], 0.74)

# ------------------------------------------------------------------ reward ribbon

## A display title over a loot row on a ribbon band (mockup idea 10). Registers the title as `title_key`
## and the loot row (a centred flow, filled by Run) as `loot_key`.
static func _ribbon(ui, title_key: String, loot_key: String, title: String) -> Box:
	var b := Box.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(Box.fill(UiKit.ribbon_band()))
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 10)
	for k in ["left", "right"]:
		m.add_theme_constant_override("margin_" + k, 16)
	var h := UiKit.disp(title, UiKit.D_M, UiKit.INK, {"align": "center", "shadow": UiKit.PLAQUE_INK, "shadow_off": Vector2(0, 3)})
	ui.el[title_key] = h
	var loot := UiKit.flow(8, true)
	ui.el[loot_key] = loot
	m.add_child(_vbox_with(8, [h, loot]))
	b.add_child(Box.fill(m))
	return b

## Pin `c` just above the sheet window (same width, 12px gap) and make it the band's bottom edge, so
## the stage (and the creature) ends above it.
static func _above_sheet(ui, id: String, c: Control) -> void:
	var scr: Control = ui.screens[id]
	var outer: Control = scr.get_meta("outer")
	scr.add_child(c)
	var pin := func():
		var r := outer.get_rect()
		var h := c.get_combined_minimum_size().y
		c.position = Vector2(r.position.x, r.position.y - h - 12.0)
		c.size = Vector2(r.size.x, h)
	outer.item_rect_changed.connect(pin)
	c.minimum_size_changed.connect(pin)
	ui.band[id].bottom = c
	c.resized.connect(func(): if ui.current == id: ui.measure())

# ------------------------------------------------------------------ title (idea 8)

## The title as a diorama: the logo on the header scrim, the lead creature alone on the stage, and at
## the bottom the team (a tappable pill of portraits, the lead's name and the best run) over the one
## brass plaque, then a four-icon dock (Team, Daily pack, Collection, Item shop). No sheet window: the
## bottom group is the "sheet" zone for Layout and the UI check, so the creature stays above it.
static func _title(ui) -> void:
	var el: Dictionary = ui.el
	var id := "scr-title"
	var scr := Control.new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.root.add_child(scr)
	ui.screens[id] = scr
	var top := logo(ui, "titleH1", "Wildbound", 55, "titleP", "Collect creatures. Deal cards. Survive.")
	var scrim := UiKit.scrim()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	scr.add_child(scrim)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	scr.add_child(top)
	top.item_rect_changed.connect(func():
		var hb := top.get_rect().end.y
		scrim.offset_bottom = hb + 44.0
		scrim.look({"s1": hb / (hb + 44.0)}))
	# a soft navy fade under the dock and plaque, so the bottom group sits on the scene, not in a box
	var floor_fade := RRect.new({"radius": 0.0, "angle": 0.0, "c0": UiKit.alpha(UiKit.SCRIM, 0.7), "c1": UiKit.alpha(UiKit.SCRIM, 0.35),
		"s1": 0.55, "c2": UiKit.alpha(UiKit.SCRIM, 0.0)})
	floor_fade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	scr.add_child(floor_fade)

	# the team pill: overlapping portraits, "Emberwick leads", the best run; tap = the Team screen
	el.teamBtn = Tap.new(UiKit.flat(UiKit.alpha(UiKit.NAVY2, 0.82), 22, 1, UiKit.HAIR, Vector4(8, 6, 16, 6)))
	el.teamBtn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pill := UiKit.hbox(10)
	el.teamRow = UiKit.hbox(-6)
	el.teamRow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_child(el.teamRow)
	var tv := UiKit.vbox(0)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	el.pickEyebrow = UiKit.lbl("", "700", UiKit.T_M, UiKit.INK)
	el.bestT = UiKit.lbl("", "500", UiKit.T_S, UiKit.INK2)
	tv.add_child(el.pickEyebrow)
	tv.add_child(el.bestT)
	pill.add_child(tv)
	el.teamBtn.add_child(pill)

	el.startBtn = big("Start expedition")
	# the dock: one window split by hairlines into four icon cells
	var dock := UiKit.win(0, false)
	dock.mouse_filter = Control.MOUSE_FILTER_STOP
	var cells := UiKit.hbox(0)
	dock.add_child(cells)
	for x in [["dockTeam", "team"], ["packBtn", "pack"], ["collBtn", "book"], ["shopBtn", "bag"]]:
		var t := dock_cell(x[1])
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.set_meta("divider", cells.get_child_count() > 0)
		el[x[0]] = t
		cells.add_child(t)

	var inner := UiKit.vbox(12)
	inner.add_child(el.teamBtn)
	inner.add_child(el.startBtn)
	inner.add_child(_pad(dock, 4))
	var outer := MarginContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	outer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	outer.add_child(inner)
	scr.add_child(outer)
	outer.item_rect_changed.connect(func(): floor_fade.offset_top = outer.get_rect().position.y - scr.size.y + 40.0)
	scr.set_meta("top", top)
	scr.set_meta("outer", outer)
	scr.set_meta("inner", inner)
	ui.band[id] = {"top": top, "bottom": outer}
	for n in [top, outer]:
		n.resized.connect(func(): if ui.current == id: ui.measure())

static func _pad(c: Control, top: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_top", top)
	m.add_child(c)
	return m

## A dock cell: icon over a label and a sub line (a count, a price, "Ready"). Fill it with set_dock_cell.
static func dock_cell(glyph: String) -> Tap:
	var t := Tap.new(UiKit.flat(Color(0, 0, 0, 0), 0, 0, Color(), Vector4(4, 10, 4, 10)))
	t.dis_mod = Color(1, 1, 1, 1)   # a waiting pack stays readable; its sub line says when
	t.set_meta("glyph", glyph)
	var b := Box.new()
	t.add_child(b)
	var v := UiKit.vbox(2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(v)
	t.set_meta("v", v)
	t.set_meta("box", b)
	# hairline on the left edge between cells (drawn inside the cell, so nothing spills)
	t.draw.connect(func(): if t.get_meta("divider", false): t.draw_rect(Rect2(0, 10, 1, t.size.y - 20), UiKit.HAIR))
	set_dock_cell(t, "", "", false, false)
	return t

## `ready` = act now (pack ready): gold icon and label plus a glowing gold dot; `dim` = waiting (muted icon).
static func set_dock_cell(t: Tap, label: String, sub: String, ready := false, dim := false) -> void:
	var v: VBoxContainer = t.get_meta("v")
	var b: Box = t.get_meta("box")
	UiKit.clear(v)
	for c in b.get_children():
		if c != v:
			b.remove_child(c)
			c.queue_free()
	var ic := UiKit.icon(t.get_meta("glyph"), 24, UiKit.GOLD_HI if ready else (UiKit.MUTE if dim else UiKit.INK))
	v.add_child(ic)
	v.add_child(UiKit.lbl(label, "700", UiKit.T_S, UiKit.GOLD_HI if ready else UiKit.INK, {"align": "center"}))
	v.add_child(UiKit.lbl(sub, "500", UiKit.T_S, UiKit.GOLD_HI if ready else UiKit.INK2, {"align": "center"}))
	if ready:   # the gold dot sits at the icon's upper right, inside the cell
		var dot := Control.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.custom_minimum_size = Vector2(16, 16)
		dot.draw.connect(func():
			dot.draw_circle(Vector2(8, 8), 7.0, UiKit.alpha(Color("#ffcf5a"), 0.3))
			dot.draw_circle(Vector2(8, 8), 4.5, Color("#ffcf5a")))
		Fx.kf(dot, 0.9, [[0.0, {"a": 0.55}], [1.0, {"a": 1.0}]], {"loop": "alternate"})
		var vh := v.get_combined_minimum_size().y
		dot.set_meta("off", Vector2(21, -vh / 2.0 + 8.0))   # Box centres it, then nudges it to the icon's corner
		b.add_child(dot)

# ------------------------------------------------------------------ collection (idea 9)

## The Collection as a bestiary: a compact header (title, how many found, Essence), a framed specimen
## window over the stage band where the selected creature stands (so it never meets the header), and
## one sheet with the six-wide portrait grid and the detail panel (name, tabs, tab body).
static func _coll(ui) -> void:
	var el: Dictionary = ui.el
	# header: the title with Back at its right (Back lives up here so the sheet leaves the specimen
	# window room), then how many are found with the Essence chips at the right
	var head := UiKit.vbox(4)
	var r1 := UiKit.hbox(12)
	var h1 := _named(ui, "collH1", UiKit.disp("Collection", UiKit.D_M, UiKit.INK, {"shadow": UiKit.PLAQUE_INK, "shadow_off": Vector2(0, 3)}))
	h1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(h1)
	el.collBack = ghost("Back")
	el.collBack.mouse_filter = Control.MOUSE_FILTER_STOP
	r1.add_child(el.collBack)
	head.add_child(r1)
	var r2 := UiKit.hbox(12)
	var cnt := _named(ui, "collCount", UiKit.lbl("", "500", UiKit.T_M, UiKit.INK))
	cnt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r2.add_child(cnt)
	el.collEss = UiKit.hbox(4)
	r2.add_child(el.collEss)
	head.add_child(r2)
	el.collGrid = UiKit.grid(6, 8)
	el.collDetail = UiKit.vbox(12)
	_screen(ui, "scr-coll", head, [el.collGrid, el.collDetail], 0.74)
	var scr: Control = ui.screens["scr-coll"]
	var outer: Control = scr.get_meta("outer")
	# the specimen window: a glassless frame over the stage band (Layout keeps the creature inside it)
	var spec := Box.new()
	spec.add_child(Box.fill(UiKit.panel(UiKit.window_frame())))
	el.collSpecChip = UiKit.hbox(0)
	spec.add_child(Box.at(el.collSpecChip, "bl", Vector2(10, 10)))
	scr.add_child(spec)
	scr.move_child(spec, 1)   # above the header scrim, under the header and sheet
	el.collSpec = spec
	var fit := func():
		var t := head.get_rect().end.y + 8.0
		var b := outer.get_rect().position.y - 8.0
		spec.position = Vector2(outer.offset_left, t)
		spec.size = Vector2(scr.size.x - outer.offset_left + outer.offset_right, maxf(b - t, 0.0))
		spec.visible = b - t + 16.0 >= Layout.MIN_ROOM
	for n in [head, outer, scr]:
		n.item_rect_changed.connect(fit)

# ------------------------------------------------------------------ pack flip cards

## Height of a pack choice card (three sit side by side in the sheet).
const PACK_CARD_H := 168.0

## One pack choice: a face-down card (navy glass, brass frame, a gold "W") over a face-up one whose
## content goes in meta "fv" (a centred VBox). flip_tint colours the front; flip_open turns it over.
## The whole card is the Tap; its meta "card" is the Box to fade or pop (Tap owns its own modulate).
static func flip_card() -> Tap:
	var t := Tap.new()
	t.press_scale = 0.97
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bx := Box.new()
	bx.custom_minimum_size.y = PACK_CARD_H
	t.add_child(bx)
	# back: navy glass in a brass frame, a gold "W"
	var back := Box.new()
	back.add_child(Box.fill(RRect.new({"radius": 7.0, "c0": UiKit.DEEP2, "c1": UiKit.NAVY2, "angle": 160.0,
		"border_w": 2.0, "border_c": UiKit.BRASS, "glow": 16.0, "glow_c": UiKit.alpha(UiKit.GOLD_HI, 0.2)})))
	var bm := MarginContainer.new()
	bm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["left", "top", "right", "bottom"]:
		bm.add_theme_constant_override("margin_" + k, 6)
	bm.add_child(RRect.new({"radius": 4.0, "c0": Color(0, 0, 0, 0), "c1": Color(0, 0, 0, 0), "border_w": 1.0,
		"border_c": UiKit.alpha(UiKit.BRASS, 0.4)}))
	back.add_child(Box.fill(bm))
	back.add_child(UiKit.lbl("W", "display", 44, UiKit.GOLD_HI, {"align": "center", "shadow": UiKit.PLAQUE_INK, "shadow_off": Vector2(0, 3), "lh": -10}))
	bx.add_child(Box.fill(back))
	# front: the creature, tinted in its element
	var front := Box.new()
	var fbg := RRect.new({"radius": 7.0, "angle": 170.0, "border_w": 2.0, "glow": 18.0})
	front.add_child(Box.fill(fbg))
	var fm := MarginContainer.new()
	fm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["left", "right"]:
		fm.add_theme_constant_override("margin_" + k, 6)
	for k in ["top", "bottom"]:
		fm.add_theme_constant_override("margin_" + k, 10)
	var fv := UiKit.vbox(4)
	fv.alignment = BoxContainer.ALIGNMENT_CENTER
	fm.add_child(fv)
	front.add_child(Box.fill(fm))
	front.visible = false
	bx.add_child(Box.fill(front))
	t.set_meta("card", bx)
	t.set_meta("back", back)
	t.set_meta("front", front)
	t.set_meta("bg", fbg)
	t.set_meta("fv", fv)
	t.resized.connect(func():
		for n in [bx, back, front]:
			n.pivot_offset = t.size / 2.0)
	return t

## Colour a flip card's front in `c` (`sel` = the kept card: a gold border).
static func flip_tint(t: Tap, c: Color, sel := false) -> void:
	(t.get_meta("bg") as RRect).look({"c0": UiKit.mix(c, UiKit.DEEP2, 0.5), "c1": UiKit.DEEP, "border_c": UiKit.GOLD_HI if sel else c,
		"glow_c": UiKit.alpha(UiKit.GOLD_HI if sel else c, 0.75 if sel else 0.45)})

## Face down (gently bobbing) or face up. `animate` = false turns it over at once (screenshots, resume).
static func flip_open(t: Tap, open: bool, animate := true) -> void:
	var back: Control = t.get_meta("back")
	var front: Control = t.get_meta("front")
	Fx.stop(back)
	Fx.stop(front)
	back.scale = Vector2.ONE
	front.scale = Vector2.ONE
	back.rotation = 0
	if not open:
		front.visible = false
		back.visible = true
		Fx.kf(back, 1.4, [[0.0, {"s": 1.0}], [0.5, {"s": 1.025}], [1.0, {"s": 1.0}]], {"loop": "loop", "ease": [0.42, 0, 0.58, 1]})
		return
	if not animate:
		back.visible = false
		front.visible = true
		return
	Fx.kf(back, 0.18, [[0.0, {"sx": 1.0, "sy": 1.0}], [1.0, {"sx": 0.0, "sy": 1.0}]], {"ease": [0.4, 0.0, 1.0, 1.0],
		"done": func():
			back.visible = false
			front.visible = true
			Fx.kf(front, 0.4, [[0.0, {"sx": 0.0, "sy": 1.0}], [1.0, {"sx": 1.0, "sy": 1.0}]], {"ease": [0.3, 1.4, 0.5, 1.0]})})
