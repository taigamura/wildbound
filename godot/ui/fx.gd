extends Node
## Screen-level feedback drawn over the 3D view (TS render/fx.ts DOM parts): damage numbers, banners,
## callouts, flashes, the hurt vignette and toasts. CSS animations in TS ran in real time, so the
## keyframe animator here (`kf`) does too; flash and vignette were gsap (scaled time) and stay scaled.

var layer := CanvasLayer.new()
var root := Control.new()
var vig := ColorRect.new()
var flash_rect := ColorRect.new()
var fx := Control.new()
var banner_box: VBoxContainer
var banner_main: Label
var banner_glow: Label
var banner_small: Label
var toast_box: PanelContainer
var toast_lbl: Label

var _anims: Array = []
var _toast_until := 0.0
var _flash_tw: Tween
var _vig_tw: Tween

const VIG_SHADER := """
shader_type canvas_item;
uniform vec4 c : source_color = vec4(1.0, 0.133, 0.267, 1.0);
uniform vec2 rsize = vec2(390.0, 844.0);
void fragment() {
	vec2 p = UV * rsize;
	float d = min(min(p.x, rsize.x - p.x), min(p.y, rsize.y - p.y));
	float k = 1.0 - smoothstep(0.0, 120.0, d - 10.0);
	COLOR = vec4(c.rgb, c.a * k * k * COLOR.a);
}
"""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 5
	add_child(layer)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.add_child(root)
	for n in [vig, flash_rect, fx]:
		n.set_anchors_preset(Control.PRESET_FULL_RECT)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(n)
	var sh := Shader.new()
	sh.code = VIG_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	vig.material = m
	vig.color = Color(1, 1, 1, 1)
	vig.modulate.a = 0.0
	vig.resized.connect(func(): m.set_shader_parameter("rsize", vig.size))
	flash_rect.color = Color.WHITE
	flash_rect.modulate.a = 0.0
	_build_banner()
	_build_toast()

func _build_banner() -> void:
	banner_box = UiKit.vbox(6)
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var stack := Box.new()
	banner_glow = UiKit.lbl("", "display", UiKit.D_L, Color(1, 1, 1, 0), {"align": "center", "outline": 18})
	banner_main = UiKit.lbl("", "display", UiKit.D_L, UiKit.INK, {"align": "center", "shadow": Color(0, 0, 0, 0.55), "shadow_off": Vector2(0, 4)})
	stack.add_child(banner_glow)
	stack.add_child(banner_main)
	banner_box.add_child(stack)
	banner_small = UiKit.lbl("", "700", UiKit.T_L, Color.WHITE, {"align": "center", "shadow": Color(0, 0, 0, 0.6), "shadow_off": Vector2(0, 2)})
	banner_box.add_child(banner_small)
	banner_box.modulate.a = 0.0
	root.add_child(banner_box)

func _build_toast() -> void:
	toast_box = UiKit.panel(UiKit.window(12, false))
	toast_lbl = UiKit.lbl("", "700", 14, UiKit.INK, {"align": "center", "wrap": true, "lh": 0})
	toast_box.add_child(toast_lbl)
	toast_box.modulate.a = 0.0
	root.add_child(toast_box)

# ------------------------------------------------------------------ API

## Coloured damage number. cls: space-separated TS classes ("crit" "weak" "heal" "shield" "dot" "player" "resist").
func pop_num(pos: Vector2, text, cls := "", label := "", color := Color(0, 0, 0, 0)) -> void:
	var cl := str(cls).split(" ", false)
	var has_nc := color.a > 0
	var size := 26
	var c := color if has_nc else Color.WHITE
	var a := 1.0
	if "crit" in cl:
		size = 38
		c = color if has_nc else UiKit.GOLD
	if "weak" in cl:
		size = 19
		a = 0.85
	if "heal" in cl:
		c = UiKit.HP
	if "shield" in cl:
		c = UiKit.SHIELD
	if "dot" in cl:
		size = 18
		c = Color("#ffb07a")
	if "player" in cl:
		c = Color("#ff5a6e") if "crit" in cl else Color("#ff8a97")
	var d := UiKit.vbox(2)
	d.alignment = BoxContainer.ALIGNMENT_CENTER
	var main := UiKit.lbl(str(text), "display", size, c, {"align": "center", "shadow": Color.BLACK, "shadow_off": Vector2(0, 2),
		"outline": 6 if "crit" in cl else 3, "outline_c": UiKit.alpha(c, 0.35) if "crit" in cl else Color(0, 0, 0, 0.35), "lh": -6})
	d.add_child(main)
	if str(label) != "":
		d.add_child(UiKit.lbl(str(label), "700", UiKit.T_S, c, {"align": "center", "shadow": Color.BLACK,
			"shadow_off": Vector2(0, 1), "outline": 4, "outline_c": Color(0, 0, 0, 0.45), "lh": -6}))
	fx.add_child(d)
	var m := d.get_combined_minimum_size()
	d.size = m
	d.pivot_offset = m / 2.0
	var base := Vector2(pos.x + randf_range(-18, 18), pos.y) - m / 2.0
	d.position = base
	d.modulate.a = 0.0
	var h := m.y
	kf(d, 0.9, [
		[0.0, {"y": h * 0.2, "s": 0.4, "a": 0.0}],
		[0.15, {"y": -h * 0.3, "s": 1.25, "a": a}],
		[0.3, {"y": -h * 0.4, "s": 1.0}],
		[1.0, {"y": -h * 1.4, "s": 0.95, "a": 0.0}],
	], {"base": base, "ease": [0.0, 0.0, 0.58, 1.0], "free": true})

## Big centred word with a sub line (enemy name, Victory, fainted).
func banner(text: String, sub := "", color := UiKit.GOLD_HI) -> void:
	color = UiKit.col(color, UiKit.GOLD_HI)
	banner_main.text = text
	banner_glow.text = text
	banner_glow.add_theme_color_override("font_outline_color", UiKit.alpha(color, 0.28))
	banner_small.text = sub
	banner_small.visible = sub != ""
	banner_small.add_theme_color_override("font_color", color)
	var vp := root.size
	var m := banner_box.get_combined_minimum_size()
	banner_box.size = Vector2(vp.x, m.y)
	var base := Vector2(0, vp.y * 0.34)
	banner_box.position = base
	banner_box.pivot_offset = Vector2(vp.x / 2.0, m.y / 2.0)
	kf(banner_box, 1.3, [
		[0.0, {"a": 0.0, "s": 2.4, "y": 0.0}],
		[0.18, {"a": 1.0, "s": 1.0}],
		[0.78, {"a": 1.0, "s": 1.04, "y": 0.0}],
		[1.0, {"a": 0.0, "s": 0.9, "y": -20.0}],
	], {"base": base, "ease": [0.2, 1.3, 0.3, 1.0]})

func flash(op := 0.5, color := Color.WHITE) -> void:
	flash_rect.color = UiKit.col(color, Color.WHITE)
	if _flash_tw:
		_flash_tw.kill()
	flash_rect.modulate.a = op
	_flash_tw = create_tween()
	_flash_tw.tween_property(flash_rect, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func vignette() -> void:
	if _vig_tw:
		_vig_tw.kill()
	vig.modulate.a = 0.55
	_vig_tw = create_tween()
	_vig_tw.tween_property(vig, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func toast(t: String) -> void:
	toast_lbl.text = t
	_toast_until = UiKit.now() + 1.8
	set_process(true)

## Big centred tilted word (PERFECT).
func callout(text: String, color := Color("#ffcf6b")) -> void:
	color = UiKit.col(color, UiKit.GOLD)
	var stack := Box.new()
	stack.add_child(UiKit.lbl(text, "display", 58, Color(1, 1, 1, 0), {"align": "center", "outline": 22, "outline_c": UiKit.alpha(color, 0.3)}))
	stack.add_child(UiKit.lbl(text, "display", 58, Color.WHITE, {"align": "center", "shadow": Color(0, 0, 0, 0.55), "shadow_off": Vector2(0, 4)}))
	fx.add_child(stack)
	var vp := root.size
	var m := stack.get_combined_minimum_size()
	stack.size = Vector2(vp.x, m.y)
	var base := Vector2(0, vp.y * 0.42)
	stack.position = base
	stack.pivot_offset = Vector2(vp.x / 2.0, m.y / 2.0)
	stack.modulate.a = 0.0
	kf(stack, 1.1, [
		[0.0, {"a": 0.0, "s": 3.0, "r": -6.0, "y": 0.0}],
		[0.15, {"a": 1.0, "s": 1.0, "r": -3.0}],
		[0.8, {"a": 1.0}],
		[1.0, {"a": 0.0, "s": 1.1, "r": -3.0, "y": -30.0}],
	], {"base": base, "ease": [0.2, 1.4, 0.3, 1.0], "free": true})

# ------------------------------------------------------------------ loot reveal (real time)

## Pop `items` (Controls, e.g. loot chips in a row) in one after another: each scales up from 0.4 with a
## small overshoot while fading in, with a coin tick (Sfx.tick) and a light haptic as it lands. Real time,
## like the rest of the UI motion. o: delay (before the first, default 0.2), step (between items, 0.12;
## shortened so the whole row lands within 0.5s of the first). The end state is the plain, fully visible
## layout, so a still frame after ~1s shows everything.
func reveal(items: Array, o := {}) -> void:
	var t0: float = o.get("delay", 0.2)
	var step: float = minf(o.get("step", 0.12), 0.5 / maxf(1.0, items.size() - 1.0))
	for i in items.size():
		var n: Control = items[i]
		if not is_instance_valid(n):
			continue
		var centre := func(): n.pivot_offset = n.size / 2.0
		centre.call()
		n.resized.connect(centre)
		var d := t0 + i * step
		kf(n, 0.34, [[0.0, {"s": 0.4, "a": 0.0}], [0.55, {"s": 1.12, "a": 1.0}], [1.0, {"s": 1.0, "a": 1.0}]],
			{"delay": d, "ease": [0.3, 0.0, 0.4, 1.0]})
		get_tree().create_timer(d + 0.12, true, false, true).timeout.connect(func():
			if is_instance_valid(n) and n.is_visible_in_tree():
				Sfx.tick()
				Platform.haptic("light"))

# ------------------------------------------------------------------ keyframe animator (real time)

## Run CSS-like keyframes on a CanvasItem. frames: [[t 0..1, {x y s sx sy r a b}], ...]; each property
## interpolates between the frames that set it. o: base (Vector2 position), ease ([x1,y1,x2,y2] per
## segment), delay, loop ("alternate" or "loop"), free (queue_free at the end), done (Callable).
## A new kf on the same node replaces the old one.
func kf(n: CanvasItem, dur: float, frames: Array, o := {}) -> void:
	stop(n)
	var props := {}
	for f in frames:
		for k in f[1]:
			if not props.has(k):
				props[k] = []
			props[k].append([f[0], f[1][k]])
	var a := {"n": n, "t0": UiKit.now() + o.get("delay", 0.0), "dur": dur, "props": props, "o": o}
	_anims.append(a)
	_apply(a, 0.0)
	set_process(true)

func stop(n: CanvasItem) -> void:
	for i in range(_anims.size() - 1, -1, -1):
		if _anims[i].n == n:
			_anims.remove_at(i)

func animating(n: CanvasItem) -> bool:
	for a in _anims:
		if a.n == n:
			return true
	return false

func _seg(list: Array, t: float, ez: Array) -> float:
	if t <= list[0][0]:
		return list[0][1]
	for i in range(1, list.size()):
		if t <= list[i][0]:
			var a = list[i - 1]
			var b = list[i]
			var k: float = (t - a[0]) / maxf(0.0001, b[0] - a[0])
			return lerpf(a[1], b[1], UiKit.bezier(k, ez[0], ez[1], ez[2], ez[3]))
	return list[-1][1]

func _apply(a: Dictionary, t: float) -> void:
	var n: CanvasItem = a.n
	var o: Dictionary = a.o
	var ez: Array = o.get("ease", [0.25, 0.1, 0.25, 1.0])
	var p: Dictionary = a.props
	var v := {}
	for k in p:
		v[k] = _seg(p[k], t, ez)
	if n is Control:
		var c := n as Control
		if v.has("x") or v.has("y"):
			var base: Vector2 = o.get("base", Vector2.ZERO)
			c.position = base + Vector2(v.get("x", 0.0), v.get("y", 0.0))
		if v.has("s") or v.has("sx") or v.has("sy"):
			var s: float = v.get("s", 1.0)
			c.scale = Vector2(v.get("sx", s), v.get("sy", s))
		if v.has("r"):
			c.rotation = deg_to_rad(v.r)
	if v.has("a"):
		n.modulate.a = v.a
	if v.has("b"):
		var a2 := n.modulate.a
		n.modulate = Color(v.b, v.b, v.b, a2)

func _process(_dt: float) -> void:
	var now := UiKit.now()
	var i := 0
	while i < _anims.size():
		var a: Dictionary = _anims[i]
		if not is_instance_valid(a.n):
			_anims.remove_at(i)
			continue
		var el: float = now - a.t0
		if el < 0:
			i += 1
			continue
		var t: float = el / a.dur
		var loop = a.o.get("loop", "")
		if loop == "alternate":
			var cyc := int(floor(t))
			t = fposmod(t, 1.0)
			if cyc % 2 == 1:
				t = 1.0 - t
		elif loop == "loop":
			t = fposmod(t, 1.0)
		if t >= 1.0 and loop == "":
			_apply(a, 1.0)
			_anims.remove_at(i)
			if a.o.get("free", false):
				a.n.queue_free()
			if a.o.has("done"):
				a.o.done.call()
			continue
		_apply(a, t)
		i += 1
	# toast fade (.3s opacity transition)
	var target := 1.0 if now < _toast_until else 0.0
	if toast_box.modulate.a != target or target > 0:
		var vp := root.size
		var tw := toast_lbl.get_theme_font("font").get_string_size(toast_lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var w := minf(tw + 30, vp.x - 32)
		toast_box.size = Vector2(w, 0)
		toast_box.position = Vector2((vp.x - w) / 2.0, vp.y * 0.18)
		toast_box.modulate.a = move_toward(toast_box.modulate.a, target, _real_dt() / 0.3)
	if _anims.is_empty() and toast_box.modulate.a == 0.0 and now >= _toast_until:
		set_process(false)

var _last := 0.0
func _real_dt() -> float:
	var n := UiKit.now()
	var d := clampf(n - _last, 0.0, 0.05)
	_last = n
	return d
