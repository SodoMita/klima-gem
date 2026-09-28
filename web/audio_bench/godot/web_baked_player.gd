class_name WebBakedPlayer
extends Node
## Playback only — no synthesis in GDScript.
##
## The web export ships `gdextensionLibs: []`, so the AudioGen GDExtension never
## loads and `play_dubstep()` used to fall back to a per-sample GDScript score at
## 22050 Hz (wrong music, main-thread cost). Human directive: no GDScript audio
## generation. The C engine output is instead baked at build time by
## `web/audio_bench/tools/bake_loops.c` and played back from memory here.
##
## Usage:
##     var p := WebBakedPlayer.new()
##     add_child(p)
##     p.play_variant("stage")          # loops/stage.wav
##     p.trigger("gem_hit", 0.8, -0.2)  # one-shots/gem_hit.wav

const LOOP_DIR := "res://web/audio_bench/public/audio"
const SFX_DIR := "res://web/audio_bench/public/audio"

const VARIANTS := ["stage", "trial", "chill", "suspense", "groove", "victory", "defeat"]

var _loop_player: AudioStreamPlayer
var _fade_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_index := 0


func _ready() -> void:
	_loop_player = AudioStreamPlayer.new()
	_loop_player.bus = "Master"
	add_child(_loop_player)
	_fade_player = AudioStreamPlayer.new()
	_fade_player.bus = "Master"
	add_child(_fade_player)
	for i in 8:
		var s := AudioStreamPlayer.new()
		s.bus = "Master"
		add_child(s)
		_sfx_pool.append(s)


func _load_loop(variant: String) -> AudioStreamWAV:
	var path := "%s/loop_%s.wav" % [LOOP_DIR, variant]
	if not ResourceLoader.exists(path):
		push_warning("WebBakedPlayer: missing %s" % path)
		return null
	return load(path) as AudioStreamWAV


## Crossfade to a baked variant over `fade` seconds. 48 kHz mono/stereo PCM.
func play_variant(variant: String, fade := 0.22) -> void:
	var stream := _load_loop(variant)
	if stream == null:
		return
	if _loop_player.playing:
		_fade_player.stream = _loop_player.stream
		_fade_player.volume_db = _loop_player.volume_db
		_fade_player.play(_loop_player.get_playback_position())
		var tw := create_tween()
		tw.tween_property(_fade_player, "volume_db", -60.0, fade)
		tw.tween_callback(_fade_player.stop)
	_loop_player.stream = stream
	_loop_player.volume_db = -60.0
	_loop_player.play()
	var tw2 := create_tween()
	tw2.tween_property(_loop_player, "volume_db", 0.0, fade)


func trigger(name: String, gain := 0.9, pan := 0.0) -> void:
	var path := "%s/sfx_%s.wav" % [SFX_DIR, name]
	if not ResourceLoader.exists(path):
		push_warning("WebBakedPlayer: missing %s" % path)
		return
	var player := _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_pool.size()
	player.stream = load(path)
	player.volume_db = linear_to_db(maxf(gain, 0.001))
	if player is AudioStreamPlayer2D:
		player.position.x = pan * 64.0
	player.play()


func stop_all(fade := 0.18) -> void:
	var tw := create_tween()
	tw.tween_property(_loop_player, "volume_db", -60.0, fade)
	tw.tween_callback(_loop_player.stop)
