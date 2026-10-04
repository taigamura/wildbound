# Real-time combat: lineup deck, lead-only cards, portrait swaps, auto attacks, enemy intents and heavies,
# statuses, Perfect Swap, chain meter. Spec: ../CLAUDE.md §3–§4. Port of game/src/game/battle.ts.
#
# Visuals go to the other modules per CONTRACT.md: Stage.projectile/lightning/tint_arena/set_biome,
# Particles.*, Fx.*, Feel.*, Ui.*, Run.*, and Actor tweens on actor.off/squash/rot.
extends Node

## A card was played from hand slot i (the UI animates it away).
signal card_played(i: int)
## A card in slot i was refused: why = "energy" | "bench" | "busy".
signal card_denied(i: int, why: String)
## A dead card (every creature of its element fainted) in slot i was thrown away for BAL.discard_cost (the UI animates it away).
signal card_discarded(i: int)

var debug := {}
var _pending: Array[bool] = []   # slot i is waiting for its delayed repaint (TS: the slot has the 'play' class)

const C_ENERGY := [Color("#c8b4ff"), Color("#ffffff"), Color("#9b7bff")]
const C_SHIELD := [Color("#8fe3ff"), Color("#ffffff"), Color("#3fb6ff")]
const C_BLOCK := [Color("#8fe3ff"), Color("#ffffff")]
const C_HEAL := [Color("#6ff0a0"), Color("#c8ffd9"), Color("#ffffff")]
const C_STAR := [Color("#ffcf6b"), Color("#fff1b0")]
const C_DUST := [Color("#8a90b8"), Color("#5a6088")]
const C_KO := [Color("#9aa3c7"), Color("#5a6088"), Color("#ffffff")]
const C_GOLD := [Color("#ffcf6b"), Color("#ffffff")]
const HEAL_COLOR := Color("#6ff0a0")
const GOLD := Color("#ffcf6b")
const FAINT := Color("#ff5a6e")

func _ready() -> void:
	debug = {
		"hurt": _dbg_hurt, "energy": _dbg_energy, "add": _dbg_add, "essence": _dbg_essence,
		"loot": _dbg_loot, "trait": _dbg_trait, "heavy": _dbg_heavy,
	}

# ---------- small helpers ----------
## Does this creature have Trait t socketed? (Always the socketed one, not the species' built-in.)
func _has(c: Mon, t: String) -> bool:
	return c != null and c.trait_key == t

func _el_hex(el) -> Color:
	return Data.ELEM[el].hex

func _glow(el) -> Array:
	return Data.ELEM[el].glow

## gsap.delayedCall: scaled game time, so hit-stop and slow-mo apply.
func _later(t: float, f: Callable) -> void:
	get_tree().create_timer(maxf(t, 0.0)).timeout.connect(f)

## A tween bound to `target` (an Actor) when it is a Node, so it dies with it.
func _tween(target) -> Tween:
	if target is Node and target.is_inside_tree():
		return target.create_tween()
	return create_tween()

## gsap power eases: power1 = quad, power2 = cubic, power3 = quart.
const P1 := Tween.TRANS_QUAD
const P2 := Tween.TRANS_CUBIC
const P3 := Tween.TRANS_QUART

func _off_from(a, from: Vector2, dur: float) -> void:
	a.off = from
	_tween(a).tween_property(a, "off", Vector2.ZERO, dur).set_trans(P2).set_ease(Tween.EASE_OUT)

## Trait feedback: a popup over the lead (or `at`) with the Trait's name.
func _trait_pop(t: String, text: String, cls := "shield", at: Mon = null) -> void:
	var a = S.actor_for(at) if at else S.active_actor()
	if a == null:
		return
	var p: Vector2 = a.head()
	Fx.pop_num(Vector2(p.x, p.y - Layout.U * 1.5), text, cls, Data.TRAITS[t].name)

func _trait_energy(t: String) -> void:
	S.energy = minf(Data.BAL.energy_max, S.energy + 1)
	Sfx.energy()
	_trait_pop(t, "+1")

# ================= setup =================
func start_battle(n: MapNode) -> void:
	S.tok += 1
	var tok := S.tok
	var sp: Dictionary = Data.SPECIES[n.sp]
	var lvl: int = n.lvl if n.lvl != null else S.floor
	var kind := "alpha" if n.type == "alpha" else "warden" if n.type == "warden" else "boss" if n.type == "boss" else "wild"
	var alpha := kind == "alpha"
	var hp_f: float = 1 + Data.BAL.hp_per_floor * (lvl - 1)
	var dmg_f: float = 1 + Data.BAL.dmg_per_floor * (lvl - 1)
	var mx: float
	if kind == "boss":
		mx = sp.hp
	elif kind == "warden":
		mx = Data.BAL.warden_hp
	else:
		mx = roundi(Data.BAL.wild_hp * (0.6 + 0.4 * sp.hp / 55.0) * hp_f * (Data.BAL.alpha_hp if alpha else 1.0))
	var dmg: float
	if kind == "boss":
		dmg = Data.BAL.boss_dmg
	elif kind == "warden":
		dmg = Data.BAL.warden_dmg
	else:
		dmg = Data.BAL.enemy_dmg * sp.get("atk", 1.0) * dmg_f * (Data.BAL.alpha_dmg if alpha else 1.0)
	var iv: float = Data.BAL.intent / sp.get("spd", 1.0)
	var e := Enemy.new()
	e.key = n.sp
	e.name = ("Alpha " if alpha else "") + sp.name
	e.el = Util.pick(Data.EL_KEYS) if kind == "boss" else sp.el
	e.kind = kind
	e.alive = true
	e.max = mx
	e.hp = mx
	e.dmg = dmg
	e.iv = iv
	e.t = 0
	e.windup = iv
	e.shift_t = Data.BAL.boss_shift
	S.enemy = e
	S.energy = Data.BAL.energy_start
	S.swap_cd = 0
	S.auto_t = 0
	S.chain = 0
	S.chain_t = 99
	S.discount = 0
	S.wired = false
	for c in S.team():
		c.shield = 0
		c.status = null
		c.reflect = 0
		c.next_strike = 1
		c.played = 0
	if not (S.active in S.lineup):
		S.active = S.lineup[0]
	if S.act() == null or not S.act().alive:
		S.active = _healthiest().uid
	_build_deck()

	Stage.set_biome(Data.biome_of(S.floor))
	if S.em != null and is_instance_valid(S.em):
		S.em.destroy()
	var m = S.make_actor(n.sp, e.el)
	S.em = m
	if alpha:
		m.extra = 1.15
	m.off = Vector2(m.off.x, -6)
	Stage.tint_arena(_el_hex(e.el))
	Run.place_player(true)
	Ui.show(null)
	Ui.render_player_plate()
	Ui.render_enemy_plate()
	Ui.render_bench()
	Ui.refresh_hand()
	S.mode = "intro"
	var sub := "The final guardian" if kind == "boss" else "Warden of the wild" if kind == "warden" else "Alpha · tougher, richer loot" if alpha else "Wild encounter"
	var tw := _tween(m)
	tw.tween_interval(0.25)
	tw.tween_property(m, "off:y", 0.0, 0.55).set_trans(P3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if tok != S.tok:
			return
		var p: Vector2 = Layout.epos()
		Sfx.stomp()
		Platform.haptic("heavy")
		Feel.shake(0.55)
		Particles.ring(p.x, p.y, _el_hex(e.el), 3, 0.7)
		Particles.emit(p.x, p.y, {"n": 70, "color": C_DUST + _glow(e.el), "spd": 4, "flat": true, "life": 0.8, "size": 0.3, "size1": 1.4, "drag": 3, "alpha": 0.6})
		m.squash = Vector2(1.4, 0.55)
		_tween(m).tween_property(m, "squash", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		Fx.banner(e.name, sub, _el_hex(e.el))
		_later(0.45, func():
			if tok == S.tok:
				S.mode = "battle"))

func _healthiest() -> Mon:
	return S.healthiest()

# ================= deck & hand =================
func _build_deck() -> void:
	var refs: Array[CardRef] = []
	for c in S.team():   # fainted creatures' cards stay in: they clog the hand until discarded
		for slot in Data.SLOTS:
			refs.append(CardRef.new(c.uid, slot))
	S.draw = refs
	Util.shuffle(S.draw)
	S.disc = []
	S.hand = []
	_pending = []
	for i in Data.BAL.hand:
		S.hand.append(_next_card())
		_pending.append(false)

func _next_card() -> CardRef:
	if S.draw.is_empty():
		S.draw = S.disc
		Util.shuffle(S.draw)
		S.disc = []
	return S.draw.pop_back() if S.draw.size() else null

## Fill slot i now; repaint after the play animation.
func _draw_into(i: int, delay := 0.3) -> void:
	S.hand[i] = _next_card()
	_pending[i] = true
	var tok := S.tok
	_later(delay, func():
		if tok != S.tok:
			return
		_pending[i] = false
		Ui.paint_card(i))

func play_card(i: int) -> void:
	Sfx.audio()
	if i < 0 or i >= S.hand.size():
		return
	var r = S.hand[i]
	if r == null:
		return
	if S.mode != "battle":
		card_denied.emit(i, "busy")
		return
	var block := S.card_block(r)
	if block != "":
		Sfx.deny()
		Platform.haptic("warning")
		if block == "bench":
			Fx.toast("Swap to a %s creature to play this" % Data.ELEM[S.card_el(r)].name)
		card_denied.emit(i, block)
		return
	if S.card_dead(r):
		_discard(i)
		return
	var co := S.card_of(r)   # fires as the lead: its Power/Spirit and Traits, "self" = the lead
	var def: Dictionary = co.def
	var pow: float = co.pow
	var by: Mon = co.by
	S.energy -= S.card_cost(r)
	S.discount = 0
	by.played += 1
	S.hand[i] = null
	S.disc.append(r)
	Sfx.card()
	Platform.haptic("light")
	card_played.emit(i)
	_draw_into(i)
	# chain: within the window of the last card → +1 step
	S.chain = mini(Data.BAL.chain_max, S.chain + 1) if S.chain_t <= Data.BAL.chain_win else 0
	S.chain_t = 0
	if not S.chain:
		S.wired = false   # a fresh chain re-arms Live Wire
	_resolve_card(def, pow, by, r.slot)
	if def.get("chain"):
		S.chain = mini(Data.BAL.chain_max, S.chain + def.chain)
	if _has(by, "livewire") and not S.wired and S.chain >= Data.BAL.livewire_chain:
		S.wired = true
		_trait_energy("livewire")
	Ui.refresh_hand()

## A dead card (no living creature of its element): pay to throw it away and draw. No chain, no Traits, discount kept.
func _discard(i: int) -> void:
	var r: CardRef = S.hand[i]
	S.energy -= Data.BAL.discard_cost
	S.hand[i] = null
	S.disc.append(r)
	Sfx.card()
	Platform.haptic("light")
	Fx.toast("Discarded a %s card" % Data.ELEM[S.card_el(r)].name)
	card_discarded.emit(i)
	_draw_into(i)
	Ui.refresh_hand()

func _resolve_card(C: Dictionary, pow: float, me: Mon, slot: String) -> void:
	var pm = S.actor_for(me)
	var pp: Vector2 = pm.head()
	var U: float = Layout.U
	if C.get("energy"):
		S.energy = minf(Data.BAL.energy_max, S.energy + C.energy)
		Particles.emit(pp.x, pp.y, {"n": 40, "color": C_ENERGY, "spd": 3, "life": 0.6, "size": 0.2, "drag": 2, "swirl": 8})
		Sfx.energy()
	if C.get("self_dmg"):
		_hurt_mon(me, C.self_dmg, null, false, true)
	if C.get("discount"):
		S.discount = C.discount
		Sfx.focus()
		Fx.pop_num(Vector2(pp.x, pp.y - U * 0.8), "−1", "shield", "Next card")
	if C.get("reflect"):
		me.reflect = C.reflect
		Sfx.shield()
		Fx.pop_num(Vector2(pp.x, pp.y - U * 0.8), str(roundi(C.reflect * 100)) + "%", "shield", "Thornveil")
	if C.get("next_strike"):
		me.next_strike = C.next_strike
		Sfx.focus()
		_stars()
	if C.get("cleanse"):
		for c in S.team():
			c.status = null
	if C.get("shield"):
		_add_shield(me, C.shield)
		if _has(me, "overshade"):
			var t: Mon = null
			for c in S.team():
				if c.alive and c.uid != me.uid and (t == null or c.hp / c.max_hp < t.hp / t.max_hp):
					t = c
			if t:
				var v := roundi(C.shield * Data.BAL.overshade)
				_add_shield(t, v)
				_trait_pop("overshade", "+%d %s" % [v, t.name])
	if C.get("shield_team"):
		for c in S.team():
			if c.alive:
				_add_shield(c, C.shield_team)
	var under := _has(me, "undercurrent")
	var heal := func(c: Mon, v: float) -> void:
		_heal_mon(c, v)
		if under and c.alive and c.status != null:
			c.status = null
			_trait_pop("undercurrent", "Cleansed", "heal", null if c.uid == S.active else c)
	if C.get("heal"):
		heal.call(me, C.heal)
	if C.get("heal_team"):
		for c in S.team():
			if c.alive:
				heal.call(c, C.heal_team)
	var thirst := slot == "strike" and _has(me, "thirst")
	var lifesteal: float = C.get("lifesteal", 0.0)
	var drain := func(d: int) -> void:
		if lifesteal and d:
			_heal_mon(me, roundi(d * lifesteal))
		if thirst and d:
			var v := roundi(d * Data.BAL.thirst)
			if v:
				_heal_mon(me, v, "Thirst")

	var dmg: float = C.get("dmg", 0)
	if C.get("from_shield"):
		dmg = roundi(me.shield * pow * me.power)
		me.shield = 0
	if slot == "strike" and me.next_strike > 1 and dmg:
		dmg *= me.next_strike
		me.next_strike = 1
	var chain_mul: float = 1 + Data.BAL.chain_step * S.chain
	var el := me.el
	var big: bool = C.cost >= 3 or dmg >= 14
	var tok := S.tok
	var uid := me.uid
	var status = C.get("status")
	if not dmg and status == null:
		return
	_lunge(pm, 0.35 if dmg else 0.2)
	var o := ({"size": 0.42 if big else 0.26, "arc": 1.6 if big else 0.7, "dur": 0.42 if big else 0.3} if dmg
		else {"size": 0.18, "arc": 1.0, "dur": 0.32})
	var hits: int = C.get("hits", 1)
	var bonus_if = C.get("bonus_if")
	Stage.projectile(pp, _enemy_head, el, o, func():
		var e := S.enemy
		if tok != S.tok or e == null or not e.alive:
			return
		if dmg:
			var bonus: float = bonus_if.dmg if bonus_if != null and e.status != null and e.status.k == bonus_if.status else 0.0
			drain.call(_hurt_enemy((dmg + bonus) * chain_mul, el, uid, {"big": big, "bonus": (Data.STATUS_PAST[bonus_if.status] + "!") if bonus else ""}))
		if status != null and e.alive:
			_apply_enemy_status(status, pow, uid)
		# extra hits of a multi-hit card follow the first one
		for h in range(1, hits):
			_later(h * 0.14, func():
				if tok != S.tok or S.enemy == null or not S.enemy.alive:
					return
				drain.call(_hurt_enemy(dmg * chain_mul, el, uid, {"small": true}))))

## Where projectiles fly to: the enemy's head (screen px).
func _enemy_head() -> Vector2:
	return S.em.head() if S.em != null and is_instance_valid(S.em) else Layout.epos()

func _lead_head() -> Vector2:
	var a = S.active_actor()
	return a.head() if a != null else Layout.ppos()

func _stars() -> void:
	for k in 3:
		_later(k * 0.08, func():
			var p: Vector2 = Layout.ppos()
			Particles.emit(p.x, p.y, {"n": 22, "color": C_STAR, "spd": 2.4, "dir": [0, -1], "cone": 0.2, "life": 0.8, "size": 0.2, "r": 0.5, "tex": "star", "spin": 5}))

# ================= statuses =================
func _apply_enemy_status(k: String, pow: float, src: int) -> void:
	var e := S.enemy
	var m = S.em
	var hp: Vector2 = m.head()
	var U: float = Layout.U
	if k == "shock":
		if e.shock_cd > 0:
			Fx.pop_num(Vector2(hp.x, hp.y - U * 0.9), "Immune", "weak", "%ds" % ceili(e.shock_cd))
			return
		var heavy := S.is_heavy(e) and e.t > 0.3
		e.t = 0
		e.perfect = false
		e.shock_cd = Data.BAL.shock_immune
		Stage.lightning(Layout.ppos(), hp, "volt")
		Particles.burst(hp, "volt", 0.8)
		m.hit_flash()
		Fx.pop_num(Vector2(hp.x, hp.y - U * 1), "Shock", "", "Wind-up broken" if heavy else "Reset", _el_hex("volt"))
		return
	var deep := k == "root" and _has(S.mon(src), "deeproots")
	e.status = {"k": k, "t": Data.STATUS_DUR[k] * pow + (Data.BAL.deep_roots if deep else 0.0), "acc": 0.0}
	e.status_src = src
	Fx.pop_num(Vector2(hp.x, hp.y - U * 1), Data.STATUS_NAME[k], "", Data.TRAITS.deeproots.name if deep else "", _el_hex(Data.STATUS_EL[k]))
	Particles.burst(hp, Data.STATUS_EL[k], 0.5)

func _apply_mon_status(c: Mon, k: String) -> void:
	var hp: Vector2 = S.actor_for(c).head()
	var U: float = Layout.U
	if k == "shock" and _has(c, "grounded"):
		_trait_energy("grounded")
		return
	if k == "shock":
		S.chain = 0
		S.chain_t = 99
		S.swap_cd = maxf(S.swap_cd, Data.BAL.shock_swap_cd)
		Fx.pop_num(Vector2(hp.x, hp.y - U * 1.1), "Shocked", "", "Chain lost", _el_hex("volt"))
		return
	c.status = {"k": k, "t": Data.STATUS_DUR[k], "acc": 0.0}
	Fx.pop_num(Vector2(hp.x, hp.y - U * 1.1), Data.STATUS_NAME[k], "", "", _el_hex(Data.STATUS_EL[k]))

func _soak_mul(s) -> float:
	return Data.BAL.soak_mult if s != null and s.k == "soak" else 1.0

# ================= visuals =================
func _lunge(a, amt: float) -> void:
	var enemy: bool = a == S.em
	var dx := -1.0 if enemy else 1.0
	var dy := 0.6 if enemy else -0.6
	var tw := _tween(a)
	tw.tween_property(a, "off", Vector2(dx * amt, dy * amt), 0.09).set_trans(P2).set_ease(Tween.EASE_OUT)
	tw.tween_property(a, "off", Vector2.ZERO, 0.22).set_trans(P2).set_ease(Tween.EASE_IN_OUT)

# ================= damage =================
## Damage the enemy. `src` is the uid of the creature that dealt it (0 = none), for Trait effects.
## o: {dot, big, small, bonus}. Returns the damage dealt.
func _hurt_enemy(amount: float, el: String, src: int, o := {}) -> int:
	var e := S.enemy
	var m = S.em
	if e == null or not e.alive or m == null:
		return 0
	var a := Data.adv(el, e.el)
	var dmg := maxi(1, roundi(amount * a * _soak_mul(e.status)))
	e.hp = maxf(0, e.hp - dmg)
	S.stats.dealt += dmg
	var hp: Vector2 = m.head()
	var U: float = Layout.U
	var dot: bool = o.get("dot", false)
	var cls := "crit" if a > 1 else "weak" if a < 1 else "dot" if dot else ""
	var label: String = "Super" if a > 1 and not dot else "RESIST" if a < 1 and not dot else o.get("bonus", "")
	Fx.pop_num(Vector2(hp.x, hp.y - U * 0.7), str(dmg), cls, label, _el_hex(el))
	if dot:
		Particles.emit(hp.x, hp.y, {"n": 10, "color": _glow(el), "spd": 1.5, "up": 1, "life": 0.7, "size": 0.22, "grav": -2})
	else:
		var big: bool = o.get("big", false)
		var small: bool = o.get("small", false)
		Particles.burst(hp, el, 1.6 if big else 0.55 if small else 1.0)
		m.hit_flash()
		Particles.light_flash(_el_hex(el), hp, 7.0 if big else 4.0)
		_off_from(m, Vector2(0.22, -0.12), 0.35)
		if a > 1 or big:
			Feel.hit_stop(0.06)
			Feel.shake(0.6 if big else 0.4)
			Fx.flash(0.3 if big else 0.18)
			Sfx.crit()
		else:
			Feel.shake(0.12 if small else 0.22)
			Sfx.hit(el)
		if not small:
			Platform.haptic("medium")
	if e.hp <= 0:
		_enemy_down()
	return dmg

## Damage one of your creatures. el = null for self-inflicted damage.
func _hurt_mon(c: Mon, amount: float, el, heavy: bool, self_hit := false) -> int:
	if not c.alive:
		return 0
	var pm = S.actor_for(c)
	var a := Data.adv(el, c.el) if el != null else 1.0
	var dmg := maxi(1, roundi(amount * a * _soak_mul(c.status)))
	var hp: Vector2 = pm.head()
	var raw := dmg
	var U: float = Layout.U
	var absorbed := 0
	if c.shield >= 1:
		absorbed = mini(floori(c.shield), dmg)
		c.shield -= absorbed
		dmg -= absorbed
	if absorbed:
		Fx.pop_num(Vector2(hp.x - U * 0.4, hp.y - U * 0.5), str(absorbed), "shield", "Blocked")
		Particles.emit(hp.x, hp.y, {"n": 30, "color": C_BLOCK, "spd": 4, "life": 0.4, "size": 0.16, "drag": 4, "tex": "spark", "streak": true})
		Sfx.shield()
		if c.uid == S.active:
			_pulse_shield(1.25, 0.3, false)
	if dmg > 0:
		c.hp = maxf(0, c.hp - dmg)
		Fx.pop_num(Vector2(hp.x, hp.y - U * 0.7), str(dmg), "player" + (" crit" if a > 1 else ""), "Super" if a > 1 else "RESIST" if a < 1 else "")
		if not self_hit:
			pm.hit_flash()
			Fx.vignette()
			Sfx.ouch()
			Feel.shake(0.6 if heavy else 0.35)
			Platform.haptic("heavy" if heavy else "medium")
			if heavy:
				Feel.hit_stop(0.06)
		_off_from(pm, Vector2(-0.22, 0.1), 0.35)
	if el != null and not self_hit:
		Particles.burst(hp, el, 1.3 if heavy else 0.8)
		Particles.light_flash(_el_hex(el), hp, 4.0)
	if c.reflect > 0 and el != null and not self_hit and S.enemy != null and S.enemy.alive:
		var back := roundi(raw * c.reflect)
		c.reflect = 0
		var tok := S.tok
		var cel := c.el
		var cu := c.uid
		Stage.projectile(hp, _enemy_head, cel, {"size": 0.3, "arc": 0.4, "dur": 0.25}, func():
			if tok == S.tok:
				_hurt_enemy(back, cel, cu, {"small": true}))
	if c.hp <= 0:
		_mon_down(c)
	return dmg

## Tween Stage.shield_pulse.s (the lead's shield bubble) from `from` to 1.
func _pulse_shield(from: float, dur: float, back: bool) -> void:
	var sp = Stage.get("shield_pulse")
	if sp == null:
		return
	var tw := create_tween().tween_property(sp, "s", 1.0, dur).from(from)
	if back:
		tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _add_shield(c: Mon, v: float) -> void:
	c.shield += v
	c.shield_t = 0
	if c.uid != S.active:
		return
	var hp: Vector2 = S.actor_for(c).head()
	Fx.pop_num(Vector2(hp.x, hp.y - Layout.U * 0.8), "+" + Data.num(v), "shield", "Shield")
	Particles.emit(hp.x, hp.y, {"n": 40, "color": C_SHIELD, "spd": 2.2, "life": 0.7, "size": 0.18, "drag": 2.5, "swirl": 9, "r": 0.5})
	_pulse_shield(0.3, 0.4, true)
	Sfx.shield()

func _heal_mon(c: Mon, v: float, label := "") -> void:
	if not c.alive:
		return
	c.hp = minf(c.max_hp, c.hp + v)
	if c.uid != S.active:
		return
	var hp: Vector2 = S.actor_for(c).head()
	var p: Vector2 = Layout.ppos()
	var U: float = Layout.U
	Fx.pop_num(Vector2(hp.x + U * 0.3, hp.y - U * 0.8), "+" + str(roundi(v)), "heal", label)
	Particles.emit(p.x, p.y, {"n": 45, "color": C_HEAL, "spd": 2.2, "dir": [0, -1], "cone": 0.25, "life": 1, "size": 0.22, "drag": 1, "r": 0.5, "swirl": 4})
	Particles.ring(p.x, p.y, HEAL_COLOR, 1.6)
	Sfx.heal()

# ================= enemy =================
func _start_windup(e: Enemy) -> void:
	e.t = 0
	e.perfect = false
	e.windup = e.iv + (Data.BAL.heavy_extra if S.is_heavy(e) else 0.0)

func _auto_attack() -> void:
	var me := S.act()
	var pm = S.active_actor()
	if me == null or not me.alive or pm == null or S.enemy == null or not S.enemy.alive:
		return
	var tok := S.tok
	var uid := me.uid
	_lunge(pm, 0.22)
	Stage.projectile(pm.head(), _enemy_head, me.el, {"size": 0.16, "arc": 0.35, "dur": 0.26}, func():
		if tok == S.tok:
			_hurt_enemy(Data.BAL.auto_dmg * me.power, me.el, uid, {"small": true}))

func _enemy_attack() -> void:
	var e := S.enemy
	var m = S.em
	var heavy := S.is_heavy(e)
	var hv := S.heavy_of(e)
	var el: String = hv.el if heavy else e.el
	var dmg: float = e.dmg * (Data.BAL.heavy_mult if heavy else 1.0)
	var tok := S.tok
	var perfect := e.perfect
	e.count += 1
	if heavy and e.kind == "warden":
		e.heavy_idx += 1
	_start_windup(e)
	var land := func(amount: float, last: bool) -> void:
		if tok != S.tok or not e.alive:
			return
		var me := S.act()
		if me == null or not me.alive:
			return
		if heavy and perfect and Data.resists(me.el, el):
			_reflect(amount, el)
			return
		_hurt_mon(me, amount, el, heavy and last)
		if heavy and last and me.alive:
			_apply_mon_status(me, Data.STATUS_OF[el])
	if e.kind == "boss" and heavy:   # charged volley
		var tw := _tween(m)
		tw.tween_property(m, "squash:y", 1.25, 0.25)
		tw.tween_property(m, "squash:y", 1.0, 0.25)
		for k in 3:
			_later(0.2 + k * 0.12, func():
				if tok != S.tok or not e.alive or S.active_actor() == null:
					return
				Stage.projectile(_enemy_head(), _lead_head, el, {"size": 0.4, "arc": 0.9, "dur": 0.3}, func(): land.call(dmg / 3.0, k == 2)))
		return
	var U: float = Layout.U
	var P: Vector2 = Layout.ppos()
	var E: Vector2 = Layout.epos()
	var tx := (P.x - E.x) / U * 0.62
	var ty := (P.y - E.y) / U * 0.62
	if heavy:
		Particles.emit(E.x, E.y, {"n": 40, "color": _glow(el), "spd": 3, "dir": [0, -1], "cone": 0.5, "life": 0.5, "size": 0.25, "r": 0.5})
	var tw := _tween(m)
	tw.tween_property(m, "off", Vector2(-tx * 0.1, -ty * 0.1 - (0.4 if heavy else 0.15)), 0.22 if heavy else 0.1).set_trans(P1).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "off", Vector2(tx, ty), 0.12).set_trans(P3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): land.call(dmg, true))
	tw.tween_property(m, "off", Vector2.ZERO, 0.32).set_trans(P2).set_ease(Tween.EASE_OUT)

## Perfect Swap payoff when the heavy lands: no damage, part of it bounces back.
func _reflect(amount: float, el: String) -> void:
	var me := S.act()
	var hp: Vector2 = S.actor_for(S.act()).head()
	var tok := S.tok
	Fx.pop_num(Vector2(hp.x, hp.y - Layout.U * 0.9), "0", "shield", "Perfect block")
	Particles.emit(hp.x, hp.y, {"n": 60, "color": [Color.WHITE] + _glow(me.el), "spd": 5, "life": 0.5, "size": 0.2, "drag": 3, "tex": "spark", "streak": true})
	Particles.ring(hp.x, hp.y, _el_hex(me.el), 2.2, 0.4, false)
	Sfx.shield()
	var uid := me.uid
	Stage.projectile(hp, _enemy_head, el, {"size": 0.45, "arc": 0.6, "dur": 0.3}, func():
		if tok == S.tok:
			_hurt_enemy(amount * Data.BAL.perfect_reflect, el, uid, {"big": true}))

func _shift_boss() -> void:
	var e := S.enemy
	var m = S.em
	e.el = Util.pick(Data.EL_KEYS.filter(func(k): return k != e.el))
	m.set_element(e.el)
	Stage.tint_arena(_el_hex(e.el))
	var E: Vector2 = Layout.epos()
	Particles.burst(m.head(), e.el, 1.4)
	Particles.ring(E.x, E.y, _el_hex(e.el), 3.2, 0.7)
	Fx.flash(0.25, _el_hex(e.el))
	Sfx.swap()
	Platform.haptic("medium")
	Ui.render_enemy_plate()
	Ui.refresh_hand()
	Fx.toast("Noctyrm shifts to " + Data.ELEM[e.el].name)

# ================= swapping & fainting =================
## Tap on a bench portrait.
func swap_tap(uid: int) -> void:
	Sfx.audio()
	if S.mode != "battle":
		return
	var c := S.mon(uid)
	if c == null or not c.alive or uid == S.active:
		return
	if S.swap_cd > 0 or S.energy < Data.BAL.swap_cost:
		Sfx.deny()
		Platform.haptic("warning")
		if S.swap_cd > 0:
			Fx.toast("Swap ready in %ds" % ceili(S.swap_cd))
		else:
			Fx.toast("Swapping costs %d energy" % Data.BAL.swap_cost)
		return
	S.energy -= Data.BAL.swap_cost
	_swap_to(uid, "tap")

## Make `uid` the lead. Logic is instant; the visuals catch up. how: "tap" | "forced".
func _swap_to(uid: int, how: String) -> void:
	var old = S.active_actor()
	var prev := S.act()
	var tok := S.tok
	if how != "forced" and prev != null and prev.alive and prev.uid != uid and _has(prev, "ebb") and prev.hp < prev.max_hp:
		prev.hp = minf(prev.max_hp, prev.hp + Data.BAL.ebb_heal)
		_trait_pop("ebb", "+%d" % Data.BAL.ebb_heal, "heal", prev)
	S.active = uid
	S.auto_t = 0
	if how != "forced":
		S.swap_cd = Data.BAL.swap_cd
		if _has(S.act(), "relay"):
			S.discount = maxi(S.discount, 1)
			_trait_pop("relay", "−1")
	Sfx.swap()
	Platform.haptic("light")
	var p: Vector2 = Layout.ppos()
	Particles.emit(p.x, p.y, {"n": 70, "color": _glow((prev if prev else S.act()).el), "spd": 4, "dir": [0, -1], "cone": 0.12, "life": 0.6, "size": 0.22, "r": 0.35, "tex": "spark", "streak": true})
	if old != null and old != S.active_actor():
		var tw := _tween(old)
		tw.tween_property(old, "squash", Vector2(0.01, 1.7), 0.14).set_trans(P2).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			if tok != S.tok or not is_instance_valid(old):
				return
			if S.act() != null and S.active_actor() != old:
				old.visible = false
			old.squash = Vector2.ONE)
	Run.place_player(true, old)
	Ui.render_player_plate()
	Ui.render_bench()
	Ui.refresh_hand()
	var e := S.enemy
	if how != "forced" and e != null and e.alive and S.in_perfect_window(e) and Data.resists(S.act().el, S.heavy_of(e).el):
		_perfect_swap()

func _perfect_swap() -> void:
	var e := S.enemy
	e.perfect = true
	S.stats.perfects += 1
	S.energy = minf(Data.BAL.energy_max, S.energy + Data.BAL.perfect_refund)
	Feel.hit_stop(0.12)
	Feel.slow_mo(Data.BAL.slow_dur, Data.BAL.slow_scale)
	Fx.flash(0.5, Color.WHITE)
	Platform.haptic("heavy")
	Sfx.crit()
	Fx.callout("PERFECT", _el_hex(S.act().el))
	var p: Vector2 = S.actor_for(S.act()).head()
	Fx.pop_num(Vector2(p.x, p.y - Layout.U * 1.3), "+%d" % Data.BAL.perfect_refund, "shield", "Energy")
	Particles.ring(p.x, p.y, Color.WHITE, 3, 0.5, false)
	var me := S.act()
	if _has(me, "counterweave"):   # free Strike: no energy, no hand change, chain untouched
		var co := S.card_of(CardRef.new(me.uid, "strike"), me)
		_trait_pop("counterweave", "Counter")
		_resolve_card(co.def, co.pow, me, "strike")

func _mon_down(c: Mon) -> void:
	c.alive = false
	c.shield = 0
	c.status = null
	var tok := S.tok
	var lead := c.uid == S.active
	Sfx.ko()
	Platform.haptic("error")
	Feel.shake(0.5)
	Feel.hit_stop(0.12)
	Ui.refresh_hand()   # cards of its element stay in hand; discards if no living creature shares it
	Ui.render_bench()
	if lead:
		var pm = S.actor_for(c)
		_tween(pm).tween_property(pm, "rot", -1.2, 0.4).set_trans(P2).set_ease(Tween.EASE_IN)
		var tw := _tween(pm)
		tw.tween_interval(0.35)
		tw.tween_property(pm, "squash", Vector2(0.01, 0.01), 0.5).set_trans(P2).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			var p: Vector2 = Layout.ppos()
			Particles.emit(p.x, p.y - Layout.U * 0.4, {"n": 60, "color": C_KO, "spd": 2, "up": 1, "life": 1, "size": 0.25, "grav": -1, "drag": 1.5}))
	var next := _healthiest()
	if next == null:
		S.mode = "over"
		_later(1.2, func():
			if tok == S.tok:
				Run.end_run(false))
		return
	if lead:
		Fx.banner(c.name + " fainted", "Next partner in", FAINT)
		_later(0.9, func():
			if tok != S.tok or (S.act() != null and S.act().alive):
				return
			var n := _healthiest()
			if n:
				_swap_to(n.uid, "forced"))
	else:
		Fx.toast(c.name + " fainted on the bench")

func _enemy_down() -> void:
	var e := S.enemy
	var m = S.em
	e.alive = false
	S.mode = "end"
	var tok := S.tok
	Sfx.ko()
	Platform.haptic("heavy")
	Feel.hit_stop(0.14)
	Feel.shake(0.6)
	Fx.flash(0.4)
	_tween(m).tween_property(m, "squash", Vector2(1.45, 0.22), 0.35).set_trans(P2).set_ease(Tween.EASE_IN)
	_later(0.32, func():
		if not is_instance_valid(m):
			return
		var p: Vector2 = m.head()
		var E: Vector2 = Layout.epos()
		m.visible = false
		for k in 3:
			_later(k * 0.1, func(): Particles.burst(p, e.el, 1.2))
		Particles.emit(p.x, p.y, {"n": 150, "color": _glow(e.el), "spd": 5, "up": 1, "life": 1.6, "size": 0.26, "grav": -1.5, "drag": 1.4, "swirl": 2})
		Particles.emit(p.x, p.y, {"n": 20, "color": C_GOLD, "spd": 4, "up": 1, "life": 1.4, "size": 0.4, "grav": 2, "drag": 1, "tex": "star", "spin": 6})
		Particles.ring(E.x, E.y, _el_hex(e.el), 4, 0.9))
	var boss := e.kind == "boss"
	Fx.banner("Noctyrm falls" if boss else "Victory",
		"The expedition is complete" if boss else "The Warden yields" if e.kind == "warden" else "Choose a reward", GOLD)
	Sfx.win()
	_later(1.4, func():
		if tok == S.tok:
			Platform.haptic("success")
			Run.after_fight())

# ================= per-frame simulation =================
func _tick_status_on_mon(c: Mon, dt: float) -> void:
	var s = c.status
	if s == null:
		return
	s.t -= dt
	if s.k == "burn":
		s.acc = s.get("acc", 0.0) + dt
		if s.acc >= 0.5:
			s.acc = 0.0
			_hurt_mon(c, Data.BAL.burn_dps * 0.5, null, false, true)
	if s.t <= 0 and is_same(c.status, s):
		c.status = null

func tick_battle(dt: float, t: float) -> void:
	var e := S.enemy
	var m = S.em
	if m != null and is_instance_valid(m) and m.has_method("set_aura"):   # wind-up aura before an attack
		if e != null and e.alive and S.mode == "battle":
			var w := e.t / e.windup
			var hvy := S.is_heavy(e)
			var a := (w - 0.75) * (4.0 if hvy else 3.2) * (0.6 + 0.4 * sin(t * 30)) if w > 0.75 else 0.0
			m.set_aura(_el_hex(S.heavy_of(e).el if hvy else e.el), a)
		else:
			m.set_aura(Color.WHITE, 0.0)
	if S.mode != "battle":
		return
	var me := S.act()
	var rooted: float = 1 - Data.BAL.root_slow if me != null and me.status != null and me.status.k == "root" else 1.0
	S.energy = minf(Data.BAL.energy_max, S.energy + dt * Data.BAL.energy_rate * rooted)
	if S.swap_cd > 0:
		S.swap_cd = maxf(0, S.swap_cd - dt)
	S.chain_t += dt
	if S.chain_t > Data.BAL.chain_win:
		S.chain = 0
	if me != null and me.alive:
		S.auto_t += dt
		if S.auto_t >= Data.BAL.auto_iv:
			S.auto_t = 0
			_auto_attack()
	for c in S.team():
		if not c.alive:
			continue
		if c.shield > 0:
			c.shield_t += dt
			if c.shield_t > Data.BAL.shield_delay + (Data.BAL.bulwark_delay if _has(c, "bulwark") else 0.0):
				c.shield -= c.shield * Data.BAL.shield_decay * dt
				if c.shield < 0.5:
					c.shield = 0
		_tick_status_on_mon(c, dt)
		if S.mode != "battle":
			return
	if e == null or not e.alive or m == null:
		return
	if e.shock_cd > 0:
		e.shock_cd = maxf(0, e.shock_cd - dt)
	var rate: float = 1 - Data.BAL.root_slow if e.status != null and e.status.k == "root" else 1.0
	e.t += dt * rate
	if e.t >= e.windup:
		_enemy_attack()
	if not e.alive or S.mode != "battle":
		return
	var p: Vector2 = m.head()
	var U: float = Layout.U
	if e.t / e.windup > 0.75 and randf() < dt * 30:
		Particles.emit(p.x, p.y + U * 0.3, {"n": 2, "color": _glow(S.heavy_of(e).el if S.is_heavy(e) else e.el), "spd": 1.2, "r": 0.5, "life": 0.4, "size": 0.18, "drag": 2, "swirl_dir": 6})
	var s = e.status
	if s != null:
		s.t -= dt
		if s.k == "burn":
			s.acc = s.get("acc", 0.0) + dt
			if s.acc >= 0.5:
				s.acc = 0.0
				_hurt_enemy(Data.BAL.burn_dps * 0.5, "ember", e.status_src, {"dot": true})
			if randf() < dt * 20:
				Particles.emit(p.x, p.y, {"n": 1, "color": _glow("ember"), "spd": 0.8, "r": 0.4, "up": 1, "life": 0.6, "size": 0.2, "grav": -2})
		elif s.k == "soak" and randf() < dt * 12:
			Particles.emit(p.x, p.y - U * 0.4, {"n": 1, "color": _glow("tide"), "spd": 0.5, "r": 0.5, "life": 0.6, "size": 0.16, "grav": 6})
		elif s.k == "root" and randf() < dt * 8:
			Particles.emit(p.x, p.y + U * 0.6, {"n": 1, "color": _glow("thorn"), "spd": 0.6, "r": 0.6, "up": 0.6, "life": 0.9, "size": 0.2, "tex": "leaf", "spin": 4})
		if s.t <= 0 and is_same(e.status, s):
			e.status = null
			var src := S.mon(e.status_src)
			if s.k == "burn" and e.alive and src != null and src.alive and _has(src, "afterglow"):
				_trait_energy("afterglow")   # its Burn ran its course
	if not e.alive:
		return
	if e.kind == "boss":
		e.shift_t -= dt
		if e.shift_t <= 0:
			e.shift_t = Data.BAL.boss_shift
			_shift_boss()

# ================= dev helpers (TS window.__wb.debug) =================
func _dbg_hurt(f := 0.65) -> void:
	var e := S.enemy
	if e != null and e.alive:
		_hurt_enemy(e.max * f, e.el, 0, {"small": true})

func _dbg_energy() -> void:
	S.energy = Data.BAL.energy_max

## Add a creature to the party (and lineup if there's room). Use on the map, before a fight.
func _dbg_add(key: String) -> int:
	var c := S.new_mon(key)
	S.party.append(c)
	if S.lineup.size() < Data.BAL.lineup:
		S.lineup.append(c.uid)
	return c.uid

func _dbg_essence(n := 20) -> void:
	for el in Data.EL_KEYS:
		Meta.earn(el, n)

## Bank gold and n of each material.
func _dbg_loot(gold := 200, n := 5) -> void:
	Meta.add_loot({"gold": gold, "sword": n, "orb": n, "jewel": n})

func _dbg_trait(t: String) -> void:
	var c := S.act()
	if c:
		c.trait_key = t

func _dbg_heavy() -> void:
	var e := S.enemy
	if e:
		while not S.is_heavy(e):
			e.count += 1
		e.windup = e.iv + Data.BAL.heavy_extra
		e.t = e.windup - 1
