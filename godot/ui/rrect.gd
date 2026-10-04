class_name RRect
extends Control
## A styled box drawn by ui/rr.gdshader: the Godot stand-in for a CSS div with border-radius,
## gradient background, border and box-shadow. Never takes input.
## `look(d)` sets any of: radius (float or Vector4 tl,tr,br,bl), mode ("linear" "radial" "stripes"),
## c0 c1 c2 s1 s_end angle rc, border_w border_c, ring_w ring_c, glow glow_c, sh_off sh_c.

const SHADER := preload("res://ui/rr.gdshader")

var _m := ShaderMaterial.new()
var _pad := 0.0
var _p := {}

func _init(d: Dictionary = {}) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_m.shader = SHADER
	material = _m
	look(d)

func look(d: Dictionary) -> RRect:
	for k in d:
		var v = d[k]
		match k:
			"radius":
				v = v if v is Vector4 else Vector4(v, v, v, v)
				_sp("radii", v)
			"mode":
				_sp("mode", {"linear": 0, "radial": 1, "stripes": 2}.get(v, 0))
			_:
				_sp(k, v)
	var sh: Vector2 = _p.get("sh_off", Vector2.ZERO)
	_pad = maxf(maxf(float(_p.get("glow", 0.0)), float(_p.get("ring_w", 0.0))), maxf(absf(sh.x), absf(sh.y))) + 2.0
	queue_redraw()
	return self

## Solid colour fill (keeps border/glow settings).
func solid(c: Color) -> RRect:
	return look({"mode": "linear", "c0": c, "c1": c, "s1": 1.0})

func _sp(k: String, v) -> void:
	if k == "radius" or (_p.has(k) and typeof(_p[k]) == typeof(v) and _p[k] == v):
		return
	if v is int and k != "mode":
		v = float(v)
	_p[k] = v
	_m.set_shader_parameter(k, v)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	_m.set_shader_parameter("rsize", size)
	draw_rect(Rect2(Vector2(-_pad, -_pad), size + Vector2(_pad, _pad) * 2.0), Color.WHITE)
