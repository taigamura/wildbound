class_name UiKit
## Shared look for every screen: the style.css palette (with the HD-2D pack's overrides), fonts,
## the Theme, and small builders that stand in for the CSS classes (.lbl, .pill, .elchip, .orb, .tag, ...).

# ---- palette (game/src/style.css :root, HD-2D cssVars applied) ----
const NIGHT := Color("#0a0f1f")
const DEEP := Color("#141b34")
const DEEP2 := Color("#1c2547")
const PANEL := Color(22 / 255.0, 20 / 255.0, 34 / 255.0, 0.86)
const LINE := Color(1.0, 226 / 255.0, 170 / 255.0, 0.18)
const INK := Color("#f0f2ff")
const MUTE := Color("#98a1c8")
const NEUTRAL := Color("#ffd9a0")
const GOLD := Color("#ffcf6b")
const HP := Color("#6ff0a0")
const FOE := Color("#ff5a6e")
const SHIELD := Color("#8fe3ff")
const PURPLE := Color("#9b7bff")
const EL := {
	"ember": Color("#ff7a45"), "tide": Color("#3fb6ff"), "thorn": Color("#5fd36a"), "volt": Color("#ffd23f"),
}
const VARS := {
	"night": NIGHT, "deep": DEEP, "deep2": DEEP2, "panel": PANEL, "line": LINE, "ink": INK, "mute": MUTE,
	"neutral": NEUTRAL, "gold": GOLD, "hp": HP, "foe": FOE, "shield": SHIELD,
	"ember": Color("#ff7a45"), "tide": Color("#3fb6ff"), "thorn": Color("#5fd36a"), "volt": Color("#ffd23f"),
}

## Element colour as the UI draws it (TS elCss: the CSS variable, not ELEM.hex).
static func el_css(el) -> Color:
	return EL.get(str(el), NEUTRAL) if el else NEUTRAL

## Any colour the TS code passed around ("var(--gold)", "#ff5a6e", 0xff5a6e, Color) as a Color.
static func col(v, fallback := NEUTRAL) -> Color:
	if v is Color:
		return v
	if v is int:
		return Color.hex((v << 8) | 0xff)
	if v is String or v is StringName:
		var s := String(v)
		if s.begins_with("var(--"):
			return VARS.get(s.substr(6, s.length() - 7), fallback)
		if s in VARS:
			return VARS[s]
		if s.begins_with("#") and Color.html_is_valid(s):
			return Color(s)
	return fallback

## CSS color-mix(in srgb, a t%, b).
static func mix(a: Color, b: Color, t: float) -> Color:
	return Color(a.r * t + b.r * (1 - t), a.g * t + b.g * (1 - t), a.b * t + b.b * (1 - t), a.a * t + b.a * (1 - t))

static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)

# ---- fonts ----
static var _fonts := {}
static var _vars := {}
static var _theme: Theme

## "display" (Lilita One) or a Baloo 2 weight: "500" "700" "800".
static func font(k: String) -> Font:
	if _fonts.has(k):
		return _fonts[k]
	var path := "res://ui/fonts/lilita-one-400.woff2" if k == "display" else "res://ui/fonts/baloo2-%s.woff2" % k
	var f: FontFile = load(path)
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Apple Symbols", "Noto Sans Symbols 2", "Noto Sans Symbols2", "DejaVu Sans", "Noto Sans", "sans-serif"])
	f.fallbacks = [fb]
	_fonts[k] = f
	return f

## A font with CSS letter-spacing (in em of `size`).
static func spaced(k: String, size: int, em: float) -> Font:
	var px := int(round(em * size))
	if px == 0:
		return font(k)
	var key := "%s/%d" % [k, px]
	if not _vars.has(key):
		var fv := FontVariation.new()
		fv.base_font = font(k)
		fv.spacing_glyph = px
		_vars[key] = fv
	return _vars[key]

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("500")
	t.default_font_size = 14
	t.set_color("font_color", "Label", INK)
	t.set_constant("line_spacing", "Label", -3)
	t.set_color("default_color", "RichTextLabel", MUTE)
	var empty := StyleBoxEmpty.new()
	for s in ["panel", "focus"]:
		t.set_stylebox(s, "ScrollContainer", empty)
	t.set_stylebox("panel", "PanelContainer", empty)
	t.set_stylebox("normal", "RichTextLabel", empty)
	t.set_stylebox("focus", "RichTextLabel", empty)
	for sb in ["VScrollBar", "HScrollBar"]:
		for s in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
			t.set_stylebox(s, sb, empty)
	_theme = t
	return t

# ---- builders ----
## Label. o: upper, ls (letter-spacing em), wrap, align ("center" "right"), ellipsis, shadow (Color),
## shadow_off (Vector2), outline (int), outline_c, lh (extra line spacing px), valign.
static func lbl(text: String, fk := "500", size := 14, color := INK, o := {}) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", spaced(fk, size, o.get("ls", 0.0)))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if o.get("upper", false):
		l.uppercase = true
	if o.get("wrap", false):
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 1
	match o.get("align", ""):
		"center": l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		"right": l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if o.has("valign"):
		l.vertical_alignment = o.valign
	if o.get("ellipsis", false):
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.custom_minimum_size.x = 1
	if o.has("shadow"):
		l.add_theme_color_override("font_shadow_color", o.shadow)
		var so: Vector2 = o.get("shadow_off", Vector2(0, 2))
		l.add_theme_constant_override("shadow_offset_x", int(so.x))
		l.add_theme_constant_override("shadow_offset_y", int(so.y))
		if o.has("shadow_outline"):
			l.add_theme_constant_override("shadow_outline_size", o.shadow_outline)
	if o.has("outline"):
		l.add_theme_constant_override("outline_size", o.outline)
		l.add_theme_color_override("font_outline_color", o.get("outline_c", Color.BLACK))
	l.add_theme_constant_override("line_spacing", o.get("lh", -3))
	return l

## BBCode label for mixed text ([b] = Baloo 800 in ink). Fits its content height.
static func rich(bb: String, size := 14, color := MUTE, fk := "500", align := "") -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size.x = 1
	r.add_theme_font_override("normal_font", font(fk))
	r.add_theme_font_override("bold_font", font("800"))
	for s in ["normal_font_size", "bold_font_size"]:
		r.add_theme_font_size_override(s, size)
	r.add_theme_color_override("default_color", color)
	r.add_theme_constant_override("line_separation", -2)
	r.text = ("[center]%s[/center]" % bb) if align == "center" else bb
	return r

static func flat(bg: Color, radius := 0.0, border := 0.0, border_c := Color(0, 0, 0, 0), pad := Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(int(radius))
	s.corner_detail = 8
	s.anti_aliasing = true
	if border > 0:
		s.set_border_width_all(int(ceil(border)))
		s.border_color = border_c
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	return s

static func glow_box(s: StyleBoxFlat, c: Color, sz: float, off := Vector2.ZERO) -> StyleBoxFlat:
	s.shadow_color = c
	s.shadow_size = int(sz)
	s.shadow_offset = off
	return s

static func panel(style: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func hbox(sep := 8, align := BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.alignment = align
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

static func vbox(sep := 8, align := BoxContainer.ALIGNMENT_BEGIN) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.alignment = align
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

static func grid(cols: int, sep := 8, vsep := -1) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep if vsep < 0 else vsep)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g

static func flow(sep := 5, center := false) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	if center:
		f.alignment = FlowContainer.ALIGNMENT_CENTER
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f

static func spacer(expand := true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

## Tinted SVG glyph at a fixed size.
static func icon(key: String, sz: float, color := INK) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Glyphs.tex(key)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(sz, sz)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.self_modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return t

## Centred box of a fixed size holding `child` over an optional full-size background.
static func boxed(child: Control, sz: Vector2, bg: Control = null) -> Box:
	var b := Box.new(sz)
	if bg:
		b.add_child(Box.fill(bg))
	b.add_child(child)
	return b

## Radial-gradient element orb (.bmon .orb, .starter .orb, ...): c lit from the upper left, glyph in dark ink.
static func orb_bg(c: Color, radius := -1.0) -> RRect:
	return RRect.new({"radius": radius if radius >= 0 else 999.0, "mode": "radial", "rc": Vector2(0.35, 0.3),
		"c0": mix(c, Color.WHITE, 0.7), "c1": c, "s1": 0.55, "c2": mix(c, Color.BLACK, 0.5)})

static func orb(c: Color, sz: float, glyph: String, gsz: float, glyph_c := Color(0, 0, 0, 0.55)) -> Box:
	return boxed(icon(glyph, gsz, glyph_c) if glyph != "" else Control.new(), Vector2(sz, sz), orb_bg(c))

## Square tinted tile with a glyph (.node .orb, .ptmain .orb).
static func tile(c: Color, sz: float, radius: float, glyph: String, gsz: float) -> Box:
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", flat(alpha(c, 0.25), radius))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return boxed(icon(glyph, gsz, c), Vector2(sz, sz), bg)

## .elchip: element glyph + name in a tinted chip.
static func elchip(el, name := "") -> PanelContainer:
	var c := el_css(el)
	var p := panel(flat(alpha(c, 0.22), 6, 1, alpha(c, 0.45), Vector4(7, 4, 7, 3)))
	var h := hbox(4)
	h.add_child(icon(str(el), 11, c))
	h.add_child(lbl(name, "800", 10, c, {"upper": true, "ls": 0.1}))
	p.add_child(h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

## .tag: small status chip.
static func tag(text: String, c: Color) -> PanelContainer:
	var p := panel(flat(Color(1, 1, 1, 0.08), 6, 0, Color(), Vector4(7, 4, 7, 3)))
	p.add_child(lbl(text, "800", 10, c, {"upper": true, "ls": 0.06}))
	return p

## .ess: icon + number chip (essence, loot, costs).
static func ess(glyph: String, c: Color, text: String) -> PanelContainer:
	var p := panel(flat(alpha(c, 0.14), 7, 1, alpha(c, 0.35), Vector4(8, 4, 8, 3)))
	var h := hbox(4)
	h.add_child(icon(glyph, 11, c))
	h.add_child(lbl(text, "800", 12, c))
	p.add_child(h)
	return p

static func eyebrow(text: String) -> Label:
	return lbl(text, "800", 11, MUTE, {"upper": true, "ls": 0.2})

static func h2(text: String) -> Label:
	return lbl(text, "display", 28, INK, {"wrap": true, "lh": -4})

static func sub(text: String, align := "") -> Label:
	return lbl(text, "500", 14, MUTE, {"wrap": true, "lh": 0, "align": align})

static func note(text: String) -> Label:
	return lbl(text, "700", 11, MUTE, {"wrap": true, "lh": -1})

static func best(text: String) -> Label:
	return lbl(text, "700", 12, MUTE, {"align": "center", "ls": 0.06, "wrap": true})

static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

## Real seconds since boot (UI motion that ignores hit-stop and slow-mo, like CSS in the TS build).
static func now() -> float:
	return Time.get_ticks_usec() / 1e6

## CSS cubic-bezier(x1,y1,x2,y2) evaluated at progress t.
static func bezier(t: float, x1: float, y1: float, x2: float, y2: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var u := t
	for i in 8:
		var x := 3.0 * (1 - u) * (1 - u) * u * x1 + 3.0 * (1 - u) * u * u * x2 + u * u * u - t
		var dx := 3.0 * (1 - u) * (1 - u) * x1 + 6.0 * (1 - u) * u * (x2 - x1) + 3.0 * u * u * (1 - x2)
		if absf(dx) < 1e-5:
			break
		u = clampf(u - x / dx, 0.0, 1.0)
	return 3.0 * (1 - u) * (1 - u) * u * y1 + 3.0 * (1 - u) * u * u * y2 + u * u * u

## Glyph for a card (TS glyphFor).
static func glyph_for(c, el) -> String:
	if c.get("dmg", 0) or c.get("from_shield", false):
		return str(el)
	if c.get("status"):
		return str(Data.STATUS_EL[c.status])
	if c.get("shield", 0) or c.get("shield_team", 0) or c.get("reflect", 0):
		return "shield"
	if c.get("heal", 0) or c.get("heal_team", 0):
		return "heart"
	if c.get("energy", 0):
		return "spark"
	return "star"
