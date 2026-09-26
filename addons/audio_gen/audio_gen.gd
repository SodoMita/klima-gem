extends RefCounted
## High-level GDScript wrapper for the AudioGen C library.
## Falls back to GDScript synthesis if the GDExtension is missing.
## Provides: SFX, drums, FM, chiptune, procedural music, ambient.

const MOODS = {
	"calm": 0, "warm": 1, "tense": 2, "night": 3,
	"dream": 4, "lofi": 5, "chiptune": 6, "ambient": 7,
	"rift": 8, "festival": 9, "lab": 10
}
const DRUMS = {
	"kick": 0, "snare": 1, "hihat_closed": 2, "hihat_open": 3,
	"clap": 4, "tom_low": 5, "tom_mid": 6, "tom_high": 7,
	"rim": 8, "cowbell": 9, "cymbal": 10
}
const SFX = {
	"coin": 0, "laser": 1, "explosion": 2, "powerup": 3,
	"hit": 4, "jump": 5, "blip": 6, "click": 7, "buzz": 8,
	"whoosh": 9, "open": 10, "close": 11
}
const FM_PRESETS = {
	"bass": 0, "lead": 1, "pad": 2, "bell": 3, "epiano": 4, "brass": 5
}

var _engine: Object = null
var _has_engine: bool = false

func _init() -> void:
	if ClassDB.class_exists("AudioGen"):
		_engine = ClassDB.instantiate("AudioGen")
		_has_engine = _engine != null

func has_engine() -> bool:
	return _has_engine

## Render helpers - return PackedVector2Array of stereo frames
func render_sfx(type: String, frames: int = 22050) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if _has_engine:
		var t: int = SFX.get(type, 0)
		_engine.call("render_sfx", t, out)
	else:
		# GDScript fallback: simple sine blip
		for i in frames:
			var ph: float = float(i) / 44100.0 * 880.0 * TAU
			var env: float = 1.0 - float(i)/frames
			var s: float = sin(ph) * env * 0.5
			out[i] = Vector2(s,s)
	return out

func render_drum(type: String, frames: int = 22050) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if _has_engine:
		var t: int = DRUMS.get(type, 0)
		_engine.call("render_drum", t, out)
	else:
		# fallback: noise burst for snare, sine for kick
		for i in frames:
			var s: float = 0.0
			if type == "kick":
				var env: float = exp(-float(i)/44100.0*20.0)
				s = sin(float(i)/44100.0*60.0*TAU) * env
			else:
				s = (randf()*2.0-1.0) * exp(-float(i)/44100.0*15.0) * 0.5
			out[i] = Vector2(s,s)
	return out

func render_fm(preset: String, frames: int = 44100, freq: float = 110.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if _has_engine:
		var p: int = FM_PRESETS.get(preset, 0)
		_engine.call("render_fm", p, out, freq)
	else:
		for i in frames:
			var s: float = sin(float(i)/44100.0*freq*TAU) * 0.3
			out[i] = Vector2(s,s)
	return out

## Procedural music - live score
var _proc_buf := PackedVector2Array()

func transition(mood: String, root_midi: int = 60, bpm: float = 90.0, fade: float = 0.8) -> void:
	if _has_engine:
		var m: int = MOODS.get(mood, 0)
		_engine.call("transition", m, float(root_midi), bpm, fade)

func render_proc(frames: int = 1024) -> PackedVector2Array:
	if _proc_buf.size() != frames:
		_proc_buf.resize(frames)
	if _has_engine:
		_engine.call("render_proc", _proc_buf)
	else:
		for i in frames:
			_proc_buf[i] = Vector2.ZERO
	return _proc_buf

## Utility: write to WAV via AudioStreamWAV (editor only)
func save_wav(path: String, data: PackedVector2Array, sr: int = 44100) -> bool:
	# Convert stereo to mono for simplicity, or keep as stereo via interleaving?
	# Use FileAccess to write minimal WAV float32
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var frames: int = data.size()
	var channels: int = 2
	var bits: int = 32
	var byte_rate: int = sr * channels * bits/8
	var data_bytes: int = frames * channels * bits/8
	var riff_size: int = 36 + data_bytes
	f.store_8(0x52); f.store_8(0x49); f.store_8(0x46); f.store_8(0x46) # RIFF
	f.store_32(riff_size)
	f.store_8(0x57); f.store_8(0x41); f.store_8(0x56); f.store_8(0x45) # WAVE
	f.store_8(0x66); f.store_8(0x6D); f.store_8(0x74); f.store_8(0x20) # fmt 
	f.store_32(16)
	f.store_16(3) # float
	f.store_16(channels)
	f.store_32(sr)
	f.store_32(byte_rate)
	f.store_16(channels * bits/8)
	f.store_16(bits)
	f.store_8(0x64); f.store_8(0x61); f.store_8(0x74); f.store_8(0x61) # data
	f.store_32(data_bytes)
	for i in frames:
		f.store_float(data[i].x)
		f.store_float(data[i].y)
	f.close()
	return true
