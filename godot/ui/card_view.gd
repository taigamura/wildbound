class_name CardView
extends Container
## One card face, the Crystal Foil look. Laid out in design px of an 85×113 card and scaled by its
## width (`u`), so the hand (70–88 px), the hold preview (2×), and the reward, upgrade and Collection
## cards share one anatomy:
##   crystal rail (left): one crystal per energy of cost (a 0-cost card: one hollow crystal), the
##     number under them from 3; crystals you can't afford yet are red outlines, a cost cut (−1
##     upgrade, discounts, Quickfuse) leaves hollow ones
##   face window: every living teammate who can play the card (S.card_faces), split for 2 or 3;
##     a glyph for cards with no creature (reward options, undiscovered species)
##   name, a rules box of fixed height, and a status strip under it (Strong, upgraded, can't afford)
##   foil by slot: Strike plain, Skill crosshatch, Signature gold double frame and a moving sheen
## Off-element cards are desaturated with a swap chip in the window; dead ones grey with KO over it.
## Colours are this file's own constants (the in-game tokens: the card always sits on the diorama).

const W0 := 85.0   # design width; every length below is design px × u
## Where a card is used (kept for callers); every variant is 3:4 with the same anatomy.
const VARIANTS := {"hand": {}, "reward": {}, "mini": {}, "coll": {}, "lo": {}}

const INK := Color("#f3ead3")
const INK2 := Color("#cdbf9f")
const NAVY2 := Color("#0b1024")
const GROUND := [Color("#1a2342"), Color("#0c1126")]
const SIG_GROUND := [Color("#24305a"), Color("#111833")]
const BRASS := Color("#c9a24a")
const GOLD := Color("#f2d68c")
const RED := Color("#ff6b5e")
const CRYSTAL := [Color("#e6fbff"), Color("#57c8ff"), Color("#2178c2")]
const CRYSTAL_GLOW := Color("#6fd3ff")
const CRYSTAL_INK := Color("#bfe9ff")
const EL_C := {"ember": Color("#ec7a3c"), "tide": Color("#3f9de4"), "thorn": Color("#5cc062"), "volt": Color("#efc63a")}
const FACE_SH := preload("res://ui/card_face.gdshader")
const FOIL_SH := preload("res://ui/card_foil.gdshader")
const Manifest := preload("res://art/hd2d/manifest.gd")

var v: Dictionary = VARIANTS.hand
var c := GOLD           # element colour (or a reward option's colour)
var key := ""           # what's painted (Ui skips identical repaints)

# visual states
var lift := false       # held in the hand
var armed := false      # swiped far enough to play on release
var sel := false        # picked (upgrade screen, pending unlock)
var pressed_state := 0  # Collection: 1 equipped, -1 not equipped, 0 neither
var bench := false      # off-element: swap to a creature of its element to play it
var dead := false       # no living teammate of its element: swipe to discard
var locked := false
var empty := true

var bg := RRect.new()
var nm := _lbl("display")
var tx := _lbl("body", true)
var _under := _Layer.new()   # crosshatch, rail, crystals, divider, Signature inner frame
var _win := RRect.new()      # face window ground
var _faces := Control.new()
var _over := _Layer.new()    # face frame, separators, KO shade
var _ko := _lbl("display")
var _cost_l := _lbl("num")
var _foil := ColorRect.new()
var _strip := Control.new()
var _chip := _Layer.new()
var _face_mat := ShaderMaterial.new()

var _args: Array = []        # how it was painted, for copy_from
var _slot := "strike"
var _cost := 0
var _base := 0               # crystals: the cost before cuts; -1 = no crystals (reward options)
var _energy := -1.0          # current energy, for red crystals and "Need N more"; < 0 = not shown
var _face_list: Array = []   # [species, element] per face, the card's owner first
var _glyph := ""
var _tags: Array = []        # [full text, short text, kind]
var _lock_n := 0
var _sat := 1.0
var _bright := 1.0

## A Control that draws through a callback (layers between the card's children).
class _Layer extends Control:
	var paint: Callable

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if paint.is_valid():
			paint.call(self)

func _init(variant := "hand") -> void:
	v = VARIANTS[variant]
	mouse_filter = MOUSE_FILTER_IGNORE
	_under.paint = _draw_under
	_over.paint = _draw_over
	_chip.paint = _draw_chip
	_win.look({"mode": "radial", "rc": Vector2(0.5, 0.7), "s1": 1.0, "s_end": 0.85})
	_faces.clip_contents = true
	_faces.mouse_filter = MOUSE_FILTER_IGNORE
	_face_mat.shader = FACE_SH
	_ko.text = "KO"
	_foil.material = ShaderMaterial.new()
	(_foil.material as ShaderMaterial).shader = FOIL_SH
	_foil.mouse_filter = MOUSE_FILTER_IGNORE
	_strip.mouse_filter = MOUSE_FILTER_IGNORE
	# tests/ui_check.gd: corner pieces must not cover the card's text
	_strip.set_meta("deco", "bl")
	_chip.set_meta("deco", "tr")
	for n in [bg, _under, _win, _faces, _over, _ko, nm, tx, _cost_l, _foil, _strip, _chip]:
		add_child(n)
	resized.connect(update_minimum_size)
	set_process(false)
	restyle()

# ------------------------------------------------------------------ painting

## A creature's card. o: slot ("strike" "skill" "sig": the foil), cost (now), base (before cuts;
## default cost), faces ([species, element] list; empty = the card's glyph), bench, dead,
## strong (the multiplier, or true for ×1.5), upgraded ("power"/"+30%" or "cost"/"−1"),
## pow (scales the rules text), energy (shows what can't be afforded).
func face(def: Dictionary, el, o := {}) -> CardView:
	_args = ["face", def, el, o]
	dead = o.get("dead", false)
	bench = o.get("bench", false) and not dead
	c = EL_C.get(str(el), GOLD)
	_slot = o.get("slot", "strike")
	_cost = int(o.get("cost", def.cost))
	_base = maxi(_cost, int(o.get("base", _cost)))
	_energy = o.get("energy", -1.0)
	_face_list = o.get("faces", [])
	_glyph = UiKit.glyph_for(def, el)
	_tags.clear()
	var strong = o.get("strong", 0.0)
	if strong is bool:
		strong = 1.5 if strong else 0.0
	var up := str(o.get("upgraded", ""))
	if not dead and strong > 1.0:
		_tags.append(["Strong ×" + Data.num(strong), "×" + Data.num(strong), "strong"])
	if not dead and up in ["power", "+30%"]:
		_tags.append(["+30% effect", "+30%", "up"])
	elif not dead and up in ["cost", "−1"]:
		_tags.append(["−1 cost", "−1", "up"])
	var text: String = ("Swipe to discard for %d" % Data.BAL.discard_cost) if dead else Data.card_text(def, o.get("pow", 1.0))
	_paint_body(def.name, text)
	return self

## A plain option card (reward screen): a glyph in the window, name and text, no cost.
func option(glyph: String, name: String, text: String, color: Color) -> CardView:
	_args = ["option", glyph, name, text, color]
	dead = false
	bench = false
	c = color
	_slot = "strike"
	_cost = 0
	_base = -1
	_energy = -1.0
	_face_list = []
	_glyph = glyph
	_tags.clear()
	_paint_body(name, text)
	return self

## Paint the same card as `o` (the hold preview copies the held hand card).
func copy_from(o: CardView) -> void:
	if o._args.is_empty() or o.empty:
		clear_face()
		return
	if o._args[0] == "face":
		face(o._args[1], o._args[2], o._args[3])
	else:
		option(o._args[1], o._args[2], o._args[3], o._args[4])
	set_energy(o._energy)
	key = o.key

## Current energy: crystals that can't be afforded turn red, and the strip says how many more.
func set_energy(e: float) -> void:
	var was := floorf(_energy) if _energy >= 0.0 else -1.0
	_energy = e
	if empty or _base < 0 or floorf(e) == was:
		return
	_build_tags()
	_under.queue_redraw()
	restyle()

## The price tag on a locked Collection card, in the strip.
func add_lock(n: int, _el: String) -> void:
	locked = true
	_lock_n = n
	_build_tags()
	restyle()

func clear_face() -> void:
	empty = true
	key = ""
	_args = []
	UiKit.clear(_faces)
	restyle()

func _paint_body(name: String, text: String) -> void:
	nm.text = name
	tx.text = text
	locked = false
	_build_faces()
	_build_tags()
	empty = false
	restyle()

func _poor() -> bool:
	return _energy >= 0.0 and _base >= 0 and not bench and _cost > floorf(_energy)

func _build_tags() -> void:
	var list: Array = _tags.duplicate()
	if _poor():
		var n := _cost - floori(_energy)
		list.push_front(["Need %d more" % n, "Need %d" % n, "poor"])
	if locked:
		list.push_front(["%d Essence" % _lock_n, str(_lock_n), "lock"])
	UiKit.clear(_strip)
	for t in list:
		var l := _lbl("body")
		l.set_meta("tag", t)
		_strip.add_child(l)
	queue_sort()

func _build_faces() -> void:
	UiKit.clear(_faces)
	var n := _face_list.size()
	if n == 0:
		var g := TextureRect.new()
		g.texture = Glyphs.tex(_glyph)
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		g.mouse_filter = MOUSE_FILTER_IGNORE
		g.set_meta("glyph", true)
		_faces.add_child(g)
		return
	# slot aspect in design px (window 60 or 57 × 42, 1 px between faces)
	var ww := 57.0 if _slot == "sig" else 60.0
	var aspect := ((ww - (n - 1)) / n) / 42.0
	for i in n:
		var f: Array = _face_list[i]
		var t := TextureRect.new()
		t.texture = face_tex(f[0], f[1], aspect, Vector2(0.55, 0.35) if n == 3 else Vector2(0.5, 0.4))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.material = _face_mat
		t.mouse_filter = MOUSE_FILTER_IGNORE
		_faces.add_child(t)

# ------------------------------------------------------------------ faces

static var _face_cache := {}

## A species' face crop in its window slot: the in-game texture (recoloured exactly as on stage)
## cropped to the manifest's `face` rect, then to the slot's aspect like CSS object-fit: cover at
## object-position `focus`.
static func face_tex(species: String, element: String, aspect: float, focus := Vector2(0.5, 0.4)) -> AtlasTexture:
	var k := "%s|%s|%.3f|%s" % [species, element, aspect, focus]
	if _face_cache.has(k):
		return _face_cache[k]
	var e := Manifest.entry(species)
	var tex := Actor.texture_for(e, element)
	var r := face_rect(e, tex.get_size())
	var crop := r
	if aspect >= r.size.x / r.size.y:
		crop.size.y = r.size.x / aspect
		crop.position.y += (r.size.y - crop.size.y) * focus.y
	else:
		crop.size.x = r.size.y * aspect
		crop.position.x += (r.size.x - crop.size.x) * focus.x
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = crop
	_face_cache[k] = at
	return at

## The manifest entry's face rect in texture px. Without one: a square of side 0.30 × the image
## height centred on `head`, clamped inside the image.
static func face_rect(entry: Dictionary, sz: Vector2) -> Rect2:
	if entry.has("face"):
		var f: Rect2 = entry.face
		return Rect2(f.position * sz, f.size * sz)
	var side := minf(0.3 * sz.y, sz.x)
	var head: Vector2 = entry.get("head", Vector2(0.5, 0.3)) * sz
	var p := (head - Vector2(side, side) / 2.0).clamp(Vector2.ZERO, sz - Vector2(side, side))
	return Rect2(p, Vector2(side, side))

# ------------------------------------------------------------------ fonts

static var _fonts := {}

## "display" (Pixelify Sans Bold: names, KO), "num" (Pixelify Sans Medium: the cost) or "body"
## (Atkinson Hyperlegible Bold: rules text and strips).
static func font(k: String) -> Font:
	if not _fonts.has(k):
		if k == "body":
			_fonts[k] = load("res://ui/fonts/atkinson-700.ttf")
		else:
			var fv := FontVariation.new()
			fv.base_font = load("res://ui/fonts/pixelify-sans.ttf")
			fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700 if k == "display" else 500}
			_fonts[k] = fv
	return _fonts[k]

static func _lbl(fk: String, wrap := false) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font(fk))
	l.add_theme_constant_override("line_spacing", 0)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l

## The largest size from `fs` down that fits `text` in w (one line) or w × h (wrapped).
static func _fit(l: Label, fs: int, w: float, h := -1.0) -> int:
	var f: Font = l.get_theme_font("font")
	while fs > 6:
		if h < 0.0:
			if f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
				break
		elif f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs).y <= h:
			break
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)
	return fs

# ------------------------------------------------------------------ look

## CSS saturate() + brightness() for everything inside the card (off-element and dead dimming).
func _tone(col: Color) -> Color:
	var l := col.r * 0.2126 + col.g * 0.7152 + col.b * 0.0722
	var g := Color(l, l, l, col.a).lerp(col, _sat)
	return Color(g.r * _bright, g.g * _bright, g.b * _bright, col.a)

func _u() -> float:
	return maxf(size.x, 1.0) / W0

## The face window in card px.
func _win_rect() -> Rect2:
	var u := _u()
	return Rect2(20.0 * u, (8.0 if _slot == "sig" else 7.0) * u, (57.0 if _slot == "sig" else 60.0) * u, 42.0 * u)

func _frame_c() -> Color:
	return _tone(GOLD) if _slot == "sig" else _tone(c.lerp(Color.BLACK, 0.2))

func restyle() -> void:
	visible = not empty
	var u := _u()
	var sig := _slot == "sig"
	_sat = 0.0 if dead else (0.25 if bench else 1.0)
	_bright = 0.5 if dead else (0.55 if bench else 1.0)
	if locked:
		_bright *= 0.6
	var gr: Array = SIG_GROUND if sig else GROUND
	var d := {"radius": 6.0 * u, "angle": 180.0, "c0": _tone(gr[0]), "c1": _tone(gr[1]), "s1": 1.0, "s_end": 1.0,
		"border_w": 1.0, "border_c": _tone(GOLD if sig else c.lerp(Color.BLACK, 0.4)),
		"sh_off": Vector2(0, 4.0 * u), "sh_c": Color(0, 0, 0, 0.3), "ring_w": 0.0, "glow": 6.0, "glow_c": Color(0, 0, 0, 0.3)}
	if lift:
		d.ring_w = 2.0
		d.ring_c = UiKit.alpha(c, 0.75)
		d.glow = 18.0
		d.glow_c = Color(0, 0, 0, 0.4)
	if pressed_state == 1:
		d.ring_w = 2.0
		d.ring_c = c
		d.glow = 14.0
		d.glow_c = UiKit.alpha(c, 0.45)
	if sel:
		d.ring_w = 2.0
		d.ring_c = GOLD
	if armed:
		d.ring_w = 2.0
		d.ring_c = Color.WHITE
		d.glow = 26.0
		d.glow_c = UiKit.alpha(c, 0.8)
	bg.look(d)
	_win.look({"radius": 4.0 * u, "c0": _tone(c.lerp(GROUND[1], 0.45)), "c1": _tone(GROUND[1])})
	_face_mat.set_shader_parameter("sat", _sat)
	_face_mat.set_shader_parameter("bright", _bright)
	for g in _faces.get_children():
		if g.has_meta("glyph"):
			g.self_modulate = _tone(c)
	var fm := _foil.material as ShaderMaterial
	fm.set_shader_parameter("sat", _sat)
	fm.set_shader_parameter("bright", _bright)
	_foil.visible = sig and not empty
	set_process(_foil.visible)
	nm.add_theme_color_override("font_color", _tone(INK))
	tx.add_theme_color_override("font_color", _tone(INK2))
	_cost_l.text = str(_cost) if _base >= 0 and _cost >= 3 else ""
	_cost_l.add_theme_color_override("font_color", _tone(RED if _poor() else CRYSTAL_INK))
	_ko.visible = dead
	_ko.add_theme_color_override("font_color", Color.WHITE)
	_chip.visible = bench
	modulate.a = 0.62 if pressed_state == -1 and not sel else 1.0
	_under.queue_redraw()
	_over.queue_redraw()
	_chip.queue_redraw()
	queue_sort()

func _process(_dt: float) -> void:
	(_foil.material as ShaderMaterial).set_shader_parameter("t", UiKit.now())

func _get_minimum_size() -> Vector2:
	return Vector2(0, round(size.x * 4.0 / 3.0))

func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var u := _u()
	var sig := _slot == "sig"
	var full := Rect2(Vector2.ZERO, size)
	for n in [bg, _under, _over, _foil]:
		fit_child_in_rect(n, full)
	bg.look({"radius": 6.0 * u, "sh_off": Vector2(0, 4.0 * u)})   # restyle may have run before the card had a size
	_win.look({"radius": 4.0 * u})
	var fm := _foil.material as ShaderMaterial
	fm.set_shader_parameter("rsize", size)
	fm.set_shader_parameter("radius", 6.0 * u)
	var wr := _win_rect()
	fit_child_in_rect(_win, wr)
	fit_child_in_rect(_faces, wr)
	fit_child_in_rect(_ko, wr)
	var faces := _faces.get_children()
	if faces.size() == 1 and faces[0].has_meta("glyph"):
		var g := roundf(wr.size.y * 0.6)
		faces[0].position = ((wr.size - Vector2(g, g)) / 2.0).round()
		faces[0].size = Vector2(g, g)
	else:
		var gap := maxf(1.0, roundf(u))
		var sw := (wr.size.x - gap * (faces.size() - 1)) / maxf(1.0, faces.size())
		for i in faces.size():
			faces[i].position = Vector2(i * (sw + gap), 0)
			faces[i].size = Vector2(sw, wr.size.y)
	_ko.add_theme_font_size_override("font_size", roundi(15.0 * u))
	# name, rules box (shorter when the strip is in use), cost under the crystals
	var nr := Rect2(17.0 * u, 55.0 * u, 65.0 * u, 13.0 * u)
	_fit(nm, roundi(11.0 * u), nr.size.x)
	fit_child_in_rect(nm, nr)
	var tags := _strip.get_child_count() > 0
	var tr := Rect2(19.0 * u, (67.0 if tags else 69.0) * u, 62.0 * u, (22.0 if tags else 26.0) * u)
	_fit(tx, roundi(9.0 * u), tr.size.x, tr.size.y)
	fit_child_in_rect(tx, tr)
	_cost_l.add_theme_font_size_override("font_size", roundi(11.0 * u))
	fit_child_in_rect(_cost_l, Rect2((4.0 if sig else 0.0) * u, 62.0 * u, (13.0 if sig else 16.0) * u, 13.0 * u))
	# status strip: one tag spans it; two or more share it with their short text
	var sr := Rect2(19.0 * u, 96.0 * u, 61.0 * u, 13.0 * u)
	fit_child_in_rect(_strip, sr)
	var n := _strip.get_child_count()
	var tg := 2.0 * u
	var tw := (sr.size.x - tg * (n - 1)) / maxf(1.0, n)
	for i in n:
		var l: Label = _strip.get_child(i)
		var t: Array = l.get_meta("tag")
		l.text = t[0] if n == 1 else t[1]
		_style_tag(l, t[2], u)
		_fit(l, roundi(7.5 * u), tw - 4.0 * u)
		l.position = Vector2(i * (tw + tg), 0)
		l.size = Vector2(tw, sr.size.y)
	var cs := 16.0 * u
	fit_child_in_rect(_chip, Rect2(size.x - (10.0 if sig else 7.0) * u - cs, (10.0 if sig else 9.0) * u, cs, cs))

## Strip tag colours: Strong gold, upgraded tinted in the element, can't afford red, lock price.
func _style_tag(l: Label, kind: String, u: float) -> void:
	var bgc := GOLD
	var ink := Color("#2a1906")
	var line := Color(0, 0, 0, 0)
	match kind:
		"up":
			bgc = c.lerp(NAVY2, 0.7)
			ink = INK
			line = c
		"poor":
			bgc = Color("#4a1714")
			ink = Color("#ffc2b8")
			line = RED
		"lock":
			bgc = Color(0, 0, 0, 0.6)
			ink = c.lerp(Color.WHITE, 0.3)
			line = UiKit.alpha(c, 0.6)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bgc
	sb.border_color = line
	sb.set_border_width_all(1 if line.a > 0.0 else 0)
	sb.set_corner_radius_all(roundi(2.0 * u))
	sb.anti_aliasing = false
	l.add_theme_stylebox_override("normal", sb)
	l.add_theme_color_override("font_color", ink)

# ------------------------------------------------------------------ drawing

func _draw_under(l: Control) -> void:
	if empty:
		return
	var u := _u()
	var sig := _slot == "sig"
	if _slot == "skill":   # fine crosshatch: 1 px lines every 4 px both ways
		var col := Color(1, 1, 1, 0.04 * _bright)
		for n in [Vector2(0.70710678, -0.70710678), Vector2(-0.70710678, -0.70710678)]:
			var ds: Array = [0.0, n.dot(Vector2(size.x, 0)), n.dot(Vector2(0, size.y)), n.dot(size)]
			var d := ceilf(ds.min() / (4.0 * u)) * 4.0 * u
			while d <= ds.max():
				var seg := _clip_line(n, d, Rect2(Vector2.ZERO, size))
				if seg.size() == 2:
					l.draw_line(seg[0], seg[1], col, maxf(1.0, u), true)
				d += 4.0 * u
	# the rail
	var rr := Rect2(4.0 * u, 4.0 * u, 13.0 * u, size.y - 8.0 * u) if sig else Rect2(0, 0, 16.0 * u, size.y)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.35)
	if not sig:
		sb.corner_radius_top_left = roundi(6.0 * u)
		sb.corner_radius_bottom_left = roundi(6.0 * u)
	l.draw_style_box(sb, rr)
	l.draw_rect(Rect2(rr.end.x - 1.0, rr.position.y, 1.0, rr.size.y), Color(1, 1, 1, 0.08 * _bright))
	# crystals
	if _base >= 0:
		var cx := (10.0 if sig else 8.0) * u
		var y0 := (14.0 if sig else 13.0) * u
		var have := floori(_energy) if _energy >= 0.0 else 99
		for i in maxi(1, _base):
			var kind := "fill"
			if _base == 0:
				kind = "free"
			elif i >= _cost:
				kind = "gone"
			elif i >= have:
				kind = "miss"
			_crystal(l, Vector2(cx, y0 + i * 13.0 * u), 5.66 * u, kind, u)
	# divider under the window
	var x0 := 20.0 * u
	var x1 := size.x - 6.0 * u
	var xm := (x0 + x1) / 2.0
	var y := 52.0 * u
	var h := 2.0 * u
	var ce := _tone(c)
	var c0 := Color(ce, 0.0)
	l.draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(xm, y), Vector2(xm, y + h), Vector2(x0, y + h)]), PackedColorArray([c0, ce, ce, c0]))
	l.draw_polygon(PackedVector2Array([Vector2(xm, y), Vector2(x1, y), Vector2(x1, y + h), Vector2(xm, y + h)]), PackedColorArray([ce, c0, c0, ce]))
	if sig:   # inner brass frame of the gold double frame (the outer gold line is bg's border)
		var fr := StyleBoxFlat.new()
		fr.draw_center = false
		fr.border_color = _tone(BRASS)
		fr.set_border_width_all(maxi(1, roundi(u)))
		fr.set_corner_radius_all(roundi(3.0 * u))
		l.draw_style_box(fr, Rect2(Vector2(3.0, 3.0) * u, size - Vector2(6.0, 6.0) * u))

## One energy crystal: an 8 px square turned 45°, lit from the top; outlines for missing (red),
## cut ("gone") and free ones.
func _crystal(l: Control, p: Vector2, r: float, kind: String, u: float) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	var line := Color(0, 0, 0, 0)
	match kind:
		"fill":
			for k in 3:
				var g := r + (k + 1) * 1.3 * u
				l.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -g), p + Vector2(g, 0), p + Vector2(0, g), p + Vector2(-g, 0)]),
					_tone(Color(CRYSTAL_GLOW, 0.13)))
			l.draw_polygon(pts, PackedColorArray([_tone(CRYSTAL[0]), _tone(CRYSTAL[1]), _tone(CRYSTAL[2]), _tone(CRYSTAL[1])]))
			return
		"miss":
			l.draw_colored_polygon(pts, _tone(Color(1, 0.31, 0.24, 0.18)))
			line = RED
		"gone":
			line = Color(0.75, 0.91, 1, 0.4)
		"free":
			line = Color(0.75, 0.91, 1, 0.55)
	var w := maxf(1.0, u)
	var ri := r - w * 0.7
	var ol := PackedVector2Array([p + Vector2(0, -ri), p + Vector2(ri, 0), p + Vector2(0, ri), p + Vector2(-ri, 0), p + Vector2(0, -ri)])
	l.draw_polyline(ol, _tone(line), w, true)

## The part of the line {p : p·n = d} inside r (empty if it misses).
static func _clip_line(n: Vector2, d: float, r: Rect2) -> PackedVector2Array:
	var t := Vector2(-n.y, n.x)
	var o := n * d
	var lo := -INF
	var hi := INF
	for ax in 2:
		var tv: float = t[ax]
		var ov: float = o[ax]
		var mn: float = r.position[ax]
		var mx: float = r.end[ax]
		if absf(tv) < 1e-6:
			if ov < mn or ov > mx:
				return PackedVector2Array()
			continue
		var a := (mn - ov) / tv
		var b := (mx - ov) / tv
		lo = maxf(lo, minf(a, b))
		hi = minf(hi, maxf(a, b))
	if hi <= lo:
		return PackedVector2Array()
	return PackedVector2Array([o + t * lo, o + t * hi])

func _draw_over(l: Control) -> void:
	if empty:
		return
	var u := _u()
	var wr := _win_rect()
	var fc := _frame_c()
	if dead:   # KO shade, confined to the window
		l.draw_rect(wr, Color(0, 0, 0, 0.45))
	var faces := _faces.get_children()
	if faces.size() > 1:
		for i in range(1, faces.size()):
			var f: Control = faces[i]
			var gap := maxf(1.0, roundf(u))
			l.draw_rect(Rect2(wr.position.x + f.position.x - gap, wr.position.y, gap, wr.size.y), fc)
	var fr := StyleBoxFlat.new()
	fr.draw_center = false
	fr.border_color = fc
	fr.set_border_width_all(maxi(1, roundi(u)))
	fr.set_corner_radius_all(roundi(4.0 * u))
	l.draw_style_box(fr, wr)

## Swap chip: a disc in the card's element colour with the swap glyph, ringed in navy.
func _draw_chip(l: Control) -> void:
	var u := l.size.x / 16.0
	var cen := l.size / 2.0
	var r := l.size.x / 2.0
	for k in 3:
		l.draw_circle(cen, r + 1.5 * u + (k + 1) * 1.2 * u, Color(c, 0.14))
	l.draw_circle(cen, r + 1.5 * u, NAVY2)
	l.draw_circle(cen, r, c)
	var g := 10.0 * u
	l.draw_texture_rect(Glyphs.tex("swap"), Rect2(cen - Vector2(g, g) / 2.0, Vector2(g, g)), false, NAVY2)
