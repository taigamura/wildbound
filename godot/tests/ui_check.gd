extends RefCounted
## Screenshot UI check, run by scenes/main.gd at the end of a `--shot` when `--ui-check` is passed
## (scripts/ui-check.sh drives it over every screen and size). Two halves:
##
## 1. Layout lint on the live Control tree and the stage actors:
##    - offscreen:  a visible box leaves the screen, or text/buttons leave the safe area
##    - spill:      a box sticks out of its parent box (badges hanging off cards, rows wider than sheets)
##    - squashed:   a box is smaller than its own minimum size (content forced past its edges)
##    - overflow:   a wrapped label has more lines than fit
##    - truncated:  a label is cut off with an ellipsis ("Emberw...")
##    - covered:    a corner piece (badge, tag, marker) sits on top of a label's text
##    - art:        a creature sprite sits under a panel or header
##    - contrast:   text floating over the scene is hard to read against what is behind it
##    - overlap:    the header band and the bottom sheet (or HUD top and bottom) overlap
## 2. Pixel diff against a golden PNG (tests/golden/<w>x<h>/wb-<screen>.png). `--update` rewrites it.
##
## A node (and its subtree) opts out of a rule with set_meta("ui_check_skip", ["spill", ...]) or
## ["*"]; a node that is placed freely over its parent (a lifted hand card) sets "ui_check_free".
## Say why next to the call.

const TOL := 1.5             # px slack for rounding
const ART_COVER := 0.12      # max share of a sprite's box that may sit under UI
const DIFF_PX := 24          # per-channel difference that counts as a changed pixel
const DIFF_SHARE := 0.001    # max share of changed pixels before the golden check fails

var fails: Array = []        # {rule, what, rect, detail}
var _names := {}             # Control → Ui.el key
var _decos: Array = []       # corner pieces seen in the walk: [Control, skips]
var _vp := Rect2()
var _safe := Rect2()
var _k := Vector2.ONE        # image px per canvas px

## Returns the process exit code: 0 if every check passed.
func check(screen: String, img: Image, out_dir: String, golden_dir: String, update: bool) -> int:
	_vp = Ui.root.get_viewport_rect()   # canvas px (the 390-wide base stretches; the image is device px)
	_k = Vector2(img.get_width(), img.get_height()) / _vp.size
	var s: Dictionary = Ui.safe()
	_safe = Rect2(Vector2(s.side, s.top), _vp.size - Vector2(s.side * 2.0, s.top + s.bottom))
	for k in Ui.el:
		if Ui.el[k] is Control:
			_names[Ui.el[k]] = k
	_walk(Ui.root, false, [])
	_covered()
	_bands()
	_art()
	_contrast(img)
	_golden(screen, img, golden_dir, update)
	_report(screen, img, out_dir)
	return 1 if fails.size() > 0 else 0

# ------------------------------------------------------------------ tree walk

func _shown(c: Control) -> bool:
	return c.is_visible_in_tree() and c.size.x > 0.5 and c.size.y > 0.5 and _alpha(c) > 0.05

func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n is CanvasItem:
		a *= (n as CanvasItem).modulate.a * (n as CanvasItem).self_modulate.a
		n = n.get_parent()
	return a

func _rect(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)

func _skips(c: Control, inherited: Array) -> Array:
	if c.has_meta("ui_check_skip"):
		return inherited + Array(c.get_meta("ui_check_skip"))
	return inherited

func _skipped(rule: String, skips: Array) -> bool:
	return rule in skips or "*" in skips

## `clipped`: some ancestor clips its children (a scroll), so sticking out of it is not a spill.
func _walk(c: Control, clipped: bool, skips: Array) -> void:
	if not c.is_visible_in_tree():
		return
	skips = _skips(c, skips)
	if _shown(c) and c != Ui.root:
		_check_box(c, clipped, skips)
		if c is Label:
			_check_label(c as Label, skips)
		if (c.has_meta("corner") or c.has_meta("deco")) and not _skipped("covered", skips):
			_decos.append(c)
	var clips := clipped or c.clip_contents or c is ScrollContainer
	for ch in c.get_children():
		if ch is Control:
			_walk(ch, clips, skips)

func _check_box(c: Control, clipped: bool, skips: Array) -> void:
	var r := _rect(c)
	var full := r.size.x >= _vp.size.x - TOL and r.size.y >= _vp.size.y - TOL   # screen roots, overlays
	if not full and not clipped and not _skipped("offscreen", skips):
		if not _vp.grow(TOL).encloses(r):
			_fail("offscreen", c, r, "box leaves the %dx%d screen" % [_vp.size.x, _vp.size.y])
		elif (c is Label or c is Tap) and not _safe.grow(TOL).encloses(r):
			_fail("offscreen", c, r, "outside the safe area")
	var p := c.get_parent() as Control
	if p and p != Ui.root and _shown(p) and not _skipped("spill", skips) \
			and not c.get_meta("ui_check_free", false) \
			and not (p is ScrollContainer) and not p.clip_contents:
		# compared in the parent's own space, so a tilted hand card is judged against its own frame
		var pr := Rect2(Vector2.ZERO, p.size)
		var lr: Rect2 = p.get_global_transform().affine_inverse() * c.get_global_transform() * Rect2(Vector2.ZERO, c.size)
		if not pr.grow(TOL).encloses(lr):
			_fail("spill", c, r, "sticks out of %s by %s" % [_what(p), _out_by(pr, lr)])
	if not _skipped("squashed", skips) and not (c is ScrollContainer) and not clipped:
		var m := c.get_combined_minimum_size()
		if c.size.x + TOL < m.x or c.size.y + TOL < m.y:
			_fail("squashed", c, r, "size %s below its minimum %s" % [c.size.round(), m.round()])

func _check_label(l: Label, skips: Array) -> void:
	if l.text.strip_edges() == "":
		return
	var r := _rect(l)
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF and not _skipped("overflow", skips):
		var shown := l.get_visible_line_count()
		if l.max_lines_visible < 0 and l.get_line_count() > shown:
			_fail("overflow", l, r, "%d lines, room for %d" % [l.get_line_count(), shown])
	if (l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING) and not _skipped("truncated", skips):
		var f := l.get_theme_font("font")
		var fs := l.get_theme_font_size("font_size")
		var txt := l.text.to_upper() if l.uppercase else l.text
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > l.size.x + TOL:
			_fail("truncated", l, r, "\"%s\" needs %dpx, has %dpx" % [txt, w, l.size.x])

## Each corner piece against the text of every label beside it (same parent, outside the piece),
## in the parent's space so tilted hand cards work.
func _covered() -> void:
	for d in _decos:
		var p: Control = d.get_parent()
		var inv := p.get_global_transform().affine_inverse()
		var dr: Rect2 = inv * d.get_global_transform() * Rect2(Vector2.ZERO, d.size)
		for l in p.find_children("*", "Label", true, false):
			if l == d or d.is_ancestor_of(l) or not _shown(l) or l.text.strip_edges() == "":
				continue
			var lr: Rect2 = inv * l.get_global_transform() * _text_rect(l)
			var x := dr.intersection(lr)
			if x.size.x > TOL and x.size.y > TOL:
				_fail("covered", l, _rect(l), "%s covers its text" % _what(d))

## A label's ink box in its own space: the lines it draws, each centred/aligned like the label.
func _text_rect(l: Label) -> Rect2:
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var txt := l.text.to_upper() if l.uppercase else l.text
	var w := f.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, l.size.x if l.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0, fs).x
	w = minf(w, l.size.x)
	var lines := maxi(1, mini(l.get_line_count(), l.get_visible_line_count()))
	var h := minf(l.size.y, lines * l.get_line_height())
	var x := 0.0
	if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = (l.size.x - w) / 2.0
	elif l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = l.size.x - w
	var y := 0.0
	if l.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		y = (l.size.y - h) / 2.0
	elif l.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		y = l.size.y - h
	return Rect2(x, y, w, h)

# ------------------------------------------------------------------ bands, art, contrast

## The blocks that make up the shown screen: the header band and the sheet panel, or the HUD's
## top and bottom pieces.
func _blocks() -> Array:
	var out := []
	if Ui.current != null:
		var scr: Control = Ui.screens[Ui.current]
		var top = scr.get_meta("top") if scr.has_meta("top") else null
		if top and _shown(top):
			out.append({"name": "header", "node": top, "rect": _content_rect(top)})
		var inner: Control = scr.get_meta("inner")
		if _shown(inner):
			out.append({"name": "sheet", "node": inner, "rect": _rect(inner)})
	elif Ui.hud.visible:
		for n in [Ui.hud_top, Ui.hud_bottom]:
			for ch in n.get_children():
				if ch is Control and _shown(ch):
					out.append({"name": "hud", "node": ch, "rect": _content_rect(ch)})
	return out

## The union of the visible content of a layout box (a header VBox is screen-wide, its text is not).
func _content_rect(c: Control) -> Rect2:
	if c is Container and c.get_child_count() > 0:
		var r := Rect2()
		var any := false
		for ch in c.get_children():
			if ch is Control and _shown(ch):
				var cr := _content_rect(ch)
				r = cr if not any else r.merge(cr)
				any = true
		if any:
			return r
	if c is Label:
		var l := c as Label
		var f := l.get_theme_font("font")
		var txt := l.text.to_upper() if l.uppercase else l.text
		var w := minf(f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x, l.size.x)
		var r := _rect(l)
		var x := r.position.x
		if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
			x += (r.size.x - w) / 2.0
		elif l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			x += r.size.x - w
		return Rect2(x, r.position.y, w, r.size.y)
	return _rect(c)

func _bands() -> void:
	var b := _blocks()
	for i in b.size():
		for j in range(i + 1, b.size()):
			var a: Rect2 = b[i].rect
			var c: Rect2 = b[j].rect
			var x := a.intersection(c)
			if x.size.x > TOL and x.size.y > TOL and b[i].name != b[j].name:
				_fail("overlap", b[i].node, x, "%s overlaps %s by %dpx" % [b[i].name, b[j].name, x.size.y])

func _actors() -> Array:
	var out := []
	for a in [S.em, S.title_actor] + S.actors.values():
		if a != null and is_instance_valid(a) and a.visible and a.has_method("screen_rect"):
			out.append(a)
	return out

func _art() -> void:
	var b := _blocks()
	for a in _actors():
		var ar: Rect2 = a.screen_rect()
		var area := ar.get_area()
		if area < 1.0:
			continue
		for blk in b:
			var x := ar.intersection(blk.rect)
			var share := x.get_area() / area
			if share > ART_COVER:
				fails.append({"rule": "art", "what": "%s sprite" % a.name, "rect": x,
					"detail": "%d%% of the sprite is under the %s" % [roundi(share * 100), blk.name]})

## Text drawn straight over the scene (the header band, floating HUD labels) against the median
## brightness behind it. Labels with a thick outline are judged against the outline.
func _contrast(img: Image) -> void:
	var roots := []
	if Ui.current != null:
		var scr: Control = Ui.screens[Ui.current]
		if scr.has_meta("top") and scr.get_meta("top"):
			roots.append(scr.get_meta("top"))
	elif Ui.hud.visible and Ui.heavy:
		roots.append(Ui.heavy)
	for root in roots:
		for l in root.find_children("*", "Label", true, false):
			# a label with a material (the gradient logo) isn't drawn in its font colour; skip it
			if _shown(l) and l.text.strip_edges() != "" and l.material == null and not _skipped("contrast", _skips(l, [])):
				_check_contrast(l, img)

func _check_contrast(l: Label, img: Image) -> void:
	var r := _content_rect(l).intersection(_vp)
	if r.size.x < 2 or r.size.y < 2:
		return
	var text := l.get_theme_color("font_color") * l.modulate
	var bg_l: float
	if l.get_theme_constant("outline_size") >= 4:
		bg_l = _lum(l.get_theme_color("font_outline_color"))
	else:
		var ls := []
		var step := maxi(1, int(r.size.x * r.size.y / 600.0))
		var i := 0
		var ir := Rect2(r.position * _k, r.size * _k).intersection(Rect2(Vector2.ZERO, Vector2(img.get_size())))
		for y in range(int(ir.position.y), int(ir.end.y)):
			for x in range(int(ir.position.x), int(ir.end.x)):
				i += 1
				if i % step == 0:
					ls.append(_lum(img.get_pixel(x, y)))
		ls.sort()
		bg_l = ls[ls.size() / 2]
	var t_l := _lum(text)
	var ratio := (maxf(t_l, bg_l) + 0.05) / (minf(t_l, bg_l) + 0.05)
	var need := 3.0 if l.get_theme_font_size("font_size") >= 18 else 4.5
	if ratio < need:
		_fail("contrast", l, r, "%.1f:1 against the scene, needs %.1f:1" % [ratio, need])

static func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

# ------------------------------------------------------------------ golden

func _golden(screen: String, img: Image, dir: String, update: bool) -> void:
	if dir == "":
		return
	var path := "%s/wb-%s.png" % [dir, screen]
	if update or not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(dir)
		img.save_png(path)
		print("UICHECK golden %s %s" % ["updated" if update else "created", path])
		return
	var g := Image.load_from_file(path)
	g.convert(img.get_format())
	if g.get_size() != img.get_size():
		fails.append({"rule": "golden", "what": "screen", "rect": _vp, "detail": "golden is %s, shot is %s" % [g.get_size(), img.get_size()]})
		return
	var diff := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	var n := 0
	var box := Rect2()
	var lim := DIFF_PX / 255.0
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y)
			var b := g.get_pixel(x, y)
			if absf(a.r - b.r) > lim or absf(a.g - b.g) > lim or absf(a.b - b.b) > lim:
				diff.set_pixel(x, y, Color(1, 0, 0.3))
				box = Rect2(x, y, 1, 1) if n == 0 else box.expand(Vector2(x + 1, y + 1))
				n += 1
			else:
				diff.set_pixel(x, y, Color(a.r, a.g, a.b, 1.0).darkened(0.7))
	_diff = diff if n > 0 else null
	var share := float(n) / (img.get_width() * img.get_height())
	if share > DIFF_SHARE:
		fails.append({"rule": "golden", "what": "screen", "rect": box,
			"detail": "%.2f%% of pixels differ from %s (run with --update if intended)" % [share * 100, path]})

var _diff: Image = null

# ------------------------------------------------------------------ report

func _what(c: Node) -> String:
	var n := c
	while n is Control and n != Ui.root:
		if _names.has(n):
			var s: String = _names[n]
			return s if n == c else "%s>%s" % [s, c.get_class()]
		n = n.get_parent()
	var t := ""
	if c is Label:
		t = (c as Label).text
	else:
		for l in c.find_children("*", "Label", true, false):
			if (l as Label).text != "":
				t = (l as Label).text
				break
	return "%s \"%s\"" % [c.get_class(), t.left(28)] if t != "" else c.get_class()

func _out_by(outer: Rect2, inner: Rect2) -> String:
	var parts := []
	if inner.position.x < outer.position.x - TOL: parts.append("L %d" % (outer.position.x - inner.position.x))
	if inner.end.x > outer.end.x + TOL: parts.append("R %d" % (inner.end.x - outer.end.x))
	if inner.position.y < outer.position.y - TOL: parts.append("T %d" % (outer.position.y - inner.position.y))
	if inner.end.y > outer.end.y + TOL: parts.append("B %d" % (inner.end.y - outer.end.y))
	return ", ".join(parts) + "px"

func _fail(rule: String, c: Control, r: Rect2, detail: String) -> void:
	fails.append({"rule": rule, "what": _what(c), "rect": r, "detail": detail})

const RULE_C := {"offscreen": Color.RED, "spill": Color(1, 0.5, 0), "squashed": Color.MAGENTA, "overflow": Color.YELLOW,
	"truncated": Color.CYAN, "covered": Color(1, 0.8, 0.2), "art": Color(0.3, 1, 0.3), "contrast": Color(0.6, 0.4, 1), "overlap": Color.WHITE, "golden": Color(1, 0, 0.3)}

func _report(screen: String, img: Image, out_dir: String) -> void:
	var tag := "%s@%dx%d" % [screen, img.get_width(), img.get_height()]
	# one line per finding; identical findings (a grid of cards) collapse into one with a count
	var seen := {}
	var order := []
	for f in fails:
		var k := "%s|%s|%s" % [f.rule, f.what, f.detail]
		if not seen.has(k):
			seen[k] = 0
			order.append(f)
		seen[k] += 1
	for f in order:
		var n: int = seen["%s|%s|%s" % [f.rule, f.what, f.detail]]
		print("UICHECK FAIL %s %-9s %s: %s%s" % [tag, f.rule, f.what, f.detail, " (x%d)" % n if n > 1 else ""])
	if fails.is_empty():
		print("UICHECK PASS %s" % tag)
		return
	var ann := img.duplicate() as Image
	ann.convert(Image.FORMAT_RGBA8)
	for f in fails:
		var r: Rect2 = f.rect if f.rule == "golden" else Rect2(f.rect.position * _k, f.rect.size * _k)
		_outline(ann, r, RULE_C.get(f.rule, Color.RED))
	ann.save_png("%s/wb-%s.fail.png" % [out_dir, screen])
	if _diff:
		_diff.save_png("%s/wb-%s.diff.png" % [out_dir, screen])

static func _outline(img: Image, r: Rect2, c: Color) -> void:
	var b := Rect2i(r).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if b.size.x <= 0 or b.size.y <= 0:
		return
	for t in 2:
		img.fill_rect(Rect2i(b.position.x, b.position.y + t, b.size.x, 1), c)
		img.fill_rect(Rect2i(b.position.x, b.end.y - 1 - t, b.size.x, 1), c)
		img.fill_rect(Rect2i(b.position.x + t, b.position.y, 1, b.size.y), c)
		img.fill_rect(Rect2i(b.end.x - 1 - t, b.position.y, 1, b.size.y), c)
