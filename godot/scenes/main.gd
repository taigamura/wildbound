extends Node
## Entry point and frame loop (TS main.ts). Autoloads build themselves; this wires the HUD and the run
## UI, opens the title screen and drives the per-frame update in TS order.
##
## Debug screenshots: `godot --path godot --resolution 390x844 -- --shot=<screen>` shows a screen
## (title team team-swap map reward upgrade party end pack coll shop battle battle-shared), waits a few frames, saves
## /tmp/claude-1000/wb-<screen>.png and quits. Add `--shot-dir=<dir>` to save elsewhere.
## With `--ui-check` (scripts/ui-check.sh) the shot is deterministic and goes through tests/ui_check.gd:
## `--golden=<dir>` compares against <dir>/wb-<screen>.png, `--update` rewrites it, and the exit code
## is 1 if any check failed.

var T := 0.0
var _last_us := 0
var _shot := ""
var _shot_dir := "/tmp/claude-1000"
var _shot_frames := 0
var _shot_scroll := -1
var _golden := ""
var _update := false
var _no_golden := false

func _ready() -> void:
	process_priority = -10   # before the autoloads' own _process (TS order: layout, battle, scene, HUD)
	Layout.measure_band(0, -1, true)
	if Stage.has_method("build_stage"):
		Stage.build_stage()
	Ui.init_hud({"play": Battle.play_card, "swap": Battle.swap_tap})
	Run.init_run_ui()
	Run.to_title()
	if Platform.has_method("notify_ready"):
		Platform.notify_ready()
	_last_us = Platform.ticks_usec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--shot-scroll="):
			_shot_scroll = int(a.substr(14))
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.substr(11)
		elif a.begins_with("--golden="):
			_golden = a.substr(9)
		elif a == "--update":
			_update = true
		elif a == "--no-golden":
			_no_golden = true
	if _shot != "":
		_start_shot.call_deferred()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		Sfx.audio()

func _process(_delta: float) -> void:
	var now := Platform.ticks_usec()
	var real := minf((now - _last_us) / 1e6, 0.05)
	_last_us = now
	# hit-stop and slow-mo live in Feel (Engine.time_scale); the world runs at that scale
	var dt := real * Engine.time_scale
	T += dt
	Layout.ease_layout(real)

	Battle.tick_battle(dt, T)
	var amb: Dictionary = Stage.ambience
	Particles.ambient(dt, amb.fireflies, amb.leaves)
	Particles.update_particles(dt)
	Stage.update_scene(T, dt)

	var E: Vector2 = Layout.epos()
	var P: Vector2 = Layout.ppos()
	if S.em != null and is_instance_valid(S.em):
		S.em.place(E.x, E.y, -1)
		S.em.update(dt)
	for a in S.actors.values():
		if a == null or not is_instance_valid(a) or not a.visible:
			continue
		a.place(P.x, P.y, 1)
		a.update(dt)
	if S.title_actor != null and is_instance_valid(S.title_actor):
		var t: Vector2 = Layout.tpos()
		S.title_actor.visible = Layout.room
		S.title_actor.place(t.x, t.y, 1 if sin(T * 0.6) > 0 else -1)
		S.title_actor.update(dt)
	var me = S.act()
	Stage.update_shield(S.active_actor(), me.shield if me else 0.0, S.mode != "title" and S.mode != "meta", T)

	if S.mode in ["battle", "anim", "intro", "end"]:
		Ui.sync_hud()
	_shot_tick()

# ------------------------------------------------------------------ debug screenshots

func _start_shot() -> void:
	if Platform.ui_check:   # a lived-in save: full team and some loot, so long names and numbers show
		Platform.store_set("lineup", ["emberwick", "bellspring", "truffmole"])
		Platform.store_set("loot", {"gold": 240, "sword": 2, "orb": 1, "jewel": 3})
		S.picks = Meta.last_lineup()
	match _shot:
		"title":
			Run.to_title()
		"battle", "flick", "inspect", "battle-shared":
			if _shot == "battle":
				S.picks = ["emberwick", "bellspring", "truffmole"]
			if _shot == "battle-shared":   # two Ember creatures share their cards (scratch save, not user://save.cfg)
				Platform.use_save_path("user://shot-battle-shared.cfg")
				Platform.store_set("owned", Array(Data.ROSTER))
				S.picks = ["emberwick", "cinderpip", "bellspring"]
			Run.start_run()
			Battle.start_battle(S.nodes[0])
		_:
			Run.debug_show(_shot)
	_shot_frames = 150 if _shot in ["battle", "flick", "inspect", "battle-shared"] else 70

func _shot_tick() -> void:
	if _shot == "" or _shot_frames <= 0:
		return
	_shot_frames -= 1
	if _shot == "battle" and _shot_frames == 40 and S.hand.size() > 1:
		S.energy = 7.0
	if _shot == "battle-shared" and _shot_frames == 40:
		_shared_hand()
	if _shot in ["flick", "inspect"]:
		_drive_input()
	if _shot_frames == 10 and _shot_scroll >= 0 and Ui.current != null:
		for sc in Ui.screens[Ui.current].find_children("*", "CapScroll", true, false):
			sc.scroll_vertical = _shot_scroll
	if _shot_frames == 0:
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		var path := "%s/wb-%s.png" % [_shot_dir, _shot]
		img.save_png(path)
		print("shot saved: ", path)
		if Platform.ui_check:
			var chk: GDScript = load("res://tests/ui_check.gd")
			if chk == null or not chk.can_instantiate():   # a broken check must fail fast, not hang
				print("UICHECK EXIT the check script failed to load")
				get_tree().quit(2)
				return
			get_tree().quit(chk.new().check(_shot, img, _shot_dir, "" if _no_golden else _golden, _update))
			return
		get_tree().quit()

## battle-shared: every card state at once. Ember cards show both Ember faces; Bellspring is down, so
## its Splash is dead; Peck has its -1 cost upgrade; 2 energy leaves Wickflare unaffordable.
func _shared_hand() -> void:
	var t := S.team()
	t[0].ups["strike"] = "cost"
	t[2].alive = false
	t[2].hp = 0
	S.hand = [CardRef.new(t[0].uid, "sig"), CardRef.new(t[1].uid, "strike"), CardRef.new(t[2].uid, "strike"), CardRef.new(t[0].uid, "strike")]
	S.energy = 2.0
	Ui.render_bench()
	Ui.refresh_hand()

## Synthetic pointer input: press card 1, scrub right onto card 2, then (flick) swipe it up to play,
## or (inspect) keep holding so the shot shows the magnified card.
var _c1 := Vector2.ZERO
var _c2 := Vector2.ZERO
func _drive_input() -> void:
	var f := _shot_frames
	if f == 62:
		_c1 = Ui.slots[1].get_global_transform() * (Ui.slots[1].size / 2.0)
		_c2 = Ui.slots[2].get_global_transform() * (Ui.slots[2].size / 2.0)
		print("before: energy=", S.energy, " mode=", S.mode, " hand2=", S.hand[2])
		_mouse(_c1, true)
	elif f > 52 and f < 62:   # scrub sideways along the fan
		_move(_c1.lerp(_c2, (62 - f) / 9.0))
	elif f == 52:
		print("scrubbed: sel=", Ui._sel)
	elif _shot == "inspect":
		return
	elif f < 52 and f > 44:
		_move(Vector2(_c2.x + 4, _c2.y - (52 - f) * 18))
	elif f == 44:
		_mouse(Vector2(_c2.x + 4, _c2.y - 140), false)
		print("after: energy=", S.energy, " playing=", Ui.slots[2].playing, " chain=", S.chain)
	elif f == 30:
		_shot_frames = 8

func _mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	get_viewport().push_input(e)

func _move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e)
