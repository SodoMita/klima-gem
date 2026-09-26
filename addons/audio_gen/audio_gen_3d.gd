extends RefCounted
## 3D Ambience wrapper - GDScript fallback + C engine if available
## Provides biome, weather, point sources, listener, soundscapes

const BIOMES = {
	"forest": 0, "cave": 1, "desert": 2, "ocean": 3, "city": 4,
	"mountain": 5, "jungle": 6, "swamp": 7, "tundra": 8, "grassland": 9,
	"river": 10, "beach": 11, "nexus": 12, "rift": 13, "lab": 14
}
const WEATHERS = {
	"clear": 0, "cloudy": 1, "rain_light": 2, "rain_medium": 3, "rain_heavy": 4,
	"thunderstorm": 5, "snow_light": 6, "snow_heavy": 7, "fog": 8, "windy": 9, "hail": 10
}
const MOODS = {
	"calm": 0, "warm": 1, "tense": 2, "night": 3, "dream": 4,
	"lofi": 5, "chiptune": 6, "ambient": 7, "rift": 8, "festival": 9, "lab": 10
}

var _engine: Object = null
var _has_engine: bool = false
var _gen: AudioStreamGenerator
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback

# GDScript fallback state
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _biome: String = "forest"
var _weather: String = "clear"
var _weather_intensity: float = 0.0
var _time_of_day: float = 0.5
var _master_gain: float = 0.6
var _listener_pos: Vector3 = Vector3.ZERO
var _listener_forward: Vector3 = Vector3(0,0,-1)
var _listener_up: Vector3 = Vector3(0,1,0)

# Simple point sources for fallback
var _point_sources: Array[Dictionary] = [] # {pos:Vector3, gain:float, freq:float}

func _init() -> void:
	_rng.seed = 12345
	if ClassDB.class_exists("AudioGen"):
		_engine = ClassDB.instantiate("AudioGen")
		_has_engine = _engine != null
	# For live playback, create a generator
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = 44100
	_gen.buffer_length = 0.1
	_player = AudioStreamPlayer.new()
	_player.stream = _gen

## Listener
func set_listener(pos: Vector3, forward: Vector3 = Vector3(0,0,-1), up: Vector3 = Vector3(0,1,0), vel: Vector3 = Vector3.ZERO) -> void:
	_listener_pos = pos
	_listener_forward = forward
	_listener_up = up
	# TODO: pass to C engine if available

func get_listener() -> Vector3:
	return _listener_pos

## Biome
func set_biome(biome_name: String, time_of_day: float = 0.5, weather_intensity: float = 0.0) -> void:
	_biome = biome_name
	_time_of_day = clampf(time_of_day, 0.0, 1.0)
	_weather_intensity = clampf(weather_intensity, 0.0, 1.0)
	if _has_engine:
		# C engine would need a dedicated 3D API; for now we use preset mapping
		# The C Ambience3D preset_for_scene is called via a separate GDExtension if built
		# Here we just store for fallback
		pass

func get_biome() -> String:
	return _biome

## Weather
func set_weather(weather_name: String, intensity: float = 0.5) -> void:
	_weather = weather_name
	_weather_intensity = clampf(intensity, 0.0, 1.0)

## Point sources
func add_point_source(pos: Vector3, min_dist: float = 1.0, max_dist: float = 20.0, gain: float = 1.0, freq: float = 440.0) -> int:
	var idx: int = _point_sources.size()
	_point_sources.append({"pos": pos, "min_dist": min_dist, "max_dist": max_dist, "gain": gain, "freq": freq})
	return idx

func set_point_pos(idx: int, pos: Vector3) -> void:
	if idx >=0 and idx < _point_sources.size():
		_point_sources[idx]["pos"] = pos

func set_point_gain(idx: int, gain: float) -> void:
	if idx >=0 and idx < _point_sources.size():
		_point_sources[idx]["gain"] = gain

func remove_point_source(idx: int) -> void:
	if idx >=0 and idx < _point_sources.size():
		_point_sources.remove_at(idx)

func clear_point_sources() -> void:
	_point_sources.clear()

## Master gain
func set_master_gain(gain: float, fade_sec: float = 0.5) -> void:
	_master_gain = clampf(gain, 0.0, 1.5)

## Render fallback (procedural, not using C)
func _render_fallback(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	var sr: float = 44100.0
	for i in frames:
		_time += 1.0 / sr
		var mix_l: float = 0.0
		var mix_r: float = 0.0

		# Wind base
		var wind: float = (randf()*2.0-1.0) * 0.05
		# Apply simple LP via smoothing
		wind *= 0.3
		mix_l += wind
		mix_r += wind

		# Water based on biome
		if _biome == "ocean" or _biome == "beach":
			var swell: float = sin(_time * 0.07 * TAU) * 0.2
			var n: float = (randf()*2.0-1.0) * 0.2
			mix_l += (n + swell*0.1) * 0.4
			mix_r += (n + swell*0.1) * 0.4
		elif _biome == "river" or _biome == "forest":
			var n: float = (randf()*2.0-1.0) * 0.1
			mix_l += n * 0.2
			mix_r += n * 0.2

		# Birds (day)
		var day_factor: float = sin(_time_of_day * PI)
		if day_factor > 0.3 and _biome in ["forest","jungle","grassland","river","beach"]:
			if randf() < 0.002 * day_factor:
				var chirp: float = sin(_time * 3000.0 * TAU) * 0.3 * exp(-fmod(_time,1.0)*5.0)
				mix_l += chirp * 0.2
				mix_r += chirp * 0.2

		# Crickets (night)
		var night_factor: float = 1.0 - day_factor
		if night_factor > 0.4:
			if fmod(_time, 0.2) < 0.05:
				var cricket: float = sin(_time * 4500.0 * TAU) * 0.15 * sin(_time * 30.0 * TAU)
				mix_l += cricket
				mix_r += cricket

		# Weather
		if _weather != "clear" and _weather_intensity > 0.01:
			var rain: float = 0.0
			if _weather.begins_with("rain") or _weather == "thunderstorm":
				if randf() < 0.05 * _weather_intensity:
					rain = (randf()*2.0-1.0) * 0.3 * _weather_intensity
			mix_l += rain
			mix_r += rain

		# Point sources with simple panning
		for ps in _point_sources:
			var pos: Vector3 = ps["pos"]
			var to_src: Vector3 = pos - _listener_pos
			var dist: float = to_src.length()
			if dist < 0.1:
				dist = 0.1
			var att: float = 1.0 / (1.0 + dist * 0.2)
			var dir: Vector3 = to_src.normalized()
			var right_dot: float = dir.dot(_listener_forward.cross(_listener_up).normalized())
			var pan: float = clampf(right_dot, -1.0, 1.0)
			var angle: float = (pan*0.5+0.5) * PI * 0.5
			var gl: float = cos(angle)
			var gr: float = sin(angle)
			var freq: float = float(ps.get("freq", 440.0))
			var s: float = sin(_time * freq * TAU) * 0.1 * att * float(ps.get("gain",1.0))
			mix_l += s * gl
			mix_r += s * gr

		# Soft clip
		mix_l = mix_l / (1.0 + absf(mix_l)) * 1.4
		mix_r = mix_r / (1.0 + absf(mix_r)) * 1.4
		mix_l *= _master_gain
		mix_r *= _master_gain
		out[i] = Vector2(mix_l, mix_r)
	return out

## Public render - uses C if available, else fallback
func render(frames: int = 1024) -> PackedVector2Array:
	if _has_engine and _engine.has_method("render_ambience_3d"):
		var out := PackedVector2Array()
		out.resize(frames)
		_engine.call("render_ambience_3d", out)
		return out
	else:
		return _render_fallback(frames)

## Live playback helpers
func attach_to_player(player: AudioStreamPlayer) -> void:
	_player = player
	if _player.stream == null:
		_player.stream = _gen
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback

func process_live() -> void:
	if _playback == null:
		if _player.playing:
			_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _playback == null:
			return
	var frames: int = mini(_playback.get_frames_available(), 2048)
	if frames <= 0:
		return
	var buf: PackedVector2Array = render(frames)
	_playback.push_buffer(buf)

## Presets for Chrono Nexus scenes
func preset_for_scene(scene_name: String) -> void:
	match scene_name:
		"classroom":
			set_biome("city", 0.6)
			set_weather("clear", 0.0)
		"grove":
			set_biome("forest", 0.5)
			set_weather("clear", 0.0)
		"shore":
			set_biome("beach", 0.6)
			set_weather("clear", 0.1)
		"nexus":
			set_biome("nexus", 0.5)
			set_weather("clear", 0.0)
		"rift":
			set_biome("rift", 0.2)
			set_weather("windy", 0.5)
		"core":
			set_biome("cave", 0.0)
			set_weather("clear", 0.0)
		"lab":
			set_biome("lab", 0.7)
			set_weather("clear", 0.0)
		"festival":
			set_biome("city", 0.8)
			set_weather("clear", 0.0)
		"sanctum":
			set_biome("cave", 0.3)
			set_weather("clear", 0.0)
		"alley":
			set_biome("city", 0.1)
			set_weather("rain_light", 0.3)
		"lighthouse":
			set_biome("ocean", 0.4)
			set_weather("windy", 0.3)
		_:
			set_biome("forest", 0.5)
