# Platform layer: the only place the game talks to its host. Port of game/src/core/platform.ts.
#
# Saves go to a ConfigFile (user://save.cfg, section "save"), one key per persisted value
# (CLAUDE.md §11 plus `lineup`, `loot`, `upgrades`). Haptics use Input.vibrate_handheld on iOS.
extends Node

const SECTION := "save"
var save_path := "user://save.cfg"
var _cfg: ConfigFile = null

var is_native: bool = OS.get_name() == "iOS" or OS.get_name() == "Android"

## UI check mode (`-- --ui-check`, used by scripts/ui-check.sh): a blank scratch save, a seeded RNG
## and a clock that advances exactly 1/60 s per frame, so a screen renders the same pixels every run.
var ui_check := false
## Simulated safe-area insets in px (`-- --safe=<top>,<bottom>`), so desktop shots show the notch.
var safe_insets := Vector2(-1, -1)

func _init() -> void:
	if "--ui-check" in OS.get_cmdline_user_args():
		ui_check = true
		seed(1)
		save_path = "user://ui-check.cfg"
		_wipe(save_path)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--safe="):
			var p := a.substr(7).split(",")
			safe_insets = Vector2(float(p[0]), float(p[1]))

func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Monotonic clock for everything in the game (real time, or frame-locked in UI check mode).
func ticks_usec() -> int:
	if ui_check:
		return Engine.get_process_frames() * 1000000 / 60
	return Time.get_ticks_usec()

func ticks_msec() -> int:
	return ticks_usec() / 1000

func _ensure() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	if FileAccess.file_exists(save_path):
		_cfg.load(save_path)

## Point the store at another file and reload (tests use a scratch path).
func use_save_path(path: String) -> void:
	if ui_check:
		_wipe(path)
	save_path = path
	_cfg = null
	_ensure()

## Persisted value for `key`, or `fallback` if unset. Arrays and dictionaries come back as copies.
func store_get(key: String, fallback = null):
	_ensure()
	if not _cfg.has_section_key(SECTION, key):
		return fallback
	var v = _cfg.get_value(SECTION, key)
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	return v

func store_set(key: String, value) -> void:
	_ensure()
	if value is Array or value is Dictionary:
		value = value.duplicate(true)
	_cfg.set_value(SECTION, key, value)   # null erases the key
	var err := _cfg.save(save_path)
	if err != OK:
		push_warning("Platform: could not save %s (%s)" % [save_path, error_string(err)])

# ---------- haptics ----------
const HAPTIC_MS := {"select": 8, "light": 10, "medium": 20, "heavy": 35, "success": 25, "warning": 15, "error": 30}
var _last_haptic := -1000
var _last_warn := -1000

## kind: "select" "light" "medium" "heavy" "success" "warning" "error".
func haptic(kind: String) -> void:
	if OS.get_name() != "iOS" and OS.get_name() != "Android":
		return
	var now := ticks_msec()
	if now - _last_haptic < 45 and (kind == "light" or kind == "select"):
		return   # don't spam the Taptic Engine
	if kind == "warning":
		if now - _last_warn < 300:
			return
		_last_warn = now
	_last_haptic = now
	Input.vibrate_handheld(HAPTIC_MS.get(kind, 15))

## The TS host handshake. Nothing to do in Godot.
func notify_ready() -> void:
	pass
