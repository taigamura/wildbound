class_name Bar
extends Control
## .bar: HP bar with a ghost trail, a striped shield overlay (right-aligned) and an optional centred
## number (`num`; the battle HUD puts its numbers outside the bar instead); or, with `intent = true`,
## a plain wind-up bar (no transitions). The battle's intent is now the plate's ring (Ui.IntentRing).
## Widths ease like the CSS transitions (fill .18s ease-out; ghost .6s ease-out after .25s), in real time.

var intent := false
var bg := RRect.new()
var ghost := RRect.new()
var fill := RRect.new()
var shf := RRect.new()
var txt: Label

var _f := 1.0
var _g := 1.0
var _s := 0.0
var _tf := 1.0
var _tg := 1.0
var _ts := 0.0
var _f_anim := {}
var _g_anim := {}
var _s_anim := {}

func _init(is_intent := false, top := Color.WHITE, bot := Color.WHITE, num := true) -> void:
	intent = is_intent
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 6 if intent else 16
	bg.look({"radius": 7.0, "c0": Color(0, 0, 0, 0.45), "c1": Color(0, 0, 0, 0.45), "border_w": 1.0, "border_c": Color(0, 0, 0, 0.25)})
	add_child(bg)
	if not intent:
		ghost.look({"radius": 7.0}).solid(Color(1, 1, 1, 0.55))
		add_child(ghost)
	fill.look({"radius": 7.0, "c0": top, "c1": bot, "angle": 90.0 if intent else 180.0})
	add_child(fill)
	if not intent:
		shf.look({"radius": 7.0, "mode": "stripes", "c0": Color(143 / 255.0, 227 / 255.0, 1, 0.85), "c1": Color(143 / 255.0, 227 / 255.0, 1, 0.55)})
		add_child(shf)
	if not intent and num:
		txt = UiKit.lbl("", "800", UiKit.T_S, UiKit.INK, {"align": "center", "shadow": Color(0, 0, 0, 0.9), "shadow_off": Vector2(0, 1),
			"shadow_outline": 1, "valign": VERTICAL_ALIGNMENT_CENTER, "lh": -4})
		add_child(txt)
	set_process(false)

## Fractions 0..1. `snap` skips the transition (first paint).
func set_values(f: float, s := 0.0, snap := false) -> void:
	f = clampf(f, 0, 1)
	s = clampf(s, 0, 1)
	if intent or snap:
		_f = f; _g = f; _s = s; _tf = f; _tg = f; _ts = s
		_f_anim = {}; _g_anim = {}; _s_anim = {}
		_layout()
		return
	var t := UiKit.now()
	if absf(f - _tf) > 0.0005:
		_tf = f
		_f_anim = {"a": _f, "b": f, "t0": t, "d": 0.18}
	if absf(f - _tg) > 0.0005:
		_tg = f
		_g_anim = {"a": _g, "b": f, "t0": t + 0.25, "d": 0.6}
	if absf(s - _ts) > 0.0005:
		_ts = s
		_s_anim = {"a": _s, "b": s, "t0": t, "d": 0.18}
	set_process(true)

func _step(a: Dictionary, t: float, cur: float) -> float:
	if a.is_empty():
		return cur
	var k := clampf((t - a.t0) / a.d, 0, 1)
	if t < a.t0:
		return cur
	return lerpf(a.a, a.b, 1.0 - pow(1.0 - k, 2.2))

func _process(_dt: float) -> void:
	var t := UiKit.now()
	_f = _step(_f_anim, t, _f)
	_g = _step(_g_anim, t, _g)
	_s = _step(_s_anim, t, _s)
	if (_f_anim.is_empty() or t > _f_anim.t0 + _f_anim.d) and (_g_anim.is_empty() or t > _g_anim.t0 + _g_anim.d) \
			and (_s_anim.is_empty() or t > _s_anim.t0 + _s_anim.d):
		_f_anim = {}; _g_anim = {}; _s_anim = {}
		set_process(false)
	_layout()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()

func _layout() -> void:
	var w := size.x
	var h := size.y
	bg.position = Vector2.ZERO
	bg.size = size
	var r := h / 2.0
	for p in [[fill, _f, false], [ghost, _g, false], [shf, _s, true]]:
		var n: RRect = p[0]
		if not n.get_parent():
			continue
		var ww: float = w * p[1]
		n.visible = ww > 0.5
		n.size = Vector2(ww, h)
		n.position = Vector2(w - ww if p[2] else 0.0, 0)
		n.look({"radius": minf(r, 7.0)})
	if txt:   # centred on the bar; the label's line box is a little taller than the bar
		var th := txt.get_combined_minimum_size().y
		txt.position = Vector2(0, roundf((size.y - th) / 2.0))
		txt.size = Vector2(size.x, th)
