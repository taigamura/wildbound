# An on-screen creature (port of render/actor.ts + the hd2d sprite creature).
# A pixel-art sprite standing upright in the 3D diorama: it receives the key light, casts a real
# shadow and is depth-sorted with the scene (so S.em stands behind the partner naturally).
# Gameplay talks to Actors in screen px (place/head) and world units U (off), exactly like TS.
#
# Node chain (all art-space below `flip`: 1 unit = 1 art unit, y up, facing right):
#   Actor (feet + off, slight lean back toward the camera)
#     flip  (scale face*A, A: world units per art unit; roll = rot)
#       rig  (idle bob / sway / breathe, per frame)
#         sq  (squash & stretch = `squash`, tweenable)
#           sprite quad (anchored at the feet)
class_name Actor
extends Node3D

const Manifest := preload("res://art/hd2d/manifest.gd")
const Recolor := preload("res://art/hd2d/recolor.gd")
const Tex := preload("res://art/hd2d/tex.gd")
const SPRITE_SHADER := preload("res://art/hd2d/shaders/sprite.gdshader")
const AURA_SHADER := preload("res://art/hd2d/shaders/fx_world.gdshader")
const ART_UNIT := 56.0   # art-space units per world unit (U)
const LEAN := 12.0       # degrees the sprite leans back toward the camera

var key := ""
var el := ""
## Lunge/knockback offset in world units (U), screen-aligned like TS. Tweenable.
var off := Vector2.ZERO
## Squash & stretch (TS sq.scale). Tweenable.
var squash := Vector2.ONE
## Roll in radians (TS flip.rotation, clockwise on screen). Tweenable.
var rot := 0.0
## Extra scale (alphas, title screen).
var extra := 1.0
var face := 1
## Hit-flash amount 0..1 (tweened by hit_flash()).
var flash := 0.0:
	set(v):
		flash = v
		if _mat: _mat.set_shader_parameter("flash", v)
## TS `k`: screen px per art unit.
var k := 1.0

var _A := 0.01   # world units per art unit
var _t := randf_range(0.0, 10.0)
var _entry: Dictionary
var _flip: Node3D
var _rig: Node3D
var _sq: Node3D
var _mesh: MeshInstance3D
var _mat: ShaderMaterial
var _shadow: MeshInstance3D
var _aura: MeshInstance3D
var _aura_mat: ShaderMaterial
var _head_art := Vector2.ZERO
var _art_rect := Rect2()   # the sprite quad in art space (x toward the facing, y down, origin at the feet)
var _emitters: Array[Vector2] = []
var _shiny := false
var _silhouette := false
var _tweens: Array[Tween] = []
var _base := Vector3.ZERO

static var _src: Dictionary = {}     # image name -> Image
static var _baked: Dictionary = {}   # "name|el|opts" -> ImageTexture


## Create an actor for species `key` (element defaults to the species') and add it to the stage.
static func create(species: String, element := "") -> Actor:
	var a := Actor.new()
	a._setup(species, element)
	Stage.world.add_child(a)
	return a


func _setup(species: String, element: String) -> void:
	key = species
	el = element if element != "" else _species_el(species)
	name = "Actor_" + species
	rotation.x = -deg_to_rad(LEAN)
	_entry = Manifest.entry(species)
	if species == "noctyrm":
		prebake(species)   # it shifts element mid-fight: bake all four now so a shift never hitches
	_flip = Node3D.new(); add_child(_flip)
	_rig = Node3D.new(); _flip.add_child(_rig)
	_sq = Node3D.new(); _rig.add_child(_sq)
	_mesh = MeshInstance3D.new(); _sq.add_child(_mesh)
	_mat = ShaderMaterial.new(); _mat.shader = SPRITE_SHADER
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_shadow = MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(1, 1); q.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = Tex.soft(64)
	sm.albedo_color = Color(0, 0, 0, 0.45)
	sm.render_priority = 1
	_shadow.material_override = sm
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)
	# wind-up aura (TS Actor.aura): soft additive glow behind the creature, driven by Battle via set_aura
	_aura = MeshInstance3D.new()
	var aq := QuadMesh.new(); aq.size = Vector2(160, 160); aq.center_offset = Vector3(0, 48, -6)
	_aura.mesh = aq
	_aura_mat = ShaderMaterial.new(); _aura_mat.shader = AURA_SHADER
	_aura_mat.set_shader_parameter("tex", Tex.soft(64))
	_aura_mat.set_shader_parameter("billboard", false)
	_aura_mat.set_shader_parameter("alpha", 0.0)
	_aura_mat.render_priority = 1
	_aura.material_override = _aura_mat
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.visible = false
	_flip.add_child(_aura)
	set_element(el)


static func _species_el(species: String) -> String:
	var ml := Engine.get_main_loop() as SceneTree
	var data: Node = ml.root.get_node_or_null("/root/Data") if ml else null
	var sp = data.get("SPECIES") if data else null
	if sp is Dictionary and sp.has(species):
		return String(sp[species].el)
	return {"emberwick": "ember", "cinderpip": "ember", "kilnback": "ember", "bellspring": "tide", "puddlet": "tide",
		"brinecrab": "tide", "truffmole": "thorn", "brambat": "thorn", "mossling": "thorn", "skiray": "volt",
		"sparkit": "volt", "coilsnail": "volt", "warden": "thorn", "noctyrm": "ember"}.get(species, "ember")


func _species_size() -> float:
	return Stage._species_size(key)


# ------------------------------------------------------------------ look

static func _image(file: String) -> Image:
	if not _src.has(file):
		var t: Texture2D = load("res://art/hd2d/%s.png" % file)
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		_src[file] = img
	return _src[file]


## Texture for a manifest entry in an element (recoloured copies are baked once and cached).
static func texture_for(entry: Dictionary, element: String) -> Texture2D:
	var file: String = entry.image
	var rc = entry.get("recolor")
	var k := "%s|%s|%s" % [file, element, str(rc)]
	if not _baked.has(k):
		var img := _image(file)
		if rc is Dictionary and not Recolor.is_identity(element, rc):
			img = Recolor.recolor_image(img, element, rc)
		_baked[k] = ImageTexture.create_from_image(img)
	return _baked[k]


## Bake every element of a species now (the element-shifting boss), so a shift never hitches.
static func prebake(species: String) -> void:
	var e := Manifest.entry(species)
	for element in ["ember", "tide", "thorn", "volt"]:
		texture_for(e, element)


func set_element(element: String) -> void:
	el = element
	var t := texture_for(_entry, el)
	_mat.set_shader_parameter("tex", t)
	var tw := float(t.get_width()); var th := float(t.get_height())
	var hgt := float(_entry.get("height", 125.0))
	var s := hgt / th
	var w := tw * s
	var anc: Vector2 = _entry.get("anchor", Vector2(0.5, 1.0))
	var q := QuadMesh.new()
	q.size = Vector2(w, hgt)
	q.center_offset = Vector3((0.5 - anc.x) * w, (anc.y - 0.5) * hgt, 0.0)
	_mesh.mesh = q
	var to_art := func(f: Vector2) -> Vector2: return Vector2((f.x - anc.x) * w, (f.y - anc.y) * hgt)
	_head_art = to_art.call(_entry.get("head", Vector2(0.55, 0.45)))
	_art_rect = Rect2(to_art.call(Vector2.ZERO), Vector2(w, hgt))
	_emitters.clear()
	for e in _entry.get("emitters", []):
		_emitters.append(to_art.call(e))


## Shiny: a hue shift.
func set_shiny(v: bool) -> void:
	_shiny = v
	_mat.set_shader_parameter("shiny", 1.0 if v else 0.0)


## Wind-up glow behind the creature (TS `aura.tint` / `aura.alpha`). alpha 0 hides it.
func set_aura(color: Color, alpha: float) -> void:
	_aura.visible = alpha > 0.005
	_aura_mat.set_shader_parameter("color", color)
	_aura_mat.set_shader_parameter("alpha", alpha)


## Unowned creatures in the collection: solid dark shape.
func set_silhouette(v: bool) -> void:
	_silhouette = v
	_mat.set_shader_parameter("silhouette", 1.0 if v else 0.0)


# ------------------------------------------------------------------ placement

## Put the feet at screen (x, y) px. face 1 = right, -1 = left.
func place(x: float, y: float, f: int) -> void:
	var u: float = Layout.U
	var s := _species_size() * extra
	k = u / ART_UNIT * s
	face = f
	_base = Stage.to_height(Vector2(x, y), Stage.STAND_Y)
	var wp: float = Stage.wpp(_base)
	_A = k * wp
	var ow: Vector3 = (Stage.cam_right() * off.x - Stage.cam_up() * off.y) * u * wp
	position = _base + ow
	_flip.scale = Vector3(face * _A, _A, _A)
	_flip.rotation.z = -rot
	_sq.scale = Vector3(squash.x, squash.y, 1.0)
	# contact shadow stays on the ground (follows off.x only), shrinks as the creature rises
	var sk := clampf(1.0 + off.y * 0.2, 0.3, 1.2)
	_shadow.global_position = _base + Stage.cam_right() * off.x * u * wp + Vector3(0, 0.015, 0)
	_shadow.scale = Vector3(92.0 * _A * sk, 1.0, 60.0 * _A * sk)
	_shadow.visible = visible and not _silhouette


## World units per art unit (for the shield and other attachments).
func art_scale() -> float:
	return _A


## World point of an art-space point (x toward the facing, y down, origin at the feet), without the idle bob.
func root_point(art: Vector2) -> Vector3:
	return global_transform * Vector3(art.x * face * _A, -art.y * _A, 0.0)


## Head position in screen px (projectile target, damage numbers).
func head() -> Vector2:
	return Stage.to_screen(root_point(_head_art))


## The sprite's bounding box in screen px (UI check: art must not sit under panels).
func screen_rect() -> Rect2:
	var r := Rect2(Stage.to_screen(root_point(_art_rect.position)), Vector2.ZERO)
	for c in [Vector2(_art_rect.end.x, _art_rect.position.y), _art_rect.end, Vector2(_art_rect.position.x, _art_rect.end.y)]:
		r = r.expand(Stage.to_screen(root_point(c)))
	return r


## Feet position in screen px (including off).
func feet() -> Vector2:
	return Stage.to_screen(global_position)


# ------------------------------------------------------------------ animation

func hit_flash() -> void:
	_kill_tweens()
	flash = 1.0
	var t1 := create_tween()
	t1.tween_property(self, "flash", 0.0, 0.22)
	squash = Vector2(1.25, 0.75)
	var t2 := create_tween()
	t2.tween_property(self, "squash", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_tweens = [t1, t2]


func _kill_tweens() -> void:
	for t in _tweens:
		if t and t.is_valid():
			t.kill()
	_tweens.clear()


func update(dt: float) -> void:
	_t += dt
	var t := _t
	_rig.position.y = absf(sin(t * 3.2)) * 5.0
	_rig.rotation.z = -sin(t * 1.6) * 0.03
	_rig.scale = Vector3(1.0 + sin(t * 6.4) * 0.015, 1.0 - sin(t * 6.4) * 0.015, 1.0)
	if visible and not _emitters.is_empty() and randf() < dt * 10.0:
		var p: Vector2 = _emitters[randi() % _emitters.size()]
		var w := global_transform * Vector3(p.x * face * _A, (-p.y + _rig.position.y) * _A, 0.0)
		var sp: Vector2 = Stage.to_screen(w)
		Particles.emit(sp.x, sp.y, {"n": 1, "color": Stage._elem(el).glow, "spd": 0.4, "up": 1.0, "life": 0.8,
			"size": 0.14, "grav": -1.2, "drag": 1.0})


func destroy() -> void:
	_kill_tweens()
	flash = 0.0
	if is_inside_tree():
		get_parent().remove_child(self)
	queue_free()
