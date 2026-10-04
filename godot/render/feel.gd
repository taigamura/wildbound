# Screen-level feel (port of the feel/shake/hitStop/slowMo/applyShake part of render/fx.ts).
# Hit-stop and slow-mo run the whole world (sim, particles, tweens, timers) slower through
# Engine.time_scale, counted down in REAL time. Shake is camera trauma, applied by Stage.
# Runs by itself every frame (process_mode ALWAYS); callers only call shake/hit_stop/slow_mo.
extends Node

## Shake amount 0..1 (decays 1.6/s). Visible shake = trauma^2.
var trauma := 0.0
## Real seconds of hit-stop left (world at 0.06x).
var hit_stop_left := 0.0
## Real seconds of slow-mo left, at slow_scale.
var slow := 0.0
var slow_scale := 1.0
## Reduced motion: no shake, no hit-stop (slow-mo still plays, as in TS).
var reduced := false

## Current shake, read by Stage: screen offset in px and roll in radians.
var shake_px := Vector2.ZERO
var shake_rot := 0.0
## Real seconds since the last frame (clamped to 0.05), for anyone who needs unscaled time.
var real_dt := 0.0

var _last_us := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100   # before everything else, so this frame's time_scale is set first
	_last_us = Time.get_ticks_usec()


func shake(v: float) -> void:
	if not reduced:
		trauma = minf(1.0, trauma + v)


func hit_stop(t: float) -> void:
	if not reduced:
		hit_stop_left = maxf(hit_stop_left, t)


## Run the whole world at `scale` speed for `t` real seconds.
func slow_mo(t: float, scale: float) -> void:
	slow = maxf(slow, t)
	slow_scale = scale


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real := minf((now - _last_us) / 1000000.0, 0.05)
	_last_us = now
	real_dt = real
	var ts := 1.0
	if hit_stop_left > 0.0:
		hit_stop_left -= real
		ts = 0.06
	elif slow > 0.0:
		slow -= real
		ts = slow_scale
	Engine.time_scale = ts
	_apply_shake(real)


## TS applyShake: Feel does this itself every frame, so calling it is a harmless no-op.
func apply_shake(_real := 0.0, _u := 0.0) -> void:
	pass


func _apply_shake(real: float) -> void:
	trauma = maxf(0.0, trauma - real * 1.6)
	var sh := trauma * trauma
	var u: float = Layout.U
	shake_px = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * sh * u * 0.35
	shake_rot = randf_range(-1, 1) * sh * 0.02
