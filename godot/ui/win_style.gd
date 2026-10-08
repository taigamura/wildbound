class_name WinStyle
extends StyleBox
## The window frame (mockup .win): navy glass gradient, a thin brass border, a dark gap, a faint second
## brass line inside it, a soft drop shadow, and two small gold diamond studs on the top edge. Usable
## anywhere a StyleBox is (PanelContainer, Tap.style). Everything but the shadow is drawn inside the
## rect: the studs sit on the top border, not above it, so nothing hangs off the box.
## Build through UiKit.window() / UiKit.win().

var radius := 5.0
var top := Color(26 / 255.0, 37 / 255.0, 72 / 255.0, 0.94)
var bottom := Color(11 / 255.0, 16 / 255.0, 36 / 255.0, 0.96)
var border := UiKit.BRASS
var gap := UiKit.NAVY2
var inner := Color(201 / 255.0, 162 / 255.0, 74 / 255.0, 0.35)
var studs := true
var shadow := true

var _sb_border := StyleBoxFlat.new()
var _sb_gap := StyleBoxFlat.new()
var _sb_inner := StyleBoxFlat.new()
var _sb_shadow := StyleBoxFlat.new()

func _init(pad := 16.0) -> void:
	set_content_margin_all(pad)

## Rebuild the internal layers after changing the public fields.
func refresh() -> WinStyle:
	for x in [[_sb_border, border, 1, radius], [_sb_gap, gap, 2, radius - 1.0], [_sb_inner, inner, 1, radius - 3.0]]:
		var sb: StyleBoxFlat = x[0]
		sb.draw_center = false
		sb.border_color = x[1]
		sb.set_border_width_all(x[2])
		sb.set_corner_radius_all(int(maxf(x[3], 0.0)))
		sb.corner_detail = 6
		sb.anti_aliasing = true
	_sb_shadow.bg_color = Color(0, 0, 0, 0)
	_sb_shadow.shadow_color = Color(0, 0, 0, 0.45 if shadow else 0.0)
	_sb_shadow.shadow_size = 14
	_sb_shadow.shadow_offset = Vector2(0, 6)
	_sb_shadow.set_corner_radius_all(int(radius))
	emit_changed()
	return self

func _draw(ci: RID, rect: Rect2) -> void:
	if _sb_border.border_width_left == 0:
		refresh()
	if shadow:
		_sb_shadow.draw(ci, rect)
	# glass: a vertical gradient as a rounded polygon (the border rings cover its unantialiased edge)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var r := minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	var corners := [[rect.position + Vector2(r, r), PI], [Vector2(rect.end.x - r, rect.position.y + r), PI * 1.5],
		[rect.end - Vector2(r, r), 0.0], [Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5]]
	for c in corners:
		for i in 4:
			var a: float = c[1] + PI * 0.5 * i / 3.0
			var p: Vector2 = c[0] + Vector2(cos(a), sin(a)) * r
			pts.append(p)
			cols.append(top.lerp(bottom, clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)))
	RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	_sb_inner.draw(ci, rect.grow(-3.0))
	_sb_gap.draw(ci, rect.grow(-1.0))
	_sb_border.draw(ci, rect)
	if studs and rect.size.x > 60.0:
		for x in [rect.position.x + 17.5, rect.end.x - 17.5]:
			_stud(ci, Vector2(x, rect.position.y + 3.5))

## A 7px gold diamond (a 5px square turned 45°) with a dark rim so it reads on the border.
func _stud(ci: RID, c: Vector2) -> void:
	var h := 3.5
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)]),
		PackedColorArray([UiKit.GOLD_LO]))
	h = 2.5
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)]),
		PackedColorArray([UiKit.GOLD_HI]))
