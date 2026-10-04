# Synth sound effects. No audio files. Port of game/src/core/audio.ts.
#
# Each SFX is rendered once into a 16-bit AudioStreamWAV with the same oscillator/noise/envelope
# parameters as the WebAudio version (exponential pitch slide, exponential gain decay to 0.0001,
# band-passed white noise), then played through a small pool of AudioStreamPlayers.
# Rendering happens on a worker thread at startup; a sound that isn't ready yet renders on first use.
extends Node

const RATE := 44100
const POOL := 10

var _muted := false
var _cache := {}            # name → AudioStreamWAV
var _mutex := Mutex.new()
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _task := -1

# ---------- recipes (TS SFX table) ----------
# Each entry is a list of voices: ["tone", f, d, type, vol, slide, delay] or ["noise", d, vol, freq, delay].
func _t(f: float, d: float, type := "square", vol := 0.05, slide := 1.0, delay := 0.0) -> Array:
	return ["tone", f, d, type, vol, slide, delay]
func _n(d: float, vol := 0.12, freq := 1200.0, delay := 0.0) -> Array:
	return ["noise", d, vol, freq, delay]
func _arp(fs: Array, d: float, type: String, vol: float, step: float) -> Array:
	var out := []
	for i in fs.size():
		out.append(_t(fs[i], d, type, vol, 1.0, i * step))
	return out

func _recipe(name: String) -> Array:
	match name:
		"card": return [_t(520, 0.07, "triangle", 0.05, 1.8)]
		"deny": return [_t(160, 0.12, "square", 0.04, 0.8)]
		"hit_700": return [_n(0.14, 0.16, 700), _t(150, 0.12, "square", 0.05, 0.5)]
		"hit_3000": return [_n(0.14, 0.16, 3000), _t(150, 0.12, "square", 0.05, 0.5)]
		"hit_1400": return [_n(0.14, 0.16, 1400), _t(150, 0.12, "square", 0.05, 0.5)]
		"crit": return [_n(0.25, 0.2, 900), _t(90, 0.3, "sawtooth", 0.07, 0.4), _t(880, 0.12, "triangle", 0.04, 1.5, 0.02)]
		"ouch": return [_n(0.18, 0.18, 500), _t(110, 0.2, "square", 0.06, 0.6)]
		"heal": return _arp([523, 659, 784], 0.16, "sine", 0.05, 0.06)
		"shield": return [_t(330, 0.2, "triangle", 0.05, 1.6)]
		"zap": return [_n(0.08, 0.12, 4000), _t(1200, 0.06, "sawtooth", 0.03, 0.4)]
		"throw": return [_t(300, 0.3, "triangle", 0.05, 2.5)]
		"tick": return [_t(900, 0.05, "square", 0.04)]
		"caught": return _arp([523, 659, 784, 1046], 0.22, "triangle", 0.06, 0.09)
		"broke": return [_n(0.3, 0.2, 2000), _t(220, 0.3, "sawtooth", 0.05, 0.5)]
		"ko": return [_t(400, 0.6, "sawtooth", 0.06, 0.15), _n(0.5, 0.15, 600)]
		"win": return _arp([392, 523, 659, 784, 1046], 0.25, "triangle", 0.05, 0.08)
		"lose": return _arp([392, 330, 262, 196], 0.35, "triangle", 0.05, 0.16)
		"swap": return [_t(250, 0.25, "sine", 0.06, 3)]
		"stomp": return [_n(0.3, 0.2, 300), _t(70, 0.3, "sine", 0.12, 0.5)]
		"pick": return [_t(660, 0.08, "triangle", 0.05, 1.3), _t(990, 0.1, "triangle", 0.04, 1, 0.06)]
		"energy": return [_t(700, 0.15, "triangle", 0.05, 2)]
		"focus": return [_t(500, 0.2, "sine", 0.05, 2)]
	return []

const NAMES := ["card", "deny", "hit_700", "hit_3000", "hit_1400", "crit", "ouch", "heal", "shield", "zap", "throw", "tick",
	"caught", "broke", "ko", "win", "lose", "swap", "stomp", "pick", "energy", "focus"]

# ---------- public API (one method per TS SFX entry) ----------
func card() -> void: _play("card")
func deny() -> void: _play("deny")
func hit(el = "") -> void: _play("hit_700" if el == "tide" else "hit_3000" if el == "volt" else "hit_1400")
func crit() -> void: _play("crit")
func ouch() -> void: _play("ouch")
func heal() -> void: _play("heal")
func shield() -> void: _play("shield")
func zap() -> void: _play("zap")
func throw() -> void: _play("throw")
func tick() -> void: _play("tick")
func caught() -> void: _play("caught")
func broke() -> void: _play("broke")
func ko() -> void: _play("ko")
func win() -> void: _play("win")
func lose() -> void: _play("lose")
func swap() -> void: _play("swap")
func stomp() -> void: _play("stomp")
func pick() -> void: _play("pick")
func energy() -> void: _play("energy")
func focus() -> void: _play("focus")

func is_muted() -> bool:
	return _muted

func set_muted(v: bool) -> void:
	_muted = v
	Platform.store_set("muted", v)

## TS unlocks WebAudio on the first touch. Godot needs nothing.
func audio() -> void:
	pass

## The rendered stream for an SFX name (see NAMES). Renders it now if needed.
func stream(name: String) -> AudioStreamWAV:
	_mutex.lock()
	var s: AudioStreamWAV = _cache.get(name)
	if s == null:
		s = _render(_recipe(name))
		_cache[name] = s
	_mutex.unlock()
	return s

# ---------- internals ----------
func _ready() -> void:
	_muted = bool(Platform.store_get("muted", false))
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = 0.0
		add_child(p)
		_players.append(p)
	_task = WorkerThreadPool.add_task(_prewarm, false, "sfx prewarm")

func _prewarm() -> void:
	for n in NAMES:
		stream(n)

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _play(name: String) -> void:
	if _muted or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream(name)
	p.play()

func _render(voices: Array) -> AudioStreamWAV:
	var length := 0.0
	for v in voices:
		var d: float = v[2] if v[0] == "tone" else v[1]
		var delay: float = v[6] if v[0] == "tone" else v[4]
		length = maxf(length, delay + d + 0.02)
	var buf := PackedFloat32Array()
	buf.resize(int(ceil(length * RATE)))
	for v in voices:
		if v[0] == "tone":
			_tone(buf, v[1], v[2], v[3], v[4], v[5], v[6])
		else:
			_noise(buf, v[1], v[2], v[3], v[4])
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

## WebAudio `exponentialRampToValueAtTime` from v0 to v1 over d, sampled at t (holds v1 afterwards).
static func _exp_ramp(v0: float, v1: float, t: float, d: float) -> float:
	return v0 * pow(v1 / v0, minf(t / d, 1.0))

func _tone(buf: PackedFloat32Array, f: float, d: float, type: String, vol: float, slide: float, delay: float) -> void:
	var start := int(delay * RATE)
	var n := mini(int((d + 0.02) * RATE), buf.size() - start)
	var f1 := maxf(20.0, f * slide)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var ft := f if slide == 1.0 else _exp_ramp(f, f1, t, d)
		phase += ft / RATE
		phase -= floorf(phase)
		var s: float
		match type:
			"sine": s = sin(TAU * phase)
			"square": s = 1.0 if phase < 0.5 else -1.0
			"sawtooth": s = 2.0 * phase - 1.0
			_: s = 1.0 - 4.0 * absf(phase - 0.5)   # triangle
		buf[start + i] += s * _exp_ramp(vol, 0.0001, t, d)

## White noise through a band-pass biquad (Q 0.8, constant 0 dB peak like WebAudio's "bandpass").
func _noise(buf: PackedFloat32Array, d: float, vol: float, freq: float, delay: float) -> void:
	var start := int(delay * RATE)
	var n := mini(int((d + 0.02) * RATE), buf.size() - start)
	var w0 := TAU * minf(freq, RATE * 0.45) / RATE
	var alpha := sin(w0) / (2.0 * 0.8)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var b2 := -alpha / a0
	var a1 := -2.0 * cos(w0) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in n:
		var x := randf() * 2.0 - 1.0
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[start + i] += y * _exp_ramp(vol, 0.0001, float(i) / RATE, d)
