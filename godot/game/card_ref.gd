## A card in the deck: its owner creature's uid and the slot (TS `CardRef`). The card's element is the
## owner's element. The owner plays it in full while it leads; another lead of that element plays it as a
## basic hit (S.card_basic); a lead of another element can't play it (S.card_block).
class_name CardRef
extends RefCounted

var uid: int = 0
var slot: String = "strike"

func _init(u := 0, s := "strike") -> void:
	uid = u
	slot = s
