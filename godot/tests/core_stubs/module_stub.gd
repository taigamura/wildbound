# Test double for the visual modules (Layout, Feel, Particles, Stage, Fx, Ui, Run).
# tests/test_core.gd swaps this script onto those autoloads so core logic runs headless,
# independent of the other modules' implementations. Every call is counted in `calls`.
extends Node

class Pulse extends RefCounted:
	var s := 1.0

var U := 40.0
var reduced := false
var trauma := 0.0
var slots: Array = []
var shield_pulse := Pulse.new()
var calls := {}
var log: Array = []

func _hit(n: String, args := []) -> void:
	calls[n] = calls.get(n, 0) + 1
	log.append([n, args])

# Layout
func epos() -> Vector2: return Vector2(270, 300)
func ppos() -> Vector2: return Vector2(120, 520)
func tpos() -> Vector2: return Vector2(195, 450)
func horizon() -> float: return 250.0
func measure_band(_a = 0, _b = 0, _c = false) -> void: _hit("measure_band")
func ease_layout(_dt = 0) -> void: pass
# Feel
func shake(v = 0) -> void: _hit("shake", [v])
func hit_stop(t = 0) -> void: _hit("hit_stop", [t])
func slow_mo(t = 0, s = 1) -> void: _hit("slow_mo", [t, s])
# Particles
func emit(_x = 0, _y = 0, _o = {}) -> void: _hit("emit")
func ring(_x = 0, _y = 0, _c = null, _s = 2.0, _d = 0.5, _f = true) -> void: _hit("ring")
func light_flash(_c = null, _p = null, _v = 4.0) -> void: _hit("light_flash")
func burst(_p = null, _el = null, _pw = 1.0) -> void: _hit("burst")
func ambient(_dt = 0, _f = 0, _l = 0) -> void: pass
# Stage
func set_biome(b = 0) -> void: _hit("set_biome", [b])
func build_stage() -> void: _hit("build_stage")
func tint_arena(c = null) -> void: _hit("tint_arena", [c])
func arena_tint() -> Color: return Color.WHITE
func update_scene(_t = 0, _dt = 0) -> void: pass
func update_shield(_a = null, _s = 0, _ac = false, _t = 0) -> void: pass
## Projectiles land instantly in tests (after resolving the target, like the real one does each frame).
func projectile(_from = null, to: Callable = Callable(), el = null, o = {}, on_hit: Callable = Callable()) -> void:
	_hit("projectile", [el, o])
	if to.is_valid():
		to.call()
	on_hit.call()
func lightning(_a = null, _b = null, el = null) -> void: _hit("lightning", [el])
# Fx
func pop_num(_pos = null, text = "", cls = "", label = "", _color = null) -> void: _hit("pop_num", [str(text), cls, label])
func banner(text = "", sub = "", _c = null) -> void: _hit("banner", [text, sub])
func flash(_op = 0.5, _c = null) -> void: _hit("flash")
func vignette() -> void: _hit("vignette")
func toast(t = "") -> void: _hit("toast", [t])
func callout(text = "", _c = null) -> void: _hit("callout", [text])
# Ui
func show(id = null) -> void: _hit("show", [id])
func paint_card(i = 0) -> void: _hit("paint_card", [i])
func refresh_hand() -> void: _hit("refresh_hand")
func render_player_plate() -> void: _hit("render_player_plate")
func render_enemy_plate() -> void: _hit("render_enemy_plate")
func render_bench() -> void: _hit("render_bench")
func sync_hud() -> void: pass
# Run
func place_player(_snap = false, _old = null) -> void: _hit("place_player")
func after_fight() -> void: _hit("after_fight")
func end_run(won = false) -> void: _hit("end_run", [won])
