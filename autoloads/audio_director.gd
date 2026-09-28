extends Node
## Runtime audio: procedural music, tiny OGG loops and SFX. play_scene()
## starts a live score for the background that just came up. ALL generated
## audio comes out of the C extensions: SceneScore mixes the pad/pluck score,
## AudioGen runs the live dubstep engine and cuts one-shots. There is no
## GDScript DSP in this file ON PURPOSE (it produced the wrong music and ate
## the frame budget on web, chat msgs 136-139): when an extension is missing
## the OGG loops stand in, silently, and nothing is synthesized per sample.
## play_music_loop() is also the "Generated music" off path.


const SAMPLE_RATE: int = 48000        ## stream rate (48 kHz, chat msg 140)
const LOOP_DB: float = -8.0           ## OGG loop level ...
const LOOP_SILENT_DB: float = -60.0   ## ... and its faded-out floor (dB)

## Fallback loops per theme.
const THEME_LOOPS: Dictionary = {
	&"calm": "res://assets/music/day.ogg",
	&"warm": "res://assets/music/day.ogg",
	&"tense": "res://assets/music/night.ogg",
	&"night": "res://assets/music/night.ogg",
}

## Scene -> mood for the non-procedural fallback (Settings "Generated music"
## off). Scene keys are not mood keys, so looking them up in THEME_LOOPS
## alone always fell through to night.ogg for every background.
const SCENE_LOOPS: Dictionary = {
	"classroom": &"calm",
	"grove": &"night",
	"shore": &"warm",
	"sanctum": &"calm",
	"nexus": &"tense",
	"rift": &"tense",
	"core": &"tense",
	"lab": &"tense",
	"alley": &"tense",
	"festival": &"warm",
	"lighthouse": &"calm",
	"stage": &"tense",
	"stage_trial": &"tense",
	"stage_chill": &"night",
}

## Scenes that run the C dubstep engine instead of the pad/pluck score.
## festival stays the calm party score; the show floor gets the wobble.
const DUB_SCENES: Dictionary = {
	"stage": 0,           ## AG_DUB_VARIANT_STAGE (general active stage floor)
	"stage_trial": 1,     ## AG_DUB_VARIANT_TRIAL (challenge / precision round)
	"stage_chill": 2,     ## AG_DUB_VARIANT_CHILL (between rounds / rest)
	"stage_suspense": 3,  ## AG_DUB_VARIANT_SUSPENSE (1 gem rolled / suspense)
	"stage_groove": 4,    ## AG_DUB_VARIANT_GROOVE (both placed / peak drop)
	"stage_victory": 5,   ## AG_DUB_VARIANT_VICTORY (overall / challenge win)
	"stage_defeat": 6,    ## AG_DUB_VARIANT_DEFEAT (overall / challenge loss)
}
const DUB_BPM: Dictionary = {
	"stage": 140.0,
	"stage_trial": 150.0,
	"stage_chill": 128.0,
	"stage_suspense": 135.0,
	"stage_groove": 142.0,
	"stage_victory": 145.0,
	"stage_defeat": 50.0,
}

## #music_event= / music_event() names -> AgDubEvent.
const DUB_EVENTS: Dictionary = {
	"riser": 0, "build": 0, "drop": 1, "impact": 2, "fill": 3, "stab": 4, "break": 5,
}

## Event sounds cut from the same dubstep palette (AgDubSfxKind).
const DUB_SFX: Dictionary = {
	"gem_hit": 0, "gem_land": 1, "gem_spawn": 2, "throw": 3, "catch": 4,
	"wobble_blip": 5, "sub_drop": 6, "impact": 7, "riser": 8, "stab": 9,
	"correct": 10, "wrong": 11, "win": 12, "lose": 13, "airhorn": 14,
	"scratch": 15, "reveal": 16, "tick": 17,
	"jump": 18, "shoot": 19, "bell_hit": 20, "pad_note": 21, "plaque_place": 22,
}

## Procedural score: chords as scale degrees; plucks/bass_hits per bar.
const THEMES: Dictionary = {
	&"calm": {
		"bpm": 72.0, "root": 60, "scale": [0, 2, 4, 7, 9],
		"prog": [[0, 2, 4], [3, 5, 0], [5, 0, 2], [3, 0, 4]],
		"pad": 0.52, "pluck": 0.30, "bass": 0.40, "plucks": 4, "bass_hits": 1,
	},
	&"warm": {
		"bpm": 66.0, "root": 65, "scale": [0, 2, 4, 7, 9],
		"prog": [[0, 2, 4], [5, 0, 2], [3, 5, 0], [4, 6, 1]],
		"pad": 0.54, "pluck": 0.26, "bass": 0.38, "plucks": 4, "bass_hits": 1,
	},
	&"tense": {
		"bpm": 96.0, "root": 62, "scale": [0, 2, 3, 5, 7, 8, 10],
		"prog": [[0, 2, 4], [0, 2, 4], [5, 0, 2], [6, 1, 3]],
		"pad": 0.42, "pluck": 0.28, "bass": 0.46, "plucks": 8, "bass_hits": 2,
	},
	&"night": {
		"bpm": 60.0, "root": 57, "scale": [0, 3, 5, 7, 10],
		"prog": [[0, 2, 4], [3, 0, 2], [5, 0, 4], [0, 2, 4]],
		"pad": 0.50, "pluck": 0.22, "bass": 0.36, "plucks": 2, "bass_hits": 1,
	},
}

## One generated score per background. Mood tags tint this; they do not replace it.
const SCENE_THEMES: Dictionary = {
	"classroom": {
		"bpm": 68.0, "root": 60, "scale": [0, 2, 4, 7, 9], "shape": 0.0,
		"prog": [[0, 2, 4], [3, 0, 2], [4, 1, 3], [0, 2, 4]],
		"pad": 0.46, "pluck": 0.18, "bass": 0.26, "plucks": 2, "bass_hits": 1,
		"pluck_shift": 12, "bass_shift": -12,
	},
	"nexus": {
		"bpm": 96.0, "root": 74, "scale": [0, 2, 4, 6, 7, 9, 11], "shape": 0.0,
		"prog": [[0, 2, 4], [4, 6, 1], [5, 0, 2], [2, 4, 6]],
		"pad": 0.22, "pluck": 0.46, "bass": 0.16, "plucks": 8, "bass_hits": 1,
		"pluck_shift": 24, "bass_shift": -24,
	},
	"rift": {
		"bpm": 128.0, "root": 61, "scale": [0, 3, 6, 9], "shape": 2.0,
		"prog": [[0, 1, 2], [2, 0, 3], [1, 2, 0], [3, 1, 2]],
		"pad": 0.16, "pluck": 0.34, "bass": 0.58, "plucks": 8, "bass_hits": 2,
		"pluck_shift": 12, "bass_shift": -24,
	},
	"grove": {
		"bpm": 62.0, "root": 64, "scale": [0, 3, 5, 7, 10], "shape": 1.0,
		"prog": [[0, 2, 4], [3, 0, 2], [4, 1, 3], [0, 2, 4]],
		"pad": 0.52, "pluck": 0.16, "bass": 0.2, "plucks": 3, "bass_hits": 1,
		"pluck_shift": 12, "bass_shift": -12,
	},
	"shore": {
		"bpm": 56.0, "root": 67, "scale": [0, 2, 4, 5, 7, 9, 11], "shape": 0.0,
		"prog": [[0, 2, 4], [3, 5, 0], [4, 6, 1], [0, 2, 4]],
		"pad": 0.58, "pluck": 0.12, "bass": 0.28, "plucks": 2, "bass_hits": 1,
		"pluck_shift": 0, "bass_shift": -12,
	},
	"core": {
		"bpm": 72.0, "root": 36, "scale": [0, 3, 7], "shape": 2.0,
		"prog": [[0, 1, 2], [0, 2, 1], [0, 1, 2], [2, 0, 1]],
		"pad": 0.3, "pluck": 0.08, "bass": 0.66, "plucks": 1, "bass_hits": 2,
		"pluck_shift": 12, "bass_shift": -12,
	},
	"festival": {
		"bpm": 114.0, "root": 65, "scale": [0, 2, 4, 5, 7, 9, 11], "shape": 1.0,
		"prog": [[0, 2, 4], [4, 6, 1], [3, 5, 0], [5, 0, 2]],
		"pad": 0.26, "pluck": 0.42, "bass": 0.34, "plucks": 6, "bass_hits": 2,
		"pluck_shift": 12, "bass_shift": -12,
	},
	"lab": {
		"bpm": 108.0, "root": 69, "scale": [0, 2, 3, 5, 7, 8, 11], "shape": 2.0,
		"prog": [[0, 2, 4], [5, 0, 2], [3, 5, 1], [6, 1, 3]],
		"pad": 0.14, "pluck": 0.36, "bass": 0.44, "plucks": 8, "bass_hits": 2,
		"pluck_shift": 12, "bass_shift": -12,
	},
	"sanctum": {
		"bpm": 48.0, "root": 72, "scale": [0, 4, 7, 11], "shape": 0.0,
		"prog": [[0, 1, 2], [2, 0, 1], [1, 2, 3], [0, 1, 2]],
		"pad": 0.6, "pluck": 0.1, "bass": 0.1, "plucks": 1, "bass_hits": 1,
		"pluck_shift": 24, "bass_shift": -24,
	},
	"alley": {
		"bpm": 86.0, "root": 46, "scale": [0, 3, 5, 7, 10], "shape": 2.0,
		"prog": [[0, 2, 4], [3, 0, 2], [4, 1, 3], [2, 4, 0]],
		"pad": 0.28, "pluck": 0.16, "bass": 0.52, "plucks": 3, "bass_hits": 2,
		"pluck_shift": 0, "bass_shift": -12,
	},
	"lighthouse": {
		"bpm": 46.0, "root": 53, "scale": [0, 7], "shape": 1.0,
		"prog": [[0, 1], [0, 1], [1, 0], [0, 1]],
		"pad": 0.62, "pluck": 0.08, "bass": 0.36, "plucks": 1, "bass_hits": 1,
		"pluck_shift": 12, "bass_shift": -12,
	},
}


# Introspection for tests/tools.
var music_source: String = ""          ## "", "procedural" or "loop"
var current_theme: StringName = &""    ## active theme ("" when none)
var procedural_enabled: bool = true    ## Settings "Generated music" toggle
var notes_scheduled: int = 0           ## scheduler events emitted so far
var frames_pushed: int = 0             ## samples pushed to the generator
var sfx_played: int = 0                ## play_sfx() calls (ogg + synth)
var last_sfx: String = ""              ## key of the most recent SFX
var last_sfx_source: String = ""       ## "ogg" or "synth"
var last_sfx_pitch: float = 1.0        ## pitch of the most recent SFX
var music_seed: int = 20260921         ## arpeggio RNG seed
## Draw a fresh music seed at boot (tests turn this off to pin the score).
var randomize_music_on_boot: bool = true
## How many different renders ("takes") of each one-shot are kept; a play
## picks one at random so two gem hits never sound identical.
const SFX_TAKES := 4
## Per-phase candidates: a phase picks one variant+intensity at random from
## its list, so the same beat of the show is scored differently each night.
const PHASE_CHOICES: Dictionary = {
	"entrance": [["stage", 0.55], ["stage_groove", 0.5], ["stage_chill", 0.6]],
	"rolling": [["stage_suspense", 0.70], ["stage_trial", 0.6], ["stage", 0.75]],
	"gem_1_rolled": [["stage_suspense", 0.78], ["stage_suspense", 0.7], ["stage", 0.8]],
	"both_revealed": [["stage_groove", 0.92], ["stage", 0.95], ["stage_victory", 0.85]],
	"challenge_build": [["stage_trial", 0.85], ["stage_suspense", 0.85], ["stage_groove", 0.8]],
	"challenge_run": [["stage_trial", 0.95], ["stage_groove", 0.95], ["stage", 1.0]],
	"challenge_victory": [["stage_groove", 0.88], ["stage_victory", 0.9], ["stage", 0.9]],
	"challenge_loss": [["stage_chill", 0.45], ["stage_defeat", 0.5], ["stage_suspense", 0.4]],
	"overall_victory": [["stage_victory", 1.0], ["stage_groove", 1.0]],
	"overall_loss": [["stage_defeat", 0.35], ["stage_chill", 0.3]],
	"chill": [["stage_chill", 0.40], ["stage_defeat", 0.45], ["stage", 0.4]],
}
const PHASE_ALIASES: Dictionary = {
	"host": "entrance", "idle": "entrance",
	"gem_throw": "rolling", "throw_1": "rolling", "throw_2": "rolling",
	"1_gem_rolled": "gem_1_rolled",
	"both_placed": "both_revealed", "gems_ready": "both_revealed",
	"trial_intro": "challenge_build", "trial_active": "challenge_run",
	"trial_win": "challenge_victory", "trial_loss": "challenge_loss",
	"show_win": "overall_victory", "show_loss": "overall_loss", "rest": "chill",
}
const PHASE_EVENTS: Dictionary = {
	"gem_1_rolled": ["stab", "fill"], "both_revealed": ["drop"],
	"challenge_build": ["fill", "riser"], "challenge_run": ["riser"],
	"challenge_victory": ["drop", "impact"], "challenge_loss": ["break"],
	"overall_victory": ["drop"], "overall_loss": ["break"],
}
## The last phase chosen and what it resolved to, for tests and the HUD.
var last_phase := ""
var last_phase_choice: Array = []
var _scene_key: String = ""
var _scene_mood: String = ""

var _gen: AudioStreamGenerator
var _gen_player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _theme: Dictionary = {}
var _rng := RandomNumberGenerator.new()

## Pushed-audio timeline, bar cursor and event queue (sorted by t).

## Voices as parallel arrays: kind 0 pad, 1 pluck, 2 bass.

## Crossfade gain + last theme.
var _last_theme: StringName = &""


var _loop_a: AudioStreamPlayer
var _loop_b: AudioStreamPlayer
var _loop_path: String = ""
var _auto_loop: bool = false   ## true when the loop was a procedural fallback

var _sfx_pool: Array[AudioStreamPlayer] = []
var _hold_player: AudioStreamPlayer
var hold_pitch: float = 1.4            ## hold tone pitch (falls as it fills)
var _c_sfx_cache: Dictionary = {}   ## C-rendered blips, on first use
var _engine: Object = null          ## SceneScore, when the extension loaded
var _dub: Object = null             ## AudioGen, the C dubstep engine
var dub_scene: String = ""          ## active dubstep scene key ("" when off)
var dub_intensity: float = 0.55     ## last requested intensity
var dub_events_sent: int = 0        ## #music_event calls that reached the engine
var dub_sfx_rendered: int = 0       ## one-shots pulled out of the C generator
var _dub_cache: Dictionary = {}     ## key|energy bucket -> AudioStreamWAV
var _push := PackedVector2Array()  ## reused generator buffer

## Mixer percents as last set through set_bus_percent (settings sliders).
## Volume 0 must STOP the audio system, not just mute it: on a phone the
## C engines would keep rendering 48k frames nobody hears (chat msg 154).
var _bus_percent: Dictionary = {"Master": 100.0, "Music": 100.0, "Voice": 100.0, "SFX": 100.0}
var _music_muted := false
var _sfx_muted := false

## Music mode (chat msg 154): "live" pumps the C engines every frame,
## "baked" renders each dubstep variant ONCE into a looped WAV (zero DSP
## per frame afterwards), "auto" picks baked on mobile web / mobile.
var music_mode: String = "auto"
var _baked_key: String = ""        ## cache key of the sounding baked loop
var _bake_job: Dictionary = {}     ## in-flight incremental bake (empty = idle)
const BAKE_BUDGET_USEC: int = 4000 ## per-frame slice of bake work (~1/4 frame)
var _max_push: int = 8192          ## per-frame push cap (bigger on web)


func _ready() -> void:
	_ensure_audio_buses()
	# The saved mixer sliders must be live before the FIRST note: the main
	# menu plays its theme long before any balloon exists to apply them.
	apply_saved_volumes()
	music_mode = _read_music_mode()
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = SAMPLE_RATE
	# Web nothreads renders on the main thread: a longer buffer rides out GC
	# and raycast spikes that underrun a 0.25 s one.
	_gen.buffer_length = 1.0 if OS.has_feature("web") else 0.25
	# Bigger recovery pushes on web: after a main-thread jank spike the
	# buffer refills in a few frames instead of draining forever.
	_max_push = 16384 if OS.has_feature("web") else 8192
	_gen_player = AudioStreamPlayer.new()
	# Godot 4.3+ defaults WEB playback to "Sample"; a generator stream cannot
	# be sampled, so the C engines would be silent on Pages without this.
	_gen_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_gen_player.stream = _gen
	_gen_player.bus = &"Music"
	_gen_player.name = "ProceduralMusic"
	add_child(_gen_player)
	_loop_a = _make_music_player("LoopA")
	_loop_b = _make_music_player("LoopB")
	for i: int in 6:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)
	_hold_player = AudioStreamPlayer.new()
	_hold_player.name = "HoldTone"
	_hold_player.bus = &"SFX"
	add_child(_hold_player)
	# Every boot is a different night: the score seed is drawn at random
	# unless a test pins it through reroll(seed) / music_seed. A fixed seed
	# made every show open on the very same bars and the very same hits.
	if randomize_music_on_boot and not OS.get_cmdline_user_args().has("--fixed-audio-seed"):
		var r := RandomNumberGenerator.new()
		r.randomize()
		music_seed = int(r.randi() & 0x7fffffff) | 1
	_rng.seed = music_seed
	_attach_engine()
	_attach_dubstep()


func _make_music_player(node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = &"Music"
	p.volume_db = LOOP_SILENT_DB
	add_child(p)
	return p


func _process(_delta: float) -> void:
	if _music_muted:
		return  # volume 0: the C engines render nothing at all
	if not _bake_job.is_empty():
		_pump_bake()
	if music_source == "dubstep":
		_pump_dubstep()
		return
	if _engine != null and bool(_engine.call("active")):
		_pump_engine()


## Drop stream refs before teardown (fewer shutdown leaks).
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		var players: Array[AudioStreamPlayer] = [_gen_player, _loop_a, _loop_b, _hold_player]
		players.append_array(_sfx_pool)
		for p: AudioStreamPlayer in players:
			if is_instance_valid(p):
				p.stop()
				p.stream = null
		_c_sfx_cache.clear()
		_dub_cache.clear()
		_playback = null



## Start/switch a mood theme; "stop"/unknown stop it; off -> mood-matched loop.
func play_theme(theme: StringName) -> void:
	if theme == &"stop" or not THEMES.has(theme):
		stop_music()
		return
	_scene_key = ""
	_scene_mood = ""
	_last_theme = theme
	if not procedural_enabled:
		play_music_loop(String(THEME_LOOPS.get(theme, "res://assets/music/day.ogg")), true)
		return
	if music_source == "procedural" and current_theme == theme:
		return
	_begin_score(theme, THEMES[theme])


## Generated score for a background. A mood tints that score; it does not swap in a shared loop.
func play_scene(scene_key: String, mood: String = "") -> void:
	if DUB_SCENES.has(scene_key):
		play_dubstep(scene_key, mood)
		return
	if not SCENE_THEMES.has(scene_key):
		return
	if music_source == "dubstep":
		_stop_dubstep(0.6)
	if procedural_enabled and _scene_key == scene_key and _scene_mood == mood and music_source == "procedural" and current_theme == StringName(scene_key):
		return
	var same_scene := procedural_enabled and music_source == "procedural" and _scene_key == scene_key and current_theme == StringName(scene_key)
	_scene_key = scene_key
	_scene_mood = mood
	var score: Dictionary = (SCENE_THEMES[scene_key] as Dictionary).duplicate(true)
	_color_mood(score, mood)
	_last_theme = StringName(scene_key)
	if not procedural_enabled:
		play_music_loop(_scene_loop_path(scene_key, mood), true)
		return
	# A mood tint changes the score that is already playing. It does not restart it.
	if same_scene and _engine != null:
		_theme = score
		_engine.call("adjust", _pack_score(score))
		return
	_begin_score(StringName(scene_key), score)


## Resolve the OGG stand-in when generated music is off. A live mood tag wins;
## otherwise a plain mood key (from play_theme) maps itself, and a scene key
## falls back to its own day/night entry in SCENE_LOOPS.
func _scene_loop_path(scene_or_mood: String, mood: String = "") -> String:
	var mood_key := StringName(mood)
	if not THEME_LOOPS.has(mood_key):
		if THEME_LOOPS.has(StringName(scene_or_mood)):
			mood_key = StringName(scene_or_mood)
		else:
			mood_key = SCENE_LOOPS.get(scene_or_mood, &"night")
	return String(THEME_LOOPS.get(mood_key, "res://assets/music/night.ogg"))


func _color_mood(score: Dictionary, mood: String) -> void:
	if mood == "calm":
		score["plucks"] = maxi(1, int(score["plucks"]) - 1)
		score["bass"] = float(score["bass"]) * 0.8
	elif mood == "warm":
		score["bpm"] = float(score["bpm"]) * 0.92
		score["pad"] = minf(0.72, float(score["pad"]) * 1.18)
		score["pluck"] = float(score["pluck"]) * 0.8
	elif mood == "tense":
		score["bpm"] = float(score["bpm"]) * 1.16
		score["plucks"] = mini(12, int(score["plucks"]) + 3)
		score["bass"] = minf(0.72, float(score["bass"]) * 1.3)
		score["pad"] = float(score["pad"]) * 0.82
	elif mood == "night":
		score["bpm"] = float(score["bpm"]) * 0.8
		score["plucks"] = maxi(1, int(score["plucks"]) - 1)
		score["bass"] = float(score["bass"]) * 0.7
		score["pluck_shift"] = int(score.get("pluck_shift", 12)) - 12


## Hand a score to the SceneScore C engine. Without the engine (an export
## that shipped without the extension) the scene's OGG loop stands in: the
## old GDScript pad/pluck mixer is gone on purpose (chat msg 139).
func _begin_score(theme_name: StringName, score: Dictionary) -> void:
	_theme = score
	if _engine == null:
		play_music_loop(_scene_loop_path(_scene_key if _scene_key != "" else String(theme_name), _scene_mood), true)
		return
	_fade_out_loops()
	current_theme = theme_name
	music_source = "procedural"
	_auto_loop = false
	var seed_value := hash(String(theme_name) + _scene_mood) ^ music_seed ^ int(_rng.randi() & 0x7fffffff)
	_rng.seed = seed_value
	var first := not bool(_engine.call("active"))
	_engine.call("transition", _pack_score(score), 0.35 if first else 0.8, hash(String(theme_name)), seed_value)
	_ensure_playback()


## Crossfade to an OGG loop; as_fallback marks a stand-in for the engine.
func play_music_loop(path: String, as_fallback: bool = false) -> void:
	if music_source == "loop" and _loop_path == path:
		return
	if _engine != null:
		_engine.call("release")
	current_theme = &""
	music_source = "loop"
	_loop_path = path
	_auto_loop = as_fallback
	var stream: AudioStream = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if stream == null:
		push_warning("AudioDirector: missing loop %s" % path)
		music_source = ""
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_crossfade_to_stream(stream)


## Crossfade the loop player pair onto a new looped stream (OGG or baked WAV).
func _crossfade_to_stream(stream: AudioStream) -> void:
	var fresh := _loop_b if _loop_a.playing else _loop_a
	var stale := _loop_a if fresh == _loop_b else _loop_b
	fresh.stream = stream
	fresh.volume_db = LOOP_SILENT_DB
	fresh.stream_paused = false
	fresh.play()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(fresh, "volume_db", LOOP_DB, 0.8)
	if stale.playing:  # crossfade the previous loop out under the new one
		tw.tween_property(stale, "volume_db", LOOP_SILENT_DB, 0.8)
		tw.chain().tween_callback(stale.stop)


## Fade everything out.
func stop_music(fade: float = 0.8) -> void:
	if _engine != null:
		_engine.call("release")
	_stop_dubstep(fade)
	current_theme = &""
	_last_theme = &""
	_scene_key = ""
	_scene_mood = ""
	_auto_loop = false
	_loop_path = ""
	music_source = ""
	for p: AudioStreamPlayer in [_loop_a, _loop_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", LOOP_SILENT_DB, fade)
			tw.tween_callback(p.stop)


## Fade out and stop the sounding loop player.
func _fade_out_loops() -> void:
	_loop_path = ""
	for p: AudioStreamPlayer in [_loop_a, _loop_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", LOOP_SILENT_DB, 0.5)
			tw.tween_callback(p.stop)


## "Generated music" setting: swap engine <-> fallback loops.
func set_procedural_enabled(on: bool) -> void:
	procedural_enabled = on
	if on:
		if _scene_key != "":
			var key := _scene_key
			var mood := _scene_mood
			_scene_key = ""
			_scene_mood = ""
			play_scene(key, mood)
		elif _last_theme != &"":
			var theme := _last_theme
			_last_theme = &""
			play_theme(theme)
	elif music_source in ["procedural", "dubstep", "baked"]:
		# The old check only knew "procedural": flipping the toggle while the
		# DUBSTEP engine played did nothing at all (chat msg 154).
		if music_source != "procedural":
			_stop_dubstep(0.4)
		var theme: StringName = current_theme if current_theme != &"" else _last_theme
		_last_theme = theme
		play_music_loop(_scene_loop_path(_scene_key if _scene_key != "" else String(theme), _scene_mood), true)


## Tag helper: #music=stop | loop:<file> | <theme>.
func request_music(spec: String) -> void:
	if spec == "stop":
		stop_music()
	elif spec.begins_with("loop:"):
		var key: String = spec.substr(5)
		var path: String = key if key.begins_with("res://") else "res://assets/music/%s.ogg" % key
		play_music_loop(path)
	elif DUB_SCENES.has(spec):
		play_dubstep(spec)
	elif spec.begins_with("event:"):
		music_event(spec.substr(6))
	elif spec.begins_with("intensity:"):
		set_music_intensity(float(spec.substr(10)))
	elif SCENE_THEMES.has(spec):
		play_scene(spec)
	elif spec in ["calm", "warm", "tense", "night"] and _scene_key != "":
		play_scene(_scene_key, spec)
	else:
		play_theme(StringName(spec))



## Play SFX by key: OGG if present, else synthesized.
func play_sfx(key: String, pitch: float = 1.0) -> void:
	sfx_played += 1
	last_sfx = key
	last_sfx_pitch = pitch
	var path: String = "res://assets/sfx/%s.ogg" % key
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		last_sfx_source = "ogg"
		_play_stream(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE),
			pitch + _rng.randf_range(-0.02, 0.02))
	else:
		var stream := _engine_sfx_stream(key)
		if stream == null:
			last_sfx_source = "none"
			return
		last_sfx_source = "dubstep"
		_play_stream(stream, pitch + _rng.randf_range(-0.05, 0.05))


## Falling, swelling tone for a hold gesture.
func hold_start() -> void:
	sfx_played += 1
	last_sfx = "hold"
	last_sfx_source = "dubstep"
	if _sfx_muted:
		return
	if _hold_player.stream == null:
		_hold_player.stream = _engine_tone_stream()
	if _hold_player.stream == null:
		last_sfx_source = "none"
		return
	hold_progress(0.0)
	_hold_player.play()


func hold_progress(p: float) -> void:
	var f: float = clampf(p, 0.0, 1.0)
	hold_pitch = 1.4 - 0.65 * f
	last_sfx_pitch = hold_pitch
	_hold_player.pitch_scale = hold_pitch
	_hold_player.volume_db = -18.0 * (1.0 - f)


func hold_stop() -> void:
	if _hold_player.playing:
		_hold_player.stop()


func _play_stream(stream: AudioStream, pitch: float = 1.0) -> void:
	if stream == null or _sfx_muted:
		return
	for p: AudioStreamPlayer in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch
			p.play()
			return
	# All busy: steal the first.
	_sfx_pool[0].stream = stream
	_sfx_pool[0].pitch_scale = pitch
	_sfx_pool[0].play()



## Re-roll plucks that have not been scheduled yet. Sounding notes stay put.
func reroll(new_seed: int = 0) -> void:
	if new_seed == 0:
		new_seed = music_seed ^ int(Time.get_ticks_usec() & 0x7fffffff)
		if new_seed == 0:
			new_seed = 1
	music_seed = new_seed
	_rng.seed = new_seed
	if _engine != null:
		_engine.call("reseed", new_seed)


## ---------------------------------------------------------------- dubstep --
## The show floor is not a calm background: it runs the C dubstep generator
## (native/audio_gen/ag_dubstep.c) live, so intensity and drops follow play.

func _attach_dubstep() -> void:
	if not ClassDB.class_exists("AudioGen"):
		push_warning("AudioDirector: AudioGen extension is not loaded; dubstep falls back to the GDScript synth.")
		return
	_dub = ClassDB.instantiate("AudioGen")
	if _dub == null:
		push_warning("AudioDirector: AudioGen failed to construct; dubstep falls back to the GDScript synth.")
		return
	# Teach the engine our stream rate (one-shots are cut at this rate too),
	# then park it silent until a stage scene asks for it.
	_dub.call("dub_start", 0, 140.0, float(music_seed), float(SAMPLE_RATE))
	_dub.call("dub_release", 0.01)


func has_dubstep_engine() -> bool:
	return _dub != null


## Start (or switch) the live dubstep score. mood tints the intensity only.
func play_dubstep(scene_key: String = "stage", mood: String = "") -> void:
	var variant: int = int(DUB_SCENES.get(scene_key, 0))
	# Random tempo drift (V4): no two entries of a scene at the same bpm.
	var bpm: float = float(DUB_BPM.get(scene_key, 140.0)) + float(_rng.randi_range(-4, 4))
	_scene_key = scene_key
	_scene_mood = mood
	_last_theme = StringName(scene_key)
	if not procedural_enabled:
		play_music_loop(_scene_loop_path(scene_key, mood), true)
		return
	if _dub == null:
		# No AudioGen extension in this export: the OGG loop stands in.
		# Never a GDScript synth again (chat msgs 136-139).
		play_music_loop(_scene_loop_path(scene_key, mood), true)
		return
	if _baked_music():
		# Mobile / user choice: render this variant once, loop the WAV,
		# zero DSP per frame afterwards (chat msg 154).
		_play_baked_dub(scene_key, mood)
		return
	_bake_job = {}  # live mode owns _dub now; a mid-flight bake would corrupt it
	if _engine != null:
		_engine.call("release")
	_fade_out_loops()
	var same := dub_scene == scene_key and music_source == "dubstep"
	dub_scene = scene_key
	music_source = "dubstep"
	current_theme = StringName(scene_key)
	_auto_loop = false
	var base: float = 0.55
	match mood:
		"calm": base = 0.3
		"night": base = 0.35
		"tense": base = 0.9
		"warm": base = 0.5
	dub_intensity = base
	if not same:
		_dub.call("dub_start", variant, bpm, float((music_seed ^ hash(scene_key) ^ _rng.randi()) & 0x7fffffff), float(SAMPLE_RATE))
	_dub.call("dub_set_intensity", base, 0.8 if same else 0.4)
	_ensure_playback()


## 0 = sub and hats only, 1 = full drop energy.
func set_music_intensity(intensity: float, fade: float = 0.6) -> void:
	dub_intensity = clampf(intensity, 0.0, 1.0)
	if music_source == "baked" and dub_scene != "":
		_play_baked_dub(dub_scene, _scene_mood)  # re-bake/crossfade if the bucket moved
		return
	if _dub != null:
		_dub.call("dub_set_intensity", dub_intensity, fade)


## riser | drop | impact | fill | stab | break
const BAKED_EVENT_SFX: Dictionary = {
	"riser": "riser", "build": "riser", "drop": "sub_drop",
	"impact": "impact", "stab": "stab", "fill": "tick", "break": "scratch",
}


func music_event(name: String) -> void:
	if _dub == null or not DUB_EVENTS.has(name):
		return
	dub_events_sent += 1
	if music_source == "baked":
		# The baked loop cannot take live events; the matching one-shot
		# (also C-rendered, cached) carries the accent instead.
		play_event(str(BAKED_EVENT_SFX.get(name, "stab")), clampf(dub_intensity + 0.2, 0.0, 1.0))
		return
	_dub.call("dub_event", int(DUB_EVENTS[name]))



## Pick the best music variant / intensity for the current gameplay phase,
## or switch smoothly between them.
func pick_best_music(phase: String) -> void:
	var key := str(PHASE_ALIASES.get(phase, phase))
	last_phase = key
	if PHASE_CHOICES.has(key):
		var options: Array = PHASE_CHOICES[key]
		# Not the same choice twice in a row when there is a choice.
		var pick: Array = options[_rng.randi_range(0, options.size() - 1)]
		if options.size() > 1 and not last_phase_choice.is_empty() and pick == last_phase_choice:
			pick = options[(options.find(pick) + 1 + _rng.randi_range(0, options.size() - 2)) % options.size()]
		last_phase_choice = pick
		var intensity := clampf(float(pick[1]) + _rng.randf_range(-0.06, 0.06), 0.0, 1.0)
		var fade := _rng.randf_range(0.25, 0.7)
		switch_dubstep(str(pick[0]), intensity, fade)
		if PHASE_EVENTS.has(key):
			var events: Array = PHASE_EVENTS[key]
			music_event(str(events[_rng.randi_range(0, events.size() - 1)]))
	elif DUB_SCENES.has(key):
		switch_dubstep(key)


## Dynamic smooth switch between dubstep variants
func switch_dubstep(scene_key: String, target_intensity: float = -1.0, fade: float = 0.6) -> void:
	if not DUB_SCENES.has(scene_key):
		return
	var variant: int = int(DUB_SCENES[scene_key])
	if target_intensity >= 0.0 and _baked_music() and _dub != null:
		dub_intensity = clampf(target_intensity, 0.0, 1.0)
	if _baked_music() and _dub != null:
		_play_baked_dub(scene_key, _scene_mood)
		return
	var running := false
	if _dub != null and _dub.has_method("dub_active"):
		running = bool(_dub.call("dub_active"))
	if target_intensity >= 0.0:
		dub_intensity = clampf(target_intensity, 0.0, 1.0)
	# Coming from the calm festival score, a plain loop, or silence: the
	# engine has to be STARTED, not merely re-tuned, or the phase stays mute.
	if not running or music_source != "dubstep":
		var wanted := dub_intensity
		play_dubstep(scene_key)
		dub_intensity = wanted
		if _dub != null:
			_dub.call("dub_set_intensity", dub_intensity, fade)
		return
	dub_scene = scene_key
	current_theme = StringName(scene_key)
	if _dub != null:
		if _dub.has_method("dub_switch_mode"):
			_dub.call("dub_switch_mode", variant, dub_intensity, fade)
		else:
			_dub.call("dub_set_intensity", dub_intensity, fade)


func _stop_dubstep(fade: float = 0.8) -> void:
	dub_scene = ""
	_bake_job = {}
	_baked_key = ""
	if _dub != null:
		_dub.call("dub_release", maxf(0.05, fade))
	if music_source == "dubstep":
		music_source = ""
	elif music_source == "baked":
		music_source = ""
		_fade_out_loops()


func _pump_dubstep() -> void:
	if _dub == null:
		music_source = ""
		return
	_ensure_playback()
	if _playback == null:
		return
	var frames: int = mini(_playback.get_frames_available(), _max_push)
	if frames <= 0:
		return
	if _push.size() != frames:
		_push.resize(frames)
	_dub.call("dub_render", _push)
	_playback.push_buffer(_push)
	frames_pushed += frames


## ------------------------------------------------------------ event sounds --
## play_event("gem_hit", 0.9) - collisions, throws, reveals, wins. The waveform
## comes out of the C generator and is cached per energy bucket.
func play_event(key: String, energy: float = 0.8, pitch: float = 1.0) -> void:
	if not DUB_SFX.has(key):
		play_sfx(key, pitch)
		return
	sfx_played += 1
	last_sfx = key
	last_sfx_pitch = pitch
	last_sfx_source = "dubstep" if _dub != null else "synth"
	var stream := _dub_stream(key, energy)
	if stream == null:
		stream = _engine_sfx_stream(key)
	if stream == null:
		last_sfx_source = "none"
		return
	_play_stream(stream, pitch + _rng.randf_range(-0.08, 0.08))


## Cheap ducking hook: a loud collision also nudges the score.
func play_collision(key: String, energy: float = 0.8) -> void:
	play_event(key, energy, 1.0 + (0.5 - energy) * 0.25)
	if energy > 0.75 and _dub != null and music_source == "dubstep":
		_dub.call("dub_event", int(DUB_EVENTS["stab"]))


func _dub_stream(key: String, energy: float) -> AudioStream:
	var kind: int = int(DUB_SFX[key])
	var bucket: int = clampi(int(round(clampf(energy, 0.0, 1.0) * 4.0)), 0, 4)
	# A random take: the generator renders each take from a fresh seed, so
	# the same hit at the same energy still comes out a little different.
	var take: int = _rng.randi_range(0, SFX_TAKES - 1)
	var cache_key := "%s#%d#%d" % [key, bucket, take]
	if _dub_cache.has(cache_key):
		return _dub_cache[cache_key]
	if _dub == null:
		return null
	var frames: int = int(_dub.call("dub_sfx_frames", kind))
	if frames <= 0:
		return null
	var buf := PackedVector2Array()
	buf.resize(frames)
	# Takes after the first are rendered at a jittered energy too (V4).
	var e := clampf(float(bucket) / 4.0 + (0.0 if take == 0 else _rng.randf_range(-0.12, 0.12)), 0.0, 1.0)
	var written: int = int(_dub.call("render_dub_sfx", kind, buf, e))
	if written <= 0:
		return null
	var mono := PackedFloat32Array()
	mono.resize(written)
	for i: int in written:
		mono[i] = buf[i].x
	var stream := _to_wav(mono)
	_dub_cache[cache_key] = stream
	dub_sfx_rendered += 1
	return stream


## ------------------------------------------------------------ baked mode --
## "auto" bakes on phones: web mobile and native mobile lack the headroom to
## run the 48 kHz engines live every frame (chat msg 154).
func _baked_music() -> bool:
	if music_mode == "baked":
		return true
	if music_mode == "live":
		return false
	return OS.has_feature("web_android") or OS.has_feature("web_ios") \
		or (OS.has_feature("mobile") and not OS.has_feature("web"))


## Settings: {"music_mode": "auto"|"live"|"baked"} or legacy {"music_baked": true}.
func _read_music_mode() -> String:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return "auto"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return "auto"
	var data: Dictionary = parsed
	var mode := str(data.get("music_mode", ""))
	if mode in ["auto", "live", "baked"]:
		return mode
	if bool(data.get("music_baked", false)):
		return "baked"
	return "auto"


## Settings hook. Re-triggers the sounding dubstep scene so the switch is
## audible immediately (live engine <-> baked loop).
func set_music_mode(mode: String) -> void:
	if mode not in ["auto", "live", "baked"] or mode == music_mode:
		return
	music_mode = mode
	var key := dub_scene
	if key != "" and music_source in ["dubstep", "baked"]:
		var mood := _scene_mood
		dub_scene = ""
		music_source = ""
		_baked_key = ""
		play_dubstep(key, mood)


## Render 2 bars of a dubstep variant through the C engine into a looped
## 16-bit stereo WAV. Runs ONCE per (variant, intensity bucket) and is
## cached; the first render costs one hitch, every later frame costs zero.
func _play_baked_dub(scene_key: String, mood: String = "") -> void:
	var variant: int = int(DUB_SCENES.get(scene_key, 0))
	var bpm: float = float(DUB_BPM.get(scene_key, 140.0))  # no jitter: cache hits
	var bucket: int = clampi(int(round(dub_intensity * 4.0)), 0, 4)
	var cache_key := "bake|%d|%d" % [variant, bucket]
	_scene_key = scene_key
	_scene_mood = mood
	_last_theme = StringName(scene_key)
	dub_scene = scene_key
	current_theme = StringName(scene_key)
	_auto_loop = false
	if music_source == "baked" and _baked_key == cache_key:
		return
	music_source = "baked"
	_baked_key = cache_key
	if _engine != null:
		_engine.call("release")
	if _gen_player.playing:
		_gen_player.stop()
	_playback = null
	var stream: AudioStream = _dub_cache.get(cache_key)
	if stream != null:
		_bake_job = {}  # a cache hit supersedes any in-flight bake
		_crossfade_to_stream(stream)
		return
	if _dub == null:
		play_music_loop(_scene_loop_path(scene_key, mood), true)
		return
	# Cache miss: bake INCREMENTALLY (chat: "on slow mobile music play with
	# stutters" — a synchronous 4-bar render froze a frame on every first
	# play and every intensity-bucket move). The scene's OGG loop bridges
	# the gap; _pump_bake crossfades to the baked WAV when it is ready.
	_start_bake_job(cache_key, variant, bpm, bucket, scene_key, mood)


func _start_bake_job(cache_key: String, variant: int, bpm: float, bucket: int, scene_key: String, mood: String) -> void:
	if not _bake_job.is_empty() and str(_bake_job.get("key")) == cache_key:
		return  # already baking exactly this loop
	var bar: int = int(float(SAMPLE_RATE) * 60.0 / bpm * 4.0)
	_dub.call("dub_start", variant, bpm, float((music_seed ^ (variant * 7919)) & 0x7fffffff), float(SAMPLE_RATE))
	_dub.call("dub_set_intensity", float(bucket) / 4.0, 0.0)
	_bake_job = {
		"key": cache_key,
		"phase": "render",
		"warm_left": bar * 2,  # ramps/fills settle before the kept bars
		"keep_left": bar * 2,
		"frames": PackedVector2Array(),
		"encode_pos": 0,
		"data": PackedByteArray(),
	}
	# Bridge: keep music sounding while the bake trickles in.
	if not _loop_a.playing and not _loop_b.playing:
		var bridge: String = _scene_loop_path(scene_key, mood)
		music_source = "baked"  # play_music_loop would overwrite these
		var keep_key := _baked_key
		var keep_theme := current_theme
		play_music_loop(bridge, true)
		music_source = "baked"
		_baked_key = keep_key
		current_theme = keep_theme
	# Headless/tests and the very first boot frame: _process may not run
	# this frame, so do one slice right away.
	_pump_bake()


## One time-budgeted slice of bake work per frame. Renders through the C
## engine in small chunks, then encodes to 16-bit in slices; never more
## than ~BAKE_BUDGET_USEC per frame, so no frame ever hitches.
func _pump_bake() -> void:
	if _bake_job.is_empty():
		return
	if _dub == null or music_source == "dubstep":
		_bake_job = {}  # live engine owns _dub; the bake is stale
		return
	var deadline: int = Time.get_ticks_usec() + BAKE_BUDGET_USEC
	while Time.get_ticks_usec() < deadline:
		match str(_bake_job["phase"]):
			"render":
				var chunk := PackedVector2Array()
				var warm: int = int(_bake_job["warm_left"])
				var keep: int = int(_bake_job["keep_left"])
				var n: int = mini(4096, warm + keep)
				if n <= 0:
					_bake_job["phase"] = "encode"
					_dub.call("dub_release", 0.01)
					var total: int = (_bake_job["frames"] as PackedVector2Array).size()
					var data: PackedByteArray = _bake_job["data"]
					data.resize(total * 4)
					_bake_job["data"] = data
					continue
				chunk.resize(n)
				_dub.call("dub_render", chunk)
				if warm > 0:
					_bake_job["warm_left"] = warm - n  # discarded
				else:
					_bake_job["keep_left"] = keep - n
					var frames: PackedVector2Array = _bake_job["frames"]
					frames.append_array(chunk)  # C-speed copy, no GDScript loop
					_bake_job["frames"] = frames
			"encode":
				var frames: PackedVector2Array = _bake_job["frames"]
				var data: PackedByteArray = _bake_job["data"]
				var pos: int = int(_bake_job["encode_pos"])
				var stop: int = mini(pos + 8192, frames.size())
				while pos < stop:
					data.encode_s16(pos * 4, int(clampf(frames[pos].x, -1.0, 1.0) * 32767.0))
					data.encode_s16(pos * 4 + 2, int(clampf(frames[pos].y, -1.0, 1.0) * 32767.0))
					pos += 1
				_bake_job["data"] = data
				_bake_job["encode_pos"] = pos
				if pos >= frames.size():
					_finish_bake_job()
					return
			_:
				_bake_job = {}
				return


func _finish_bake_job() -> void:
	var frames: PackedVector2Array = _bake_job["frames"]
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames.size()
	wav.data = _bake_job["data"]
	var key := str(_bake_job["key"])
	_dub_cache[key] = wav
	_bake_job = {}
	# Only crossfade if this bake is still the loop the director wants.
	if music_source == "baked" and _baked_key == key:
		_crossfade_to_stream(wav)


## Synchronous bake for tests/tools: drives the same incremental job to
## completion in one call. Gameplay never calls this.
func bake_dub_loop_now(scene_key: String, intensity: float = -1.0) -> AudioStreamWAV:
	if _dub == null:
		return null
	if intensity >= 0.0:
		dub_intensity = clampf(intensity, 0.0, 1.0)
	var variant: int = int(DUB_SCENES.get(scene_key, 0))
	var bucket: int = clampi(int(round(dub_intensity * 4.0)), 0, 4)
	var cache_key := "bake|%d|%d" % [variant, bucket]
	if _dub_cache.has(cache_key):
		return _dub_cache[cache_key]
	_start_bake_job(cache_key, variant, float(DUB_BPM.get(scene_key, 140.0)), bucket, scene_key, "")
	var guard: int = 0
	while not _bake_job.is_empty() and guard < 100000:
		_pump_bake()
		guard += 1
	return _dub_cache.get(cache_key)


## Wrap stereo frames in a forward-looped 16-bit WAV.
func _to_wav_stereo(frames: PackedVector2Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames.size()
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for i: int in frames.size():
		data.encode_s16(i * 4, int(clampf(frames[i].x, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(frames[i].y, -1.0, 1.0) * 32767.0))
	wav.data = data
	return wav


func _attach_engine() -> void:
	if not ClassDB.class_exists("SceneScore"):
		push_warning("AudioDirector: SceneScore extension is not loaded; using the GDScript mixer.")
		return
	_engine = ClassDB.instantiate("SceneScore")
	if _engine == null:
		push_warning("AudioDirector: SceneScore failed to construct; using the GDScript mixer.")


## Flat score blob. Layout matches native/scene_score/mix.h.
func _pack_score(score: Dictionary) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(60)
	out[0] = float(score.get("bpm", 72.0))
	out[1] = float(score.get("root", 60))
	out[2] = float(score.get("shape", 0.0))
	out[3] = float(score.get("pad", 0.4))
	out[4] = float(score.get("pluck", 0.2))
	out[5] = float(score.get("bass", 0.3))
	out[6] = float(score.get("plucks", 4))
	out[7] = float(score.get("bass_hits", 1))
	out[8] = float(score.get("pluck_shift", 12))
	out[9] = float(score.get("bass_shift", -12))
	var scale: Array = score.get("scale", [0, 2, 4, 7, 9])
	var scale_n: int = mini(8, scale.size())
	out[10] = scale_n
	for i in scale_n:
		out[11 + i] = float(scale[i])
	var prog: Array = score.get("prog", [[0, 2, 4]])
	var chord_n: int = mini(8, prog.size())
	out[19] = chord_n
	for c in chord_n:
		var chord: Array = prog[c]
		var tones: int = mini(4, chord.size())
		var base: int = 20 + c * 5
		out[base] = tones
		for k in tones:
			out[base + 1 + k] = float(chord[k])
	return out


func _ensure_playback() -> void:
	if _music_muted:
		return
	if not _gen_player.playing:
		_gen_player.play()
	if _playback == null:
		_playback = _gen_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _pump_engine() -> void:
	_ensure_playback()
	if _playback == null:
		return
	var frames: int = mini(_playback.get_frames_available(), _max_push)
	if frames <= 0:
		return
	if _push.size() != frames:
		_push.resize(frames)
	_engine.call("render_into", _push)
	_playback.push_buffer(_push)
	frames_pushed += frames
	notes_scheduled = int(_engine.call("notes_scheduled"))


## ------------------------------------------------- C-rendered UI blips --
## Small one-shots for keys that have no OGG. Rendered ONCE by the AudioGen
## C library and cached; never synthesized in GDScript (chat msg 139).
## Returns null when the extension is missing: silence beats a slow synth.
const C_SFX_PRESETS: Dictionary = {
	"click": 6, "advance": 6, "choice": 6, "blip": 6, "rollback": 3,
	"error": 4, "buzz": 4, "open": 3, "close": 5, "skip": 5, "coin": 0,
}


func _engine_sfx_stream(key: String) -> AudioStream:
	if _dub == null:
		return null
	var cache_key := "sfx|" + key
	if _c_sfx_cache.has(cache_key):
		return _c_sfx_cache[cache_key]
	var preset: int = int(C_SFX_PRESETS.get(key, absi(hash(key)) % 7))
	var buf := PackedVector2Array()
	buf.resize(int(0.3 * SAMPLE_RATE))
	_dub.call("render_sfx", preset, buf)
	var mono := PackedFloat32Array()
	mono.resize(buf.size())
	for i: int in buf.size():
		mono[i] = buf[i].x
	var stream := _to_wav(mono)
	_c_sfx_cache[cache_key] = stream
	return stream


## Sustained FM pad tone for the hold-to-close charge; the player's
## pitch_scale carries the falling pitch (hold_progress).
func _engine_tone_stream() -> AudioStream:
	if _dub == null:
		return null
	if _c_sfx_cache.has("tone|hold"):
		return _c_sfx_cache["tone|hold"]
	var buf := PackedVector2Array()
	buf.resize(SAMPLE_RATE)  # one second at 48 kHz
	_dub.call("render_fm", 2, buf, 220.0)
	var mono := PackedFloat32Array()
	mono.resize(buf.size())
	for i: int in buf.size():
		mono[i] = buf[i].x
	var wav := _to_wav(mono)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = int(0.25 * SAMPLE_RATE)
	wav.loop_end = int(0.75 * SAMPLE_RATE)
	_c_sfx_cache["tone|hold"] = wav
	return wav


## Wrap samples in 16-bit mono WAV.
func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = data
	return wav



## Idempotent bus setup.
## Where the game keeps its settings (the same file the balloon writes).
const SETTINGS_PATH := "user://klima_gem/settings.json"


## Read the saved mixer sliders and push them onto the buses. Safe to call
## at any time; missing or malformed settings leave the buses alone.
func apply_saved_volumes() -> void:
	_ensure_audio_buses()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	for pair: Array in [["vol_master", "Master"], ["vol_music", "Music"], ["vol_voice", "Voice"], ["vol_sfx", "SFX"]]:
		if data.has(pair[0]):
			set_bus_percent(String(pair[1]), float(data[pair[0]]))


## One mixer slider, in percent (0..100), applied to one bus.
func set_bus_percent(bus_name: String, percent: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	var linear: float = clampf(percent, 0.0, 100.0) / 100.0
	AudioServer.set_bus_volume_db(index, linear_to_db(linear) if linear > 0.0 else -80.0)
	_bus_percent[bus_name] = clampf(percent, 0.0, 100.0)
	_update_mute_state()


## Volume 0 turns the audio SYSTEM off, not just the fader (chat msg 154):
## the generator player stops (no dub_render/render_into calls at all) and
## the loop players pause their decoders. Unmuting resumes and refills.
func _update_mute_state() -> void:
	var music_off: bool = _bus_percent.get("Master", 100.0) <= 0.0 \
		or _bus_percent.get("Music", 100.0) <= 0.0
	_sfx_muted = _bus_percent.get("Master", 100.0) <= 0.0 \
		or _bus_percent.get("SFX", 100.0) <= 0.0
	if _sfx_muted and _hold_player != null and _hold_player.playing:
		_hold_player.stop()
	if music_off == _music_muted:
		return
	_music_muted = music_off
	if _music_muted:
		if _gen_player != null and _gen_player.playing:
			_gen_player.stop()
		_playback = null
		for p: AudioStreamPlayer in [_loop_a, _loop_b]:
			if p != null:
				p.stream_paused = true
	else:
		for p: AudioStreamPlayer in [_loop_a, _loop_b]:
			if p != null:
				p.stream_paused = false
	# The generator restarts through _ensure_playback on the next pump.


func _ensure_audio_buses() -> void:
	for bus_name: String in ["Music", "Voice", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")
