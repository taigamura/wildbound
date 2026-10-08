# Stage preview (the stage's visual test). Builds both biomes, puts an enemy and a partner of
# different elements on the pedestals, fires a projectile, a burst and a lightning bolt, and saves
# screenshots. Run:  godot --path godot --resolution 390x844 --audio-driver Dummy res://tests/stage_preview.tscn
# Output: /tmp/claude-1000/stage_*.png (-- --out=<dir> to change, -- --nohud to drop the HUD bands,
# -- --pair=<enemy>,<partner> to put two species keys on the biome 0 pedestals, e.g. a new sprite)
extends Node

var out := "/tmp/claude-1000"
var em: Actor
var pa: Actor
var t := 0.0
var shield := 0.0
var hud := true
var pair: PackedStringArray = []
var band := Vector2(110, 560)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a == "--nohud": hud = false
		if a.begins_with("--pair="): pair = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out)
	if pair.size() == 2:
		await _scene(0, pair[0], Data.SPECIES[pair[0]].el, pair[1], Data.SPECIES[pair[1]].el)
		get_tree().quit()
		return
	await _scene(0, "brinecrab", "tide", "emberwick", "ember")
	await _scene(1, "noctyrm", "volt", "sparkit", "volt", true)
	await _title()
	get_tree().quit()


func _scene(biome: int, ek: String, eel: String, pk: String, pel: String, bolt := false) -> void:
	_clear()
	Stage.set_biome(biome)
	em = Actor.create(ek, eel)
	pa = Actor.create(pk, pel)
	Stage.debug_peds = {"e": em, "p": pa}
	Stage.tint_arena(Stage._elem(eel).hex)
	shield = 14.0
	if biome == 1:
		em.set_aura(Color("#ff6a3d"), 0.5)   # heavy wind-up glow
	await _frames(40)
	await _shot("stage_b%d_idle" % biome)
	print("biome %d: draw calls %d, objects %d, primitives %d" % [biome,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	var st := {"hit": false}
	Stage.projectile(pa.head(), func(): return em.head(), pel, {"size": 0.42, "arc": 1.6, "dur": 0.42}, func():
		st.hit = true
		Particles.burst(em.head(), pel, 1.0)
		Particles.light_flash(Stage._elem(pel).hex, em.head(), 5.0)
		em.hit_flash()
		Feel.shake(0.4))
	await _frames(1)
	await _shot("stage_b%d_projectile" % biome)
	var guard := 0
	while not st.hit and guard < 120:
		guard += 1
		await _frames(1)
	await _frames(4)
	await _shot("stage_b%d_burst" % biome)
	if bolt:
		await _frames(30)
		Stage.lightning(Layout.ppos() + Vector2(0, -60), em.head(), "volt")
		Particles.burst(em.head(), "volt", 0.8)
		Particles.ring(Layout.ppos().x, Layout.ppos().y, Color("#ffcf2e"), 2.6, 0.7)
		await _frames(1)
		await _shot("stage_b%d_lightning" % biome)
	await _frames(20)


func _title() -> void:
	_clear()
	Stage.set_biome(0)
	band = Vector2(80, 520)
	pa = Actor.create("kilnback", "thorn")
	pa.extra = 1.15
	pa.set_shiny(true)
	Stage.debug_peds = {"p": pa, "title": true}
	Stage.tint_arena(Stage._elem("thorn").hex)
	shield = 0.0
	await _frames(30)
	await _shot("stage_title_shiny")
	pa.set_silhouette(true)
	await _frames(4)
	await _shot("stage_title_silhouette")


func _clear() -> void:
	for a in [em, pa]:
		if a and is_instance_valid(a): a.destroy()
	em = null; pa = null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _process(delta: float) -> void:
	t += delta
	# the UI (if loaded) also measures the band; force the test's HUD band every frame
	Layout.measure_band(band.x, band.y, true)
	Layout.ease_layout(delta)
	Particles.ambient(delta, Stage.ambience.fireflies, Stage.ambience.leaves)
	Particles.update_particles(delta)
	Stage.update_scene(t, delta)
	if em and is_instance_valid(em):
		var e := Layout.epos(); em.place(e.x, e.y, -1); em.update(delta)
	if pa and is_instance_valid(pa):
		var title: bool = Stage.debug_peds.get("title", false)
		var p := Layout.tpos() if title else Layout.ppos()
		pa.place(p.x, p.y, 1); pa.update(delta)
	Stage.update_shield(pa, shield, not Stage.debug_peds.get("title", false), t)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if hud:
		# translucent HUD bands so the composition can be judged as in-game
		img.convert(Image.FORMAT_RGBA8)
		var k := img.get_height() / 844.0
		var bi := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		bi.fill(Color(0.06, 0.05, 0.1, 0.55))
		img.blend_rect(bi, Rect2i(0, 0, img.get_width(), int(band.x * k)), Vector2i.ZERO)
		img.blend_rect(bi, Rect2i(0, 0, img.get_width(), img.get_height() - int(band.y * k)), Vector2i(0, int(band.y * k)))
	img.save_png("%s/%s.png" % [out, name])
	print("saved ", name)

