## A card in the deck: its source creature's uid and the slot (TS `CardRef`). The card's element is the
## source's element, and any lead of that element plays it (S.card_block).
class_name CardRef
extends RefCounted

var uid: int = 0
var slot: String = "strike"

func _init(u := 0, s := "strike") -> void:
	uid = u
	slot = s
