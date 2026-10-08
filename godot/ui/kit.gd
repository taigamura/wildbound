class_name UiKit
## Shared look for every screen: the warm HD-2D palette, the type system (Pixelify Sans display,
## Atkinson Hyperlegible body), the Theme, and small builders: windows (WinStyle), hairline lists (Rows),
## list rows, chips, portraits, labels. Mockup: "UI Directions" ideas 1-3 (docs/UI-QUEUE.md).

# ---- palette: parchment on navy glass, brass trim; element colours are accents only ----
const INK := Color("#f3ead3")        # parchment: primary text
const INK2 := Color("#cdbf9f")       # secondary text (subs, quiet buttons)
const MUTE := Color("#a3967a")       # muted text, inactive marks
const NAVY := Color("#121a33")       # window glass
const NAVY2 := Color("#0b1024")      # the deepest navy: gaps, wells, dark ink on gold
const BRASS := Color("#c9a24a")      # trim: window borders, quiet-button outlines
const GOLD_HI := Color("#f2d68c")    # highlight: selection, labels, studs, currency
const GOLD_LO := Color("#7a5a1c")    # shaded brass: passed steps, pressed edges
const PLAQUE_INK := Color("#2a1906") # dark brown text on the brass plaque
const HAIR := Color(201 / 255.0, 162 / 255.0, 74 / 255.0, 0.24)   # hairline between list rows
const SCRIM := Color(8 / 255.0, 11 / 255.0, 24 / 255.0)           # header scrim (alpha set where used)
const SEL_BG := Color("#24293a")     # selected row: navy with an 8% gold wash, opaque so a glow can't tint it
# older names, kept for existing callers and retargeted to the warm palette
const NIGHT := NAVY2
const DEEP := NAVY
const DEEP2 := Color("#1a2548")      # top of the window gradient
const PANEL := Color(18 / 255.0, 26 / 255.0, 51 / 255.0, 0.94)
const LINE := Color(201 / 255.0, 162 / 255.0, 74 / 255.0, 0.45)   # brass outline (quiet buttons, idle tiles)
const NEUTRAL := INK2
const GOLD := GOLD_HI
const HP := Color("#62d68a")
const FOE := Color("#e8565a")
const SHIELD := Color("#8fe3ff")
const EL := {
	"ember": Color("#ec7a3c"), "tide": Color("#3f9de4"), "thorn": Color("#5cc062"), "volt": Color("#efc63a"),
}
const VARS := {
	"night": NIGHT, "deep": DEEP, "deep2": DEEP2, "panel": PANEL, "line": LINE, "ink": INK, "mute": MUTE,
	"neutral": NEUTRAL, "gold": GOLD, "hp": HP, "foe": FOE, "shield": SHIELD,
	"ember": Color("#ec7a3c"), "tide": Color("#3f9de4"), "thorn": Color("#5cc062"), "volt": Color("#efc63a"),
}

# ---- type scale (px on the 390 canvas). Pixelify Sans sits on a grid of about 1/11 em, so display
# sizes are multiples of 11 and its pixels land whole on 1x shots and 3x phones alike.
const T_S := 12      # body small: labels, notes, chips
const T_M := 14      # body
const T_L := 16      # body large: lead lines
const D_S := 22      # display small: section titles, big numbers
const D_M := 33      # display: sheet titles
const D_L := 44      # display large: screen logos
const NAME := 16     # creature and item names in rows (display face)

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

## "display" = Pixelify Sans Bold (titles, names, numbers); "500" = Atkinson Hyperlegible Regular;
## "700" / "800" = Atkinson Hyperlegible Bold. The old faces (Lilita One, Baloo 2) stay as fallbacks,
## then system symbol fonts for the glyphs neither has (★ ✦ →).
static func font(k: String) -> Font:
	if _fonts.has(k):
		return _fonts[k]
	var f: Font
	if k == "display":
		var px := _file("pixelify-sans.ttf", "lilita-one-400.woff2")
		px.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED   # keep its pixels on whole px
		px.hinting = TextServer.HINTING_NONE
		var fv := FontVariation.new()
		fv.base_font = px
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
		f = fv
	else:
		f = _file("atkinson-400.ttf" if k == "500" else "atkinson-700.ttf", "baloo2-%s.woff2" % ("500" if k == "500" else "800"))
	_fonts[k] = f
	return f

## A bundled font file with a fallback chain: the old face, then system symbol fonts.
static func _file(name: String, old: String) -> FontFile:
	var f: FontFile = load("res://ui/fonts/" + name)
	if f.fallbacks.is_empty():
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Apple Symbols", "Noto Sans Symbols 2", "Noto Sans Symbols2", "DejaVu Sans", "Noto Sans", "sans-serif"])
		var o: FontFile = load("res://ui/fonts/" + old)
		o.fallbacks = [sys]
		f.fallbacks = [o, sys]
	return f

## A font with CSS letter-spacing (in em of `size`).
static func spaced(k: String, size: int, em: float) -> Font:
	var px := int(round(em * size))
	if px == 0:
		return font(k)
	var key := "%s/%d" % [k, px]
	if not _vars.has(key):
		var base := font(k)
		var fv: FontVariation
		if base is FontVariation:   # don't nest variations (the inner wght would be lost)
			fv = base.duplicate()
		else:
			fv = FontVariation.new()
			fv.base_font = base
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
	t.set_constant("line_spacing", "Label", 1)
	t.set_color("default_color", "RichTextLabel", INK2)
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
const BODY_LEAD := 4
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
	# `lh` was tuned for Baloo 2's tall line box (1.6 em); Atkinson's is 1.24 em, so body text gets
	# BODY_LEAD back to land near 1.3-1.5 em. The display face is about as tall as Lilita was.
	l.add_theme_constant_override("line_spacing", o.get("lh", -3) + (0 if fk == "display" else BODY_LEAD))
	return l

## BBCode label for mixed text ([b] = Atkinson Bold). Fits its content height.
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
	r.add_theme_constant_override("line_separation", 2)
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

## .chip: a dark pill with a coloured rim; the glyph carries the colour, the text stays parchment.
## Used for element mixes, wallet and loot counts, Essence.
static func chip(glyph: String, c: Color, text: String) -> PanelContainer:
	var p := panel(flat(Color(0, 0, 0, 0.35), 11, 1, alpha(c, 0.7), Vector4(8, 3, 8, 3)))
	p.custom_minimum_size.y = 22
	var h := hbox(4)
	if glyph != "":
		h.add_child(icon(glyph, 12, c))
	var l := lbl(text, "700", T_S, INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	p.add_child(h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

## .elchip: element glyph + name.
static func elchip(el, name := "") -> PanelContainer:
	return chip(str(el), el_css(el), name)

## .tag: small status chip (sentence case, no tracking).
static func tag(text: String, c: Color) -> PanelContainer:
	var p := panel(flat(Color(0, 0, 0, 0.35), 4, 0, Color(), Vector4(6, 2, 6, 2)))
	p.add_child(lbl(text, "700", T_S, c))
	return p

## .ess: icon + number chip (essence, loot, costs).
static func ess(glyph: String, c: Color, text: String) -> PanelContainer:
	return chip(glyph, c, text)

# ---- windows and lists (idea 3) ----
## The window frame StyleBox: double brass border on navy glass, gold studs on the top edge.
## `pad` = content margin (16 inside windows); `studs` off for small or nested frames.
static func window(pad := 16.0, studs := true) -> WinStyle:
	var w := WinStyle.new(pad)
	w.studs = studs
	return w.refresh()

## A PanelContainer framed as a window.
static func win(pad := 16.0, studs := true) -> PanelContainer:
	return panel(window(pad, studs))

## A list split by hairlines (see Rows). Put rows styled with row_style() in it.
static func rows() -> Rows:
	return Rows.new()

## A list row: flat and transparent (the hairlines separate rows); `sel` = the gold outline and faint gold
## wash that mark the chosen row. Glow is reserved for act-now rows (act_style).
static func row_style(sel := false, pad := Vector4(8, 10, 8, 10)) -> StyleBoxFlat:
	if sel:
		return flat(SEL_BG, 4, 1.5, GOLD_HI, pad)
	return flat(Color(0, 0, 0, 0), 4, 0, Color(), pad)

## A row or tile that wants a tap right now (pack ready): gold outline with a soft gold glow.
static func act_style(pad := Vector4(8, 10, 8, 10)) -> StyleBoxFlat:
	return glow_box(flat(SEL_BG, 4, 1.5, GOLD_HI, pad), alpha(GOLD_HI, 0.3), 8)

## A quiet well inside a window (an unlock offer, a stat, a detail block): darker glass with a
## hairline rim. `gold` = it holds the act-now choice (a gold rim instead).
static func inset(pad := Vector4(12, 10, 12, 10), gold := false) -> StyleBoxFlat:
	return flat(Color(0, 0, 0, 0.22), 4, 1, alpha(GOLD_HI, 0.55) if gold else HAIR, pad)

## Row content: a leading piece (portrait, tile), a name in the display face, a sub line, and an
## optional trailing piece (price, marker, button). Returns the HBox; put it in a Tap or a panel.
static func list_row(lead: Control, title: String, sub_text := "", trail: Control = null, title_c := INK) -> HBoxContainer:
	var h := hbox(12)
	if lead:
		lead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lead)
	var v := vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(lbl(title, "display", NAME, title_c, {"wrap": true, "lh": -2}))
	if sub_text != "":
		v.add_child(lbl(sub_text, "500", 13, INK2, {"wrap": true, "lh": -4}))
	h.add_child(v)
	if trail:
		trail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(trail)
	return h

## .por: element portrait, a lit orb inside a dark gap and an element ring (gold when `sel`).
## Rings are drawn inside the box, so it never spills.
static func por(c: Color, sz: float, glyph: String, sel := false) -> Box:
	var b := Box.new(Vector2(sz, sz))
	b.add_child(Box.fill(RRect.new({"radius": 999.0}).solid(GOLD_HI if sel else mix(c, Color.BLACK, 0.8))))
	var gap := RRect.new({"radius": 999.0}).solid(NAVY2)
	gap.custom_minimum_size = Vector2(sz - 2, sz - 2) if not sel else Vector2(sz - 3, sz - 3)
	b.add_child(gap)
	var o := RRect.new({"radius": 999.0, "mode": "radial", "rc": Vector2(0.4, 0.35),
		"c0": mix(mix(c, Color.WHITE, 0.85), c, 0.12), "c1": mix(c, NAVY2, 0.45)})
	o.custom_minimum_size = Vector2(sz - 6, sz - 6)
	b.add_child(o)
	if glyph != "":
		var g := icon(glyph, roundf(sz * 0.5), Color.WHITE)
		b.add_child(g)
	return b

## .bar: a thin rounded meter (HP outside battle, progress). `frac` 0..1 filled in `c`.
static func meter(frac: float, c := HP, h := 8.0) -> Control:
	var m := Control.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.custom_minimum_size.y = h
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := flat(Color(0, 0, 0, 0.5), h / 2.0, 1, Color(1, 1, 1, 0.08))
	var fg := flat(c, h / 2.0)
	m.draw.connect(func():
		m.draw_style_box(bg, Rect2(Vector2.ZERO, m.size))
		var w := roundf(m.size.x * clampf(frac, 0.0, 1.0))
		if w >= 1.0:
			m.draw_style_box(fg, Rect2(0, 0, maxf(w, h), m.size.y)))
	return m

## A progress bar for the pack meter: a dark track, the points banked before this run in shaded brass
## and this run's points in bright gold. Drive it with set_fill (cheap: it only redraws).
static func fill_bar(h := 10.0) -> Control:
	var m := Control.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.custom_minimum_size.y = h
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.set_meta("f", 0.0)
	m.set_meta("f0", 0.0)
	var bg := flat(Color(0, 0, 0, 0.5), 2, 1, alpha(BRASS, 0.45))
	m.draw.connect(func():
		m.draw_style_box(bg, Rect2(Vector2.ZERO, m.size))
		var inner := Rect2(Vector2(2, 2), m.size - Vector2(4, 4))
		var f: float = clampf(m.get_meta("f"), 0.0, 1.0)
		var f0: float = clampf(m.get_meta("f0"), 0.0, f)
		if f0 > 0.0:
			m.draw_rect(Rect2(inner.position, Vector2(roundf(inner.size.x * f0), inner.size.y)), GOLD_LO)
		if f > f0:
			var x0 := roundf(inner.size.x * f0)
			var r := Rect2(inner.position + Vector2(x0, 0), Vector2(roundf(inner.size.x * f) - x0, inner.size.y))
			m.draw_rect(r, GOLD_HI)
			m.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), mix(GOLD_HI, Color.WHITE, 0.6)))
	m.resized.connect(m.queue_redraw)
	return m

## Set a fill_bar: `f` filled (0..1), of which the part before `f0` is shaded (banked earlier).
static func set_fill(bar: Control, f: float, f0 := 0.0) -> void:
	bar.set_meta("f", f)
	bar.set_meta("f0", f0)
	bar.queue_redraw()

## Header scrim (mockup .scrim): navy fading to clear, behind text drawn over the scene.
## `solid` = share of the height at full strength before the fade.
static func scrim(solid := 0.7) -> RRect:
	return RRect.new({"radius": 0.0, "angle": 180.0, "c0": alpha(SCRIM, 0.88), "c1": alpha(SCRIM, 0.6), "s1": solid,
		"c2": alpha(SCRIM, 0.0)})

# ---- type roles (idea 2) ----
## .lbl: the gold sentence-case label over a section or a sheet (replaces tracked uppercase eyebrows).
static func eyebrow(text: String) -> Label:
	return lbl(text, "700", T_S, GOLD_HI)

## .disp: display-face text (titles, names, numbers).
static func disp(text: String, size := D_S, color := INK, o := {}) -> Label:
	var d := {"lh": -2}
	d.merge(o, true)
	return lbl(text, "display", size, color, d)

static func h2(text: String) -> Label:
	return lbl(text, "display", D_M, INK, {"wrap": true, "lh": -4})

static func sub(text: String, align := "") -> Label:
	return lbl(text, "500", T_M, INK2, {"wrap": true, "lh": -2, "align": align})

static func note(text: String) -> Label:
	return lbl(text, "500", T_S, INK2, {"wrap": true, "lh": -3})

static func best(text: String) -> Label:
	return lbl(text, "500", T_S, INK2, {"align": "center", "wrap": true})

static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

## Real seconds since boot (UI motion that ignores hit-stop and slow-mo, like CSS in the TS build).
static func now() -> float:
	return Platform.ticks_usec() / 1e6

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

# ---- map, reward and results pieces (UI-QUEUE items 8 and 10) ----
## UI colours of the materials (the Ember / Tide / Thorn accents), as Run.MAT_COL.
const MAT_C := {"sword": Color("#ec7a3c"), "orb": Color("#3f9de4"), "jewel": Color("#5cc062")}

## One wallet entry without a pill: a tinted glyph and a number (the map and reward footers).
static func stat(glyph: String, c: Color, text: String) -> HBoxContainer:
	var h := hbox(3)
	h.add_child(icon(glyph, 14, c))
	var l := lbl(text, "700", T_S, INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h

## The wallet as one row: gold, then each material (Meta.wallet() shape). Never wraps.
static func wallet_row(w: Dictionary, sep := 10) -> HBoxContainer:
	var h := hbox(sep)
	h.add_child(stat("coin", GOLD_HI, str(w.get("gold", 0))))
	for m in MAT_C:
		h.add_child(stat(m, MAT_C[m], str(w.get(m, 0))))
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return h

## A party member as a portrait with a thin HP bar under it and no name (names truncate at this size).
## `lead` = the gold ring. A knocked-out creature is dimmed with an empty bar.
static func party_por(c, sz := 30.0, lead := false) -> VBoxContainer:
	var v := vbox(4)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var p := por(el_css(c.el), sz, str(c.el), lead)
	if not c.alive or c.hp <= 0:
		p.modulate = Color(0.5, 0.5, 0.55)
	v.add_child(p)
	var frac: float = clampf(c.hp / float(c.max_hp), 0.0, 1.0)
	var m := meter(frac, HP if frac > 0.3 else FOE, 4.0)
	m.custom_minimum_size.x = sz
	m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(m)
	return v

## A loot or Essence chip sized for the ribbon (28 px tall, 14 px text).
static func loot_chip(glyph: String, c: Color, text: String) -> PanelContainer:
	var p := panel(flat(Color(0, 0, 0, 0.45), 14, 1, alpha(c, 0.8), Vector4(10, 4, 10, 4)))
	p.custom_minimum_size.y = 28
	var h := hbox(5)
	h.add_child(icon(glyph, 14, c))
	var l := lbl(text, "700", T_M, INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	p.add_child(h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

## A ribbon chip holding several glyph + number pairs after one word ("+ Essence  [ember] 9  [tide] 4").
## pairs: [[glyph, Color, text], ...].
static func multi_chip(word: String, pairs: Array) -> PanelContainer:
	var p := panel(flat(Color(0, 0, 0, 0.45), 14, 1, alpha(BRASS, 0.8), Vector4(10, 4, 10, 4)))
	p.custom_minimum_size.y = 28
	var h := hbox(8)
	var w := lbl(word, "700", T_M, INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(w)
	for pr in pairs:
		var s := hbox(3)
		s.add_child(icon(pr[0], 14, pr[1]))
		var l := lbl(pr[2], "700", T_M, INK, {"valign": VERTICAL_ALIGNMENT_CENTER})
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.add_child(l)
		h.add_child(s)
	p.add_child(h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

## The ribbon band behind "Victory" and a loot row: deep navy fading out at both ends between two
## gold hairlines. Put it behind content with Box.fill (it draws inside its rect).
static func ribbon_band() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var w := c.size.x
		var h := c.size.y
		var fade := w * 0.15
		var deep := alpha(NAVY2, 0.92)
		for band in [[0.0, h, deep], [0.0, 1.0, GOLD_HI], [h - 1.0, 1.0, GOLD_HI]]:
			var y: float = band[0]
			var bh: float = band[1]
			var on: Color = band[2]
			var off := alpha(on, 0.0)
			c.draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(fade, y), Vector2(fade, y + bh), Vector2(0, y + bh)]),
				PackedColorArray([off, on, on, off]))
			c.draw_rect(Rect2(fade, y, w - 2 * fade, bh), on)
			c.draw_polygon(PackedVector2Array([Vector2(w - fade, y), Vector2(w, y), Vector2(w, y + bh), Vector2(w - fade, y + bh)]),
				PackedColorArray([on, off, off, on])))
	c.resized.connect(c.queue_redraw)
	return c

## Pips for picks remaining: `left` filled gold diamonds, then `total - left` hollow ones.
static func pick_pips(left: int, total: int, sz := 10.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := maxi(total, left)
	var step := sz + 4.0
	c.custom_minimum_size = Vector2(n * step - 2.0, sz + 4.0)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func():
		var r := sz * 0.6
		for i in n:
			var o := Vector2(1.0 + i * step + sz / 2.0, c.size.y / 2.0)
			var pts := PackedVector2Array([o + Vector2(0, -r), o + Vector2(r, 0), o + Vector2(0, r), o + Vector2(-r, 0)])
			if i < left:
				c.draw_colored_polygon(pts, GOLD_HI)
			else:
				pts.append(pts[0])
				c.draw_polyline(pts, alpha(GOLD_HI, 0.6), 1.0, true))
	return c

# ---- title dock and bestiary pieces (UI Directions ideas 8 and 9) ----
## A frame with no glass: the window's double brass border and studs around a see-through middle.
## For a window onto the stage (the Collection's specimen window), where the 3D scene is the content.
static func window_frame(studs := true) -> WinStyle:
	var w := WinStyle.new(0)
	w.studs = studs
	w.shadow = false
	w.top = Color(0, 0, 0, 0)
	w.bottom = Color(0, 0, 0, 0)
	return w.refresh()

## Level pips (upgrade tracks): `n` of `total` fixed-size bars filled in `c`, the rest dark navy.
static func pips(n: int, total: int, c := GOLD_HI, w := 22.0, h := 8.0, sep := 4.0) -> Control:
	var m := Control.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.custom_minimum_size = Vector2(total * w + (total - 1) * sep, h)
	m.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	m.draw.connect(func():
		for i in total:
			var r := Rect2(i * (w + sep), 0, w, h)
			m.draw_rect(r, c if i < n else Color("#2a3350"))
			if i < n:   # a light top edge, like the plaque's bevel
				m.draw_rect(Rect2(r.position, Vector2(w, 1)), mix(c, Color.WHITE, 0.5)))
	return m

## A tab strip: sentence-case labels over a brass hairline; the current tab is gold with a 2px gold
## underline. `f.call(i)` runs when another tab is tapped.
static func tabs(names: Array, cur: int, f: Callable) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := hbox(0)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(h)
	for i in names.size():
		var on := i == cur
		var t := Tap.new(flat(Color(0, 0, 0, 0), 0, 0, Color(), Vector4(14, 6, 14, 8)))
		t.press_scale = 1.0
		t.add_child(lbl(str(names[i]), "700", T_M, GOLD_HI if on else INK2, {"align": "center"}))
		if on:
			t.draw.connect(func(): t.draw_rect(Rect2(0, t.size.y - 2, t.size.x, 2), GOLD_HI))
		t.pressed.connect(func(): if not on: f.call(i))
		h.add_child(t)
	wrap.draw.connect(func(): wrap.draw_rect(Rect2(0, wrap.size.y - 1, wrap.size.x, 1), alpha(BRASS, 0.3)))
	wrap.custom_minimum_size.y = h.get_combined_minimum_size().y
	h.minimum_size_changed.connect(func(): wrap.custom_minimum_size.y = h.get_combined_minimum_size().y)
	return wrap

# ---- battle HUD pieces (UI-QUEUE items 5-6) ----
const FACE_SHADER := preload("res://ui/por_face.gdshader")
const CRYSTAL := Color("#57c8ff")       # the cards' crystal blue (energy orb, energy particles)
const CRYSTAL_HI := Color("#e6fbff")
const CRYSTAL_LO := Color("#2178c2")
const GUARD := Color("#9fe8ff")         # "this creature resists the incoming heavy" (shield marker)

## A round creature portrait: the creature's face (its in-game sprite, recoloured as on stage) on a
## lit element orb, inside a dark gap and a ring (`ring`; default a light tint of the element).
## Everything is drawn inside `sz`. `set_face_ko(box, true)` greys it out.
static func face_por(key: String, el: String, sz: float, ring := Color(0, 0, 0, 0)) -> Box:
	var c := el_css(el)
	var b := Box.new(Vector2(sz, sz))
	var rim := RRect.new({"radius": 999.0}).solid(ring if ring.a > 0.0 else mix(c, Color.WHITE, 0.75))
	b.add_child(Box.fill(rim))
	var gap := RRect.new({"radius": 999.0}).solid(NAVY2)
	gap.custom_minimum_size = Vector2(sz - 3, sz - 3)
	b.add_child(gap)
	var o := RRect.new({"radius": 999.0, "mode": "radial", "rc": Vector2(0.4, 0.35),
		"c0": mix(mix(c, Color.WHITE, 0.6), c, 0.3), "c1": mix(c, NAVY2, 0.55)})
	o.custom_minimum_size = Vector2(sz - 6, sz - 6)
	b.add_child(o)
	var f := TextureRect.new()
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	f.stretch_mode = TextureRect.STRETCH_SCALE
	f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	f.custom_minimum_size = Vector2(sz - 6, sz - 6)
	var m := ShaderMaterial.new()
	m.shader = FACE_SHADER
	m.set_shader_parameter("rsize", Vector2(sz - 6, sz - 6))
	f.material = m
	if key != "":
		f.texture = CardView.face_tex(key, el, 1.0, Vector2(0.5, 0.4))
	b.add_child(f)
	b.set_meta("face", f)
	b.set_meta("rim", rim)
	return b

## Grey a face_por out (knocked out) or bring it back.
static func set_face_ko(b: Box, ko: bool) -> void:
	var m: ShaderMaterial = (b.get_meta("face") as TextureRect).material
	m.set_shader_parameter("sat", 0.0 if ko else 1.0)
	m.set_shader_parameter("bright", 0.55 if ko else 1.0)
	b.modulate = Color(0.62, 0.62, 0.66) if ko else Color.WHITE

## Small HUD frame over the scene (floor pill, mute, quit): navy glass with a brass hairline.
static func hud_btn_style(radius := 8.0, pad := Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	return glow_box(flat(alpha(NAVY, 0.9), radius, 1, LINE, pad), Color(0, 0, 0, 0.3), 4, Vector2(0, 2))
