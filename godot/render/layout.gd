# Stage layout (port of render/layout.ts): everything is placed relative to the free band
# between the HUD's top and bottom pieces, in "units" (U px). Positions ease toward targets.
# All values are canvas pixels in the 390x844 base viewport (stretch expand).
extends Node

## One world unit in pixels (eased).
var U := 60.0
## Logical canvas size in px.
var size := Vector2(390, 844)

var _t := {"u": 60.0, "ex": 0.0, "ey": 0.0, "px": 0.0, "py": 0.0, "tx": 0.0, "ty": 0.0}
var _c := _t.duplicate()
## Free band height (px) below which the title creature is hidden instead of drawn over panels.
const MIN_ROOM := 90.0
## Whether the free band is tall enough for the title creature.
var room := true
var _band := Vector2(0, -1)   # last (top, bottom) passed to measure_band; bottom < 0 = full height


func _ready() -> void:
	get_viewport().size_changed.connect(func(): measure_band(_band.x, _band.y, true))
	measure_band(0.0, -1.0, true)


func _view_size() -> Vector2:
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp else Vector2(390, 844)


## top_px: bottom edge of the HUD's top pieces; bottom_px: top edge of its bottom pieces
## (pass a negative bottom for "nothing at the bottom").
func measure_band(top_px: float, bottom_px: float, snap := false) -> void:
	_band = Vector2(top_px, bottom_px)
	size = _view_size()
	var w := size.x
	var h := size.y
	# Spots stay inside the free band, even a short one: running the stage up under the header or
	# down under the sheet put the title creature behind panels (tests/ui_check.gd "art").
	var top := maxf(0.0, top_px)
	var bot := h if bottom_px < 0.0 else minf(h, bottom_px)
	var bh := maxf(bot - top, 1.0)
	room = bh >= MIN_ROOM
	var cx := w / 2.0
	_t.u = clampf(minf(bh / 4.8, w / 5.0), 20.0, 110.0)
	var spread := minf(w * 0.19, _t.u * 1.6)
	_t.ex = cx + spread; _t.ey = top + bh * 0.5    # enemy: upper right
	_t.px = cx - spread; _t.py = top + bh * 0.92   # partner: lower left
	_t.tx = cx; _t.ty = top + bh * 0.82            # title creature: centred
	if snap:
		_c = _t.duplicate()
		U = _c.u


func ease_layout(dt: float) -> void:
	var k := 1.0 - exp(-dt * 7.0)
	for key in _t:
		_c[key] += (_t[key] - _c[key]) * k
	U = _c.u


func epos() -> Vector2: return Vector2(_c.ex, _c.ey)
func ppos() -> Vector2: return Vector2(_c.px, _c.py)
func tpos() -> Vector2: return Vector2(_c.tx, _c.ty)
## Target (not eased) positions; the stage builds its diorama around these.
func epos_target() -> Vector2: return Vector2(_t.ex, _t.ey)
func ppos_target() -> Vector2: return Vector2(_t.px, _t.py)


## Where the spots land for a given HUD band (no easing, current canvas size). The stage builds
## its diorama around the canonical battle band so it doesn't depend on which screen is open.
func band_spots(top_px: float, bottom_px: float) -> Dictionary:
	var h := size.y
	var bh := bottom_px - top_px
	var cx := size.x / 2.0
	var u := clampf(minf(bh / 4.8, size.x / 5.0), 34.0, 110.0)
	var spread := minf(size.x * 0.19, u * 1.6)
	return {"u": u, "e": Vector2(cx + spread, top_px + bh * 0.5), "p": Vector2(cx - spread, top_px + bh * 0.92),
		"t": Vector2(cx, top_px + bh * 0.82), "h": h}


## Horizon line used by scene art so creatures always stand below it.
func horizon() -> float:
	return size.y * 0.36
