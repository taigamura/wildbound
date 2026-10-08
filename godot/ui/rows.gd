class_name Rows
extends VBoxContainer
## A list inside a window (mockup: shop, party): rows stacked with a 1px brass hairline between them,
## instead of one glowing pill per row. A row that is selected (Tap.on, or meta "sel") skips the
## hairlines touching it, since its own gold outline already separates it. Build with UiKit.rows().

var hair := UiKit.HAIR

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 1)
	sort_children.connect(queue_redraw)

func _draw() -> void:
	var shown: Array = []
	for c in get_children():
		if c is Control and c.visible and not c.top_level:
			shown.append(c)
	for i in range(1, shown.size()):
		var a: Control = shown[i - 1]
		var b: Control = shown[i]
		if _sel(a) or _sel(b):
			continue
		var y := floorf((a.position.y + a.size.y + b.position.y) / 2.0)
		draw_rect(Rect2(0, y, size.x, 1), hair)

static func _sel(c: Control) -> bool:
	return (c is Tap and c.on) or c.get_meta("sel", false)
