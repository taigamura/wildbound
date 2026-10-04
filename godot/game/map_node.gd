## A node on the run map (TS `MapNode`).
class_name MapNode
extends RefCounted

var type: String = "wild"       ## "wild" | "alpha" | "spring" | "warden" | "boss"
var sp = null                   ## species key (String) or null
var lvl = null                  ## floor level used for scaling (int) or null = current floor

func _init(t := "wild", s = null, l = null) -> void:
	type = t
	sp = s
	lvl = l
