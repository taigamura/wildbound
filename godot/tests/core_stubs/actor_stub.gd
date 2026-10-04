# Test double for Actor (render/actor.gd): the fields and methods Battle and S touch.
extends Node

var key := ""
var el := ""
var off := Vector2.ZERO
var squash := Vector2.ONE
var rot := 0.0
var extra := 1.0
var face := 1
var visible := true
var shiny := false
var flashes := 0
var aura := 0.0
var pos := Vector2(120, 520)

static func make(k: String, e := "") -> Node:
	var a = load("res://tests/core_stubs/actor_stub.gd").new()
	a.key = k
	a.el = e
	return a

func head() -> Vector2: return pos + Vector2(0, -60)
func place(x, y, f = 1) -> void:
	pos = Vector2(x, y)
	face = f
func set_element(e) -> void: el = e
func set_shiny(v) -> void: shiny = v
func set_silhouette(_v) -> void: pass
func hit_flash() -> void: flashes += 1
func set_aura(_c, a) -> void: aura = a
func update(_dt) -> void: pass
func destroy() -> void: queue_free()
