extends Node
## Battle HUD, the card hand and the screen frames (TS game/ui.ts + index.html + style.css).
## Reads state, never changes game rules. Screens' static parts are built by ui/screens.gd into `el`
## (TS $('#id') → Ui.el["id"]); game/run.gd fills them.

# hand: tap to inspect, flick up to play (TS constants)
const FLICK_DIST := 0.4   # dragged up more than this × card height → plays on release
const FLICK_VEL := 0.6    # or released moving up faster than this (px/ms)...
const FLICK_MIN := 0.15   # ...after at least this × card height of travel
const SLOP := 6.0         # px of movement before a press counts as a drag
const FAN_DEG := 8.0      # rotation per step from the centre (4 cards → ±4°, ±12°)
const FAN_DROP := 0.06    # × card width × step² that outer cards sit lower

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
var segs: Array = []
var heavy: Control
var chain: Control
var current = null      # shown screen id, or null for the battle HUD

var _h := {}
var _sel := -1
var _sel_ref = null
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

	# ---- top band: floor pill + mute, enemy plate
	hud_top = UiKit.vbox(8)
	hud_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud.add_child(hud_top)
	var meta := UiKit.hbox(6)
	hud_top.add_child(meta)
	var pill := UiKit.panel(UiKit.flat(UiKit.PANEL, 99, 1, UiKit.LINE, Vector4(10, 6, 10, 6)))
	var ph := UiKit.hbox(0)
	ph.add_child(UiKit.lbl("Floor ", "700", 12, UiKit.MUTE, {"upper": true, "ls": 0.06}))
	el.floorT = UiKit.lbl("1", "800", 12, UiKit.INK, {"ls": 0.06})
	ph.add_child(el.floorT)
	ph.add_child(UiKit.lbl("/8", "700", 12, UiKit.MUTE, {"ls": 0.06}))
	pill.add_child(ph)
	meta.add_child(pill)
	meta.add_child(UiKit.spacer())
	var mute := Tap.new(UiKit.flat(UiKit.PANEL, 16, 1, UiKit.LINE))
	mute.custom_minimum_size = Vector2(32, 32)
	mute.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	el.muteIcon = UiKit.icon("sound", 16, UiKit.MUTE)
	mute.add_child(el.muteIcon)
	mute.pressed.connect(func():
		Sfx.set_muted(not Sfx.is_muted())
		paint_mute()
		Sfx.audio())
	el.muteBtn = mute
	meta.add_child(mute)
	# quit (no pause): the first tap arms it, the second ends the run (Run.quit_tap)
	var quit := Tap.new(UiKit.flat(UiKit.PANEL, 16, 1, UiKit.LINE))
	quit.custom_minimum_size = Vector2(32, 32)
	quit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quit.add_child(UiKit.icon("exit", 16, UiKit.MUTE))
	quit.pressed.connect(func(): Run.quit_tap(quit))
	el.quitBtn = quit
	meta.add_child(quit)

	var foe := _plate()
	hud_top.add_child(foe.panel)
	el.eEl = foe.chip
	el.eName = foe.name
	el.eLv = foe.lv
	el.eHp = Bar.new(false, Color("#ff8a97"), UiKit.FOE)
	foe.box.add_child(el.eHp)
	el.eIntBar = Bar.new(true, Color("#ff9d5c"), Color("#ff4d6a"))
	foe.box.add_child(el.eIntBar)
	el.eStat = UiKit.flow(5)
	foe.box.add_child(el.eStat)

	# ---- bottom band: my plate, bench, energy, hand
	hud_bottom = UiKit.vbox(8)
	hud_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hud_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.add_child(hud_bottom)
	var mine := _plate()
	hud_bottom.add_child(mine.panel)
	el.pEl = mine.chip
	el.pName = mine.name
	el.pLv = mine.lv
	el.pHp = Bar.new(false, Color("#a8ffc6"), UiKit.HP)
	mine.box.add_child(el.pHp)
	el.pStat = UiKit.flow(5)
	mine.box.add_child(el.pStat)
	el.bench = UiKit.hbox(8)
	hud_bottom.add_child(el.bench)

	var energy := UiKit.hbox(10)
	hud_bottom.add_child(energy)
	var sg := UiKit.hbox(3)
	sg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	energy.add_child(sg)
	for i in Data.BAL.energy_max:
		var s := Control.new()
		s.custom_minimum_size.y = 12
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bgs := RRect.new({"radius": 3.0, "border_w": 1.0, "border_c": Color(170 / 255.0, 186 / 255.0, 1, 0.12)}).solid(Color(0, 0, 0, 0.5))
		var f := RRect.new({"radius": 3.0, "c0": Color("#e3d6ff"), "c1": PURPLE_SEG, "angle": 180.0})
		s.add_child(bgs)
		s.add_child(f)
		s.resized.connect(func(): bgs.size = s.size; f.size.y = s.size.y)
		s.set_meta("fill", f)
		sg.add_child(s)
		segs.append(s)
	var en := UiKit.hbox(0)
	en.custom_minimum_size.x = 42
	en.alignment = BoxContainer.ALIGNMENT_END
	el.enN = UiKit.lbl("3", "display", 22, Color("#d9ccff"))
	el.enMax = UiKit.lbl("/%d" % Data.BAL.energy_max, "700", 11, UiKit.MUTE, {"valign": VERTICAL_ALIGNMENT_BOTTOM})
	el.enMax.size_flags_vertical = Control.SIZE_SHRINK_END
	en.add_child(el.enN)
	en.add_child(el.enMax)
	energy.add_child(en)

	hand = Control.new()
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.resized.connect(_hand_resized)
	hud_bottom.add_child(hand)
	for i in Data.BAL.hand:
		var b := HandSlot.new(i)
		b.gui_input.connect(_slot_input.bind(i))
		hand.add_child(b)
		slots.append(b)

	# ---- pinned over the world: heavy telegraph and chain counter (outside #hud in TS)
	heavy = UiKit.vbox(2)
	heavy.alignment = BoxContainer.ALIGNMENT_CENTER
	heavy.size = Vector2(160, 0)
	heavy.visible = false
	var hv_icon := Box.new(Vector2(44, 44))
	el.heavyGlow = Box.fill(RRect.new({"radius": 999.0, "mode": "radial", "rc": Vector2(0.5, 0.5), "c0": Color(1, 1, 1, 0.5), "c1": Color(1, 1, 1, 0)}))
	el.heavyGlow.set_meta("fill", true)
	hv_icon.add_child(el.heavyGlow)
	el.heavyIcon = UiKit.icon("ember", 44)
	hv_icon.add_child(el.heavyIcon)
	hv_icon.pivot_offset = Vector2(22, 22)
	el.heavyPulse = hv_icon
	heavy.add_child(hv_icon)
	el.heavyName = UiKit.lbl("", "display", 17, Color.WHITE, {"align": "center", "shadow": Color.BLACK, "shadow_off": Vector2(0, 2), "outline": 6})
	heavy.add_child(el.heavyName)
	root.add_child(heavy)

	chain = UiKit.vbox(2)
	chain.alignment = BoxContainer.ALIGNMENT_CENTER
	chain.size = Vector2(60, 0)
	chain.visible = false
	el.chainN = UiKit.lbl("", "display", 26, UiKit.GOLD, {"align": "center", "shadow": Color.BLACK, "shadow_off": Vector2(0, 2),
		"outline": 5, "outline_c": Color(1, 207 / 255.0, 107 / 255.0, 0.25), "lh": -6})
	chain.add_child(el.chainN)
	el.chainS = UiKit.lbl("", "800", 10, UiKit.GOLD, {"align": "center", "ls": 0.08, "shadow": Color.BLACK, "shadow_off": Vector2(0, 2), "lh": -6})
	chain.add_child(el.chainS)
	root.add_child(chain)

const PURPLE_SEG := Color("#9b7bff")

## A .plate: panel with a prow (element chip, name, level line) and a body column.
func _plate() -> Dictionary:
	var p := UiKit.panel(UiKit.flat(UiKit.PANEL, 16, 1, UiKit.LINE, Vector4(12, 9, 12, 10)))
	var box := UiKit.vbox(6)
	p.add_child(box)
	var row := UiKit.hbox(8)
	box.add_child(row)
	var chip := UiKit.hbox(0)
	row.add_child(chip)
	var name := UiKit.lbl("", "display", 19, UiKit.INK, {"ellipsis": true})
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var lv := UiKit.hbox(0)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lv)
	return {"panel": p, "box": box, "chip": chip, "name": name, "lv": lv}

func paint_mute() -> void:
	el.muteIcon.texture = Glyphs.tex("mute" if Sfx.is_muted() else "sound")

func init_hud(h: Dictionary) -> void:
	_h = h
	if Battle.has_signal("card_played"):
		Battle.card_played.connect(_on_card_played)
	if Battle.has_signal("card_denied"):
		Battle.card_denied.connect(_on_card_denied)
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
	var co = S.card_of(r)
	var def: Dictionary = co.def
	var owner = co.owner
	var e = S.enemy
	var bench: bool = r.uid != S.active
	var strong: bool = e != null and (def.get("dmg", 0) or def.get("from_shield", false)) and Data.adv(owner.el, e.el) > 1
	var up = owner.ups.get(r.slot, "") if owner.ups is Dictionary else owner.ups.get(r.slot)
	if up == null:
		up = ""
	var cost = S.card_cost(r)
	var k := "%s|%s|%s|%s|%s|%s|%s" % [r.uid, r.slot, def.cost, cost, bench, strong, up]
	if b.face.key == k and not b.face.empty:
		return
	b.face.face(def, owner.el, {"cost": cost, "owner": owner, "bench": bench, "strong": strong, "pow": co.pow,
		"upgraded": "+30%" if up == "power" else ("−1" if up == "cost" else "")})
	b.face.key = k

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

func _on_card_denied(i: int, why := "") -> void:
	if why == "busy":   # TS returned silently outside mode "battle"
		return
	var b: HandSlot = slots[i]
	if Fx.animating(b.face) and b.face.modulate.a < 1.0:
		return
	Fx.kf(b.face, 0.3, [[0.0, {"x": 0.0}], [0.25, {"x": -5.0}], [0.75, {"x": 5.0}], [1.0, {"x": 0.0}]], {"ease": [0.25, 0.1, 0.25, 1.0]})

# ---- hand: fan, tap to inspect, flick up to play

func _hand_resized() -> void:
	for b in slots:
		b.base = Vector2(round(hand.size.x / 2.0 - _cw / 2.0), 0)
		b._apply()
	_queue_layout()

## Fan the slots that hold a card; the inspected one lifts, straightens and grows.
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
		var s := 1.16
		var lim := maxf(0.0, (W - cw * s) / 2.0)
		p.x = clampf(p.x, -lim, lim)
		p.y = -ch * 0.3
		p.r = 0.0
		p.s = s
		p.z = 20
	return out

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
		var z: int = 30 if (_drag and _drag.b == b) else (p.z if p else 0)
		order.append([z, i])
		if p == null or b.playing or (_drag and _drag.b == b):
			continue
		if b.flown:
			b.flown = false
			b.set_pose(p, false)
		else:
			b.set_pose(p, true)
	order.sort_custom(func(a, c): return a[0] < c[0] or (a[0] == c[0] and a[1] < c[1]))
	for k in order.size():
		hand.move_child(slots[order[k][1]], k)

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
	var was_sel := _sel == i
	if not was_sel:
		_sel = i
		_sel_ref = S.hand[i]
		_layout_hand()
	_drag = {"b": b, "i": i, "x0": pos.x, "y0": pos.y, "moved": false, "was_sel": was_sel, "base": _poses()[i],
		"trail": [{"y": pos.y, "t": Time.get_ticks_msec()}]}

## Upward travel and release speed decide the play.
func _flicked(d: Dictionary, pos: Vector2) -> bool:
	var ch: float = d.b.size.y
	var up: float = d.y0 - pos.y
	var t0: Dictionary = d.trail[0]
	var vel: float = (t0.y - pos.y) / maxf(1.0, Time.get_ticks_msec() - t0.t)
	return up > ch * FLICK_DIST or (up > ch * FLICK_MIN and vel > FLICK_VEL)

func _hand_move(pos: Vector2) -> void:
	var d = _drag
	if d == null:
		return
	var dx: float = pos.x - d.x0
	var dy: float = pos.y - d.y0
	if not d.moved:
		if Vector2(dx, dy).length() < SLOP:
			return
		d.moved = true
		d.b.dragging = true
		_layout_hand()
	var now := Time.get_ticks_msec()
	d.trail.append({"y": pos.y, "t": now})
	while d.trail.size() > 2 and now - d.trail[0].t > 90:
		d.trail.pop_front()
	var p: Dictionary = d.base   # mostly vertical; sideways moves only tilt it, downward is rubber-banded
	d.b.set_pose({"x": p.x + dx * 0.3, "y": p.y + (dy if dy < 0 else dy * 0.25), "r": clampf(dx * 0.08, -9, 9), "s": p.s}, false)
	var armed := _flicked(d, pos)
	if d.b.face.armed != armed:
		d.b.face.armed = armed
		d.b.face.restyle()

func _hand_up(pos: Vector2, use_handlers: bool) -> void:
	var d = _drag
	if d == null:
		return
	_drag = null
	var b: HandSlot = d.b
	if b.face.armed:
		b.face.armed = false
		b.face.restyle()
	if not d.moved:   # tap
		b.dragging = false
		if d.was_sel and use_handlers:
			_sel = -1
		_layout_hand()
		return
	if use_handlers and _flicked(d, pos) and _h.has("play"):
		_h.play.call(d.i)   # Battle emits card_played (→ .play) or card_denied (→ shake)
		if b.playing:
			b.flown = true
			b.dragging = false
			return
	b.dragging = false
	_layout_hand()   # snap back to the inspected pose

func _input(e: InputEvent) -> void:
	# tapping anywhere outside the hand puts the inspected card back
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _sel >= 0:
		for b in slots:
			if not b.face.empty and b.visible and hud.visible and b.has_global(e.global_position):
				return
		_sel = -1
		_layout_hand()

# ================================================================== plates

func _chip_into(holder: HBoxContainer, el_key) -> void:
	UiKit.clear(holder)
	holder.add_child(UiKit.elchip(el_key, Data.ELEM[el_key].name))

func render_player_plate() -> void:
	var c = S.act()
	if c == null:
		return
	_chip_into(el.pEl, c.el)
	el.pName.text = c.name
	UiKit.clear(el.pLv)
	var role = Data.SPECIES[c.key].get("role", "")
	el.pLv.add_child(UiKit.lbl(str(role if role else ""), "700", 12, UiKit.MUTE))
	if c.trait_key:
		el.pLv.add_child(UiKit.lbl(" · ", "700", 12, UiKit.MUTE))
		el.pLv.add_child(UiKit.lbl(Data.TRAITS[c.trait_key].name, "700", 12, UiKit.GOLD))
	el.pHp.set_values(c.hp / float(c.max_hp), clampf(c.shield / float(c.max_hp), 0, 1), true)

func render_enemy_plate() -> void:
	var e = S.enemy
	if e == null:
		return
	_chip_into(el.eEl, e.el)
	el.eName.text = e.name
	UiKit.clear(el.eLv)
	var kind: String = {"boss": "Boss", "warden": "Warden", "alpha": "Alpha"}.get(e.kind, "Wild")
	el.eLv.add_child(UiKit.lbl(kind, "700", 12, UiKit.MUTE))
	el.floorT.text = str(S.floor)

func render_bench() -> void:
	UiKit.clear(el.bench)
	for c in S.team():
		if c.uid == S.active:
			continue
		var b := _bmon(c, "", true)
		el.bench.add_child(b)

## .bmon: element orb, name, mini HP bar; in the bench also the swap cooldown wedge and the guard/advantage marker.
func _bmon(c, extra := "", interactive := false) -> PanelContainer:
	var col := UiKit.el_css(c.el)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.flat(UiKit.PANEL, 14, 1, UiKit.LINE))
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	p.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bx := Box.new()
	p.add_child(bx)
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in [["left", 6], ["top", 6], ["right", 10], ["bottom", 6]]:
		m.add_theme_constant_override("margin_" + s[0], s[1])
	bx.add_child(Box.fill(m))
	var h := UiKit.hbox(7)
	m.add_child(h)
	h.add_child(UiKit.orb(col, 30, str(c.el), 14))
	var t := UiKit.vbox(3)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var nm := UiKit.lbl(c.name + extra, "display", 13, UiKit.INK, {"lh": -4} if interactive else {"ellipsis": true, "lh": -4})
	t.add_child(nm)
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
	p.set_meta("uid", c.uid)
	p.set_meta("mini", mf)
	p.set_meta("col", col)
	if interactive:
		var cd := Pie.new()
		bx.add_child(Box.fill(cd))
		p.set_meta("cd", cd)
		var adv := Box.new()
		bx.add_child(Box.at(adv, "tr", Vector2(5, 3)))
		p.set_meta("adv", adv)
		p.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				p.accept_event()
				if _h.has("swap"):
					_h.swap.call(int(p.get_meta("uid"))))
	_bmon_state(p, c.alive, false)
	return p

func _bmon_state(p: PanelContainer, alive: bool, guard: bool) -> void:
	var k := "%s%s" % [alive, guard]
	if p.get_meta("state", "") == k:
		return
	p.set_meta("state", k)
	var col: Color = p.get_meta("col")
	var st := UiKit.flat(UiKit.PANEL, 14, 1, Color.WHITE if guard else UiKit.LINE)
	if guard:
		UiKit.glow_box(st, UiKit.alpha(col, 0.7), 10)
	p.add_theme_stylebox_override("panel", st)
	p.modulate = Color.WHITE if alive else Color(0.5, 0.5, 0.52)

## TS monChip: a non-interactive .bmon for the map/end party rows.
func mon_chip(c, extra := "") -> Control:
	var b := _bmon(c, extra, false)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

## TS partyHTML: chips for the lineup (★ marks the lead).
func party_html(list = null) -> Array:
	var out: Array = []
	for c in (list if list != null else S.team()):
		out.append(mon_chip(c, " ★" if (S.lineup.size() > 0 and c.uid == S.lineup[0]) else ""))
	return out

# ================================================================== per-frame sync

func _tag_sig(list: Array) -> String:
	var s := ""
	for t in list:
		s += t[0] + "#" + t[1].to_html() + ";"
	return s

func _fill_tags(box: Control, list: Array) -> void:
	UiKit.clear(box)
	for t in list:
		box.add_child(UiKit.tag(t[0], t[1]))
	box.visible = not list.is_empty()

func sync_hud() -> void:
	var e = S.enemy
	var me = S.act()
	if e == null or me == null:
		return
	var battle: bool = S.mode == "battle"
	el.eHp.set_values(e.hp / float(e.max))
	el.eHp.txt.text = "%d / %d" % [ceili(e.hp), e.max]
	var w: float = e.t / e.windup if e.windup > 0 else 0.0
	var heavy_now: bool = S.is_heavy(e)
	var hv = S.heavy_of(e)
	var perfect: bool = battle and e.alive and S.in_perfect_window(e)
	_paint_intent(clampf(w, 0, 1), w > 0.75, heavy_now, perfect, UiKit.el_css(hv.el if heavy_now else e.el))

	# heavy telegraph over the enemy
	var show_hv: bool = battle and e.alive and heavy_now
	heavy.visible = show_hv and S.em != null
	if heavy.visible:
		var k := str(hv.name) + str(hv.el)
		if _heavy_k != k:
			_heavy_k = k
			var c := UiKit.el_css(hv.el)
			el.heavyIcon.texture = Glyphs.tex(str(hv.el))
			el.heavyName.text = hv.name
			el.heavyName.add_theme_color_override("font_outline_color", UiKit.alpha(c, 0.45))
			el.heavyGlow.look({"c0": UiKit.alpha(c, 0.55), "c1": UiKit.alpha(c, 0.0)})
		var now: bool = S.in_perfect_window(e)
		el.heavyIcon.self_modulate = Color.WHITE if now else UiKit.el_css(hv.el)
		if now != _heavy_now or not Fx.animating(el.heavyPulse):
			_heavy_now = now
			Fx.kf(el.heavyPulse, 0.12 if now else 0.5, [[0.0, {"s": 1.0}], [1.0, {"s": 1.18}]], {"loop": "alternate", "ease": [0.42, 0, 0.58, 1]})
		var hd: Vector2 = S.em.head()
		var U: float = Layout.U
		heavy.size = Vector2(160, heavy.get_combined_minimum_size().y)
		heavy.position = (Vector2(hd.x - U * 2.3, hd.y - U * 0.2) - Vector2(80, 0)).round()

	var pp: float = me.hp / float(me.max_hp)
	el.pHp.set_values(pp, clampf(me.shield / float(me.max_hp), 0, 1))
	el.pHp.txt.text = "%d / %d" % [ceili(me.hp), me.max_hp] + ("  +%d" % floori(me.shield) if me.shield >= 1 else "")

	var en: float = S.energy
	for i in segs.size():
		var f := clampf(en - i, 0, 1)
		var fr: RRect = segs[i].get_meta("fill")
		fr.size.x = segs[i].size.x * f
		fr.visible = f > 0.001
	el.enN.text = str(floori(en))
	for i in slots.size():
		var r = S.hand[i] if i < S.hand.size() else null
		if r == null:
			continue
		var why: String = S.card_block(r)
		slots[i].set_dim(why == "energy" or why == "busy", why == "swap")

	var es: Array = []
	var ps: Array = []
	if e.status:
		es.append(["%s %ss" % [Data.STATUS_NAME[e.status.k], "%.0f" % e.status.t], UiKit.el_css(Data.STATUS_EL[e.status.k])])
	if e.shock_cd > 0:
		es.append(["Shock immune %ds" % ceili(e.shock_cd), UiKit.MUTE])
	if e.kind == "boss":
		es.append(["Shifts in %ds" % ceili(e.shift_t), UiKit.GOLD])
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
	var a: float = Data.adv(me.el, e.el)
	if a > 1:
		ps.append(["Strong vs " + Data.ELEM[e.el].name, UiKit.GOLD])
	elif a < 1:
		ps.append(["Weak vs " + Data.ELEM[e.el].name, Color("#b8bdd6")])
	var st := _tag_sig(es) + "|" + _tag_sig(ps)
	if st != _last_stat:
		_last_stat = st
		_fill_tags(el.eStat, es)
		_fill_tags(el.pStat, ps)

	for b in el.bench.get_children():
		if not b.has_meta("uid"):
			continue
		var c = S.mon(int(b.get_meta("uid")))
		if c == null:
			continue
		b.get_meta("cd").p = (S.swap_cd / Data.BAL.swap_cd) if S.swap_cd > 0 else 0.0
		b.get_meta("mini").size.x = 56.0 * clampf(c.hp / float(c.max_hp), 0, 1)
		var guard: bool = c.alive and heavy_now and Data.resists(c.el, hv.el)
		_bmon_state(b, c.alive, guard and battle)
		var adv: Box = b.get_meta("adv")
		var ak := "g" if guard else ("a" if (c.alive and Data.adv(c.el, e.el) > 1) else "")
		if adv.get_meta("k", "-") != ak:
			adv.set_meta("k", ak)
			UiKit.clear(adv)
			if ak == "g":
				adv.add_child(UiKit.icon("shield", 12, Color.WHITE))
			elif ak == "a":
				adv.add_child(UiKit.lbl("▲", "800", 9, UiKit.GOLD))

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
		chain.size = Vector2(60, chain.get_combined_minimum_size().y)
		chain.pivot_offset = chain.size / 2.0
		chain.position = (Vector2(p.x + U * 1.2 - 30, p.y - U * 1.9)).round()
	else:
		_chain_k = ""

func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else str(snappedf(v, 0.1))

var _int_k := ""
func _paint_intent(w: float, hot: bool, hv: bool, perfect: bool, c: Color) -> void:
	var bar: Bar = el.eIntBar
	bar.set_values(w)
	var k := "%s%s%s%s" % [hot, hv, perfect, c.to_html()]
	if k == _int_k:
		return
	_int_k = k
	bar.custom_minimum_size.y = 9 if hv else 6
	var f := {"c0": Color("#ff9d5c"), "c1": Color("#ff4d6a")}
	var bgl := {"ring_w": 0.0, "glow": 0.0}
	if hot:
		f = {"c0": Color("#ffdd66"), "c1": Color("#ff3355")}
		bgl = {"ring_w": 0.0, "glow": 10.0, "glow_c": Color(1, 0.2, 0.333, 0.6)}
	if hv:
		f = {"c0": UiKit.mix(c, Color.WHITE, 0.6), "c1": c}
	if perfect:
		f = {"c0": Color.WHITE, "c1": Color.WHITE}
		bgl = {"ring_w": 2.0, "ring_c": Color.WHITE, "glow": 16.0, "glow_c": UiKit.alpha(c, 0.8)}
	bar.fill.look(f)
	bar.bg.look(bgl)

# ================================================================== swap cooldown wedge

class Pie extends Control:
	## conic-gradient(rgba(10,15,31,.72) p, transparent 0): a clockwise wedge from 12 o'clock.
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
		var r := size.length()
		var pts := PackedVector2Array([c])
		var n := maxi(2, int(48 * p))
		for k in n + 1:
			var a := -PI / 2.0 + TAU * p * k / n
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(10 / 255.0, 15 / 255.0, 31 / 255.0, 0.72))
