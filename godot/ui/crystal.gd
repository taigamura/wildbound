class_name Crystal
extends Control
## The energy crystal beside the hand (docs/UI-QUEUE.md item 6): a glass orb that fills like liquid as
## energy regenerates, the whole number inside, and one pip per energy point around the rim (lit
## clockwise from the top; the next pip brightens as it charges). Colours are the cards' crystal
## (#e6fbff → #57c8ff → #2178c2). Replaces the lilac segment bar.

const SHADER := preload("res://ui/crystal.gdshader")
const SZ := 68.0
const ORB := 46.0
const PIP_R := 3.1
const PIP_ON := Color("#9fe0ff")
const PIP_OFF := Color("#1d2a44")
const GLOW := Color(0.34, 0.78, 1.0)

var energy := -1.0
var cap := 10.0
var num: Label
var _orb := ColorRect.new()
var _m := ShaderMaterial.new()

func _init() -> void:
	custom_minimum_size = Vector2(SZ, SZ)
	mouse_filter = MOUSE_FILTER_IGNORE
	size_flags_vertical = SIZE_SHRINK_CENTER
	_m.shader = SHADER
	_m.set_shader_parameter("rsize", Vector2(ORB, ORB))
	_orb.material = _m
	_orb.mouse_filter = MOUSE_FILTER_IGNORE
	_orb.position = Vector2.ONE * (SZ - ORB) / 2.0
	_orb.size = Vector2(ORB, ORB)
	add_child(_orb)
	num = UiKit.lbl("0", "display", UiKit.D_S, Color.WHITE, {"align": "center", "valign": VERTICAL_ALIGNMENT_CENTER,
		"shadow": Color("#0b1430"), "shadow_off": Vector2(0, 2), "outline": 4, "outline_c": Color(0.04, 0.08, 0.19, 0.55)})
	num.position = _orb.position
	num.size = _orb.size
	add_child(num)

## Energy now and its cap. Cheap to call every frame.
func set_energy(e: float, mx: float) -> void:
	_m.set_shader_parameter("t", UiKit.now())
	if absf(e - energy) < 0.002 and mx == cap:
		return
	energy = e
	cap = mx
	_m.set_shader_parameter("level", clampf(e / maxf(mx, 1.0), 0.0, 1.0))
	_m.set_shader_parameter("full", 1.0 if e >= mx else 0.0)
	num.text = str(floori(e))
	queue_redraw()

func _draw() -> void:
	var c := Vector2.ONE * SZ / 2.0
	# soft glow behind the orb, stronger when full (kept inside the box)
	var g := 0.22 if energy >= cap else 0.12
	for k in 3:
		draw_circle(c, ORB / 2.0 + 2.0 + k * 2.0, Color(GLOW, g * (1.0 - k * 0.3)), true, -1.0, true)
	var n := int(cap)
	var rr := SZ / 2.0 - PIP_R - 0.6
	for i in n:
		var a := -PI / 2.0 + TAU * i / n
		var p := c + Vector2(cos(a), sin(a)) * rr
		var f := clampf(energy - i, 0.0, 1.0)
		draw_circle(p, PIP_R, PIP_OFF, true, -1.0, true)
		if f >= 1.0:
			draw_circle(p, PIP_R + 1.2, Color(GLOW, 0.35), true, -1.0, true)
			draw_circle(p, PIP_R, PIP_ON, true, -1.0, true)
		elif f > 0.0:   # charging: the next pip brightens
			draw_circle(p, PIP_R, Color(PIP_ON, 0.15 + 0.45 * f), true, -1.0, true)
