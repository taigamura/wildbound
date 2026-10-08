class_name MapTrail
extends Control
## The map's trail (docs/UI-QUEUE.md item 8, mockup idea 7): a gold "you are here" dot at the bottom,
## dashed paths branching up to this floor's 2-3 medallions, and above them the floors still to walk,
## fading upward toward the goal (the Warden on floor 4, Noctyrm on floor 8). Drawn in code; the
## medallions are Taps placed over the drawing. Run fills it with set_trail() and listens to `tapped`.

signal tapped(i: int)

const MED := 52.0        # medallion size
const MED_SEL := 60.0    # the selected medallion
const CELL := Vector2(104, 86)   # medallion box (64) + its label
const BOX := 64.0
const DASH := 3.0
const GAP := 5.0
const H := 206.0         # full height; the goal rows take the top TOP px
const TOP := 56.0

var _views: Array = []   # [{c, g, t}] per node
var _goal := {}          # {t, g} or empty on the final floor
var _between := ""       # the floors between this one and the goal, highest first
var _sel := -1
var _cells: Array = []   # Tap per node
var _goal_row: HBoxContainer
var _between_lbl: Label

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size_flags_horizontal = SIZE_EXPAND_FILL
	custom_minimum_size.y = H
	resized.connect(_place)

## views: [{c: Color, g: glyph, t: label}] for this floor's nodes; goal: {t, g} ({} = nothing ahead);
## between: the in-between floors as one faded line; sel: the selected node (-1 = none).
func set_trail(views: Array, goal: Dictionary, between: String, sel: int) -> void:
	_views = views
	_goal = goal
	_between = between
	_sel = sel
	custom_minimum_size.y = H if not goal.is_empty() else H - TOP
	_build()

func select(i: int) -> void:
	if i == _sel:
		return
	_sel = i
	_build()

func _top() -> float:
	return 0.0 if not _goal.is_empty() else -TOP

func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_cells.clear()
	_goal_row = null
	_between_lbl = null
	if not _goal.is_empty():
		_goal_row = UiKit.hbox(6)
		_goal_row.modulate.a = 0.6
		var ring := Box.new(Vector2(20, 20))
		ring.add_child(Box.fill(RRect.new({"radius": 999.0, "c0": UiKit.NAVY2, "c1": UiKit.NAVY2, "border_w": 1.5, "border_c": UiKit.BRASS})))
		ring.add_child(UiKit.icon(_goal.g, 11, UiKit.GOLD_HI))
		_goal_row.add_child(ring)
		_goal_row.add_child(UiKit.lbl(_goal.t, "700", UiKit.T_S, UiKit.INK, {"valign": VERTICAL_ALIGNMENT_CENTER}))
		add_child(_goal_row)
		if _between != "":
			_between_lbl = UiKit.lbl(_between, "700", UiKit.T_S, UiKit.MUTE, {"align": "center"})
			add_child(_between_lbl)
	for i in _views.size():
		var vw: Dictionary = _views[i]
		var on := i == _sel
		var t := Tap.new()
		t.press_scale = 0.94
		var v := UiKit.vbox(4)
		var b := Box.new(Vector2(BOX, BOX))
		b.add_child(UiKit.por(vw.c, MED_SEL if on else MED, vw.g, on))
		v.add_child(b)
		v.add_child(UiKit.lbl(vw.t, "700", UiKit.T_S, UiKit.GOLD_HI if on else UiKit.INK, {"align": "center"}))
		t.add_child(v)
		t.pressed.connect(func(): tapped.emit(i))
		add_child(t)
		_cells.append(t)
	_place()

## Medallion centre x for node i of n (evenly spread, like the mockup's space-around with a 24px pad).
func _mx(i: int, n: int) -> float:
	if n <= 1:
		return size.x / 2.0
	var pad := 24.0
	var w := size.x - pad * 2.0
	return pad + w * (i + 0.5) / n

func _my() -> float:
	return _top() + 106.0

func _place() -> void:
	var oy := _top()
	if _goal_row:
		var m := _goal_row.get_combined_minimum_size()
		_goal_row.position = Vector2(roundf((size.x - m.x) / 2.0), oy)
		_goal_row.size = m
	if _between_lbl:
		var m2 := _between_lbl.get_combined_minimum_size()
		_between_lbl.position = Vector2(roundf((size.x - m2.x) / 2.0), oy + 26.0)
		_between_lbl.size = m2
	for i in _cells.size():
		var t: Tap = _cells[i]
		var m3 := t.get_combined_minimum_size()
		var w := maxf(m3.x, minf(CELL.x, size.x / maxf(1, _cells.size())))
		t.size = Vector2(w, m3.y)
		t.position = Vector2(roundf(_mx(i, _cells.size()) - w / 2.0), roundf(_my() - BOX / 2.0))
	queue_redraw()

func _draw() -> void:
	var n := _views.size()
	if n == 0:
		return
	var cx := size.x / 2.0
	var my := _my()
	var oy := _top()
	var start := Vector2(cx, size.y - 10.0)
	var brass := UiKit.alpha(UiKit.BRASS, 0.7)
	var label_end := my + BOX / 2.0 + 24.0   # below the medallion's label
	var conv := Vector2(cx, oy + 52.0)       # where the paths meet above the medallions
	for i in n:
		var x := _mx(i, n)
		var a := Vector2(x, label_end)
		_dashed_curve(start, Vector2(cx, start.y - 18.0), Vector2(x, a.y + 14.0), a, UiKit.GOLD_HI if i == _sel else brass)
		if not _goal.is_empty():
			var top := Vector2(x, my - BOX / 2.0 - 2.0)
			_dashed_curve(top, Vector2(x, top.y - 10.0), Vector2(cx, conv.y + 12.0), conv, brass)
	if not _goal.is_empty():
		if _between_lbl:
			_dashed(conv, Vector2(cx, oy + 44.0), UiKit.alpha(UiKit.BRASS, 0.5))
			_dashed(Vector2(cx, oy + 24.0), Vector2(cx, oy + 22.0), UiKit.alpha(UiKit.BRASS, 0.3))
		else:
			_dashed(conv, Vector2(cx, oy + 24.0), UiKit.alpha(UiKit.BRASS, 0.4))
	# soft gold glow behind the selected medallion
	if _sel >= 0 and _sel < n:
		var sc := Vector2(_mx(_sel, n), my)
		for k in 6:
			draw_circle(sc, MED_SEL / 2.0 + 2.0 + k * 2.0, UiKit.alpha(UiKit.GOLD_HI, 0.1 - k * 0.015))
	# you are here
	draw_circle(start, 8.0, UiKit.NAVY2)
	draw_circle(start, 6.0, UiKit.GOLD_HI)

func _dashed_curve(p0: Vector2, c0: Vector2, c1: Vector2, p1: Vector2, col: Color) -> void:
	var cv := Curve2D.new()
	cv.add_point(p0, Vector2.ZERO, c0 - p0)
	cv.add_point(p1, c1 - p1, Vector2.ZERO)
	_dash_poly(cv.tessellate_even_length(5, 2.0), col)

func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	_dash_poly(PackedVector2Array([a, b]), col)

## Dashes along a polyline (3 on, 5 off, 2px), like the mockup's stroke-dasharray.
func _dash_poly(pts: PackedVector2Array, col: Color) -> void:
	var on := true
	var left := DASH
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var d := 0.0
		while d < seg:
			var step := minf(left, seg - d)
			var p := a.lerp(b, d / seg)
			var q := a.lerp(b, (d + step) / seg)
			if on:
				draw_line(p, q, col, 2.0, true)
			d += step
			left -= step
			if left <= 0.0:
				on = not on
				left = DASH if on else GAP
