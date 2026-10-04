## A party member (TS `Mon` in game/state.ts).
class_name Mon
extends RefCounted

var uid: int = 0
var key: String = ""            ## species (cards, stats, art)
var name: String = ""
var el: String = ""
var max_hp: int = 1
var hp: float = 1.0
var alive: bool = true
var shield: float = 0.0
var shield_t: float = 0.0       ## seconds since the shield was last added to
var status = null               ## null or {k: status key, t: seconds left, acc: burn tick accumulator}
var ups: Dictionary = {}        ## slot → "power" | "cost" (in-run card upgrades, §7)
var shiny: bool = false
var power: float = 1.0          ## permanent upgrades (§5.2): damage ×power
var spirit: float = 1.0         ## shield/heal amounts ×spirit (max HP is baked into max_hp)
var reflect: float = 0.0        ## Thornveil: next hit taken reflects this fraction
var next_strike: float = 1.0    ## Capacitor: next Strike multiplier
var moves: Dictionary = {"strike": 0, "skill": 0, "sig": 0}   ## equipped card per slot (index into SPECIES[key].cards[slot])
## Socketed Trait key or null, fixed when it joins. (TS `trait`; renamed because `trait` is a GDScript keyword.)
var trait_key = null
var played: int = 0             ## cards this creature has played this fight (Quickfuse)
