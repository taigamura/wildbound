# Procedural pixel-art textures for the HD-2D diorama (no image files). Every texture is
# painted once into a small Image (ordered dither, ramp palettes, key light from the upper
# left baked into card art) and sampled nearest-neighbour, so the 3D world reads as pixel art.
# Results are cached per (name, look) for the session.
extends RefCounted

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var _cache: Dictionary = {}


static func dither(x: int, y: int) -> float:
	return (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16.0


## Pick from a dark->light ramp with ordered dithering. v in 0..1.
static func ramp(r: Array, v: float, x: int, y: int) -> Color:
	var n := r.size()
	var f := clampf(v, 0.0, 0.9999) * (n - 1) + dither(x, y) - 0.5
	return r[clampi(int(round(f)), 0, n - 1)]


static func _noise(seed: int, freq: float, octaves := 3) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n


static func _tex(img: Image, mip := true) -> ImageTexture:
	if mip:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func cached(key: String, make: Callable) -> Texture2D:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## Seamless noise value 0..1 at (x, y) of a w x h tile (4D torus trick via two 2D samples).
static func _tile_noise(n: FastNoiseLite, x: float, y: float, w: float, h: float) -> float:
	# blend 4 samples so the tile wraps
	var fx := x / w
	var fy := y / h
	var a := n.get_noise_2d(x, y)
	var b := n.get_noise_2d(x - w, y)
	var c := n.get_noise_2d(x, y - h)
	var d := n.get_noise_2d(x - w, y - h)
	var v := lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)
	return clampf(v * 0.5 + 0.5, 0.0, 1.0)


# ---------------------------------------------------------------- ground

## Tileable grass/earth ground (biome look). 128 texels.
static func ground(look: Dictionary, seed: int) -> Texture2D:
	return cached("ground%d" % seed, func():
		var w := 128
		var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
		var n1 := _noise(seed, 0.035, 4)
		var n2 := _noise(seed + 7, 0.16, 2)
		var g: Array = look.ground
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		for y in w:
			for x in w:
				var v := _tile_noise(n1, x, y, w, w) * 0.75 + _tile_noise(n2, x, y, w, w) * 0.35 - 0.12
				img.set_pixel(x, y, ramp(g, v, x, y))
		# grass blades: short vertical strokes, lit on top
		for i in 520:
			var x := rng.randi_range(0, w - 1)
			var y := rng.randi_range(0, w - 1)
			var hgt := rng.randi_range(1, 3)
			for k in hgt:
				var c: Color = g[clampi(g.size() - 1 - k, 0, g.size() - 1)] if k == 0 else g[clampi(g.size() - 2 - k, 0, g.size() - 1)]
				img.set_pixel(x, posmod(y - k, w), c)
		# flowers and pebbles
		for i in 46:
			var x := rng.randi_range(0, w - 1)
			var y := rng.randi_range(0, w - 1)
			var fc: Color = look.flowers[rng.randi_range(0, look.flowers.size() - 1)]
			img.set_pixel(x, y, fc)
			if rng.randf() < 0.5:
				img.set_pixel(posmod(x + 1, w), y, fc.darkened(0.25))
		for i in 30:
			var x := rng.randi_range(0, w - 2)
			var y := rng.randi_range(0, w - 2)
			var s: Array = look.stone
			img.set_pixel(x, y, s[2]); img.set_pixel(x + 1, y, s[3]); img.set_pixel(x, y + 1, s[0]); img.set_pixel(x + 1, y + 1, s[1])
		return _tex(img))


## Flagstone paving (plaza). Irregular blocks in running bond, mortar, moss in the joints.
static func flagstone(look: Dictionary, seed: int) -> Texture2D:
	return cached("flag%d" % seed, func():
		var w := 128
		var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		var n := _noise(seed + 3, 0.12, 2)
		var s: Array = look.stone
		var moss: Color = look.moss
		var rows := [0]
		while rows[-1] < w:
			rows.append(mini(w, rows[-1] + rng.randi_range(9, 13)))
		for ri in rows.size() - 1:
			var y0: int = rows[ri]; var y1: int = rows[ri + 1]
			var x := rng.randi_range(-12, 0)
			while x < w:
				var bw := rng.randi_range(12, 24)
				var tone := rng.randf_range(-0.18, 0.18)
				for yy in range(y0, y1):
					for xx in range(x, x + bw):
						var px := posmod(xx, w)
						var edge := yy == y0 or xx == x
						var lit := yy == y0 + 1 or xx == x + 1
						var shade := yy == y1 - 1 or xx == x + bw - 1
						var v := 0.55 + tone + (_tile_noise(n, px, yy, w, w) - 0.5) * 0.5
						if lit: v += 0.25
						if shade: v -= 0.22
						var c := ramp(s, v, px, yy)
						if edge:
							c = s[0].darkened(0.35)
							if rng.randf() < 0.35: c = moss.darkened(0.2)
						img.set_pixel(px, yy, c)
				x += bw
		# moss patches
		for i in 40:
			var cx := rng.randi_range(0, w - 1); var cy := rng.randi_range(0, w - 1)
			for k in 7:
				img.set_pixel(posmod(cx + rng.randi_range(-2, 2), w), posmod(cy + rng.randi_range(-1, 1), w), moss if rng.randf() < 0.6 else moss.lightened(0.15))
		return _tex(img))


## Stone courses for pillars / walls (u wraps around, v up). Light baked from the left.
static func stone_blocks(look: Dictionary, seed: int, course := 9, block := 14) -> Texture2D:
	return cached("blocks%d_%d_%d" % [seed, course, block], func():
		var w := 64; var h := 64
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		var n := _noise(seed + 11, 0.15, 2)
		var s: Array = look.stone
		var moss: Color = look.moss
		var y := 0; var row := 0
		while y < h:
			var off := (row % 2) * block / 2
			var x := -off
			while x < w:
				var tone := rng.randf_range(-0.15, 0.15)
				for yy in range(y, mini(y + course, h)):
					for xx in range(x, x + block):
						var px := posmod(xx, w)
						var v := 0.5 + tone + (_tile_noise(n, px, yy, w, h) - 0.5) * 0.45
						if yy == y + 1: v += 0.22
						if yy == y + course - 1: v -= 0.25
						var c := ramp(s, v, px, yy)
						if yy == y or xx == x: c = s[0].darkened(0.3)
						img.set_pixel(px, yy, c)
				x += block
			y += course; row += 1
		# moss specks in the joints
		for i in 60:
			var x := rng.randi_range(0, w - 1); var yy := rng.randi_range(0, h - 1)
			img.set_pixel(x, yy, moss if i % 3 else moss.darkened(0.25))
		return _tex(img))


## Vertical bark.
static func bark(look: Dictionary, seed: int) -> Texture2D:
	return cached("bark%d" % seed, func():
		var w := 32; var h := 64
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var n := _noise(seed, 0.09, 3)
		var b: Array = look.bark
		for y in h:
			for x in w:
				var v := _tile_noise(n, x * 4.0, y * 0.5, w * 4.0, h * 0.5)
				v = v * 0.8 + 0.1
				img.set_pixel(x, y, ramp(b, v, x, y))
		return _tex(img))


# ---------------------------------------------------------------- cards (alpha cut-outs, camera facing)

## Leafy tree card: trunk + clustered canopy blobs, shaded from the upper left, 1 px darker outline.
## pine = stacked tiers instead of blobs. Returns texture of w x h.
static func tree_card(look: Dictionary, seed: int, pine := false, canopy_only := false) -> Texture2D:
	return cached("tree%d%s%s%s" % [seed, "p" if pine else "", "c" if canopy_only else "", look.tree[1].to_html()], func():
		var w := 96; var h := 144
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		var bk: Array = look.bark
		var tr: Array = look.tree
		var nz := _noise(seed + 5, 0.18, 2)
		var trunk_x := w / 2 + rng.randi_range(-4, 4)
		var tw := rng.randi_range(5, 8)
		# trunk
		for y in range(int(h * 0.35), h if not canopy_only else int(h * 0.35)):
			var spread := int(float(y - h * 0.35) / (h * 0.65) * 3.0) if y > h - 14 else 0
			for x in range(trunk_x - tw / 2 - spread, trunk_x + tw / 2 + spread + 1):
				var t := float(x - (trunk_x - tw / 2 - spread)) / float(tw + 2 * spread + 1)
				img.set_pixel(x, y, ramp(bk, 1.0 - t * 0.9 + (nz.get_noise_2d(x * 3.0, y * 0.3)) * 0.2, x, y))
		# canopy
		var blobs := []
		if pine:
			var tiers := 6
			for i in tiers:
				var ty := int(h * 0.08 + i * h * 0.12)
				var half := 8 + i * 6
				blobs.append([trunk_x, ty, half, int(h * 0.16)])
			for y in h:
				for x in w:
					var inside := false; var shade := 0.0
					for bl in blobs:
						var dy: int = y - bl[1]
						if dy >= 0 and dy < bl[3]:
							var hw := float(bl[2]) * float(dy) / float(bl[3]) + 2.0
							var jag := nz.get_noise_2d(x * 1.0, y * 2.0) * 3.0
							if absf(x - bl[0]) < hw + jag:
								inside = true
								shade = 0.75 - (float(x - bl[0]) / hw) * 0.35 - float(dy) / float(bl[3]) * 0.35
					if inside:
						img.set_pixel(x, y, ramp(tr, shade + nz.get_noise_2d(x * 2.0, y * 2.0) * 0.25, x, y))
		else:
			var nb := rng.randi_range(6, 9)
			for i in nb:
				var bx := trunk_x + rng.randi_range(-30, 30)
				var by := rng.randi_range(18, int(h * 0.45))
				var br := rng.randi_range(14, 24)
				blobs.append([bx, by, br])
			for y in h:
				for x in w:
					var best := -1.0; var shade := 0.0
					for bl in blobs:
						var dx := float(x - bl[0]); var dy := float(y - bl[1])
						var r := float(bl[2]) * (1.0 + nz.get_noise_2d(x * 1.5, y * 1.5) * 0.25)
						var d := sqrt(dx * dx + dy * dy) / r
						if d < 1.0:
							# light from the upper left: normal-ish dot
							var lv := 0.55 + (-dx - dy) / r * 0.32 + (1.0 - d) * 0.2
							if 1.0 - d > best:
								best = 1.0 - d; shade = lv
					if best >= 0.0:
						var leaf := nz.get_noise_2d(x * 4.0, y * 4.0) * 0.22
						img.set_pixel(x, y, ramp(tr, shade + leaf, x, y))
		_outline(img, tr[0].darkened(0.45))
		return _tex(img, false))


## Low bush / fern clump card.
static func bush_card(look: Dictionary, seed: int) -> Texture2D:
	return cached("bush%d" % seed, func():
		var w := 64; var h := 36
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		var nz := _noise(seed + 2, 0.25, 2)
		var tr: Array = look.tree
		var blobs := []
		for i in 6:
			blobs.append([rng.randi_range(12, w - 12), rng.randi_range(14, h - 8), rng.randi_range(8, 13)])
		for y in h:
			for x in w:
				var best := -1.0; var shade := 0.0
				for bl in blobs:
					var dx := float(x - bl[0]); var dy := float(y - bl[1])
					var d := sqrt(dx * dx + dy * dy * 1.6) / float(bl[2])
					if d < 1.0 and y < h - 1:
						var lv := 0.6 + (-dx - dy) / float(bl[2]) * 0.3
						if 1.0 - d > best: best = 1.0 - d; shade = lv
				if best >= 0.0:
					img.set_pixel(x, y, ramp(tr, shade + nz.get_noise_2d(x * 3.0, y * 3.0) * 0.25, x, y))
		# a few flowers
		for i in 5:
			var x := rng.randi_range(4, w - 5); var y := rng.randi_range(4, h - 6)
			if img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, look.flowers[i % look.flowers.size()])
		_outline(img, tr[0].darkened(0.4))
		return _tex(img, false))


## Tall grass tuft card.
static func grass_card(look: Dictionary, seed: int) -> Texture2D:
	return cached("grass%d" % seed, func():
		var w := 24; var h := 16
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		var g: Array = look.ground
		for i in 11:
			var x0 := float(rng.randi_range(3, w - 4))
			var lean := rng.randf_range(-0.5, 0.5)
			var bh := rng.randi_range(6, h - 1)
			for k in bh:
				var x := int(round(x0 + lean * k))
				var y := h - 1 - k
				if x >= 0 and x < w:
					img.set_pixel(x, y, g[clampi(2 + k * (g.size() - 2) / bh, 0, g.size() - 1)])
		return _tex(img, false))


## Sky backdrop: gradient sky, sun or moon with glow, stars, far ridge and ruin/castle silhouettes.
static func backdrop(look: Dictionary, seed: int) -> Texture2D:
	return cached("sky%d" % seed, func():
		var w := 192; var h := 112
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		var sky: Array = look.sky
		var nz := _noise(seed + 9, 0.02, 3)
		var cel: Dictionary = look.celestial
		var cx: float = cel.x * w; var cy: float = cel.y * h * 1.6
		for y in h:
			for x in w:
				var t := float(y) / float(h)
				var c: Color = sky[0].lerp(sky[1], clampf(t * 1.6, 0, 1)) if t < 0.62 else sky[1].lerp(sky[2], clampf((t - 0.62) / 0.38, 0, 1))
				# banding dither between steps
				var q := 14.0
				c = Color(floor(c.r * q + dither(x, y)) / q, floor(c.g * q + dither(x, y)) / q, floor(c.b * q + dither(x, y)) / q)
				var d := Vector2(x - cx, (y - cy) * 1.0).length()
				var gl := clampf(1.0 - d / 46.0, 0, 1)
				c = c.lerp(Color(cel.color), gl * gl * 0.55)
				img.set_pixel(x, y, c)
		# clouds
		if look.clouds != null:
			for y in int(h * 0.55):
				for x in w:
					var v := nz.get_noise_2d(x * 1.0, y * 3.2) + 0.15 - float(y) / h * 0.4
					if v > 0.12:
						var cc: Color = Color(look.clouds)
						cc = cc.darkened(0.08) if v < 0.2 else cc
						img.set_pixel(x, y, img.get_pixel(x, y).lerp(cc, 0.75 if v > 0.2 else 0.4))
		# stars
		for i in int(cel.stars):
			var x := rng.randi_range(0, w - 1); var y := rng.randi_range(0, int(h * 0.6))
			img.set_pixel(x, y, Color(1, 1, 1, 1).lerp(img.get_pixel(x, y), rng.randf_range(0.0, 0.6)))
		# sun / moon disc
		var rr := 7.0 if cel.moon else 9.0
		for y in range(int(cy - rr - 1), int(cy + rr + 2)):
			for x in range(int(cx - rr - 1), int(cx + rr + 2)):
				if x < 0 or y < 0 or x >= w or y >= h: continue
				var d := Vector2(x - cx, y - cy).length()
				if d <= rr:
					var c: Color = Color(cel.color)
					if cel.moon and Vector2(x - cx - 3, y - cy + 2).length() < 3.0: c = c.darkened(0.12)
					img.set_pixel(x, y, c)
		# far ridges (two layers)
		var rg: Array = look.ridge
		for layer in 2:
			var base := h * (0.52 + layer * 0.14)
			for x in w:
				var top := base - (nz.get_noise_2d(x * 2.0 + layer * 400.0, 0.0) * 0.5 + 0.5) * h * (0.3 - layer * 0.12)
				for y in range(int(top), h):
					var c: Color = rg[layer]
					if y == int(top) and layer == 0: c = rg[2]
					img.set_pixel(x, y, c)
		# ruins / castle silhouette on the ridge
		var ru: Array = look.ruins
		var bx := int(w * 0.62); var by := int(h * 0.62)
		var towers := [[0, 30, 7], [9, 22, 14], [24, 34, 6], [31, 18, 18], [48, 26, 7]]
		for tw in towers:
			for y in range(by - int(tw[1]), by + 20):
				for x in range(bx + int(tw[0]), bx + int(tw[0]) + int(tw[2])):
					if x >= w or y >= h: continue
					var c: Color = ru[0]
					if x == bx + int(tw[0]): c = ru[1]
					# crenellations
					if y < by - int(tw[1]) + 2 and (x - bx) % 2 == 0: continue
					img.set_pixel(x, y, c)
			if look.windows != null:
				for k in 2:
					var wx := bx + int(tw[0]) + int(tw[2]) / 2; var wy := by - int(tw[1]) + 5 + k * 6
					if wx < w and wy < h and rng.randf() < 0.8:
						img.set_pixel(wx, wy, Color(look.windows))
		return _tex(img, false))


## Soft radial glow (linear filtered), white.
static func soft(sz := 64, hard := 0.0) -> Texture2D:
	return cached("soft%d_%s" % [sz, hard], func():
		var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
		for y in sz:
			for x in sz:
				var d := Vector2(x + 0.5 - sz / 2.0, y + 0.5 - sz / 2.0).length() / (sz / 2.0)
				var a := clampf(1.0 - d, 0, 1)
				a = a * a * (1.0 - hard) + (1.0 if d < 1.0 else 0.0) * hard
				img.set_pixel(x, y, Color(1, 1, 1, a))
		return _tex(img))


## Vertical light shaft: bright core fading to the sides and toward the bottom.
static func shaft() -> Texture2D:
	return cached("shaft", func():
		var w := 32; var h := 128
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var u := absf((x + 0.5) / w - 0.5) * 2.0
				var v := float(y) / h
				var a := pow(clampf(1.0 - u, 0, 1), 1.6) * pow(1.0 - v, 0.7) * smoothstep(0.0, 0.12, v)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		return _tex(img))


static func _outline(img: Image, col: Color) -> void:
	var w := img.get_width(); var h := img.get_height()
	var src := img.duplicate() as Image
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0: continue
			var edge := false
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and src.get_pixel(q.x, q.y).a > 0.0:
					edge = true; break
			if edge:
				img.set_pixel(x, y, col)
