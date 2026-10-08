# The stage: a real 3D HD-2D diorama behind the UI (port of render/stage.ts, render/app.ts,
# the shield in render/actor.ts, art/packs/hd2d/scene.ts and battle.ts projectile/lightning).
#
# Screen <-> world mapping. Every other module speaks canvas pixels (390x844 base). The stage
# owns a fixed REFERENCE camera (portrait telephoto, pitched down, see CAM_*). A screen point
# maps to 3D by casting its ray through that reference camera:
#   - to_height(p, h): onto the horizontal plane y = h (feet on pedestals: h = STAND_Y)
#   - to_stage(p):     onto the "stage plane", the vertical plane through the enemy and partner
#                      spots (particles, projectiles, flashes: they travel in depth between them)
#   - to_screen(w):    world -> screen px, wpp(w): world units per screen px at w's depth.
# The real Camera3D = reference * slow "breath" sway * shake; the mapping ignores both, so the
# world stays put and the whole view sways/shakes like TS shook the world container.
extends Node

const Diorama := preload("res://art/hd2d/diorama.gd")
const Manifest := preload("res://art/hd2d/manifest.gd")
const Pedestal := preload("res://art/hd2d/pedestal.gd")
const Tex := preload("res://art/hd2d/tex.gd")
const FX_SHADER := preload("res://art/hd2d/shaders/fx.gdshader")
const SHIELD_SHADER := preload("res://art/hd2d/shaders/shield.gdshader")
const BOLT_SHADER := preload("res://art/hd2d/shaders/lightning.gdshader")

## Reference camera: vertical FOV (deg), pitch down (deg), position. Ground is y = 0.
const CAM_FOV := 30.0
const CAM_PITCH := 19.0
const CAM_POS := Vector3(0.0, 8.0, 20.0)
## Height of the pedestal tops: creatures' feet stand on y = STAND_Y.
const STAND_Y := 0.3

class Pulse extends RefCounted:
	var s := 1.0

## Tweenable shield pulse (TS shieldPulse): tween its `s`.
var shield_pulse := Pulse.new()
## Ambient particle colours of the HD-2D look: {fireflies, leaves, neutral} (TS getStyle().ambience).
var ambience: Dictionary = Manifest.AMBIENCE
## Tests: {"e": Actor, "p": Actor} overrides which actors get the pedestals (normally read from S).
var debug_peds := {}

var world: Node3D
var camera: Camera3D
var environment: Environment
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var diorama: Node3D
var ped_e: Node3D
var ped_p: Node3D

var _biome := 0
var _built := false
var _tint := Color("#ffd9a0")
var _ref := Transform3D()
var _inv := Transform3D()
var _f := 1575.0
var _vsize := Vector2(390, 844)
var _plane_n := Vector3(0, 0, 1)
var _plane_d := 0.0
var _plane_ok := false
var _shield: MeshInstance3D
var _shield_mat: ShaderMaterial
var _shield_a := 0.0
var _vig: CanvasLayer
var _t := 0.0


func _ready() -> void:
	process_priority = -50
	world = Node3D.new(); world.name = "World3D"; add_child(world)
	camera = Camera3D.new(); camera.name = "Camera"
	camera.fov = CAM_FOV; camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.5; camera.far = 160.0
	world.add_child(camera); camera.current = true
	_ref = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-CAM_PITCH), 0, 0)), CAM_POS)
	_inv = _ref.affine_inverse()
	camera.transform = _ref
	camera.attributes = _make_cam_attributes()
	# round bokeh (the default box reads as squares on bright motes), low quality for mobile
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_LOW, true)

	environment = Environment.new()
	var we := WorldEnvironment.new(); we.environment = environment; world.add_child(we)
	key_light = DirectionalLight3D.new(); key_light.name = "Key"; world.add_child(key_light)
	fill_light = DirectionalLight3D.new(); fill_light.name = "Fill"; world.add_child(fill_light)
	key_light.shadow_enabled = true
	# 2 splits: the near split covers the plaza at good resolution, the far one the ruins
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key_light.directional_shadow_max_distance = 42.0
	key_light.directional_shadow_split_1 = 0.55
	key_light.shadow_blur = 1.2
	key_light.shadow_bias = 0.02
	key_light.shadow_normal_bias = 0.3
	key_light.shadow_opacity = 0.85
	fill_light.shadow_enabled = false

	ped_e = Pedestal.new(); world.add_child(ped_e)
	ped_p = Pedestal.new(); world.add_child(ped_p)
	_init_shield()
	_init_vignette()
	_update_projection()
	build_stage()


# ------------------------------------------------------------------ mapping

func _update_projection() -> void:
	_vsize = Layout.size if Layout.size.x > 0 else Vector2(390, 844)
	_f = _vsize.y * 0.5 / tan(deg_to_rad(CAM_FOV) * 0.5)
	# stage plane: vertical, through the enemy and partner spots
	var e := to_height(Layout.epos(), STAND_Y)
	var p := to_height(Layout.ppos(), STAND_Y)
	var n := (e - p).cross(Vector3.UP)
	_plane_ok = n.length() > 0.5
	if _plane_ok:
		n = n.normalized()
		_plane_n = n; _plane_d = n.dot(p)


## Ray direction through screen point p (reference camera).
func ray_dir(p: Vector2) -> Vector3:
	var d := Vector3((p.x - _vsize.x * 0.5) / _f, -(p.y - _vsize.y * 0.5) / _f, -1.0)
	return (_ref.basis * d).normalized()


## Screen px -> point on the horizontal plane y = h.
func to_height(p: Vector2, h := 0.0) -> Vector3:
	var o := _ref.origin
	var d := ray_dir(p)
	if d.y > -0.02:
		d.y = -0.02   # at/above the horizon: clamp far away instead of failing
	return o + d * ((h - o.y) / d.y)


## Screen px -> point on the plane z = z.
func at_z(p: Vector2, z: float) -> Vector3:
	var o := _ref.origin
	var d := ray_dir(p)
	return o + d * ((z - o.z) / minf(d.z, -0.001))


## Screen px -> point at view depth `depth` (distance along the view axis).
func at_depth(p: Vector2, depth: float) -> Vector3:
	var d := Vector3((p.x - _vsize.x * 0.5) / _f, -(p.y - _vsize.y * 0.5) / _f, -1.0) * depth
	return _ref * d


## Screen px -> point on the stage plane (between the enemy and partner spots).
func to_stage(p: Vector2) -> Vector3:
	var o := _ref.origin
	var d := ray_dir(p)
	if _plane_ok:
		var den := _plane_n.dot(d)
		if absf(den) > 0.05:
			var t := (_plane_d - _plane_n.dot(o)) / den
			if t > 8.0 and t < 60.0:
				return o + d * t
	return at_depth(p, 24.0)


## World -> screen px (reference camera).
func to_screen(w: Vector3) -> Vector2:
	var l := _inv * w
	var z := maxf(-l.z, 0.01)
	return Vector2(_vsize.x * 0.5 + l.x / z * _f, _vsize.y * 0.5 - l.y / z * _f)


## View depth of a world point.
func depth_of(w: Vector3) -> float:
	return -(_inv * w).z


## World units per screen px at w's depth.
func wpp(w: Vector3) -> float:
	return maxf(depth_of(w), 0.01) / _f


func cam_right() -> Vector3: return _ref.basis.x
func cam_up() -> Vector3: return _ref.basis.y
func cam_back() -> Vector3: return _ref.basis.z


# ------------------------------------------------------------------ stage API

## Switch the background to a biome (0 or 1). Rebuilds only if it changed.
func set_biome(b: int) -> void:
	if b == _biome and _built:
		return
	_biome = b
	build_stage()


func build_stage() -> void:
	_update_projection()
	if diorama:
		diorama.queue_free()
		world.remove_child(diorama)
	diorama = Diorama.new()
	world.add_child(diorama)
	diorama.build(_biome, self)
	_apply_look(diorama.look)
	ped_e.set_look(diorama.look)
	ped_p.set_look(diorama.look)
	_tint = ambience.neutral
	_built = true


func tint_arena(c: Color) -> void:
	_tint = c


func arena_tint() -> Color:
	return _tint


func update_scene(t: float, dt: float) -> void:
	_t = t
	if diorama:
		diorama.update(t, dt)
	_update_pedestals(t)


func _s() -> Node:
	return get_node_or_null("/root/S")


func _species_size(key: String) -> float:
	var data := get_node_or_null("/root/Data")
	var sp = data.get("SPECIES") if data else null
	if sp is Dictionary and sp.has(key):
		return float(sp[key].get("size", 1.0))
	return float(_FALLBACK_SIZE.get(key, 1.0))


const _FALLBACK_SIZE := {"emberwick": 1.0, "cinderpip": 0.85, "kilnback": 1.22, "bellspring": 0.95, "puddlet": 0.85,
	"brinecrab": 1.18, "truffmole": 1.0, "brambat": 0.9, "mossling": 1.1, "skiray": 0.9, "sparkit": 0.85,
	"coilsnail": 1.12, "warden": 1.45, "noctyrm": 1.5}


func _update_pedestals(t: float) -> void:
	var em = null
	var pa = null
	var pos_p := Layout.ppos()
	var hide_p := false
	if not debug_peds.is_empty():
		em = debug_peds.get("e")
		pa = debug_peds.get("p")
		if debug_peds.get("title", false):
			pos_p = Layout.tpos()
	else:
		var s := _s()
		if s:
			em = s.get("em")
			var mode = s.get("mode")
			var title: bool = mode == "title" or mode == "meta"
			if title:
				pa = s.get("title_actor"); pos_p = Layout.tpos()
			elif s.has_method("active_actor"):
				pa = s.active_actor()
			hide_p = mode == "over"
	var u := Layout.U
	ped_e.visible = em != null and is_instance_valid(em)
	if ped_e.visible:
		var w: float = u * 1.05 * em.extra * _species_size(em.key)
		ped_e.place(to_height(Layout.epos(), 0.0), w * wpp(to_height(Layout.epos(), STAND_Y)), _tint, t)
	ped_p.visible = pa != null and is_instance_valid(pa) and not hide_p
	if ped_p.visible:
		var w2: float = u * 1.05 * pa.extra * _species_size(pa.key)
		ped_p.place(to_height(pos_p, 0.0), w2 * wpp(to_height(pos_p, STAND_Y)), _tint, t)


# ------------------------------------------------------------------ per frame

func _process(_delta: float) -> void:
	_update_projection()
	# camera: reference * breath * shake (real time, so it keeps breathing through hit-stop)
	var rt := Platform.ticks_msec() / 1000.0
	var breath := Transform3D(Basis.from_euler(Vector3(sin(rt * 0.23) * 0.0025, sin(rt * 0.17) * 0.004, 0.0)),
		Vector3(sin(rt * 0.19) * 0.06, sin(rt * 0.27) * 0.03, 0.0))
	var focus := 24.0 / _f
	var sh: Vector2 = Feel.shake_px
	var shake := Transform3D(Basis(Vector3(0, 0, 1), Feel.shake_rot), Vector3(-sh.x * focus, sh.y * focus, 0.0))
	camera.transform = _ref * breath * shake


func _make_cam_attributes() -> CameraAttributesPractical:
	var a := CameraAttributesPractical.new()
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = 34.0
	a.dof_blur_far_transition = 18.0
	a.dof_blur_near_enabled = true
	a.dof_blur_near_distance = 17.0
	a.dof_blur_near_transition = 5.0
	a.dof_blur_amount = 0.12
	return a


func _apply_look(look: Dictionary) -> void:
	var env := environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = look.sky[1]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = look.ambient
	env.ambient_light_energy = look.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = look.exposure
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = look.glow_intensity
	env.glow_strength = 1.0
	env.glow_bloom = look.bloom
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = look.glow_threshold
	env.glow_hdr_scale = 2.0
	var levels := [0.0, 0.6, 1.0, 0.8, 0.45, 0.2, 0.0]
	for i in 7:
		env.set_glow_level(i, levels[i])
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = look.fog
	env.fog_light_energy = 1.0
	env.fog_density = look.fog_density
	env.fog_depth_begin = 26.0
	env.fog_depth_end = 80.0
	env.fog_depth_curve = 1.4
	env.fog_aerial_perspective = 0.0
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = look.contrast
	env.adjustment_saturation = look.saturation
	key_light.light_color = look.key
	key_light.light_energy = look.key_energy
	key_light.basis = Basis.looking_at(look.key_dir, Vector3.UP)
	fill_light.light_color = look.fill
	fill_light.light_energy = look.fill_energy
	fill_light.basis = Basis.looking_at(look.fill_dir, Vector3.UP)
	if _vig:
		(_vig.get_child(0).material as ShaderMaterial).set_shader_parameter("vig", look.vignette)
		(_vig.get_child(1).material as ShaderMaterial).set_shader_parameter("wash", look.wash)


# ------------------------------------------------------------------ shield (TS initShield/updateShield)

func _init_shield() -> void:
	_shield = MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	_shield.mesh = q
	_shield_mat = ShaderMaterial.new(); _shield_mat.shader = SHIELD_SHADER
	_shield_mat.render_priority = 2
	_shield.material_override = _shield_mat
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.visible = false
	world.add_child(_shield)


func update_shield(a, shield: float, active: bool, t: float) -> void:
	if a == null or not is_instance_valid(a) or not a.visible or not active:
		_shield_a = 0.0
		_shield.visible = false
		return
	_shield_a += (minf(1.0, shield / 20.0) * 0.9 - _shield_a) * 0.2
	_shield.visible = _shield_a > 0.005
	if not _shield.visible:
		return
	var A: float = a.art_scale()
	var centre: Vector3 = a.root_point(Vector2(0, -48))
	var r := 64.0 * A * shield_pulse.s
	_shield.global_position = centre + cam_back() * 0.4
	_shield.scale = Vector3(r * 2.2, r * 2.2, 1.0)
	_shield_mat.set_shader_parameter("alpha", _shield_a)
	_shield_mat.set_shader_parameter("rot", t * 0.6)


# ------------------------------------------------------------------ vignette + key-light wash (2D, under the UI)

func _init_vignette() -> void:
	_vig = CanvasLayer.new(); _vig.layer = -1; add_child(_vig)
	# vignette (mix) and upper-left key-light wash (add); parameters come from the biome look
	var codes := ["""
shader_type canvas_item;
uniform vec4 vig : source_color = vec4(0.15, 0.09, 0.03, 0.6);
void fragment() {
	vec2 p = UV - 0.5; p.x *= 0.85;
	COLOR = vec4(vig.rgb, smoothstep(0.3, 0.8, length(p)) * vig.a);
}
""", """
shader_type canvas_item;
render_mode blend_add;
uniform vec4 wash : source_color = vec4(1.0, 0.82, 0.54, 0.16);
void fragment() {
	float k = clamp(1.0 - length((UV - vec2(-0.08, -0.04)) * vec2(1.0, 0.75)) / 0.9, 0.0, 1.0);
	COLOR = vec4(wash.rgb * k * k * wash.a, 1.0);
}
"""]
	for code in codes:
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new(); sh.code = code
		var m := ShaderMaterial.new(); m.shader = sh
		r.material = m
		_vig.add_child(r)


# ------------------------------------------------------------------ projectile / lightning (from battle.ts)

func _fx_quad(tex: Texture2D, col: Color, prio := 3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	mi.mesh = q
	var m := ShaderMaterial.new(); m.shader = FX_SHADER
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("color", col)
	m.render_priority = prio
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _elem(el) -> Dictionary:
	var ml := Engine.get_main_loop() as SceneTree
	var data: Node = ml.root.get_node_or_null("/root/Data") if ml else null
	var e = data.get("ELEM") if data else null
	if e is Dictionary and el != null and e.has(el):
		return e[el]
	return _FALLBACK_ELEM.get(el, {"hex": Color("#d9ccff"), "glow": [Color.WHITE, Color("#d9ccff")]})


const _FALLBACK_ELEM := {
	"ember": {"hex": Color("#ff6a3d"), "glow": [Color("#ff6a3d"), Color("#ffa23d"), Color("#ffe08a")]},
	"tide": {"hex": Color("#34a8ff"), "glow": [Color("#34a8ff"), Color("#8fe3ff"), Color("#e8fbff")]},
	"thorn": {"hex": Color("#4fcf5c"), "glow": [Color("#4fcf5c"), Color("#b6f27a"), Color("#2fae55")]},
	"volt": {"hex": Color("#ffcf2e"), "glow": [Color("#ffcf2e"), Color("#ffffff"), Color("#fff3a0")]},
}


## Glowing orb that arcs from `from` to the (live) point `to.call()`, leaving an element trail,
## lighting the diorama as it flies. Calls on_hit when it lands. o = {size, arc, dur} (U units, s).
func projectile(from: Vector2, to: Callable, el, o: Dictionary, on_hit: Callable) -> void:
	var ed := _elem(el)
	var col: Color = ed.hex
	var glow: Array = ed.glow
	var size := float(o.get("size", 0.25)); var arc := float(o.get("arc", 1.0)); var dur := float(o.get("dur", 0.3))
	var node := Node3D.new(); world.add_child(node)
	var halo := _fx_quad(Particles.tex("glow"), col); node.add_child(halo)
	var core := _fx_quad(Particles.tex("glow"), Color(1, 1, 1)); node.add_child(core)
	var light := OmniLight3D.new(); light.light_color = col; light.light_energy = 2.5 + size * 4.0
	light.omni_range = 3.5; light.shadow_enabled = false; node.add_child(light)
	var trail := {}
	match el:
		"tide": trail = {"grav": 4.0}
		"ember": trail = {"grav": -2.0}
		"thorn": trail = {"swirl": 5.0, "tex": "leaf", "spin": 6.0}
		"volt": trail = {"drag": 6.0, "tex": "spark", "streak": true}
	var step := func(t: float) -> void:
		var b: Vector2 = to.call()
		var u := Layout.U
		var p := Vector2(lerpf(from.x, b.x, t), lerpf(from.y, b.y, t) - sin(t * PI) * arc * u)
		var w := to_stage(p)
		node.global_position = w + cam_back() * 0.5
		var k := wpp(w)
		var s := size * u * 2.6 * k   # TS: halo is the glow texture at size * U * 2.6 px
		halo.scale = Vector3.ONE * s * (1.0 + sin(t * 40.0) * 0.15)
		core.scale = Vector3.ONE * s * 0.45
		var opts := {"n": 3, "color": glow, "spd": 0.6, "life": 0.45, "size": size * 1.1, "size1": 0.1, "drag": 2.0, "r": size * 0.3}
		opts.merge(trail, true)
		Particles.emit(p.x, p.y, opts)
	step.call(0.0)
	var tw := create_tween()
	tw.tween_method(step, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		node.queue_free()
		on_hit.call())


## Volt-style lightning bolt from a to b (screen px): jagged additive strip, sparks, zap, flash.
func lightning(a: Vector2, b: Vector2, el: String) -> void:
	var ed := _elem(el)
	var glow: Array = ed.glow
	var u := Layout.U
	var pts: Array[Vector2] = [a]
	for s in range(1, 9):
		var t := s / 8.0
		var p := a.lerp(b, t)
		if s < 8:
			p += Vector2(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35)) * u
		pts.append(p)
	var im := ImmediateMesh.new()
	_bolt_strip(im, pts, u * 0.28, Color(ed.hex, 0.35))
	_bolt_strip(im, pts, u * 0.07, Color(1, 1, 1, 1))
	var mi := MeshInstance3D.new(); mi.mesh = im
	var m := ShaderMaterial.new(); m.shader = BOLT_SHADER; m.render_priority = 3
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	for p in pts:
		Particles.emit(p.x, p.y, {"n": 3, "color": [Color.WHITE] + glow, "spd": 1.5, "life": 0.25, "size": 0.16, "drag": 4.0, "tex": "spark", "streak": true})
	var tw := create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("alpha", v), 1.0, 0.0, 0.2)
	tw.tween_callback(mi.queue_free)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx and sfx.has_method("zap"):
		sfx.zap()
	Particles.light_flash(ed.hex, b, 3.0)


func _bolt_strip(im: ImmediateMesh, pts: Array[Vector2], width: float, col: Color) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[i]; var p1 := pts[i + 1]
		var dir := (p1 - p0).normalized()
		var nrm := Vector2(-dir.y, dir.x) * width * 0.5
		var a0 := to_stage(p0 + nrm); var b0 := to_stage(p0 - nrm)
		var a1 := to_stage(p1 + nrm); var b1 := to_stage(p1 - nrm)
		for v in [a0, b0, a1, b0, b1, a1]:
			im.surface_set_color(col); im.surface_add_vertex(v)
		# round joint: a small quad fan at p1
		if i < n - 2:
			var c := to_stage(p1)
			var r := width * 0.5
			for k in 6:
				var t0 := k / 6.0 * TAU; var t1 := (k + 1) / 6.0 * TAU
				for v in [c, to_stage(p1 + Vector2(cos(t0), sin(t0)) * r), to_stage(p1 + Vector2(cos(t1), sin(t1)) * r)]:
					im.surface_set_color(col); im.surface_add_vertex(v)
	im.surface_end()
