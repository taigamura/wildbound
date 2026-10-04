# The HD-2D diorama for one biome, in real 3D (the intent of art/packs/hd2d/scene.ts):
#   biome 0 (floors 1-4): sunlit forest ruins. Warm key light from the upper left, flagstone
#     plaza, broken pillars, a ruined wall, trees and bushes as pixel-art cards, light shafts.
#   biome 1 (floors 5-8): moonlit dusk castle ruins. Cool moonlight, castle wall with lit
#     windows, pines, warm lanterns (OmniLights) pooling light on the stones.
# Solid props are low-poly meshes with world-triplanar pixel textures (nearest filtering);
# foliage is camera-facing alpha-cut cards painted with the light baked in. Everything casts
# real shadows from the key light. Depth of field, glow and fog come from the Stage's camera
# and environment. The plaza is centred on the enemy/partner spots so they stand on stone.
extends Node3D

const Tex := preload("res://art/hd2d/tex.gd")
const SHAFT_SHADER := preload("res://art/hd2d/shaders/shaft.gdshader")

## Biome A: sunlit forest ruins, warm.
const FOREST := {
	"sky": [Color("#79aecb"), Color("#d9dcb8"), Color("#f6d595")],
	"celestial": {"moon": false, "x": 0.16, "y": 0.13, "color": "#fff6d8", "stars": 0},
	"clouds": "#fff3dc",
	"ridge": [Color("#a7bdb6"), Color("#8aa596"), Color("#d3dbbd")],
	"ruins": [Color("#7d9488"), Color("#c3cdb0")],
	"windows": null,
	"tree": [Color("#2a4530"), Color("#3f5f45"), Color("#5f8253"), Color("#8aab5e"), Color("#b9cf7a")],
	"far_tree": [Color("#5d7a6a"), Color("#6f8c76"), Color("#86a284"), Color("#a3bb95")],
	"bark": [Color("#2c2a22"), Color("#4a4434"), Color("#6e6448"), Color("#9c8c5e")],
	"ground": [Color("#2f4a2c"), Color("#3e5e33"), Color("#53763d"), Color("#6c8f46"), Color("#8eab58"), Color("#bdc67a")],
	"stone": [Color("#5a5444"), Color("#776f5a"), Color("#968c74"), Color("#b5aa8c"), Color("#d2c7a6")],
	"moss": Color("#6f9a45"),
	"flowers": [Color("#fff1c9"), Color("#ffd36e"), Color("#ff9fb3")],
	"lanterns": false,
	"shaft": Color("#ffe2a0"), "shaft_alpha": 0.7,
	# lighting / environment
	"key": Color("#ffe0b0"), "key_energy": 1.55, "key_dir": Vector3(0.78, -0.56, -0.28),
	"fill": Color("#9fb8ff"), "fill_energy": 0.32, "fill_dir": Vector3(-0.7, -0.3, -0.6),
	"ambient": Color("#9fb0a8"), "ambient_energy": 0.55,
	"exposure": 1.05, "glow_intensity": 0.7, "bloom": 0.015, "glow_threshold": 1.05,
	"fog": Color("#d9dcc0"), "fog_density": 0.55, "contrast": 1.06, "saturation": 1.08,
	"vignette": Color(0.15, 0.09, 0.03, 0.55), "wash": Color(1.0, 0.82, 0.54, 0.22),
}

## Biome B: moonlit dusk, cool blue with warm lanterns.
const MOONLIT := {
	"sky": [Color("#10183a"), Color("#263867"), Color("#6d7fae")],
	"celestial": {"moon": true, "x": 0.2, "y": 0.12, "color": "#eef3ff", "stars": 90},
	"clouds": null,
	"ridge": [Color("#33447a"), Color("#28365f"), Color("#5a71a8")],
	"ruins": [Color("#222d52"), Color("#56699c")],
	"windows": "#ffc56e",
	"tree": [Color("#0c1128"), Color("#151d3a"), Color("#22305a"), Color("#3a4c80"), Color("#5b70a8")],
	"far_tree": [Color("#1a2448"), Color("#24325c"), Color("#2f3f6c"), Color("#3e5182")],
	"bark": [Color("#0e1226"), Color("#1a2140"), Color("#2c3660"), Color("#6577ad")],
	"ground": [Color("#121a34"), Color("#1b2646"), Color("#26345a"), Color("#33456f"), Color("#465c8a"), Color("#6479a8")],
	"stone": [Color("#2b3252"), Color("#3b4468"), Color("#4f5a82"), Color("#6a759c"), Color("#8d97bb")],
	"moss": Color("#3d5a6e"),
	"flowers": [Color("#9fd8ff"), Color("#c9b8ff"), Color("#ffe0a0")],
	"lanterns": true,
	"shaft": Color("#a8c4ff"), "shaft_alpha": 0.45,
	"key": Color("#a9c2ff"), "key_energy": 1.25, "key_dir": Vector3(0.74, -0.6, -0.3),
	"fill": Color("#ffb070"), "fill_energy": 0.12, "fill_dir": Vector3(-0.7, -0.3, -0.6),
	"ambient": Color("#4a5a90"), "ambient_energy": 0.9,
	"exposure": 1.1, "glow_intensity": 0.8, "bloom": 0.02, "glow_threshold": 0.95,
	"fog": Color("#2a3a6a"), "fog_density": 0.6, "contrast": 1.08, "saturation": 1.05,
	"vignette": Color(0.02, 0.03, 0.12, 0.65), "wash": Color(0.62, 0.72, 1.0, 0.16),
}

var look: Dictionary
var _lanterns: Array[OmniLight3D] = []
var _lamp_mats: Array[StandardMaterial3D] = []
var _stage: Node
var _rng := RandomNumberGenerator.new()
var _e := Vector3.ZERO
var _p := Vector3.ZERO


func build(biome: int, stage: Node) -> void:
	_stage = stage
	look = MOONLIT if biome == 1 else FOREST
	_rng.seed = 1234 + biome * 77
	# canonical battle band (HUD top ~13%, hand from ~66%): the plaza is laid out around these spots
	var spots: Dictionary = Layout.band_spots(Layout.size.y * 0.13, Layout.size.y * 0.664)
	_e = stage.to_height(spots.e, 0.0)
	_p = stage.to_height(spots.p, 0.0)
	var c := (_e + _p) * 0.5
	_ground(c)
	_backdrop()
	if biome == 1:
		_castle(c)
		_tree_line(true)
		_lantern(Vector3(_e.x + 2.6, 0, _e.z - 1.2))
		_lantern(Vector3(_p.x - 2.4, 0, _p.z - 3.0))
		_lantern(Vector3(_e.x - 3.6, 0, _e.z - 3.4))
	else:
		_wall_ruins(c)
		_tree_line(false)
	_ruins_near(c, biome)
	_framing(c, biome)
	_shrubs(c)
	_shafts(c, biome)


func update(t: float, _dt: float) -> void:
	for i in _lanterns.size():
		var l := _lanterns[i]
		var f := 1.0 + sin(t * 9.0 + i * 1.7) * 0.06 + sin(t * 23.0 + i) * 0.04
		l.light_energy = 2.4 * f


# ------------------------------------------------------------------ helpers

func _x_at(sx: float, z: float) -> float:
	# screen-x fraction (0 = left edge, 1 = right edge) -> world x at ground depth z
	var vs: Vector2 = Layout.size
	var a: Vector3 = _stage.at_z(Vector2(0, vs.y * 0.5), z)
	var b: Vector3 = _stage.at_z(Vector2(vs.x, vs.y * 0.5), z)
	return lerpf(a.x, b.x, sx)


func _solid(tex: Texture2D, texel := 0.06, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / (64.0 * texel)
	m.roughness = 1.0
	m.metallic_specular = 0.15
	return m


func _card_mat(tex: Texture2D, tint := Color.WHITE, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Upright camera-facing card standing on the ground at (x, z); h = height in world units.
func _card(tex: Texture2D, x: float, z: float, h: float, mat: Material = null, y := 0.0, flip := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var ar := float(tex.get_width()) / float(tex.get_height())
	q.size = Vector2(h * ar, h)
	q.center_offset = Vector3(0, h * 0.5, 0)
	mi.mesh = q
	mi.material_override = mat if mat else _card_mat(tex)
	mi.position = Vector3(x, y, z)
	if flip:
		mi.scale.x = -1.0
	add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b; mi.material_override = mat
	mi.position = pos; mi.rotation = rot
	add_child(mi)
	return mi


func _cyl(r: float, h: float, pos: Vector3, mat: Material, sides := 8, top_r := -1.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r if top_r < 0.0 else top_r; c.bottom_radius = r; c.height = h
	c.radial_segments = sides; c.rings = 1
	mi.mesh = c; mi.material_override = mat
	mi.position = pos + Vector3(0, h * 0.5, 0) if rot == Vector3.ZERO else pos
	mi.rotation = rot
	add_child(mi)
	return mi


# ------------------------------------------------------------------ ground

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D grass : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D stone : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform vec2 centre;
uniform vec2 radius;
uniform float texel = 0.05;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 snapped = (floor(wp.xz / texel) + 0.5) * texel;
	float n = texture(noise, snapped * 0.11).r;
	float d = length((snapped - centre) / radius) + (n - 0.5) * 0.5;
	vec3 g = texture(grass, wp.xz / (128.0 * texel)).rgb;
	vec3 s = texture(stone, wp.xz / (128.0 * texel)).rgb;
	float m = step(d, 1.0);
	// darker grass right at the plaza edge (contact)
	float edge = smoothstep(1.25, 1.0, d) * (1.0 - m);
	ALBEDO = mix(g * (1.0 - 0.25 * edge), s, m);
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
"""


func _ground(c: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(160, 160); pm.subdivide_width = 0; pm.subdivide_depth = 0
	mi.mesh = pm
	mi.position = Vector3(c.x, 0, c.z - 30)
	var sh := Shader.new(); sh.code = GROUND_SHADER
	var m := ShaderMaterial.new(); m.shader = sh
	m.set_shader_parameter("grass", Tex.ground(look, 3 + (1 if look == MOONLIT else 0) * 100))
	m.set_shader_parameter("stone", Tex.flagstone(look, 5 + (1 if look == MOONLIT else 0) * 100))
	var nz := FastNoiseLite.new(); nz.seed = 9; nz.frequency = 0.05
	m.set_shader_parameter("noise", ImageTexture.create_from_image(nz.get_seamless_image(64, 64)))
	var len := absf(_e.z - _p.z)
	m.set_shader_parameter("centre", Vector2(c.x, c.z))
	m.set_shader_parameter("radius", Vector2(maxf(4.2, absf(_e.x - _p.x) + 3.0), len * 0.5 + 3.2))
	m.set_shader_parameter("texel", 0.022)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _backdrop() -> void:
	var tex := Tex.backdrop(look, 21 + (100 if look == MOONLIT else 0))
	var z := _e.z - 48.0
	var w := 64.0
	var h := w * float(tex.get_height()) / float(tex.get_width())
	var mi := _card(tex, _e.x * 0.5, z, h, _card_mat(tex, Color.WHITE, true), -h * 0.2)
	(mi.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	(mi.material_override as StandardMaterial3D).disable_fog = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ trees

func _tree_line(pine: bool) -> void:
	var far := look.duplicate()
	far.tree = look.far_tree
	# far line (blurred by DOF, hazed by fog)
	for i in 16:
		var z := _e.z - _rng.randf_range(20.0, 34.0)
		var x := lerpf(_x_at(-0.25, z), _x_at(1.25, z), (i + _rng.randf_range(-0.3, 0.3)) / 15.0)
		var t := Tex.tree_card(far, 300 + i % 5, pine)
		var mi := _card(t, x, z, _rng.randf_range(10.0, 15.0), null, 0.0, _rng.randf() < 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# mid line, behind the ruins
	for i in 9:
		var z := _e.z - _rng.randf_range(10.0, 16.0)
		var x := lerpf(_x_at(-0.3, z), _x_at(1.3, z), (i + _rng.randf_range(-0.25, 0.25)) / 8.0)
		var t := Tex.tree_card(look, 200 + i % 4, pine)
		_card(t, x, z, _rng.randf_range(9.0, 12.0), null, 0.0, _rng.randf() < 0.5)


# ------------------------------------------------------------------ ruins

func _wall_ruins(c: Vector3) -> void:
	var stone := _solid(Tex.stone_blocks(look, 7), 0.03)
	var z := _e.z - 7.5
	var x0 := _e.x - 1.5
	# ruined wall: a run of blocks with a broken, stepped top
	var heights := [2.6, 3.1, 2.2, 1.4, 0.9, 1.8, 2.7, 3.4, 2.0]
	for i in heights.size():
		var h: float = heights[i]
		_box(Vector3(1.0, h, 0.9), Vector3(x0 - 4.0 + i * 1.0, h * 0.5, z), stone)
	# arch with two tall columns
	var col := _solid(Tex.stone_blocks(look, 8, 6, 10), 0.028)
	var ax := _e.x + 3.2
	_cyl(0.42, 5.2, Vector3(ax - 1.4, 0, z - 1.0), col, 10)
	_cyl(0.42, 4.1, Vector3(ax + 1.4, 0, z - 1.0), col, 10)
	_box(Vector3(1.2, 0.5, 1.0), Vector3(ax - 1.4, 5.45, z - 1.0), stone)
	_box(Vector3(2.4, 0.45, 0.9), Vector3(ax - 0.5, 5.9, z - 1.0), stone, Vector3(0, 0, 0.12))
	# rubble at the wall foot
	for i in 7:
		var s := _rng.randf_range(0.25, 0.6)
		_box(Vector3(s, s * 0.7, s), Vector3(x0 - 3.0 + _rng.randf_range(0, 8), s * 0.35, z + _rng.randf_range(0.6, 1.6)), stone, Vector3(0, _rng.randf() * 3, 0))


func _castle(c: Vector3) -> void:
	var stone := _solid(Tex.stone_blocks(look, 7), 0.035)
	var z := _e.z - 9.0
	var xc := _e.x - 0.5
	# curtain wall with merlons
	_box(Vector3(26.0, 5.0, 1.2), Vector3(xc, 2.5, z), stone)
	for i in 22:
		_box(Vector3(0.6, 0.6, 1.2), Vector3(xc - 12.6 + i * 1.2, 5.3, z), stone)
	# towers with roofs
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color("#1a2246"); roof.roughness = 1.0
	for tx in [xc - 5.5, xc + 6.0]:
		_cyl(1.7, 8.0, Vector3(tx, 0, z + 0.3), stone, 12)
		_cyl(2.0, 3.0, Vector3(tx, 8.0, z + 0.3), roof, 12, 0.0)
		for k in 3:
			_window(Vector3(tx + _rng.randf_range(-0.6, 0.6), 2.5 + k * 1.8, z + 2.02), 0.35, 0.55)
	# gate (dark) with a warm glow inside
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color("#05070f"); dark.roughness = 1.0
	_box(Vector3(2.2, 3.0, 0.2), Vector3(xc, 1.5, z + 0.55), dark)
	_window(Vector3(xc, 0.9, z + 0.68), 1.2, 1.2, 0.5)
	for k in 5:
		_window(Vector3(xc - 10.0 + k * 4.4 + _rng.randf_range(-0.5, 0.5), 3.4, z + 0.62), 0.3, 0.5)


func _window(pos: Vector3, w: float, h: float, strength := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(w, h)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(look.windows) * (1.6 * strength)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	add_child(mi)


func _lantern(pos: Vector3) -> void:
	var iron := StandardMaterial3D.new(); iron.albedo_color = Color("#1b1d2a"); iron.roughness = 0.8
	_box(Vector3(0.14, 2.3, 0.14), pos + Vector3(0, 1.15, 0), iron)
	_box(Vector3(0.5, 0.12, 0.12), pos + Vector3(0.18, 2.25, 0), iron)
	var lamp := StandardMaterial3D.new()
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.albedo_color = Color("#ffc56e") * 2.2
	_lamp_mats.append(lamp)
	_box(Vector3(0.26, 0.34, 0.26), pos + Vector3(0.38, 2.0, 0), lamp)
	var l := OmniLight3D.new()
	l.light_color = Color("#ffb35c"); l.light_energy = 2.4; l.omni_range = 5.5; l.omni_attenuation = 1.3
	l.shadow_enabled = false
	l.position = pos + Vector3(0.38, 1.9, 0.3)
	add_child(l)
	_lanterns.append(l)


## Broken pillars, a fallen column and blocks around the plaza.
func _ruins_near(c: Vector3, biome: int) -> void:
	var col := _solid(Tex.stone_blocks(look, 8, 6, 10), 0.028)
	var stone := _solid(Tex.stone_blocks(look, 7), 0.03)
	# left, between the two spots (frames the partner)
	_cyl(0.38, 2.7, Vector3(_x_at(0.04, _p.z - 3.5), 0, _p.z - 3.5), col, 10)
	_box(Vector3(0.95, 0.35, 0.95), Vector3(_x_at(0.04, _p.z - 3.5), 2.85, _p.z - 3.5), stone, Vector3(0, 0.3, 0.06))
	# right of the enemy, taller and snapped
	var rx := _x_at(0.98, _e.z - 1.5)
	_cyl(0.4, 3.6, Vector3(rx, 0, _e.z - 1.5), col, 10)
	_cyl(0.4, 1.0, Vector3(rx + 0.15, 3.65, _e.z - 1.5), col, 10, -1.0, Vector3(0.0, 0.0, 0.5))
	# fallen column behind the enemy, left
	_cyl(0.36, 3.6, Vector3(_e.x - 2.6, 0.36, _e.z - 3.2), col, 10, -1.0, Vector3(0.0, 0.5, PI * 0.5))
	# stumps and blocks
	_cyl(0.42, 0.7, Vector3(_x_at(0.12, _e.z - 4.0), 0, _e.z - 4.0), col, 10)
	_box(Vector3(0.7, 0.5, 0.6), Vector3(_x_at(0.88, _p.z - 1.5), 0.25, _p.z - 1.5), stone, Vector3(0, 0.4, 0))
	_box(Vector3(0.45, 0.35, 0.4), Vector3(_x_at(0.95, _p.z - 0.5), 0.17, _p.z - 0.5), stone, Vector3(0, 1.1, 0))
	if biome == 0:
		# a mossy plinth near the enemy
		_box(Vector3(1.4, 0.5, 1.2), Vector3(_e.x + 1.9, 0.25, _e.z - 3.8), stone)


## Big out-of-focus elements near the camera and at the sides (tilt-shift framing).
func _framing(c: Vector3, biome: int) -> void:
	var pine := biome == 1
	# a large trunk on the left edge, close to the camera (near blur)
	var tz := _p.z + 3.5
	var tx := _x_at(-0.1, tz)
	var bark := _solid(Tex.bark(look, 4), 0.03)
	_cyl(0.5, 14.0, Vector3(tx, 0, tz), bark, 10, 0.42)
	# canopy over the top of the frame
	if not pine:
		_card(Tex.tree_card(look, 77, false, true), tx + 1.2, tz - 1.0, 9.0, null, 4.2)
	_card(Tex.tree_card(look, 78, pine), _x_at(1.05, _e.z - 5.0), _e.z - 5.0, 11.0, null, 0.0, true)
	_card(Tex.tree_card(look, 79, pine), _x_at(-0.1, _e.z - 7.0), _e.z - 7.0, 10.0)
	# foreground bushes at the bottom corners
	var bz := _p.z + 6.0
	_card(Tex.bush_card(look, 31), _x_at(0.02, bz), bz, 1.3)
	_card(Tex.bush_card(look, 32), _x_at(0.98, bz + 1.0), bz + 1.0, 1.2, null, 0.0, true)


## Bushes and grass tufts around the plaza edge (grass as one MultiMesh).
func _shrubs(c: Vector3) -> void:
	for i in 6:
		var z := lerpf(_e.z - 5.0, _p.z + 2.0, i / 5.0)
		var left := i % 2 == 0
		var x := _x_at(0.03 if left else 0.97, z) + _rng.randf_range(-0.4, 0.4)
		_card(Tex.bush_card(look, 33 + i % 3), x, z, _rng.randf_range(0.8, 1.2), null, 0.0, not left)
	var gt := Tex.grass_card(look, 51)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	var h := 0.42
	q.size = Vector2(h * 1.5, h); q.center_offset = Vector3(0, h * 0.5, 0)
	mm.mesh = q
	var n := 90
	mm.instance_count = n
	var len := absf(_e.z - _p.z)
	var rx := maxf(4.2, absf(_e.x - _p.x) + 3.0)
	var rz := len * 0.5 + 3.2
	for i in n:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(1.0, 1.6)
		if i < 18:
			d = _rng.randf_range(0.2, 0.95)   # a few between the paving stones
		var p := Vector3(c.x + cos(a) * rx * d, 0, c.z + sin(a) * rz * d)
		var s := _rng.randf_range(0.7, 1.4) * (0.6 if d < 1.0 else 1.0)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s * (-1.0 if _rng.randf() < 0.5 else 1.0), s, 1)), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _card_mat(gt)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Additive light shafts slanting down from the upper left.
func _shafts(c: Vector3, biome: int) -> void:
	var tex := Tex.shaft()
	var spots := [[0.2, _e.z - 5.0, 2.6], [0.55, _e.z - 9.0, 3.4], [0.82, _e.z - 3.0, 2.0], [0.62, _p.z - 6.0, 1.6]]
	for i in spots.size():
		var s: Array = spots[i]
		var z: float = s[1]
		var w: float = s[2]
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new(); q.size = Vector2(w, 16.0); q.center_offset = Vector3(0, -8.0, 0)
		mi.mesh = q
		var m := ShaderMaterial.new(); m.shader = SHAFT_SHADER
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("color", look.shaft)
		m.set_shader_parameter("strength", float(look.shaft_alpha) * (1.0 if i != 3 else 0.6))
		m.set_shader_parameter("phase", i * 1.9)
		m.render_priority = -1
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# top of the beam high up and to the left; tilted so it falls toward the lower right
		var x := _x_at(float(s[0]), z)
		mi.position = Vector3(x - 3.0, 13.0, z)
		mi.rotation = Vector3(0, 0, deg_to_rad(28.0))
		add_child(mi)
