## The current foe (TS `Enemy` in game/state.ts).
class_name Enemy
extends RefCounted

var key: String = ""
var name: String = ""
var el: String = ""
var kind: String = "wild"       ## "wild" | "alpha" | "warden" | "boss"
var alive: bool = true
var hp: float = 1.0
var max: float = 1.0
var dmg: float = 0.0
var iv: float = 3.0             ## normal wind-up length
var t: float = 0.0              ## progress through the current wind-up (s)
var windup: float = 3.0         ## length of the current wind-up (s)
var count: int = 0              ## attacks made so far
var status = null               ## null or {k, t, acc}
var status_src: int = 0
var shock_cd: float = 0.0
var shift_t: float = 0.0        ## boss: seconds to next element shift
var perfect: bool = false       ## a Perfect Swap was made during this heavy's window
var heavy_idx: int = 0          ## warden: which heavy comes next
