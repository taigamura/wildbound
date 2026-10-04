class_name HandSlot
extends Control
## One card slot of the fanned hand. Its pose (translate x/y, rotate, scale about the bottom centre)
## eases like the TS CSS transition (.24s, cubic-bezier(.2,.9,.3,1.12) for translate/scale and
## (.2,.9,.3,1) for rotate) in real time, so hit-stop and slow-mo don't touch it. The keyframe
## animations (deal, play, deny) run on `face` inside, composing on top of the pose.

const DUR := 0.24

var i := 0
var face := CardView.new("hand")
var base := Vector2.ZERO          # unposed top-left inside the hand
var playing := false              # TS .play: flying off, waiting for drawInto's repaint
var flown := false                # flicked off the top: the next card snaps to its fan spot
var dragging := false             # TS .drag: transitions off
var poor := false
var swapcd := false

var cur := {"x": 0.0, "y": 0.0, "r": 0.0, "s": 1.0}
var _from := {}
var _to := {}
var _t0 := 0.0

func _init(idx: int) -> void:
	i = idx
	mouse_filter = MOUSE_FILTER_STOP
	add_child(face)
	set_process(false)

func set_card_size(sz: Vector2) -> void:
	size = sz
	face.size = sz
	face.position = Vector2.ZERO
	pivot_offset = Vector2(sz.x / 2.0, sz.y)
	face.pivot_offset = pivot_offset
	_apply()

## TS setPose. `animate` = false is "transition: none".
func set_pose(p: Dictionary, animate := true) -> void:
	var to := {"x": p.x, "y": p.y, "r": p.r, "s": p.s}
	if not animate or dragging:
		cur = to
		_to = {}
		set_process(false)
		_apply()
		return
	if not _to.is_empty() and _to.x == to.x and _to.y == to.y and _to.r == to.r and _to.s == to.s:
		return
	if _to.is_empty() and cur.x == to.x and cur.y == to.y and cur.r == to.r and cur.s == to.s:
		return
	_from = cur.duplicate()
	_to = to
	_t0 = UiKit.now()
	set_process(true)

func _process(_dt: float) -> void:
	if _to.is_empty():
		set_process(false)
		return
	var k := clampf((UiKit.now() - _t0) / DUR, 0.0, 1.0)
	var e1 := UiKit.bezier(k, 0.2, 0.9, 0.3, 1.12)
	var e2 := UiKit.bezier(k, 0.2, 0.9, 0.3, 1.0)
	cur = {"x": lerpf(_from.x, _to.x, e1), "y": lerpf(_from.y, _to.y, e1), "r": lerpf(_from.r, _to.r, e2), "s": lerpf(_from.s, _to.s, e1)}
	if k >= 1.0:
		cur = _to
		_to = {}
		set_process(false)
	_apply()

func _apply() -> void:
	position = base + Vector2(cur.x, cur.y)
	rotation = deg_to_rad(cur.r)
	scale = Vector2(cur.s, cur.s)

## Filters: .poor saturate(.25) brightness(.55); .swapcd saturate(.4) brightness(.7).
func set_dim(is_poor: bool, is_swapcd: bool) -> void:
	if is_poor == poor and is_swapcd == swapcd:
		return
	poor = is_poor
	swapcd = is_swapcd
	var c := Color.WHITE
	if poor:
		c = Color(0.5, 0.5, 0.56)
	elif swapcd:
		c = Color(0.66, 0.66, 0.72)
	create_tween().set_ignore_time_scale(true).tween_property(self, "modulate", c, 0.2)

func has_global(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(get_global_transform().affine_inverse() * p)
