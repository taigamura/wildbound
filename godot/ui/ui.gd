extends Node
## Battle HUD, the card hand and the screen frames (TS game/ui.ts + index.html + style.css).
## Reads state, never changes game rules. Screens' static parts are built by ui/screens.gd into `el`
## (TS $('#id') → Ui.el["id"]); game/run.gd fills them.

# hand: touch magnifies, slide sideways to scrub the fan, swipe up to play
const FLICK_DIST := 0.4   # swiped up more than this × card height → plays on release
const FLICK_VEL := 0.6    # or released moving up faster than this (px/ms)...
const FLICK_MIN := 0.15   # ...after at least this × card height of travel
const LIFT_LOCK := 0.12   # upward travel (× card height, and more up than sideways) that commits the swipe and locks the card
const SCRUB_HYST := 0.22  # × card width a neighbour must be closer than the magnified card before the magnifier moves
const FAN_DEG := 8.0      # rotation per step from the centre (4 cards → ±4°, ±12°)
const FAN_DROP := 0.06    # × card width × step² that outer cards sit lower
const HELD_LIFT := 12.0   # px the held card rises out of the fan (the preview does the magnifying)
const PREVIEW_K := 2.0    # hold preview width × card width (shrinks to fit the stage)

const SCREENS := ["scr-title", "scr-team", "scr-map", "scr-reward", "scr-upgrade", "scr-party", "scr-end", "scr-pack", "scr-coll", "scr-shop"]

var layer := CanvasLayer.new()
var root := Control.new()
var el := {}            # named elements (index.html ids)
var screens := {}       # id → Control
var band := {}          # id → {"top": Control or null, "bottom": Control}
var slots: Array = []   # the 4 HandSlots (TS slots)
var hud: Control
var hud_top: VBoxContainer
var hud_bottom: VBoxContainer
var hand: Control
var preview := CardView.new("hand")   # the held card, large, on the stage
var heavy: Control   # the heavy banner (BannerBg) in the telegraph strip under the enemy plate
var chain: Control
var current = null      # shown screen id, or null for the battle HUD

var _h := {}
var _sel := -1
var _sel_ref = null
var _pv_sel := -1
var _laid_q := false
var _drag = null
var _last_stat := ""
var _measure_frames := 0
var _measure_snap := false
var _cw := 80.0
var _chain_k := ""
var _heavy_k := ""
var _heavy_now := false
var _chain_exp := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 10
	add_child(layer)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.add_child(root)
	_build_hud()
	UiScreens.build(self)
	for id in SCREENS:
		screens[id].visible = false
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()

# ================================================================== frame & band

## Insets: TS env(safe-area-inset-*) plus a max content width of 460px.
func safe() -> Dictionary:
	var vp := root.get_viewport_rect().size
	var top := 0.0
	var bottom := 0.0
	var win := DisplayServer.window_get_size()
	var sa := DisplayServer.get_display_safe_area()
	if win.y > 0 and sa.size.y > 0 and OS.has_feature("mobile"):
		var k := vp.y / float(win.y)
		top = sa.position.y * k
		bottom = maxf(0.0, (win.y - sa.end.y) * k)
	if Platform.safe_insets.x >= 0.0:
		top = Platform.safe_insets.x
		bottom = Platform.safe_insets.y
	return {"top": top, "bottom": bottom, "side": maxf(0.0, (vp.x - 460.0) / 2.0)}

func _on_resize() -> void:
	var vp := root.get_viewport_rect().size
	var s := safe()
	var side: float = s.side + 14.0
	hud_top.offset_left = side
	hud_top.offset_right = -side
	hud_top.offset_top = 10.0 + s.top
	hud_bottom.offset_left = side
	hud_bottom.offset_right = -side
	hud_bottom.offset_bottom = -(12.0 + s.bottom)
	UiScreens.frame(self, s)
	# hand: --cw: clamp(70px, min(100vw - 28px, 460px) × .235, 88px), aspect 3/4, height cw × 1.48
	_cw = clampf(minf(vp.x - 28.0, 460.0) * 0.235, 70.0, 88.0)
	hand.custom_minimum_size.y = round(_cw * 1.48)
	for b in slots:
		b.set_card_size(Vector2(_cw, round(_cw * 4.0 / 3.0)))
	_queue_layout()
	measure(true)

## Ask for a band re-measure once layout has settled (TS measureBand after rAF). `snap` jumps the stage.
func measure(snap := false) -> void:
	_measure_frames = 2
	_measure_snap = _measure_snap or snap

func _do_measure() -> void:
	var vp := root.get_viewport_rect().size
	var top := 0.0
	var bot := vp.y
	if current == null and hud.visible:
		top = hud_top.get_global_rect().end.y
		bot = hud_bottom.get_global_rect().position.y
	elif current != null and band.has(current):
		var b: Dictionary = band[current]
		if b.top and b.top.visible:
			top = b.top.get_global_rect().end.y
		if b.bottom and b.bottom.visible:
			bot = b.bottom.get_global_rect().position.y
	if Layout.has_method("measure_band"):
		Layout.measure_band(top, bot, _measure_snap)

func _process(_dt: float) -> void:
	if _measure_frames > 0:
		_measure_frames -= 1
		_do_measure()
		if _measure_frames == 0:
			_measure_snap = false

# ================================================================== HUD

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)

	# ---- top band (UI-QUEUE item 5): floor pill + mute + quit, the one-line enemy plate, and the
	# telegraph strip under it. The strip is always reserved (part of the band), so the heavy banner
	# it holds never covers the creatures and the stage doesn't jump when a heavy starts.
	hud_top = UiKit.vbox(8)
	hud_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.add_child(hud_top)
	var meta := UiKit.hbox(8)
	hud_top.add_child(meta)
	var pill := UiKit.panel(UiKit.hud_btn_style(14, Vector4(12, 0, 12, 0)))
	pill.custom_minimum_size.y = 28
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ph := UiKit.hbox(5)
	ph.add_child(UiKit.lbl("Floor", "700", UiKit.T_S, UiKit.INK2, {"valign": VERTICAL_ALIGNMENT_CENTER}))
	el.floorT = UiKit.lbl("1/8", "700", UiKit.T_S, UiKit.INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
	ph.add_child(el.floorT)
	pill.add_child(ph)
	meta.add_child(pill)
	meta.add_child(UiKit.spacer())
	var mute := Tap.new(UiKit.hud_btn_style(8))
	mute.custom_minimum_size = Vector2(34, 32)
	mute.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	el.muteIcon = UiKit.icon("sound", 16, UiKit.INK2)
	mute.add_child(el.muteIcon)
	mute.pressed.connect(func():
		Sfx.set_muted(not Sfx.is_muted())
		paint_mute()
		Sfx.audio())
	el.muteBtn = mute
	meta.add_child(mute)
	# quit (no pause): the first tap arms it, the second ends the run (Run.quit_tap)
	var quit := Tap.new(UiKit.hud_btn_style(8))
	quit.custom_minimum_size = Vector2(34, 32)
	quit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quit.add_child(UiKit.icon("exit", 16, UiKit.INK2))
	quit.pressed.connect(func(): Run.quit_tap(quit))
	el.quitBtn = quit
	meta.add_child(quit)

	# enemy plate: intent ring | name, statuses, element chip / HP bar + number
	var pst := UiKit.window(0, false)
	pst.content_margin_left = 10
	pst.content_margin_right = 12
	pst.content_margin_top = 8
	pst.content_margin_bottom = 8
	var foe := UiKit.panel(pst)
	hud_top.add_child(foe)
	var fh := UiKit.hbox(10)
	foe.add_child(fh)
	el.eRing = IntentRing.new()
	fh.add_child(el.eRing)
	var fv := UiKit.vbox(4)
	fv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(fv)
	var nr := UiKit.hbox(6)
	nr.custom_minimum_size.y = 22
	fv.add_child(nr)
	el.eName = UiKit.lbl("", "display", UiKit.NAME, UiKit.INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
	nr.add_child(el.eName)
	el.eStat = UiKit.hbox(4)   # Burn/Soak/Root, Shock immune, Shifts in, Heavy next: as many as fit
	el.eStat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nr.add_child(el.eStat)
	el.eEl = UiKit.hbox(0)
	el.eEl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nr.add_child(el.eEl)
	var hr := UiKit.hbox(8)
	fv.add_child(hr)
	el.eHp = Bar.new(false, Color("#ff8a97"), UiKit.FOE, false)
	el.eHp.custom_minimum_size.y = 10
	el.eHp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	el.eHp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(el.eHp)
	el.eHpN = UiKit.lbl("", "700", UiKit.T_S, UiKit.INK, {"align": "right", "valign": VERTICAL_ALIGNMENT_CENTER})
	el.eHpN.custom_minimum_size.x = 56
	hr.add_child(el.eHpN)

	# telegraph strip: the heavy banner (attack name, element, seconds left, who resists)
	var strip := Control.new()
	strip.custom_minimum_size.y = 32
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_top.add_child(strip)
	heavy = BannerBg.new()
	heavy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	heavy.offset_left = 10
	heavy.offset_right = -10
	heavy.visible = false
	strip.add_child(heavy)
	var hb := UiKit.hbox(8, BoxContainer.ALIGNMENT_CENTER)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	heavy.add_child(hb)
	el.heavyIcon = UiKit.icon("ember", 18)
	el.heavyIcon.pivot_offset = Vector2(9, 9)
	hb.add_child(el.heavyIcon)
	el.heavyName = UiKit.lbl("", "display", UiKit.D_S, UiKit.INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
	hb.add_child(el.heavyName)
	el.heavySecs = UiKit.lbl("", "700", UiKit.T_M, UiKit.INK, {"align": "right", "valign": VERTICAL_ALIGNMENT_CENTER})
	el.heavySecs.custom_minimum_size.x = 30   # fixed, so the line doesn't shift as the seconds tick
	hb.add_child(el.heavySecs)
	el.heavySub = UiKit.lbl("", "500", UiKit.T_M, UiKit.INK2, {"valign": VERTICAL_ALIGNMENT_CENTER})
	hb.add_child(el.heavySub)

	# ---- bottom band: the party rail (lead | bench), then the energy crystal beside the hand
	hud_bottom = UiKit.vbox(8)
	hud_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hud_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.add_child(hud_bottom)
	var rst := UiKit.window(0, false)
	rst.content_margin_left = 10
	rst.content_margin_right = 10
	rst.content_margin_top = 8
	rst.content_margin_bottom = 8
	var rail := UiKit.panel(rst)
	hud_bottom.add_child(rail)
	var rh := UiKit.hbox(10)
	rail.add_child(rh)
	el.pPor = UiKit.hbox(0)
	el.pPor.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(el.pPor)
	var pv := UiKit.vbox(3)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(pv)
	var pn := UiKit.hbox(6)
	pv.add_child(pn)
	el.pName = UiKit.lbl("", "display", UiKit.NAME, UiKit.INK, {"ellipsis": true, "valign": VERTICAL_ALIGNMENT_CENTER})
	el.pName.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pn.add_child(el.pName)
	el.pHpN = UiKit.lbl("", "700", UiKit.T_S, UiKit.INK, {"align": "right", "valign": VERTICAL_ALIGNMENT_CENTER})
	pn.add_child(el.pHpN)
	el.pHp = Bar.new(false, Color("#a8ffc6"), UiKit.HP, false)
	el.pHp.custom_minimum_size.y = 10
	pv.add_child(el.pHp)
	var pt := UiKit.hbox(6)
	pt.custom_minimum_size.y = 20
	pv.add_child(pt)
	el.pTrait = UiKit.lbl("", "700", UiKit.T_S, UiKit.GOLD_HI, {"valign": VERTICAL_ALIGNMENT_CENTER})
	pt.add_child(el.pTrait)
	el.pStat = UiKit.hbox(4)   # the lead's status, discount, reflect, next Strike, matchup: as many as fit
	el.pStat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pt.add_child(el.pStat)
	el.railSep = ColorRect.new()
	el.railSep.color = UiKit.HAIR
	el.railSep.custom_minimum_size = Vector2(1, 44)
	el.railSep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	el.railSep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rh.add_child(el.railSep)
	el.bench = UiKit.hbox(6)
	el.bench.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(el.bench)

	var hrow := UiKit.hbox(2)
	hud_bottom.add_child(hrow)
	el.energy = Crystal.new()
	hrow.add_child(el.energy)
	hand = Control.new()
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand.resized.connect(_hand_resized)
	hrow.add_child(hand)
	var tail := Control.new()   # keeps the fanned, tilted outer card (and its neighbour's nudge) on screen
	tail.custom_minimum_size.x = 8
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(tail)
	for i in Data.BAL.hand:
		var b := HandSlot.new(i)
		b.gui_input.connect(_slot_input.bind(i))
		hand.add_child(b)
		slots.append(b)
	preview.visible = false
	hud.add_child(preview)

	# ---- pinned over the world: the chain counter beside the lead (outside #hud in TS)
	chain = UiKit.vbox(0)
	chain.alignment = BoxContainer.ALIGNMENT_CENTER
	chain.size = Vector2(64, 0)
	chain.visible = false
	el.chainN = UiKit.lbl("", "display", UiKit.D_M, UiKit.GOLD_HI, {"align": "center", "shadow": Color.BLACK, "shadow_off": Vector2(0, 2),
		"outline": 5, "outline_c": Color(0.04, 0.06, 0.14, 0.75), "lh": -8})
	chain.add_child(el.chainN)
	el.chainS = UiKit.lbl("", "700", UiKit.T_S, UiKit.GOLD_HI, {"align": "center", "shadow": Color.BLACK, "shadow_off": Vector2(0, 1),
		"outline": 4, "outline_c": Color(0.04, 0.06, 0.14, 0.75), "lh": -6})
	chain.add_child(el.chainS)
	root.add_child(chain)

func paint_mute() -> void:
	el.muteIcon.texture = Glyphs.tex("mute" if Sfx.is_muted() else "sound")

func init_hud(h: Dictionary) -> void:
	_h = h
	if Battle.has_signal("card_played"):
		Battle.card_played.connect(_on_card_played)
	if Battle.has_signal("card_denied"):
		Battle.card_denied.connect(_on_card_denied)
	if Battle.has_signal("card_discarded"):
		Battle.card_discarded.connect(_on_card_discarded)
	paint_mute()

## Show a screen by id ("scr-title"...), or the battle HUD with null.
func show(id) -> void:
	var was = current
	current = id
	for s in SCREENS:
		var on: bool = s == id
		if on and not screens[s].visible:
			UiScreens.sheet_in(self, s)
		screens[s].visible = on
	hud.visible = id == null
	preview.visible = false
	_pv_sel = -1
	chain.visible = false
	heavy.visible = false
	if id == null and was != null:
		# a fresh battle: forget the last fight's flying cards and inspection
		_sel = -1
		_drag = null
		for b in slots:
			b.playing = false
			b.flown = false
			b.dragging = false
			Fx.stop(b.face)
			_reset_face(b)
			b.face.key = ""
		_last_stat = ""
		_deal_all.call_deferred()
	measure(false)

func _deal_all() -> void:
	for b in slots:
		if not b.face.empty:
			_deal(b, b.i * 0.06)

# ================================================================== cards

## TS cardFace: a card Control for screens (reward/upgrade/collection). o as CardView.face.
func card_face(def: Dictionary, el_key, o := {}, variant := "mini") -> CardView:
	return CardView.new(variant).face(def, el_key, o)

## TS drawInto's repaint: the slot stops flying, shows S.hand[i] and deals it in.
func paint_card(i: int) -> void:
	var b: HandSlot = slots[i]
	b.playing = false
	Fx.stop(b.face)
	_reset_face(b)
	_paint(i)
	if S.hand[i] != null and not b.face.empty:
		_deal(b, 0.0)

## Deal-in animation on slot i (exposed for Battle; show(null) deals the opening hand itself).
func deal(i: int, delay := 0.0) -> void:
	_deal(slots[i], delay)

func _deal(b: HandSlot, delay: float) -> void:
	Fx.kf(b.face, 0.32, [[0.0, {"y": 60.0, "s": 0.6, "r": 8.0, "a": 0.0}], [1.0, {"y": 0.0, "s": 1.0, "r": 0.0, "a": 1.0}]],
		{"ease": [0.2, 1.4, 0.4, 1.0], "delay": delay})

func _reset_face(b: HandSlot) -> void:
	b.face.position = Vector2.ZERO
	b.face.rotation = 0
	b.face.scale = Vector2.ONE
	b.face.modulate = Color.WHITE

func _paint(i: int) -> void:
	_queue_layout()
	var b: HandSlot = slots[i]
	var r = S.hand[i] if i < S.hand.size() else null
	if r == null or S.mon(r.uid) == null:
		if not b.face.empty:
			b.face.clear_face()
		return
	var basic: bool = S.card_basic(r)
	# a basic card's rules text (dimmed) reads as its owner would play it
	var co = S.card_of(r, S.mon(r.uid)) if basic else S.card_of(r)
	var def: Dictionary = co.def
	var src: Mon = co.src
	var e = S.enemy
	var dead: bool = S.card_dead(r)
	var bench: bool = S.card_benched(r)
	var hits: bool = basic or def.get("dmg", 0) or def.get("from_shield", false)
	var strong: bool = not dead and e != null and hits and Data.adv(co.el, e.el) > 1
	var bdmg: int = S.basic_dmg(r) if basic else -1
	var up = src.ups.get(r.slot, "")
	if up == null:
		up = ""
	var cost = Data.BAL.discard_cost if dead else S.card_cost(r)
	var base = cost if dead else S.base_card(src, r.slot).cost
	var faces := S.card_faces(r).map(func(m: Mon): return [m.key, m.el])
	var k := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [r.uid, r.slot, co.by.uid, def.cost, cost, bench, strong, up, dead, faces, bdmg]
	if b.face.key == k and not b.face.empty:
		return
	b.face.face(def, co.el, {"slot": r.slot, "cost": cost, "base": base, "faces": faces, "bench": bench, "dead": dead, "basic": bdmg,
		"strong": Data.adv(co.el, e.el) if strong else 0.0, "pow": co.pow, "upgraded": up, "energy": S.energy})
	b.face.key = k
	if i == _sel:
		_preview_paint()

func refresh_hand() -> void:
	for i in slots.size():
		if not slots[i].playing:
			_paint(i)

func _on_card_played(i: int) -> void:
	var b: HandSlot = slots[i]
	b.playing = true
	Fx.kf(b.face, 0.3, [[0.0, {"y": 0.0, "s": 1.0, "r": 0.0, "a": 1.0, "b": 1.0}], [1.0, {"y": -90.0, "s": 1.25, "r": -6.0, "a": 0.0, "b": 2.2}]],
		{"ease": [0.42, 0.0, 1.0, 1.0]})
	_queue_layout()

## A fainted creature's card was thrown away: it drops out of the hand instead of flying up.
func _on_card_discarded(i: int) -> void:
	var b: HandSlot = slots[i]
	b.playing = true
	Fx.kf(b.face, 0.32, [[0.0, {"y": 0.0, "s": 1.0, "r": 0.0, "a": 1.0}], [1.0, {"y": 80.0, "s": 0.8, "r": 14.0, "a": 0.0}]],
		{"ease": [0.55, 0.0, 0.9, 0.6]})
	_queue_layout()

func _on_card_denied(i: int, why := "") -> void:
	if why == "busy":   # TS returned silently outside mode "battle"
		return
	var b: HandSlot = slots[i]
	if Fx.animating(b.face) and b.face.modulate.a < 1.0:
		return
	Fx.kf(b.face, 0.3, [[0.0, {"x": 0.0}], [0.25, {"x": -5.0}], [0.75, {"x": 5.0}], [1.0, {"x": 0.0}]], {"ease": [0.25, 0.1, 0.25, 1.0]})

# ---- hand: fan; touch magnifies, slide to scrub, swipe up to play

func _hand_resized() -> void:
	for b in slots:
		b.base = Vector2(round(hand.size.x / 2.0 - _cw / 2.0), 0)
		b._apply()
	_queue_layout()

## Fan the slots that hold a card; the inspected one straightens and lifts a little (HELD_LIFT, so
## the bench and lead plate stay visible) while the big preview shows it on the stage.
func _poses() -> Array:
	var W := hand.size.x
	var cw := _cw
	var ch := roundf(_cw * 4.0 / 3.0)
	var live: Array = []
	for i in slots.size():
		if not slots[i].face.empty:
			live.append(i)
	var n := live.size()
	var si := live.find(_sel)
	var step := minf(cw * 0.78, (W - cw * 1.3) / (n - 1)) if n > 1 else 0.0
	var out: Array = []
	out.resize(slots.size())
	for k in n:
		var i: int = live[k]
		var t := k - (n - 1) / 2.0
		var nudge := ((-1.0 if k < si else 1.0) * cw * 0.14) if (si >= 0 and k != si) else 0.0
		out[i] = {"x": t * step + nudge, "y": cw * FAN_DROP * t * t, "r": t * FAN_DEG, "s": 1.0, "z": k + 1}
	if si >= 0:
		var p: Dictionary = out[_sel]
		var lim := maxf(0.0, (W - cw) / 2.0)
		p.x = clampf(p.x, -lim, lim)
		p.y = -HELD_LIFT
		p.r = 0.0
		p.s = 1.0
		p.z = 20
	return out

## The hold preview: the held card at about 2× in the middle of the stage, between the enemy plate
## and the lead plate (shrunk to fit a short stage). Hidden once a swipe is committed.
func _preview_layout() -> void:
	var on: bool = _sel >= 0 and current == null and not (_drag != null and _drag.lifted) and not slots[_sel].face.empty
	if not on:
		_pv_sel = -1
		preview.visible = false
		return
	var top := hud_top.get_global_rect().end.y + 8.0
	var bot := hud_bottom.get_global_rect().position.y - 8.0
	var vp := root.get_viewport_rect().size
	var w := floorf(minf(_cw * PREVIEW_K, minf((bot - top) * 0.75, vp.x - 32.0)))
	var sz := Vector2(w, roundf(w * 4.0 / 3.0))
	preview.size = sz
	preview.position = Vector2(roundf((vp.x - sz.x) / 2.0), roundf(top + (bot - top - sz.y) / 2.0))
	preview.pivot_offset = sz / 2.0
	if _pv_sel != _sel:
		_pv_sel = _sel
		_preview_paint()
		preview.visible = true
		Fx.kf(preview, 0.14, [[0.0, {"s": 0.9, "a": 0.0}], [1.0, {"s": 1.0, "a": 1.0}]], {"ease": [0.2, 0.9, 0.3, 1.0]})

func _preview_paint() -> void:
	if _sel >= 0:
		preview.copy_from(slots[_sel].face)

func _layout_hand() -> void:
	_laid_q = false
	if hand.size.x <= 0 or slots.is_empty():
		return
	if _sel >= 0:
		var b: HandSlot = slots[_sel]
		if b.face.empty or b.playing or S.hand.size() <= _sel or S.hand[_sel] != _sel_ref:
			_sel = -1
	var ps := _poses()
	var order: Array = []
	for i in slots.size():
		var b: HandSlot = slots[i]
		var lift := i == _sel
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE if (b.face.empty or b.playing) else Control.MOUSE_FILTER_STOP
		if b.face.lift != lift:
			b.face.lift = lift
			b.face.restyle()
		var p = ps[i]
		var z: int = 30 if (_drag and _drag.b == b and _drag.lifted) else (p.z if p else 0)
		order.append([z, i])
		if p == null or b.playing or (_drag and _drag.b == b and _drag.lifted):
			continue
		if b.flown:
			b.flown = false
			b.set_pose(p, false)
		else:
			b.set_pose(p, true)
	order.sort_custom(func(a, c): return a[0] < c[0] or (a[0] == c[0] and a[1] < c[1]))
	for k in order.size():
		hand.move_child(slots[order[k][1]], k)
	_preview_layout()

func _queue_layout() -> void:
	if not _laid_q:
		_laid_q = true
		_layout_hand.call_deferred()

func _slot_input(e: InputEvent, i: int) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_hand_down(i, e.global_position)
		else:
			_hand_up(e.global_position, true)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hand_move(e.global_position)

func _hand_down(i: int, pos: Vector2) -> void:
	var b: HandSlot = slots[i]
	if _drag != null or b.face.empty or b.playing:
		return
	Sfx.audio()
	_select(i)
	_drag = {"b": b, "i": i, "x0": pos.x, "y0": pos.y, "lifted": false, "dy0": 0.0, "base": _poses()[i],
		"trail": [{"y": pos.y, "t": Platform.ticks_msec()}]}

func _select(i: int) -> void:
	_sel = i
	_sel_ref = S.hand[i] if i < S.hand.size() else null
	_layout_hand()

## Global x of each live card's centre in the plain fan (no magnified card): the scrub targets.
func _fan_x() -> Dictionary:
	var keep := _sel
	_sel = -1
	var ps := _poses()
	_sel = keep
	var xf := hand.get_global_transform()
	var out := {}
	for i in slots.size():
		if ps[i] != null and not slots[i].playing:
			out[i] = (xf * Vector2(slots[i].base.x + ps[i].x + _cw / 2.0, 0)).x
	return out

## Move the magnifier to the card nearest the finger, with hysteresis so it doesn't flicker between two.
func _scrub(d: Dictionary, pos: Vector2) -> void:
	var xs := _fan_x()
	var best := -1
	var bd := INF
	for i in xs:
		var dd := absf(xs[i] - pos.x)
		if dd < bd:
			bd = dd
			best = i
	if best < 0 or best == d.i:
		return
	var cd: float = absf(xs[d.i] - pos.x) if xs.has(d.i) else INF
	if cd - bd < _cw * SCRUB_HYST:
		return
	d.i = best
	d.b = slots[best]
	d.x0 = pos.x
	d.y0 = pos.y
	d.trail = [{"y": pos.y, "t": Platform.ticks_msec()}]
	_select(best)
	d.base = _poses()[best]
	Sfx.tick()
	Platform.haptic("select")

## Upward travel and release speed decide the play.
func _flicked(d: Dictionary, pos: Vector2) -> bool:
	var ch: float = d.b.size.y
	var up: float = d.y0 - pos.y
	var t0: Dictionary = d.trail[0]
	var vel: float = (t0.y - pos.y) / maxf(1.0, Platform.ticks_msec() - t0.t)
	return up > ch * FLICK_DIST or (up > ch * FLICK_MIN and vel > FLICK_VEL)

func _hand_move(pos: Vector2) -> void:
	var d = _drag
	if d == null:
		return
	var now := Platform.ticks_msec()
	d.trail.append({"y": pos.y, "t": now})
	while d.trail.size() > 2 and now - d.trail[0].t > 90:
		d.trail.pop_front()
	var dx: float = pos.x - d.x0
	var dy: float = pos.y - d.y0
	var b: HandSlot = d.b
	if not d.lifted:
		if -dy > b.size.y * LIFT_LOCK and -dy > absf(dx):
			d.lifted = true   # the swipe is committed: this card follows the finger, no more scrubbing
			d.dy0 = dy
			d.x0 = pos.x
			d.base = _poses()[d.i]
			b.dragging = true
			_layout_hand()
		else:
			_scrub(d, pos)
			return
	elif dy > 0:   # dragged back below where it started: drop the swipe, scrub again
		d.lifted = false
		b.dragging = false
		if b.face.armed:
			b.face.armed = false
			b.face.restyle()
		_layout_hand()
		return
	dx = pos.x - d.x0
	var p: Dictionary = d.base
	b.set_pose({"x": p.x + dx * 0.3, "y": p.y + dy - d.dy0, "r": clampf(dx * 0.08, -9, 9), "s": p.s}, false)
	var armed := _flicked(d, pos)
	if b.face.armed != armed:
		b.face.armed = armed
		b.face.restyle()

## Release: a swipe up plays the magnified card; anything else puts it back in the fan.
func _hand_up(pos: Vector2, use_handlers: bool) -> void:
	var d = _drag
	if d == null:
		return
	_drag = null
	var b: HandSlot = d.b
	if b.face.armed:
		b.face.armed = false
		b.face.restyle()
	var upward: bool = d.lifted or (d.y0 - pos.y) > absf(pos.x - d.x0)
	if use_handlers and upward and _flicked(d, pos) and _h.has("play"):
		b.dragging = true
		_h.play.call(d.i)   # Battle emits card_played / card_discarded (→ fly off) or card_denied (→ shake)
		if b.playing:
			b.flown = true
			b.dragging = false
			_sel = -1
			return
	b.dragging = false
	_sel = -1
	_layout_hand()   # back into the fan

# ================================================================== plates and the party rail

const BENCH := 56.0   # bench portrait diameter (the HP ring); the cell adds 2px each side for the guard glow

func render_player_plate() -> void:
	var c = S.act()
	if c == null:
		return
	var k := "%s|%s|%s" % [c.uid, c.key, c.el]
	if el.pPor.get_meta("k", "") != k:
		el.pPor.set_meta("k", k)
		UiKit.clear(el.pPor)
		el.pPor.add_child(UiKit.face_por(c.key, c.el, 44))
	el.pName.text = c.name
	el.pTrait.text = Data.TRAITS[c.trait_key].name if c.trait_key else ""
	el.pHp.set_values(c.hp / float(c.max_hp), clampf(c.shield / float(c.max_hp), 0, 1), true)
	_last_stat = ""

func render_enemy_plate() -> void:
	var e = S.enemy
	if e == null:
		return
	el.eName.text = e.name
	UiKit.clear(el.eEl)
	var kind: String = {"boss": "Boss", "warden": "Warden", "alpha": "Alpha"}.get(e.kind, "Wild")
	el.eEl.add_child(UiKit.chip(str(e.el), UiKit.el_css(e.el), "%s · %s" % [kind, Data.ELEM[e.el].name]))
	el.floorT.text = "%d/8" % S.floor
	_last_stat = ""

## The bench half of the party rail: one round portrait per benched creature (tap to swap).
func render_bench() -> void:
	UiKit.clear(el.bench)
	var n := 0
	for c in S.team():
		if c.uid == S.active:
			continue
		el.bench.add_child(_bench_cell(c))
		n += 1
	el.railSep.visible = n > 0

## A bench portrait: the creature's face inside an HP ring, the swap cooldown as a dark wedge with the
## seconds in the middle, a shield marker (top left) while it resists the incoming heavy, and the
## count of hand cards it owns and would fire in full as an element chip (bottom right). All inside its box.
func _bench_cell(c) -> Box:
	var cell := Box.new(Vector2(BENCH + 4, BENCH + 4))
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	var ring := HpRing.new()
	cell.add_child(Box.fill(ring))
	var por := UiKit.face_por(c.key, c.el, BENCH - 8)
	cell.add_child(por)
	var cd := Pie.new()
	cd.custom_minimum_size = Vector2(BENCH - 8, BENCH - 8)
	cell.add_child(cd)
	var secs := UiKit.lbl("", "display", UiKit.D_S, Color.WHITE, {"align": "center", "valign": VERTICAL_ALIGNMENT_CENTER,
		"outline": 4, "outline_c": Color(0, 0, 0, 0.6)})
	secs.visible = false
	cell.add_child(secs)
	var guard := Box.new(Vector2(20, 20))
	guard.add_child(Box.fill(RRect.new({"radius": 999.0, "border_w": 1.5, "border_c": UiKit.GUARD}).solid(Color("#0b2635"))))
	guard.add_child(UiKit.icon("shield", 12, UiKit.GUARD))
	guard.visible = false
	cell.add_child(Box.at(guard, "tl"))
	var pips := Box.new()
	cell.add_child(Box.at(pips, "br"))
	cell.set_meta("uid", c.uid)
	cell.set_meta("col", UiKit.el_css(c.el))
	cell.set_meta("ring", ring)
	cell.set_meta("por", por)
	cell.set_meta("cd", cd)
	cell.set_meta("secs", secs)
	cell.set_meta("guard", guard)
	cell.set_meta("pips", pips)
	cell.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			cell.accept_event()
			if _h.has("swap"):
				_h.swap.call(int(cell.get_meta("uid"))))
	_bench_state(cell, c, false)
	return cell

func _bench_state(cell: Box, c, guard: bool) -> void:
	var ring: HpRing = cell.get_meta("ring")
	ring.hp = clampf(c.hp / float(c.max_hp), 0, 1) if c.alive else 0.0
	ring.guard = guard
	var k := "%s%s" % [c.alive, guard]
	if cell.get_meta("state", "") == k:
		return
	cell.set_meta("state", k)
	UiKit.set_face_ko(cell.get_meta("por"), not c.alive)
	cell.get_meta("guard").visible = guard

## Swap cooldown on a bench portrait: the wedge sweeps away, the seconds count down, and it pops when ready.
func _bench_cd(b: Box, alive: bool) -> void:
	var cd: bool = S.swap_cd > 0 and alive
	b.get_meta("cd").p = clampf(S.swap_cd / Data.BAL.swap_cd, 0, 1) if cd else 0.0
	var secs: Label = b.get_meta("secs")
	secs.visible = cd
	if cd:
		secs.text = str(ceili(S.swap_cd))
	if b.get_meta("cooling", false) and not cd and alive and S.mode == "battle":
		b.pivot_offset = b.size / 2.0
		Fx.kf(b, 0.3, [[0.0, {"s": 1.0}], [0.4, {"s": 1.14}], [1.0, {"s": 1.0}]], {"ease": [0.2, 1.4, 0.4, 1.0]})
		Sfx.tick()
	b.set_meta("cooling", cd)

## Hand cards `c` (a bench creature) owns and would fire in full once it leads (S.card_waiting_for).
## A knocked-out creature counts nothing.
func _bench_playable(c) -> int:
	if not c.alive:
		return 0
	var n := 0
	for r in S.hand:
		if r != null and S.card_waiting_for(r) == c:
			n += 1
	return n

## .bmon for the map and end-of-run party rows: element orb, name, mini HP bar.
func _bmon(c, extra := "") -> PanelContainer:
	var col := UiKit.el_css(c.el)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 14, 1, UiKit.LINE))
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bx := Box.new()
	p.add_child(bx)
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the map/end rows fit three chips in a sheet, so the chips are tight
	var pad := [5, 5, 7, 5]
	for i in 4:
		m.add_theme_constant_override("margin_" + ["left", "top", "right", "bottom"][i], pad[i])
	bx.add_child(Box.fill(m))
	var h := UiKit.hbox(5)
	m.add_child(h)
	h.add_child(UiKit.orb(col, 24, str(c.el), 12))
	var t := UiKit.vbox(3)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	t.add_child(UiKit.lbl(c.name + extra, "display", 12, UiKit.INK, {"ellipsis": true, "lh": -4}))
	var mini := Control.new()
	mini.custom_minimum_size = Vector2(56, 5)
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var mbg := Panel.new()
	mbg.add_theme_stylebox_override("panel", UiKit.flat(Color(0, 0, 0, 0.5), 3))
	mbg.size = Vector2(56, 5)
	mbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.add_child(mbg)
	var mf := Panel.new()
	mf.add_theme_stylebox_override("panel", UiKit.flat(UiKit.HP, 2))
	mf.size = Vector2(56.0 * clampf(c.hp / float(c.max_hp), 0, 1), 5)
	mf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.add_child(mf)
	t.add_child(mini)
	p.modulate = Color.WHITE if c.alive else Color(0.5, 0.5, 0.52)
	return p

## TS monChip: a non-interactive .bmon for the map/end party rows. `lead` puts a gold star on the
## orb (not after the name, where it cost the name its last letters).
func mon_chip(c, lead := false) -> Control:
	var b := _bmon(c, "")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if lead:
		var star := UiKit.lbl("★", "800", UiKit.T_S, UiKit.GOLD, {"outline": 4, "outline_c": Color(0, 0, 0, 0.7), "lh": -6})
		b.get_child(0).add_child(Box.at(star, "tl", Vector2(3, 0)))
	return b

## TS partyHTML: chips for the lineup (★ marks the lead).
func party_html(list = null) -> Array:
	var out: Array = []
	for c in (list if list != null else S.team()):
		out.append(mon_chip(c, S.lineup.size() > 0 and c.uid == S.lineup[0]))
	return out

# ================================================================== per-frame sync

func _tag_sig(list: Array) -> String:
	var s := ""
	for t in list:
		s += t[0] + "#" + t[1].to_html() + ";"
	return s

## Status tags in a one-line row: as many as fit `avail` px, in priority order (the row never wraps,
## so the plate and the rail keep their height and the band doesn't move).
## `used` = px already taken in the row. Returns the px used after placing.
func _fit_tags(box: Control, list: Array, avail: float, used := 0.0) -> float:
	if used == 0.0:
		UiKit.clear(box)
	for t in list:
		var need := _text_w(t[0]) + 12.0 + (4.0 if used > 0.0 else 0.0)
		if used + need > avail:
			break
		box.add_child(UiKit.tag(t[0], t[1]))
		used += need
	return used

func _text_w(text: String) -> float:
	return ceilf(UiKit.font("700").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.T_S).x)

## The rail's last line: the lead's live tags first, then its Trait if there's room, then the matchup.
func _fit_lead_line(hi: Array, lo: Array, avail: float) -> void:
	var tw: float = _text_w(el.pTrait.text) + 6.0 if el.pTrait.text != "" else 0.0
	var used := _fit_tags(el.pStat, hi, avail - tw)
	var all_hi: bool = el.pStat.get_child_count() == hi.size()
	if not all_hi:
		used = _fit_tags(el.pStat, hi, avail)
	el.pTrait.visible = all_hi and el.pTrait.text != ""
	if all_hi:
		_fit_tags(el.pStat, lo, avail - tw, maxf(used, 0.001))

## The element that resists attacks of element `el` (the one that beats it).
func _resister(el) -> String:
	for k in Data.BEATS:
		if Data.BEATS[k] == el:
			return k
	return ""

func sync_hud() -> void:
	var e = S.enemy
	var me = S.act()
	if e == null or me == null:
		return
	var battle: bool = S.mode == "battle"
	el.eHp.set_values(e.hp / float(e.max))
	el.eHpN.text = "%d/%d" % [ceili(e.hp), e.max]
	var w: float = e.t / e.windup if e.windup > 0 else 0.0
	var heavy_now: bool = S.is_heavy(e)
	var hv = S.heavy_of(e)
	var perfect: bool = battle and e.alive and S.in_perfect_window(e)
	var ring_el = hv.el if heavy_now else e.el
	el.eRing.paint(clampf(w, 0, 1), w > 0.75, heavy_now, perfect, UiKit.el_css(ring_el), str(ring_el))

	# heavy wind-up: the banner in the telegraph strip under the plate
	var show_hv: bool = battle and e.alive and heavy_now and S.em != null
	heavy.visible = show_hv
	if show_hv:
		var k := str(hv.name) + str(hv.el)
		var c := UiKit.el_css(hv.el)
		if _heavy_k != k:
			_heavy_k = k
			var res := _resister(hv.el)
			el.heavyIcon.texture = Glyphs.tex(str(hv.el))
			el.heavyName.text = hv.name
			el.heavySub.text = "· %s resists" % Data.ELEM[res].name if res != "" else ""
			heavy.col = c
		el.heavySecs.text = "%.1fs" % maxf(0.0, e.windup - e.t)
		if perfect != _heavy_now or not Fx.animating(el.heavyIcon):
			_heavy_now = perfect
			heavy.hot = perfect
			el.heavyIcon.self_modulate = Color.WHITE if perfect else c
			Fx.kf(el.heavyIcon, 0.12 if perfect else 0.5, [[0.0, {"s": 1.0}], [1.0, {"s": 1.25}]], {"loop": "alternate", "ease": [0.42, 0, 0.58, 1]})
	elif _heavy_k != "":
		_heavy_k = ""
		Fx.stop(el.heavyIcon)
		el.heavyIcon.scale = Vector2.ONE

	var pp: float = me.hp / float(me.max_hp)
	el.pHp.set_values(pp, clampf(me.shield / float(me.max_hp), 0, 1))
	el.pHpN.text = "%d/%d" % [ceili(me.hp), me.max_hp] + (" +%d" % floori(me.shield) if me.shield >= 1 else "")

	var en: float = S.energy
	el.energy.set_energy(en, Data.BAL.energy_max)
	for i in slots.size():
		var r = S.hand[i] if i < S.hand.size() else null
		if r == null:
			continue
		# the card shows bench/dead/can't-afford itself; the slot only dims while cards can't be played at all
		slots[i].set_dim(S.card_block(r) == "busy")
		slots[i].face.set_energy(en)
	if preview.visible:
		preview.set_energy(en)

	var es: Array = []
	var ps: Array = []
	if e.status:
		es.append(["%s %ss" % [Data.STATUS_NAME[e.status.k], "%.0f" % e.status.t], UiKit.el_css(Data.STATUS_EL[e.status.k])])
	if e.kind == "boss":
		es.append(["Shifts in %ds" % ceili(e.shift_t), UiKit.GOLD])
	if e.shock_cd > 0:
		es.append(["Shock immune %ds" % ceili(e.shock_cd), UiKit.MUTE])
	if not heavy_now and (e.count + 2) % int(Data.BAL.heavy_every) == 0:
		es.append(["Heavy next", UiKit.FOE])
	if me.status:
		ps.append(["%s %ss" % [Data.STATUS_NAME[me.status.k], "%.0f" % me.status.t], UiKit.el_css(Data.STATUS_EL[me.status.k])])
	if S.discount:
		ps.append(["Next card −1", UiKit.GOLD])
	if me.reflect:
		ps.append(["Reflect %d%%" % roundi(me.reflect * 100), UiKit.SHIELD])
	if me.next_strike > 1:
		ps.append(["Strike ×%s" % _num(me.next_strike), UiKit.GOLD])
	var lo: Array = []   # the matchup ranks below the Trait (the cards and the bench chips show it too)
	var a: float = Data.adv(me.el, e.el)
	if a > 1:
		lo.append(["Strong vs " + Data.ELEM[e.el].name, UiKit.GOLD])
	elif a < 1:
		lo.append(["Weak vs " + Data.ELEM[e.el].name, Color("#b8bdd6")])
	var ew: float = floorf(el.eStat.size.x)
	var pw: float = floorf(el.pStat.get_parent().size.x)
	var st: String = _tag_sig(es) + "|" + _tag_sig(ps) + _tag_sig(lo) + el.pTrait.text + "|%d|%d" % [ew, pw]
	if st != _last_stat:
		_last_stat = st
		_fit_tags(el.eStat, es, ew)
		_fit_lead_line(ps, lo, pw)

	for b in el.bench.get_children():
		if not b.has_meta("uid"):
			continue
		var c = S.mon(int(b.get_meta("uid")))
		if c == null:
			continue
		_bench_cd(b, c.alive)
		_bench_state(b, c, battle and c.alive and heavy_now and Data.resists(c.el, hv.el))
		var pips: Box = b.get_meta("pips")
		var n := _bench_playable(c) if battle else 0
		if pips.get_meta("n", -1) != n:
			pips.set_meta("n", n)
			UiKit.clear(pips)
			if n > 0:   # an element-coloured chip with the count, inset in the portrait's corner
				var col: Color = b.get_meta("col")
				var chip := UiKit.panel(UiKit.flat(col, 10, 1.5, UiKit.NAVY2, Vector4(5, 0, 5, 0)))
				chip.custom_minimum_size = Vector2(20, 20)
				chip.add_child(UiKit.lbl(str(n), "800", UiKit.T_S, UiKit.NAVY2, {"align": "center", "valign": VERTICAL_ALIGNMENT_CENTER, "lh": -6}))
				pips.add_child(chip)

	# chain counter beside the lead
	var show_ch: bool = battle and S.chain > 0
	chain.visible = show_ch
	if show_ch:
		var k := str(S.chain)
		var expiring: bool = S.chain_t > Data.BAL.chain_win - 0.5
		if _chain_k != k:
			_chain_k = k
			el.chainN.text = "×%d" % (S.chain + 1)
			el.chainS.text = "+%d%%" % roundi(S.chain * Data.BAL.chain_step * 100)
			if not expiring:
				Fx.kf(chain, 0.25, [[0.0, {"s": 1.6}], [1.0, {"s": 1.0}]], {"ease": [0.2, 1.6, 0.4, 1.0]})
		if expiring != _chain_exp:
			_chain_exp = expiring
			if expiring:
				Fx.kf(chain, 0.25, [[0.0, {"s": 1.0, "a": 1.0}], [1.0, {"s": 0.9, "a": 0.35}]], {"loop": "alternate", "ease": [0.42, 0, 0.58, 1]})
			else:
				Fx.stop(chain)
				chain.scale = Vector2.ONE
				chain.modulate.a = 1.0
		var p: Vector2 = Layout.ppos()
		var U: float = Layout.U
		chain.size = Vector2(64, chain.get_combined_minimum_size().y)
		chain.pivot_offset = chain.size / 2.0
		chain.position = (Vector2(p.x + U * 1.2 - 32, p.y - U * 1.9)).round()
	else:
		_chain_k = ""

func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else str(snappedf(v, 0.1))

# ================================================================== HUD pieces

## The enemy's intent ring (replaces the wind-up bar): a dark track that fills clockwise from 12 o'clock
## over the wind-up, around the element glyph. Hot (last quarter) glows; a heavy draws thicker in the
## heavy's element; the Perfect Swap window turns it white.
class IntentRing extends Control:
	const SZ := 44.0
	var w := 0.0
	var col := Color.WHITE
	var hot := false
	var hv := false
	var perfect := false
	var icon: TextureRect
	var _g := ""

	func _init() -> void:
		custom_minimum_size = Vector2(SZ, SZ)
		mouse_filter = MOUSE_FILTER_IGNORE
		size_flags_vertical = SIZE_SHRINK_CENTER
		icon = UiKit.icon("ember", 18)
		icon.position = Vector2.ONE * (SZ - 18.0) / 2.0
		icon.size = Vector2(18, 18)
		add_child(icon)

	func paint(nw: float, nhot: bool, nhv: bool, nperf: bool, ncol: Color, glyph: String) -> void:
		if glyph != _g:
			_g = glyph
			icon.texture = Glyphs.tex(glyph)
		icon.self_modulate = Color.WHITE if nperf else ncol
		if absf(nw - w) < 0.002 and nhot == hot and nhv == hv and nperf == perfect and ncol == col:
			return
		w = nw
		hot = nhot
		hv = nhv
		perfect = nperf
		col = ncol
		queue_redraw()

	func _draw() -> void:
		var c := Vector2.ONE * SZ / 2.0
		var fc := Color.WHITE if perfect else (UiKit.mix(col, Color.WHITE, 0.75) if hot else col)
		if perfect or hot:
			draw_circle(c, SZ / 2.0, Color(col, 0.4 if perfect else 0.22), true, -1.0, true)
		var wd := 5.0 if hv else 4.0
		draw_arc(c, 18.0, 0.0, TAU, 64, Color(0, 0, 0, 0.6), wd, true)
		if w > 0.001:
			draw_arc(c, 18.0, -PI / 2.0, -PI / 2.0 + TAU * w, maxi(4, int(64 * w)), fc, wd, true)
		draw_circle(c, 15.5, UiKit.NAVY2, true, -1.0, true)

## The heavy banner's backing: navy glass that fades out at both ends, with element-coloured rules
## along the top and bottom (white during the Perfect Swap window).
class BannerBg extends Control:
	var col := Color.WHITE:
		set(v):
			col = v
			queue_redraw()
	var hot := false:
		set(v):
			hot = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var f := minf(48.0, w * 0.14)
		var glass := Color(18 / 255.0, 26 / 255.0, 51 / 255.0, 0.95)
		if hot:
			glass = UiKit.mix(glass, col, 0.7)
			glass.a = 0.95
		var line := Color.WHITE if hot else col
		var stops := [[0.0, 0.0], [f, 1.0], [w - f, 1.0], [w, 0.0]]
		for i in 3:
			var x0: float = stops[i][0]
			var x1: float = stops[i + 1][0]
			var a0: float = stops[i][1]
			var a1: float = stops[i + 1][1]
			draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, h), Vector2(x0, h)]),
				PackedColorArray([Color(glass, glass.a * a0), Color(glass, glass.a * a1), Color(glass, glass.a * a1), Color(glass, glass.a * a0)]))
			for y in [0.0, h - 1.0]:
				draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x1, y), Vector2(x1, y + 1.0), Vector2(x0, y + 1.0)]),
					PackedColorArray([Color(line, a0), Color(line, a1), Color(line, a1), Color(line, a0)]))

## A bench portrait's HP ring (3px, clockwise from 12 o'clock; red under 30%), with a cyan glow behind
## the portrait while it resists the incoming heavy.
class HpRing extends Control:
	var hp := 1.0:
		set(v):
			if absf(v - hp) > 0.002:
				hp = v
				queue_redraw()
	var guard := false:
		set(v):
			if v != guard:
				guard = v
				queue_redraw()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 3.5   # the 56px ring inside the 60px cell
		if guard:
			draw_circle(c, minf(size.x, size.y) / 2.0, Color(UiKit.GUARD, 0.45), true, -1.0, true)
		draw_arc(c, r, 0.0, TAU, 64, Color(0.02, 0.03, 0.08, 0.85), 3.0, true)
		if hp > 0.001:
			var hc := UiKit.FOE if hp < 0.3 else UiKit.HP
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * hp, maxi(4, int(64 * hp)), hc, 3.0, true)
		if guard:
			draw_arc(c, r + 2.0, 0.0, TAU, 64, UiKit.GUARD, 1.0, true)

## The swap cooldown wedge: conic-gradient(rgba(10,15,31,.72) p, transparent 0), a clockwise circular
## sector from 12 o'clock over the portrait.
class Pie extends Control:
	var p := 0.0:
		set(v):
			if absf(v - p) > 0.001:
				p = v
				queue_redraw()
	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if p <= 0.001:
			return
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		var pts := PackedVector2Array([c])
		var n := maxi(2, int(64 * p))
		for k in n + 1:
			var a := -PI / 2.0 + TAU * p * k / n
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(5 / 255.0, 8 / 255.0, 18 / 255.0, 0.72))
