# Element recolouring for pixel art painted in Ember colours. Port of
# game/src/art/sprite/recolor.ts: the Ember hue ramp (outline -> shadow -> base -> highlight)
# is mapped piecewise onto the target element's ramp, so shadows and outlines shift the way a
# pixel artist would shift them. Low-saturation pixels (skin, cream bellies, grey cloth) and
# hues outside the warm band keep their colour. Baked once per (image, element, options).
extends RefCounted

## Source ramp of the Ember art: [outline, shadow, base, highlight] hues in degrees.
const SRC := [-40.0, -6.0, 14.0, 35.0]
const RAMPS := {
	"ember": [-40.0, -6.0, 14.0, 35.0],
	"tide": [250.0, 232.0, 208.0, 188.0],
	"thorn": [172.0, 148.0, 122.0, 82.0],
	"volt": [-12.0, 34.0, 48.0, 56.0],
}
const EL_LIGHT := {"ember": 1.0, "tide": 1.0, "thorn": 0.88, "volt": 1.0}
const EL_SAT := {"ember": 1.0, "tide": 0.95, "thorn": 0.8, "volt": 0.95}
const EL_GAMMA := {"ember": 1.0, "tide": 1.0, "thorn": 1.0, "volt": 0.72}


## True if recolouring to `el` with options `o` changes nothing.
static func is_identity(el: String, o: Dictionary) -> bool:
	var ramps: Dictionary = o.get("ramps", {})
	return el == "ember" and not ramps.has("ember") and not o.has("wash") \
		and float(o.get("light", 1.0)) == 1.0 and float(o.get("sat", 1.0)) == 1.0


static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _map_hue(h: float, r: Array) -> float:
	if h <= SRC[0]:
		return r[0]
	if h >= SRC[3]:
		return r[3]
	for i in 3:
		if h <= SRC[i + 1]:
			var t: float = (h - SRC[i]) / (SRC[i + 1] - SRC[i])
			return r[i] + (r[i + 1] - r[i]) * t
	return r[3]


## Returns a recoloured copy of `src` (any format; converted to RGBA8).
static func recolor_image(src: Image, el: String, o: Dictionary = {}) -> Image:
	var img := src.duplicate() as Image
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var ramps: Dictionary = o.get("ramps", {})
	var ramp: Array = ramps.get(el, RAMPS[el])
	var max_hue := float(o.get("max_hue", 28.0))
	var min_sat := float(o.get("min_sat", 0.5))
	var kv := float(o.get("light", 1.0)) * float(EL_LIGHT[el])
	var ks := float(o.get("sat", 1.0)) * float(EL_SAT[el])
	var gamma := float(EL_GAMMA[el])
	var wash: Array = o.get("wash", [1.0, 1.0, 1.0])
	var touch := el != "ember" or ramps.has("ember") or kv != 1.0 or ks != 1.0
	var px := img.get_data()
	var n := px.size()
	var i := 0
	while i < n:
		if px[i + 3] == 0:
			i += 4
			continue
		var r := px[i] / 255.0
		var g := px[i + 1] / 255.0
		var b := px[i + 2] / 255.0
		if touch:
			var mx := maxf(r, maxf(g, b))
			var mn := minf(r, minf(g, b))
			var d := mx - mn
			var v := mx
			var s := d / mx if mx > 0.0 else 0.0
			var h := 0.0
			if d > 0.0:
				if mx == r:
					h = ((g - b) / d) * 60.0
				elif mx == g:
					h = ((b - r) / d + 2.0) * 60.0
				else:
					h = ((r - g) / d + 4.0) * 60.0
			if h < 0.0:
				h += 360.0
			if h > 270.0:
				h -= 360.0
			var w := _smooth(-75.0, -60.0, h) * (1.0 - _smooth(max_hue, max_hue + 12.0, h)) * _smooth(min_sat, min_sat + 0.12, s)
			if w > 0.0:
				var nh := fmod(_map_hue(h, ramp), 360.0)
				if nh < 0.0:
					nh += 360.0
				var nv := minf(1.0, pow(v, gamma) * kv)
				var ns := minf(1.0, s * ks)
				var c := nv * ns
				var x := c * (1.0 - absf(fmod(nh / 60.0, 2.0) - 1.0))
				var m := nv - c
				var k := int(floor(nh / 60.0))
				var rr := c; var gg := x; var bb := 0.0
				match k:
					1: rr = x; gg = c; bb = 0.0
					2: rr = 0.0; gg = c; bb = x
					3: rr = 0.0; gg = x; bb = c
					4: rr = x; gg = 0.0; bb = c
					5: rr = c; gg = 0.0; bb = x
				r += (rr + m - r) * w
				g += (gg + m - g) * w
				b += (bb + m - b) * w
		px[i] = clampi(int(r * float(wash[0]) * 255.0 + 0.5), 0, 255)
		px[i + 1] = clampi(int(g * float(wash[1]) * 255.0 + 0.5), 0, 255)
		px[i + 2] = clampi(int(b * float(wash[2]) * 255.0 + 0.5), 0, 255)
		i += 4
	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, px)
