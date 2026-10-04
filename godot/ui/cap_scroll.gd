class_name CapScroll
extends ScrollContainer
## A vertical scroller that is as tall as its content up to `max_frac` × viewport height minus `minus` px
## (CSS max-height + overflow:auto). Drag or wheel to scroll; no visible bar.

var content: Control
var max_frac := 0.68
var minus := 0.0

func _init(c: Control, frac := 0.68, minus_px := 0.0) -> void:
	content = c
	max_frac = frac
	minus = minus_px
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	vertical_scroll_mode = SCROLL_MODE_SHOW_NEVER
	mouse_filter = MOUSE_FILTER_PASS
	size_flags_horizontal = SIZE_EXPAND_FILL
	c.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(c)
	c.minimum_size_changed.connect(fit)
	c.resized.connect(fit)

func _ready() -> void:
	get_viewport().size_changed.connect(fit)
	fit()

func fit() -> void:
	if not is_inside_tree():
		return
	var cap := get_viewport().get_visible_rect().size.y * max_frac - minus
	var h := minf(content.get_combined_minimum_size().y, maxf(40.0, cap))
	if absf(custom_minimum_size.y - h) > 0.5:
		custom_minimum_size.y = h
