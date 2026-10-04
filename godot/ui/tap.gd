class_name Tap
extends PanelContainer
## A button that holds arbitrary content (the TS <button> with innerHTML). Fires `pressed` on a
## release inside it that didn't travel (so drags still scroll a parent ScrollContainer).
## Look: `style` (normal) and optional `style_on` (aria-pressed / selected).

signal pressed

const SLOP := 12.0

var disabled := false:
	set(v):
		disabled = v
		_refresh()
var on := false:
	set(v):
		on = v
		_refresh()
## modulate while disabled (.node:disabled .5, .card:disabled .45, .metabtn:disabled .7, .big:disabled darker)
var dis_mod := Color(1, 1, 1, 0.5)
## scale while held (.node:active .98, .card:active .97, .big:active pushed)
var press_scale := 0.98
var style: StyleBox
var style_on: StyleBox

var _down := false
var _p0 := Vector2.ZERO

func _init(st: StyleBox = null, st_on: StyleBox = null) -> void:
	mouse_filter = MOUSE_FILTER_PASS
	focus_mode = FOCUS_NONE
	style = st if st else StyleBoxEmpty.new()
	style_on = st_on
	_refresh()

func _ready() -> void:
	resized.connect(func(): pivot_offset = size / 2.0)

func _refresh() -> void:
	add_theme_stylebox_override("panel", style_on if on and style_on else style)
	modulate = dis_mod if disabled else Color.WHITE
	mouse_default_cursor_shape = CURSOR_ARROW if disabled else CURSOR_POINTING_HAND

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if disabled:
				return
			_down = true
			_p0 = e.global_position
			_hold(true)
		elif _down:
			_down = false
			_hold(false)
			if get_global_rect().has_point(e.global_position) and e.global_position.distance_to(_p0) < SLOP:
				pressed.emit()
	elif e is InputEventMouseMotion and _down and e.global_position.distance_to(_p0) >= SLOP:
		_down = false
		_hold(false)

func _hold(v: bool) -> void:
	scale = Vector2.ONE * (press_scale if v else 1.0)
