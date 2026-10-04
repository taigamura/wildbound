# Lit stone pedestal under a creature (port of hd2dPedestal in art/packs/hd2d/scene.ts, in 3D):
# a low stone drum with a paved top, an arena-tinted glow pooled on the ground, a tinted rim
# light around the top edge and a small tinted OmniLight that rim-lights the creature's feet.
extends Node3D

const Tex := preload("res://art/hd2d/tex.gd")
const FX_SHADER := preload("res://art/hd2d/shaders/fx_world.gdshader")
const H := 0.3   # must match Stage.STAND_Y

var _drum: MeshInstance3D
var _top: MeshInstance3D
var _glow: MeshInstance3D
var _rim: MeshInstance3D
var _shadow: MeshInstance3D
var _light: OmniLight3D
var _glow_m: ShaderMaterial
var _rim_m: ShaderMaterial


func _init() -> void:
	_drum = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0; cyl.bottom_radius = 1.06; cyl.height = H; cyl.radial_segments = 18; cyl.rings = 1
	_drum.mesh = cyl; _drum.position.y = H * 0.5
	add_child(_drum)
	_top = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.94; disc.bottom_radius = 0.94; disc.height = 0.02; disc.radial_segments = 18; disc.rings = 1
	_top.mesh = disc; _top.position.y = H + 0.005
	_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_top)
	_shadow = _flat(Tex.soft(64), Color(0, 0, 0, 1), false)
	_shadow.position = Vector3(0.18, 0.012, -0.12)
	add_child(_shadow)
	_glow = _flat(Tex.soft(64), Color.WHITE, true)
	_glow.position.y = 0.02
	_glow_m = _glow.material_override
	add_child(_glow)
	_rim = _flat(_ring_tex(), Color.WHITE, true)
	_rim.position.y = H + 0.03
	_rim_m = _rim.material_override
	add_child(_rim)
	_light = OmniLight3D.new()
	_light.omni_range = 3.0; _light.light_energy = 0.4; _light.shadow_enabled = false
	_light.omni_attenuation = 2.0
	add_child(_light)


static func _ring_tex() -> Texture2D:
	return Tex.cached("pedring", func():
		var s := 128
		var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
		for y in s:
			for x in s:
				var d := Vector2(x + 0.5 - s / 2.0, y + 0.5 - s / 2.0).length() / (s / 2.0)
				var a := clampf(1.0 - absf(d - 0.86) / 0.12, 0, 1)
				a = a * a + clampf(1.0 - absf(d - 0.86) / 0.03, 0, 1) * 0.6
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0, 1)))
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


func _flat(tex: Texture2D, col: Color, additive: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(2, 2); q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if additive:
		var m := ShaderMaterial.new(); m.shader = FX_SHADER
		m.set_shader_parameter("tex", tex); m.set_shader_parameter("color", col)
		m.set_shader_parameter("billboard", false); m.set_shader_parameter("intensity", 1.0)
		m.render_priority = 1
		mi.material_override = m
	else:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_texture = tex; sm.albedo_color = Color(0, 0, 0, 0.55)
		sm.disable_receive_shadows = true
		mi.material_override = sm
	return mi


## Re-skin for a biome look (stone colours).
func set_look(look: Dictionary) -> void:
	var side := StandardMaterial3D.new()
	side.albedo_texture = Tex.stone_blocks(look, 41, 5, 12)
	side.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	side.uv1_scale = Vector3(4.0, 0.6, 1.0)
	side.roughness = 1.0
	side.metallic_specular = 0.2
	_drum.material_override = side
	var top := StandardMaterial3D.new()
	top.albedo_texture = Tex.flagstone(look, 17)
	top.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	top.uv1_triplanar = true
	top.uv1_world_triplanar = true
	top.uv1_scale = Vector3.ONE / 2.4
	top.albedo_color = Color(1.12, 1.1, 1.05)
	top.roughness = 1.0
	top.metallic_specular = 0.25
	_top.material_override = top


## ground: point on the ground under the feet; w: TS pedestal width (px) converted to world units.
func place(ground: Vector3, w: float, tint: Color, t: float) -> void:
	global_position = ground
	var r := w * 1.05
	_drum.scale = Vector3(r, 1.0, r)
	_top.scale = Vector3(r, 1.0, r)
	_shadow.scale = Vector3(w * 1.35, 1.0, w * 1.15)
	_glow.scale = Vector3(w * 1.45, 1.0, w * 1.45)
	_glow_m.set_shader_parameter("color", tint)
	_glow_m.set_shader_parameter("alpha", 0.3 + sin(t * 2.0) * 0.06)
	_rim.scale = Vector3(r * 1.02, 1.0, r * 1.02)
	_rim_m.set_shader_parameter("color", tint)
	_rim_m.set_shader_parameter("alpha", 0.55 + sin(t * 2.0) * 0.15)
	_light.light_color = tint
	# low and in front: a soft tinted bounce on the creature's feet and the drum, not a hotspot
	_light.position = Vector3(0.0, H + w * 0.45, w * 1.15)
	_light.omni_range = w * 2.2
