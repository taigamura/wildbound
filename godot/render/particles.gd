# Pooled particles, shockwave rings, light flashes and element bursts (port of render/particles.ts).
# The simulation runs in screen px exactly like TS (same option keys, U-based speeds/sizes).
# Rendering is 3D: each particle is mapped onto the Stage's stage plane (between the enemy and
# partner spots) and drawn as a camera-facing quad in one of two MultiMeshes (additive / normal),
# sized so it covers the same screen px as in TS. They draw over the scene like the TS front layer
# but get the scene's glow, and light flashes are real OmniLights that light the diorama.
extends Node

const Tex := preload("res://art/hd2d/tex.gd")
const FX_SHADER := preload("res://art/hd2d/shaders/fx.gdshader")
const ADD_SHADER := preload("res://art/hd2d/shaders/particles_add.gdshader")
const MIX_SHADER := preload("res://art/hd2d/shaders/particles_mix.gdshader")

const PN := 2200
## Atlas cells (same names as TS TEX).
const TEXN := {"glow": 0, "soft": 1, "spark": 2, "leaf": 3, "star": 4, "ring": 5}
const STRIDE := 20   # floats per instance: transform 12, colour 4, custom 4

var _x := PackedFloat32Array(); var _y := PackedFloat32Array()
var _vx := PackedFloat32Array(); var _vy := PackedFloat32Array()
var _life := PackedFloat32Array(); var _max := PackedFloat32Array()
var _grav := PackedFloat32Array(); var _drag := PackedFloat32Array()
var _s0 := PackedFloat32Array(); var _s1 := PackedFloat32Array(); var _a0 := PackedFloat32Array()
var _swirl := PackedFloat32Array(); var _spin := PackedFloat32Array(); var _rot := PackedFloat32Array()
var _floor := PackedFloat32Array()
var _flags := PackedInt32Array()   # bit0 alive, bit1 streak, bit2 has floor, bit3 normal blend, bits 8.. tex cell
var _col := PackedColorArray()
var _act := PackedInt32Array()     # indices that may be alive
var _pi := 0

var _mm_add: MultiMesh
var _mm_mix: MultiMesh
var _buf_add := PackedFloat32Array()
var _buf_mix := PackedFloat32Array()
var _atlas: ImageTexture
var _cells: Array[ImageTexture] = []

var _rings: Array[MeshInstance3D] = []
var _ring_tw: Array = []
var _blooms: Array[MeshInstance3D] = []
var _bloom_tw: Array = []
var _lights: Array[OmniLight3D] = []
var _light_tw: Array = []
var _li := 0
var _amb_t := 0.0
var _leaf_t := 0.0
var _ready_done := false


func _ready() -> void:
	_x.resize(PN); _y.resize(PN); _vx.resize(PN); _vy.resize(PN); _life.resize(PN); _max.resize(PN)
	_grav.resize(PN); _drag.resize(PN); _s0.resize(PN); _s1.resize(PN); _a0.resize(PN); _swirl.resize(PN)
	_spin.resize(PN); _rot.resize(PN); _floor.resize(PN); _flags.resize(PN); _col.resize(PN)
	_build_textures()
	# Stage (and its 3D world) is created after us in autoload order: finish setup next frame.
	_setup_render.call_deferred()


func _setup_render() -> void:
	var w: Node3D = Stage.world
	_mm_add = _make_mm(ADD_SHADER, w, 10)
	_mm_mix = _make_mm(MIX_SHADER, w, 9)
	_buf_add.resize(PN * STRIDE); _buf_mix.resize(PN * STRIDE)
	for i in 12:
		var r := _quad(_cells[TEXN.ring], 6); w.add_child(r); _rings.append(r); _ring_tw.append(null)
	for i in 6:
		var b := _quad(_cells[TEXN.soft], 7); w.add_child(b); _blooms.append(b); _bloom_tw.append(null)
	for i in 4:
		var l := OmniLight3D.new(); l.visible = false; l.shadow_enabled = false; l.omni_attenuation = 1.4
		w.add_child(l); _lights.append(l); _light_tw.append(null)
	_ready_done = true


func _make_mm(shader: Shader, parent: Node3D, prio: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = PN
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := ShaderMaterial.new(); m.shader = shader
	m.set_shader_parameter("atlas", _atlas)
	m.render_priority = prio
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	parent.add_child(mmi)
	return mm


func _quad(tex: Texture2D, prio: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	mi.mesh = q
	var m := ShaderMaterial.new(); m.shader = FX_SHADER
	m.set_shader_parameter("tex", tex)
	m.render_priority = prio
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


# ------------------------------------------------------------------ textures (TS buildTextures)

## One of the effect textures (TS TEX): "glow" "soft" "spark" "leaf" "star" "ring".
func tex(name: String) -> Texture2D:
	return _cells[TEXN.get(name, 0)]


func _build_textures() -> void:
	var S := 64
	var atlas := Image.create(S * 6, S, false, Image.FORMAT_RGBA8)
	var cells: Array[Image] = []
	for c in 6:
		cells.append(Image.create(S, S, false, Image.FORMAT_RGBA8))
	for y in S:
		for x in S:
			var px := (x + 0.5) / S * 2.0 - 1.0
			var py := (y + 0.5) / S * 2.0 - 1.0
			var d := sqrt(px * px + py * py)
			# glow: 0 -> 1, .22 -> .85, .55 -> .2, 1 -> 0
			var g := 0.0
			if d < 0.22: g = lerpf(1.0, 0.85, d / 0.22)
			elif d < 0.55: g = lerpf(0.85, 0.2, (d - 0.22) / 0.33)
			elif d < 1.0: g = lerpf(0.2, 0.0, (d - 0.55) / 0.45)
			cells[0].set_pixel(x, y, Color(1, 1, 1, g))
			# soft: 0 -> .9, .4 -> .35, 1 -> 0
			var s := 0.0
			if d < 0.4: s = lerpf(0.9, 0.35, d / 0.4)
			elif d < 1.0: s = lerpf(0.35, 0.0, (d - 0.4) / 0.6)
			cells[1].set_pixel(x, y, Color(1, 1, 1, s))
			# spark: horizontal ellipse (64x16 in TS, stretched to the square cell), bright toward +x
			var e := px * px + py * py
			var sp := 0.0
			if e < 1.0:
				var u := (px + 1.0) * 0.5
				sp = (u / 0.7 * 0.9 if u < 0.7 else lerpf(0.9, 1.0, (u - 0.7) / 0.3)) * clampf((1.0 - e) * 3.0, 0, 1)
			cells[2].set_pixel(x, y, Color(1, 1, 1, sp))
			# leaf: two quadratic arcs (pointed ellipse)
			var lx := (x + 0.5) / S; var ly := (y + 0.5) / S
			var half := 0.5 * sin(clampf((lx - 0.125) / 0.75, 0, 1) * PI) * 0.75
			var lf := 1.0 if lx > 0.125 and lx < 0.875 and absf(ly - 0.5) < half else 0.0
			cells[3].set_pixel(x, y, Color(1, 1, 1, lf))
			# star: 8-point star (r 20 / 6 of 48) with a soft halo
			var ang := atan2(py, px)
			var rr := lerpf(20.0 / 24.0, 6.0 / 24.0, absf(fmod(ang / (PI / 4.0) + 8.0, 2.0) - 1.0) * -1.0 + 1.0)
			var st := clampf((rr - d) * 10.0, 0, 1) + clampf(1.0 - d, 0, 1) * 0.25
			cells[4].set_pixel(x, y, Color(1, 1, 1, clampf(st, 0, 1)))
			# ring: circle r 54/64, width 6/64 with a 10px glow
			var rg := clampf(1.0 - absf(d - 54.0 / 64.0) / (3.0 / 64.0), 0, 1)
			rg = maxf(rg, clampf(1.0 - absf(d - 54.0 / 64.0) / (10.0 / 64.0), 0, 1) * 0.45)
			cells[5].set_pixel(x, y, Color(1, 1, 1, rg))
	for c in 6:
		atlas.blit_rect(cells[c], Rect2i(0, 0, S, S), Vector2i(c * S, 0))
		var ci := cells[c].duplicate() as Image
		ci.generate_mipmaps()
		_cells.append(ImageTexture.create_from_image(ci))
	_atlas = ImageTexture.create_from_image(atlas)


# ------------------------------------------------------------------ emit / update

static func _rand(a: float, b: float) -> float:
	return a + randf() * (b - a)


static func _colors(c) -> Array:
	if c is Array:
		return c if not c.is_empty() else [Color.WHITE]
	if c is Color:
		return [c]
	if c is int:
		return [Color.hex((c << 8) | 0xff)]
	return [Color.WHITE]


## Speeds, sizes, gravity and radius are in world units (U); positions in screen px.
func emit(x: float, y: float, o: Dictionary) -> void:
	var u: float = Layout.U
	var fx_mul := 0.5 if Feel.reduced else 1.0
	var n := maxi(1, int(round(float(o.get("n", 20)) * fx_mul)))
	var cols := _colors(o.get("color", Color.WHITE))
	var cell: int = TEXN.get(o.get("tex", "glow"), 0)
	var has_dir := o.has("dir")
	var dv = o.get("dir", [0.0, 0.0])
	var dir: Array = [dv.x, dv.y] if dv is Vector2 else dv
	var cone := float(o.get("cone", 0.4))
	var up := float(o.get("up", 0.0))
	var flat: bool = o.get("flat", false)
	var spd := float(o.get("spd", 3.0))
	var r := float(o.get("r", 0.0)) * u
	var life := float(o.get("life", 0.8))
	var grav := float(o.get("grav", 0.0)) * u
	var drag := float(o.get("drag", 1.0))
	var swirl := float(o.get("swirl", 0.0))
	var has_swirl_dir := o.has("swirl_dir")
	var size := float(o.get("size", 0.25))
	var size1 := float(o.get("size1", 0.1))
	var alpha := float(o.get("alpha", 1.0))
	var streak: bool = o.get("streak", false)
	var spin := float(o.get("spin", 0.0))
	var has_floor := o.has("floor") and o.floor != null
	var floor_v := float(o.get("floor", 0.0)) if has_floor else 0.0
	var normal: bool = o.get("normal", false)
	for kk in n:
		var i := _pi
		_pi = (_pi + 1) % PN
		var dx: float; var dy: float
		if has_dir:
			dx = float(dir[0]) + _rand(-cone, cone); dy = float(dir[1]) + _rand(-cone, cone)
		else:
			var a := randf() * TAU
			dx = cos(a); dy = sin(a)
		if up != 0.0:
			dy = -absf(dy) * up - 0.2
		if flat:
			dy *= 0.2
		var ln := sqrt(dx * dx + dy * dy)
		if ln == 0.0: ln = 1.0
		var sp := spd * (0.35 + randf() * 0.85) * u
		_vx[i] = dx / ln * sp; _vy[i] = dy / ln * sp
		_x[i] = x + _rand(-r, r); _y[i] = y + _rand(-r, r) * (0.3 if flat else 1.0)
		_life[i] = 0.0; _max[i] = life * (0.55 + randf() * 0.7)
		_grav[i] = grav; _drag[i] = drag
		_swirl[i] = float(o.swirl_dir) if has_swirl_dir else swirl * (1.0 if randf() < 0.5 else -1.0)
		_s0[i] = size * (0.55 + randf() * 0.9) * u * 1.6; _s1[i] = size1; _a0[i] = alpha
		_spin[i] = _rand(-spin, spin) if spin != 0.0 else 0.0
		_rot[i] = _rand(0.0, 6.0) if spin != 0.0 else 0.0
		_floor[i] = floor_v
		var was_alive := _flags[i] & 1
		_flags[i] = 1 | (2 if streak else 0) | (4 if has_floor else 0) | (8 if normal else 0) | (cell << 8)
		_col[i] = cols[randi() % cols.size()]
		if not was_alive:
			_act.append(i)


## Advance and draw all particles (call once per frame with the scaled dt; TS updateParticles).
func update_particles(dt: float) -> void:
	if not _ready_done:
		return
	var u: float = Layout.U
	var na := 0
	var nm := 0
	var keep := PackedInt32Array()
	var right: Vector3 = Stage.cam_right()
	for i in _act:
		if (_flags[i] & 1) == 0:
			continue
		_life[i] += dt
		var t := _life[i] / _max[i]
		if t >= 1.0:
			_flags[i] = _flags[i] & ~1
			continue
		keep.append(i)
		var dr := maxf(0.0, 1.0 - _drag[i] * dt)
		var vx := _vx[i] * dr
		var vy := _vy[i] * dr + _grav[i] * dt
		if _swirl[i] != 0.0:
			var a := _swirl[i] * dt
			var c := cos(a); var s := sin(a)
			var ovx := vx
			vx = ovx * c - vy * s
			vy = ovx * s + vy * c
		_x[i] += vx * dt; _y[i] += vy * dt
		var f := _flags[i]
		if (f & 4) and _y[i] > _floor[i] and vy > 0.0:
			_y[i] = _floor[i]; vy *= -0.35; vx *= 0.7
		_vx[i] = vx; _vy[i] = vy
		var sz := _s0[i] * (1.0 + (_s1[i] - 1.0) * t)
		var al := _a0[i] * (t / 0.08 if t < 0.08 else 1.0 - (t - 0.08) / 0.92)
		var ang := 0.0
		var stretch := 1.0
		if f & 2:
			ang = atan2(vy, vx)
			stretch = 1.0 + minf(3.0, sqrt(vx * vx + vy * vy) / (u * 3.0))
		else:
			if _spin[i] != 0.0:
				_rot[i] += _spin[i] * dt
			ang = _rot[i]
		var w: Vector3 = Stage.to_stage(Vector2(_x[i], _y[i]))
		var ws: float = sz * Stage.wpp(w)
		var col := _col[i]
		if f & 8:
			_write(true, nm * STRIDE, w, ws, col, al, -ang, stretch, f >> 8); nm += 1
		else:
			_write(false, na * STRIDE, w, ws, col, al, -ang, stretch, f >> 8); na += 1
	_act = keep
	_mm_add.buffer = _buf_add
	_mm_add.visible_instance_count = na
	_mm_mix.buffer = _buf_mix
	_mm_mix.visible_instance_count = nm


## Packed arrays are passed by value in GDScript, so this writes the member buffers directly.
func _write(mix: bool, o: int, w: Vector3, s: float, c: Color, a: float, ang: float, stretch: float, cell: int) -> void:
	if mix:
		_buf_mix[o] = s
		_buf_mix[o + 1] = 0.0
		_buf_mix[o + 2] = 0.0
		_buf_mix[o + 3] = w.x
		_buf_mix[o + 4] = 0.0
		_buf_mix[o + 5] = s
		_buf_mix[o + 6] = 0.0
		_buf_mix[o + 7] = w.y
		_buf_mix[o + 8] = 0.0
		_buf_mix[o + 9] = 0.0
		_buf_mix[o + 10] = s
		_buf_mix[o + 11] = w.z
		_buf_mix[o + 12] = c.r
		_buf_mix[o + 13] = c.g
		_buf_mix[o + 14] = c.b
		_buf_mix[o + 15] = a
		_buf_mix[o + 16] = ang
		_buf_mix[o + 17] = stretch
		_buf_mix[o + 18] = float(cell)
		_buf_mix[o + 19] = 0.0
	else:
		_buf_add[o] = s
		_buf_add[o + 1] = 0.0
		_buf_add[o + 2] = 0.0
		_buf_add[o + 3] = w.x
		_buf_add[o + 4] = 0.0
		_buf_add[o + 5] = s
		_buf_add[o + 6] = 0.0
		_buf_add[o + 7] = w.y
		_buf_add[o + 8] = 0.0
		_buf_add[o + 9] = 0.0
		_buf_add[o + 10] = s
		_buf_add[o + 11] = w.z
		_buf_add[o + 12] = c.r
		_buf_add[o + 13] = c.g
		_buf_add[o + 14] = c.b
		_buf_add[o + 15] = a
		_buf_add[o + 16] = ang
		_buf_add[o + 17] = stretch
		_buf_add[o + 18] = float(cell)
		_buf_add[o + 19] = 0.0


# ------------------------------------------------------------------ rings, flashes, bursts

func _pick(pool: Array, tws: Array) -> int:
	for i in pool.size():
		if not pool[i].visible:
			return i
	return 0


## Shockwave ring. flat = lying on the ground (a real circle on the floor in 3D).
func ring(x: float, y: float, color: Color, scale := 2.0, dur := 0.5, flat := true) -> void:
	if not _ready_done:
		return
	var i := _pick(_rings, _ring_tw)
	if _ring_tw[i] and _ring_tw[i].is_valid(): _ring_tw[i].kill()
	var s := _rings[i]
	var m: ShaderMaterial = s.material_override
	var u: float = Layout.U
	var p := Vector2(x, y)
	var w: Vector3 = Stage.to_height(p, Stage.STAND_Y + 0.03) if flat else Stage.to_stage(p)
	var k: float = scale * u * 1.6 * (128.0 / 108.0) * Stage.wpp(w)
	s.global_position = w
	s.rotation = Vector3(-PI * 0.5, 0, 0) if flat else Vector3.ZERO
	m.set_shader_parameter("billboard", not flat)
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("alpha", 0.95)
	s.scale = Vector3(0.05, 0.05, 1.0) * k
	s.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector3(k, k, 1.0), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha", v), 0.95, 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): s.visible = false)
	_ring_tw[i] = tw


## Bloom at a point plus a real light pulse that lights the diorama around it.
func light_flash(color: Color, pos: Vector2, v := 4.0) -> void:
	if not _ready_done:
		return
	var u: float = Layout.U
	var w: Vector3 = Stage.to_stage(pos)
	var wp: float = Stage.wpp(w)
	var i := _pick(_blooms, _bloom_tw)
	if _bloom_tw[i] and _bloom_tw[i].is_valid(): _bloom_tw[i].kill()
	var b := _blooms[i]
	var m: ShaderMaterial = b.material_override
	b.global_position = w
	var sz := u * 3.2 * minf(1.5, v / 4.0 + 0.4) * wp
	b.scale = Vector3(sz, sz, 1.0)
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("intensity", 1.2)
	b.visible = true
	var a0 := 0.55 * minf(1.4, v / 4.0)
	var tw := create_tween()
	tw.tween_method(func(a: float): m.set_shader_parameter("alpha", a), a0, 0.0, 0.35)
	tw.tween_callback(func(): b.visible = false)
	_bloom_tw[i] = tw
	# real light
	var li := _li; _li = (_li + 1) % _lights.size()
	if _light_tw[li] and _light_tw[li].is_valid(): _light_tw[li].kill()
	var l := _lights[li]
	l.global_position = w + Stage.cam_back() * (u * 0.8 * wp)
	l.light_color = color
	l.omni_range = u * 5.0 * wp
	l.visible = true
	var e0 := 1.6 * minf(2.0, v / 2.0)
	l.light_energy = e0
	var tl := create_tween()
	tl.tween_property(l, "light_energy", 0.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tl.tween_callback(func(): l.visible = false)
	_light_tw[li] = tl


func burst(p: Vector2, el, power := 1.0) -> void:
	var u: float = Layout.U
	var c: Array = Stage._elem(el).glow if el != null else [Color.WHITE, Color("#d9ccff"), Color("#9b7bff")]
	match el:
		"ember":
			emit(p.x, p.y, {"n": 50 * power, "color": c, "spd": 4.2 * power, "life": 0.85, "size": 0.3, "size1": 0.05, "grav": -2.6, "drag": 2.2})
			emit(p.x, p.y, {"n": 22 * power, "color": [Color("#fff1b0"), Color("#ffa23d")], "spd": 7, "life": 0.4, "size": 0.18, "drag": 4, "tex": "spark", "streak": true})
		"tide":
			emit(p.x, p.y, {"n": 46 * power, "color": c, "spd": 4.6 * power, "up": 1.2, "life": 1.0, "size": 0.22, "size1": 0.5, "grav": 9, "drag": 0.5, "floor": p.y + u * 0.9})
			emit(p.x, p.y + u * 0.8, {"n": 22 * power, "color": c, "spd": 3, "flat": true, "life": 0.6, "size": 0.2, "drag": 3})
		"thorn":
			emit(p.x, p.y, {"n": 30 * power, "color": c, "spd": 3.4 * power, "life": 1.3, "size": 0.32, "size1": 0.6, "grav": 1.4, "drag": 2.4, "swirl": 6, "tex": "leaf", "spin": 8})
			emit(p.x, p.y, {"n": 16 * power, "color": c, "spd": 3, "life": 0.6, "size": 0.22, "drag": 3})
		"volt":
			emit(p.x, p.y, {"n": 50 * power, "color": c, "spd": 8 * power, "life": 0.32, "size": 0.22, "size1": 0.2, "drag": 7, "tex": "spark", "streak": true})
			emit(p.x, p.y, {"n": 6 * power, "color": [Color.WHITE], "spd": 1, "life": 0.15, "size": 0.9, "size1": 0.2, "drag": 3, "tex": "star", "spin": 6})
		_:
			emit(p.x, p.y, {"n": 40 * power, "color": c, "spd": 4.5 * power, "life": 0.6, "size": 0.25, "drag": 3})
	emit(p.x, p.y, {"n": 14 * power, "color": [Color.WHITE], "spd": 7, "life": 0.22, "size": 0.16, "drag": 5, "tex": "spark", "streak": true})
	ring(p.x, p.y, Stage._elem(el).hex if el != null else Color("#d9ccff"), 1.4 * power, 0.45, false)


## Fireflies and drifting leaves (colours: Stage.ambience).
func ambient(dt: float, fireflies: Array, leaves: Array) -> void:
	var sz: Vector2 = Layout.size
	_amb_t += dt
	if _amb_t > 0.07:
		_amb_t = 0.0
		emit(_rand(0, sz.x), _rand(sz.y * 0.3, sz.y * 0.95), {"n": 1, "color": fireflies, "spd": 0.25, "life": 3.5, "size": 0.11, "size1": 1, "grav": -0.06, "drag": 0.2, "alpha": 0.85})
	_leaf_t += dt
	if _leaf_t > 0.5:
		_leaf_t = 0.0
		emit(_rand(-sz.x * 0.1, sz.x), -10, {"n": 1, "color": leaves, "spd": 0.6, "dir": [0.4, 1.0], "cone": 0.2, "life": 9, "size": 0.2, "size1": 1, "grav": 0.05, "drag": 0.1, "alpha": 0.45, "tex": "leaf", "spin": 1.5, "swirl": 0.6, "normal": true})
