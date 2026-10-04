## A card in the deck: the owner's uid and the slot (TS `CardRef`).
class_name CardRef
extends RefCounted

var uid: int = 0
var slot: String = "strike"

func _init(u := 0, s := "strike") -> void:
	uid = u
	slot = s
