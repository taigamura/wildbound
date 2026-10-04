class_name Box
extends Container
## CSS "display:grid; place-items:center": children tagged fill (Box.fill) stretch over the whole box,
## children tagged with a corner (Box.at) sit there, the rest are centred at their minimum size
## (optional meta "off" nudges them). Minimum size = the largest child's (or custom_minimum_size).

func _init(sz := Vector2.ZERO) -> void:
	custom_minimum_size = sz
	mouse_filter = MOUSE_FILTER_IGNORE
	if sz != Vector2.ZERO:
		size_flags_vertical = SIZE_SHRINK_CENTER
		size_flags_horizontal = SIZE_SHRINK_CENTER

static func fill(c: Control) -> Control:
	c.set_meta("fill", true)
	return c

## Pin a child to a corner ("tl" "tr" "bl" "br") with an inset.
static func at(c: Control, corner: String, off := Vector2.ZERO) -> Control:
	c.set_meta("corner", corner)
	c.set_meta("off", off)
	return c

func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and not c.top_level and c.visible and not c.has_meta("corner"):
			m = m.max(c.get_combined_minimum_size())
	return m

func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	for c in get_children():
		if not c is Control or c.top_level:
			continue
		var m: Vector2 = c.get_combined_minimum_size()
		var off: Vector2 = c.get_meta("off", Vector2.ZERO)
		if c.get_meta("fill", false):
			fit_child_in_rect(c, Rect2(Vector2.ZERO, size))
		elif c.has_meta("corner"):
			var p := off
			match c.get_meta("corner"):
				"tr": p = Vector2(size.x - m.x - off.x, off.y)
				"bl": p = Vector2(off.x, size.y - m.y - off.y)
				"br": p = Vector2(size.x - m.x - off.x, size.y - m.y - off.y)
			fit_child_in_rect(c, Rect2(p, m))
		else:
			fit_child_in_rect(c, Rect2(((size - m) / 2.0 + off).round(), m))
