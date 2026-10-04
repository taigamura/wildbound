class_name CardView
extends Container
## One card face (.card): gradient body in its element colour, cost bubble, element orb chip,
## bench-swap marker, STRONG badge, upgrade tag, glyph, name and rules text. Used by the hand, the
## reward/upgrade screens and the collection. Size variants via `v` (padding, font sizes, glyph %, aspect).

const VARIANTS := {
	"hand": {"pad": Vector4(5, 22, 5, 7), "nm": 14, "tx": 10, "gl": 0.34, "aspect": true},
	"reward": {"pad": Vector4(5, 26, 5, 7), "nm": 16, "tx": 11, "gl": 0.34, "aspect": true},
	"mini": {"pad": Vector4(5, 20, 5, 7), "nm": 13, "tx": 10, "gl": 0.34, "aspect": true},
	"coll": {"pad": Vector4(5, 20, 5, 7), "nm": 13, "tx": 10, "gl": 0.34, "aspect": false, "min_h": 84},
	"lo": {"pad": Vector4(4, 15, 4, 7), "nm": 13, "tx": 10, "gl": 0.24, "aspect": false, "min_h": 0},
}

var v: Dictionary = VARIANTS.hand
var c := UiKit.NEUTRAL
var bg := RRect.new()
var box := UiKit.vbox(3)
var gl: TextureRect
var nm: Label
var tx: Label
var decos: Array = []   # [Control, corner "tl" "tr" "bl" "br", offset Vector2]
var key := ""           # what's painted (TS dataset.k)
const DEAD_C := Color("#8c8c9c")   # a dead card (its element all fainted) is drained of its element colour

# visual states (CSS classes)
var lift := false
var armed := false
var sel := false
var pressed_state := 0   # aria-pressed: 0 none, 1 true, -1 false
var bench := false
var dead := false
var locked := false
var empty := true

func _init(variant := "hand") -> void:
	v = VARIANTS[variant]
	mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(box)
	resized.connect(update_minimum_size)
	restyle()

## TS cardFace(c, el, o). o: cost, chip (show the element orb), bench, dead, strong, upgraded, pow.
func face(def: Dictionary, el, o := {}) -> CardView:
	dead = o.get("dead", false)
	c = DEAD_C if dead else UiKit.el_css(el)
	_reset()
	_deco(_cost_bubble(str(o.get("cost", def.cost))), "tl", Vector2(-6, -7))
	if o.get("chip", false) and el != null and str(el) != "":   # cards belong to an element, not a creature
		_deco(UiKit.orb(c, 22, str(el), 13), "tr", Vector2(-5, -6))
	if o.get("bench", false) and not dead:   # swap to a creature of this element first
		var s := UiKit.icon("swap", 14, UiKit.mix(c, Color.WHITE, 0.35))
		_deco(s, "tr", Vector2(5, 22))
	if o.get("strong", false) and not dead:
		_deco(_badge("STRONG", Vector4(4, 3, 4, 2), 4), "bl", Vector2(5, 5))
	if str(o.get("upgraded", "")) != "" and not dead:
		_deco(_badge(str(o.upgraded), Vector4(3, 2, 3, 2), 3), "br", Vector2(5, 5))
	_body(UiKit.glyph_for(def, el), def.name, "Fainted: swipe to discard" if dead else Data.card_text(def, o.get("pow", 1.0)))
	bench = o.get("bench", false)
	empty = false
	restyle()
	return self

## A plain option card (reward screen): glyph, name, text, no cost.
func option(glyph: String, name: String, text: String, color: Color) -> CardView:
	c = color
	_reset()
	_body(glyph, name, text)
	empty = false
	restyle()
	return self

## The price tag on a locked collection card (.lock).
func add_lock(n: int, el: String) -> void:
	var p := UiKit.panel(UiKit.flat(Color(0, 0, 0, 0.6), 5, 1, UiKit.alpha(c, 0.5), Vector4(6, 3, 6, 2)))
	var h := UiKit.hbox(2)
	h.add_child(UiKit.lbl(str(n), "800", 10, c))
	h.add_child(UiKit.icon(el, 11, c))
	p.add_child(h)
	p.set_meta("lock", true)
	_deco(p, "tr", Vector2(5, 5))
	locked = true
	restyle()

func clear_face() -> void:
	_reset()
	empty = true
	key = ""
	restyle()

func _reset() -> void:
	for d in decos:
		d[0].queue_free()
	decos.clear()
	UiKit.clear(box)
	gl = null; nm = null; tx = null
	locked = false

func _body(glyph: String, name: String, text: String) -> void:
	gl = UiKit.icon(glyph, 24, c)
	box.add_child(gl)
	nm = UiKit.lbl(name, "display", v.nm, UiKit.INK, {"align": "center", "lh": -4})
	box.add_child(nm)
	tx = UiKit.lbl(text, "700", v.tx, UiKit.MUTE, {"align": "center", "wrap": true, "lh": -3})
	box.add_child(tx)
	queue_sort()

func _deco(n: Control, corner: String, off: Vector2) -> void:
	add_child(n)
	decos.append([n, corner, off])
	queue_sort()

func _cost_bubble(t: String) -> Control:
	var b := RRect.new({"radius": 13.0, "mode": "radial", "rc": Vector2(0.35, 0.3), "c0": Color.WHITE, "c1": Color("#c8b4ff"),
		"s1": 0.6, "c2": Color("#8f6cff"), "sh_off": Vector2(0, 2), "sh_c": Color("#4b2fa8")})
	var l := UiKit.lbl(t, "display", 15, Color("#1b1035"), {"align": "center"})
	var bx := UiKit.boxed(l, Vector2(26, 26), b)
	l.set_meta("off", Vector2(0, 1))
	return bx

func _badge(t: String, pad: Vector4, r: float) -> Control:
	var p := UiKit.panel(UiKit.flat(UiKit.GOLD, r, 0, Color(), pad))
	p.add_child(UiKit.lbl(t, "800", 8, Color("#241600"), {"ls": 0.06, "lh": -6}))
	return p

func restyle() -> void:
	visible = not empty
	var d := {"radius": 13.0, "angle": 172.0, "c0": UiKit.mix(c, UiKit.DEEP2, 0.42), "c1": UiKit.DEEP, "s1": 1.0, "s_end": 0.62,
		"border_w": 1.5, "border_c": UiKit.alpha(c, 0.45 if bench else 0.7), "sh_off": Vector2(0, 5), "sh_c": Color(0, 0, 0, 0.4),
		"ring_w": 0.0, "glow": 0.0}
	if lift:
		d.ring_w = 2.0
		d.ring_c = UiKit.alpha(c, 0.75)
		d.glow = 22.0
		d.glow_c = Color(0, 0, 0, 0.35)
	if pressed_state == 1:
		d.ring_w = 2.0
		d.ring_c = c
		d.glow = 16.0
		d.glow_c = UiKit.alpha(c, 0.45)
	if sel:
		d.ring_w = 2.0
		d.ring_c = UiKit.GOLD
	if armed:
		d.ring_w = 2.0
		d.ring_c = Color.WHITE
		d.glow = 30.0
		d.glow_c = UiKit.alpha(c, 0.8)
	bg.look(d)
	if gl:
		gl.self_modulate = c
	var dim := Color(0.6, 0.6, 0.6) if locked else Color.WHITE
	box.modulate = dim
	for x in decos:
		if not x[0].get_meta("lock", false):
			x[0].modulate = dim
	bg.modulate = dim if locked else Color.WHITE
	if pressed_state != 0:
		modulate.a = 0.62 if pressed_state == -1 and not sel else 1.0

func _get_minimum_size() -> Vector2:
	if v.aspect:
		return Vector2(0, round(size.x * 4.0 / 3.0))
	var p: Vector4 = v.pad
	return Vector2(0, maxf(v.get("min_h", 0), p.y + box.get_combined_minimum_size().y + p.w))

func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var p: Vector4 = v.pad
	var w := size.x
	fit_child_in_rect(bg, Rect2(Vector2.ZERO, size))
	var inner := maxf(1.0, w - p.x - p.z)
	if gl:
		var g := roundf(inner * v.gl)
		gl.custom_minimum_size = Vector2(g, g)
	if nm:
		var f: Font = nm.get_theme_font("font")
		var tw := f.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, v.nm).x
		var fs: int = v.nm if tw <= inner + 6 else maxi(9, int(floor(v.nm * (inner + 6) / tw)))
		nm.add_theme_font_size_override("font_size", fs)
	fit_child_in_rect(box, Rect2(p.x, p.y, inner, maxf(0, size.y - p.y - p.w)))
	for x in decos:
		var n: Control = x[0]
		var m := n.get_combined_minimum_size()
		var o: Vector2 = x[2]
		var pos := Vector2.ZERO
		match x[1]:
			"tl": pos = o
			"tr": pos = Vector2(w - m.x - o.x, o.y)
			"bl": pos = Vector2(o.x, size.y - m.y - o.y)
			"br": pos = Vector2(w - m.x - o.x, size.y - m.y - o.y)
		fit_child_in_rect(n, Rect2(pos, m))
