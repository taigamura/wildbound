# Small helpers shared everywhere. Port of game/src/core/util.ts.
extends Node

## Respect "reduce motion". iOS exposes no setting to Godot, so this stays false (other modules may override it).
var REDUCED := false

func rand(a: float, b: float) -> float:
	return a + randf() * (b - a)

func pick(a: Array):
	return a[randi() % a.size()]

func clamp(v: float, a: float, b: float) -> float:
	return maxf(a, minf(b, v))

## Fisher-Yates in place; returns the same array.
func shuffle(a: Array) -> Array:
	for i in range(a.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
	return a
