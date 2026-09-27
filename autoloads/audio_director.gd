extends Node
## Runtime audio: procedural music, tiny OGG loops and SFX. play_scene()
## starts a live score for the background that just came up. The mix runs in
## the SceneScore C extension: each frame is generated, a scene change
## crossfades, a mood adjusts the score that is already playing, and reroll()
## reseeds plucks that have not been scheduled yet. Nothing is baked to a loop
## or a WAV. The GDScript mixer below is only the fallback if that library is
## missing. play_music_loop() is the "Generated music" off path.


const SAMPLE_RATE: int = 22050        ## stream rate
const MAX_PUSH_PER_FRAME: int = 4096  ## ~0.19 s of audio per process frame
const LOOKAHEAD: float = 0.6          ## notes scheduled this far ahead
const BLOCK: int = 256                ## render quantum; events snap to blocks
const MUSIC_GAIN: float = 0.5         ## peak theme level on top of the bus slider
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
	"stage_defeat": 110.0,
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
var _playhead: float = 0.0
var _next_bar: float = 0.0
var _bar_index: int = 0
var _queue: Array[Dictionary] = []

## Voices as parallel arrays: kind 0 pad, 1 pluck, 2 bass.
var _v_px := PackedFloat64Array()
var _v_py := PackedFloat64Array()
var _v_dx := PackedFloat64Array()
var _v_dy := PackedFloat64Array()
var _v_t := PackedFloat64Array()
var _v_dur := PackedFloat64Array()
var _v_atk := PackedFloat64Array()
var _v_rel := PackedFloat64Array()
var _v_peak := PackedFloat64Array()
var _v_tau := PackedFloat64Array()
var _v_gl := PackedFloat64Array()
var _v_gr := PackedFloat64Array()
var _v_kind := PackedFloat64Array()
var _voice_count: int = 0

## Crossfade gain + last theme.
var _gain: float = 0.0
var _gain_target: float = 0.0
var _last_theme: StringName = &""


var _loop_a: AudioStreamPlayer
var _loop_b: AudioStreamPlayer
var _loop_path: String = ""
var _auto_loop: bool = false   ## true when the loop was a procedural fallback

var _sfx_pool: Array[AudioStreamPlayer] = []
var _hold_player: AudioStreamPlayer
var hold_pitch: float = 1.4            ## hold tone pitch (falls as it fills)
var _synth_cache: Dictionary = {}   ## synth blips, on first use
var _engine: Object = null          ## SceneScore, when the extension loaded
var _dub: Object = null             ## AudioGen, the C dubstep engine
var dub_scene: String = ""          ## active dubstep scene key ("" when off)
var dub_intensity: float = 0.55     ## last requested intensity
var dub_events_sent: int = 0        ## #music_event calls that reached the engine
var dub_sfx_rendered: int = 0       ## one-shots pulled out of the C generator
var _dub_cache: Dictionary = {}     ## key|energy bucket -> AudioStreamWAV
var _push := PackedVector2Array()  ## reused generator buffer


func _ready() -> void:
	_ensure_audio_buses()
	# The saved mixer sliders must be live before the FIRST note: the main
	# menu plays its theme long before any balloon exists to apply them.
	apply_saved_volumes()
	_gen = AudioStreamGenerator.new()
	_gen.mix_rate = SAMPLE_RATE
	_gen.buffer_length = 0.25
	_gen_player = AudioStreamPlayer.new()
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


func _process(delta: float) -> void:
	if music_source == "dubstep":
		_pump_dubstep()
		return
	if _engine != null:
		if bool(_engine.call("active")):
			_pump_engine()
		return
	if music_source != "procedural" and _gain <= 0.0005 and _gain_target <= 0.0005:
		return
	_ramp_gain(delta)
	_pump()


## Drop stream refs before teardown (fewer shutdown leaks).
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		var players: Array[AudioStreamPlayer] = [_gen_player, _loop_a, _loop_b, _hold_player]
		players.append_array(_sfx_pool)
		for p: AudioStreamPlayer in players:
			if is_instance_valid(p):
				p.stop()
				p.stream = null
		_synth_cache.clear()
		_dub_cache.clear()
		_playback = null


## Ramp the crossfade gain.
func _ramp_gain(delta: float) -> void:
	_gain = move_toward(_gain, _gain_target, delta * 0.85)



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


func _begin_score(theme_name: StringName, score: Dictionary) -> void:
	_fade_out_loops()
	_theme = score
	current_theme = theme_name
	music_source = "procedural"
	_auto_loop = false
	var seed_value := hash(String(theme_name) + _scene_mood) ^ music_seed ^ int(_rng.randi() & 0x7fffffff)
	_rng.seed = seed_value
	if _engine != null:
		var first := not bool(_engine.call("active"))
		_engine.call("transition", _pack_score(score), 0.35 if first else 0.8, hash(String(theme_name)), seed_value)
		_ensure_playback()
		return
	_bar_index = 0
	_queue.clear()
	_voice_count = 0
	_trim_voices()
	_next_bar = _playhead + 0.02
	_gain_target = MUSIC_GAIN
	_ensure_playback()


## Crossfade to an OGG loop; as_fallback marks a stand-in for the engine.
func play_music_loop(path: String, as_fallback: bool = false) -> void:
	if music_source == "loop" and _loop_path == path:
		return
	_gain_target = 0.0  # fade the procedural engine out under the loop
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
	var fresh := _loop_b if _loop_a.playing else _loop_a
	var stale := _loop_a if fresh == _loop_b else _loop_b
	fresh.stream = stream
	fresh.volume_db = LOOP_SILENT_DB
	fresh.play()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(fresh, "volume_db", LOOP_DB, 0.8)
	if stale.playing:  # crossfade the previous loop out under the new one
		tw.tween_property(stale, "volume_db", LOOP_SILENT_DB, 0.8)
		tw.chain().tween_callback(stale.stop)


## Fade everything out.
func stop_music(fade: float = 0.8) -> void:
	_gain_target = 0.0
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
	_queue.clear()
	_voice_count = 0
	_trim_voices()
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
	elif music_source == "procedural":
		var theme: StringName = current_theme if current_theme != &"" else _last_theme
		_last_theme = theme
		play_music_loop(_scene_loop_path(String(theme), _scene_mood), true)


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
		last_sfx_source = "synth"
		_play_stream(_synth_stream(key), pitch + _rng.randf_range(-0.05, 0.05))


## Falling, swelling tone for a hold gesture.
func hold_start() -> void:
	sfx_played += 1
	last_sfx = "hold"
	last_sfx_source = "synth"
	if _hold_player.stream == null:
		_hold_player.stream = _synth_stream("holdtone")
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
	if stream == null:
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
		# No extension: the pad/pluck mixer plays the most driving score we have.
		_begin_score(StringName(scene_key), (SCENE_THEMES["rift"] as Dictionary).duplicate(true))
		return
	if _engine != null:
		_engine.call("release")
	_fade_out_loops()
	_gain_target = 0.0
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
	if _dub != null:
		_dub.call("dub_set_intensity", dub_intensity, fade)


## riser | drop | impact | fill | stab | break
func music_event(name: String) -> void:
	if _dub == null or not DUB_EVENTS.has(name):
		return
	dub_events_sent += 1
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
	if _dub != null:
		_dub.call("dub_release", maxf(0.05, fade))
	if music_source == "dubstep":
		music_source = ""


func _pump_dubstep() -> void:
	if _dub == null:
		music_source = ""
		return
	_ensure_playback()
	if _playback == null:
		return
	var frames: int = mini(_playback.get_frames_available(), MAX_PUSH_PER_FRAME)
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
		last_sfx_source = "synth"
		_play_stream(_synth_stream(key), pitch)
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
	if not _gen_player.playing:
		_gen_player.play()
	if _playback == null:
		_playback = _gen_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _pump_engine() -> void:
	_ensure_playback()
	if _playback == null:
		return
	var frames: int = mini(_playback.get_frames_available(), MAX_PUSH_PER_FRAME)
	if frames <= 0:
		return
	if _push.size() != frames:
		_push.resize(frames)
	_engine.call("render_into", _push)
	_playback.push_buffer(_push)
	frames_pushed += frames
	notes_scheduled = int(_engine.call("notes_scheduled"))


func _pump() -> void:
	if _playback == null:
		if _gen_player.playing:
			_playback = _gen_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if _playback == null:
			return
	var frames: int = mini(_playback.get_frames_available(), MAX_PUSH_PER_FRAME)
	if frames <= 0:
		return
	# Schedule upcoming bars while the theme plays.
	if music_source == "procedural" and not _theme.is_empty():
		var bar_len: float = 60.0 / float(_theme["bpm"]) * 4.0
		while _next_bar < _playhead + LOOKAHEAD:
			_schedule_bar(_bar_index, _next_bar)
			_next_bar += bar_len
			_bar_index += 1
	_playback.push_buffer(_render_frames(frames))
	frames_pushed += frames


func _render_frames(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	var pos: int = 0
	var inv_sr: float = 1.0 / SAMPLE_RATE
	while pos < n:
		var block: int = mini(BLOCK, n - pos)
		var block_end: float = _playhead + float(block) * inv_sr
		while not _queue.is_empty() and _queue[0]["t"] <= block_end:
			_spawn_voice(_queue.pop_front())
		for i in block:
			var l: float = 0.0
			var r: float = 0.0
			var vi: int = 0
			while vi < _voice_count:
				var t: float = _v_t[vi]
				var env: float
				var kind: float = _v_kind[vi]
				if kind > 0.5 and kind < 1.5:  # pluck: fast attack, exp decay
					env = exp(-t / _v_tau[vi])
					if t < _v_atk[vi]:
						env *= t / _v_atk[vi]
				elif t < _v_atk[vi]:  # pad/bass: linear attack, hold, release
					env = t / _v_atk[vi]
				elif t < _v_dur[vi] - _v_rel[vi]:
					env = 1.0
				else:
					env = maxf(0.0, (_v_dur[vi] - t) / _v_rel[vi])
				if env <= 0.0002 and t > _v_atk[vi]:
					# Dead voice: swap-remove.
					_voice_count -= 1
					_copy_voice(vi, _voice_count)
					_trim_voices()
					continue
				var raw: float = _v_py[vi]
				var shape: float = float(_theme.get("shape", 0.0)) if not _theme.is_empty() else 0.0
				if shape >= 2.0:
					raw = signf(raw) * 0.72 + raw * 0.28
				elif shape >= 1.0:
					raw = asin(clampf(raw, -1.0, 1.0)) * 0.63662
				var s: float = raw * env * _v_peak[vi]
				l += s * _v_gl[vi]
				r += s * _v_gr[vi]
				# Rotate.
				var px: float = _v_px[vi]
				var py: float = _v_py[vi]
				_v_px[vi] = px * _v_dx[vi] - py * _v_dy[vi]
				_v_py[vi] = px * _v_dy[vi] + py * _v_dx[vi]
				_v_t[vi] = t + inv_sr
				vi += 1
			# Saturation.
			l = l / (1.0 + absf(l)) * 1.4
			r = r / (1.0 + absf(r)) * 1.4
			out[pos + i] = Vector2(l * _gain, r * _gain)
		pos += block
		_playhead += float(block) * inv_sr
	return out


func _voice_arrays() -> Array:
	return [_v_px, _v_py, _v_dx, _v_dy, _v_t, _v_dur, _v_atk, _v_rel,
		_v_peak, _v_tau, _v_gl, _v_gr, _v_kind]


func _copy_voice(from_i: int, to_i: int) -> void:
	if from_i != to_i:
		for a: PackedFloat64Array in _voice_arrays():
			a[from_i] = a[to_i]



func _trim_voices() -> void:
	for a: PackedFloat64Array in _voice_arrays():
		a.resize(_voice_count)


## Scale degree -> MIDI note (wraps across octaves).
func _degree_midi(deg: int, root: int, scale: Array) -> int:
	var n: int = scale.size()
	var oct: int = floori(float(deg) / float(n))
	return root + 12 * oct + scale[posmod(deg, n)]


## Queue one 4/4 bar of pad, bass and arpeggio at time `bt`.
func _schedule_bar(bar: int, bt: float) -> void:
	var bar_len: float = 60.0 / float(_theme["bpm"]) * 4.0
	var prog: Array = _theme["prog"]
	var chord: Array = prog[bar % prog.size()]
	var root: int = int(_theme["root"])
	var scale: Array = _theme["scale"]
	# Pad: chord tones up an octave, slight overlap into the next bar.
	for i: int in chord.size():
		_queue.append({"t": bt, "midi": _degree_midi(int(chord[i]) + 7, root, scale),
			"kind": 0, "dur": bar_len * 1.15, "peak": float(_theme["pad"]) / chord.size(),
			"pan": 0.22 if i % 2 == 1 else -0.22})
		notes_scheduled += 1
	# Bass on the root. Scene scores may sit an octave lower than the demo moods.
	var bass_shift: int = int(_theme.get("bass_shift", -12))
	var hits: int = int(_theme["bass_hits"])
	for h: int in hits:
		var t: float = bt + bar_len * 0.5 * h
		_queue.append({"t": t, "midi": _degree_midi(int(chord[0]), root, scale) + bass_shift,
			"kind": 2, "dur": bar_len * 0.45, "peak": float(_theme["bass"]), "pan": 0.0})
		notes_scheduled += 1
	# Arpeggio: one pluck per plucks-th of the bar.
	var pluck_shift: int = int(_theme.get("pluck_shift", 12))
	var plucks: int = int(_theme["plucks"])
	for k in plucks:
		var t: float = bt + bar_len * (float(k) / plucks)
		var deg: int = int(chord[(k + bar) % chord.size()])
		var midi: int = _degree_midi(deg, root, scale) + pluck_shift
		if plucks >= 8 and k % 3 == 2:
			midi += 12
		_queue.append({"t": t, "midi": midi, "kind": 1, "dur": bar_len * 0.6,
			"peak": float(_theme["pluck"]), "pan": _rng.randf_range(-0.35, 0.35)})
		notes_scheduled += 1


func _spawn_voice(ev: Dictionary) -> void:
	var kind: int = int(ev["kind"])
	var peak: float = float(ev["peak"])
	var pan: float = float(ev.get("pan", 0.0))
	if kind == 0:
		# Two detuned partials per pad note (soft chorus).
		_add_voice(ev, peak * 0.5, pan, -0.0022)
		_add_voice(ev, peak * 0.5, -pan, 0.0022)
	else:
		_add_voice(ev, peak, pan, 0.0)


func _add_voice(ev: Dictionary, peak: float, pan: float, detune: float) -> void:
	if _voice_count >= 48:
		return
	var freq: float = 440.0 * pow(2.0, (float(ev["midi"]) - 69.0) / 12.0) * (1.0 + detune)
	var ang: float = TAU * freq / SAMPLE_RATE
	var kind: int = int(ev["kind"])
	_voice_count += 1
	_v_px.append(1.0)
	_v_py.append(0.0)
	_v_dx.append(cos(ang))
	_v_dy.append(sin(ang))
	_v_t.append(0.0)
	_v_dur.append(float(ev["dur"]))
	if kind == 1:
		_v_atk.append(0.004)
		_v_rel.append(0.05)
		_v_tau.append(float(ev["dur"]) / 4.5)
	elif kind == 2:
		_v_atk.append(0.02)
		_v_rel.append(0.18)
		_v_tau.append(1.0)
	else:
		_v_atk.append(minf(0.6, float(ev["dur"]) * 0.35))
		_v_rel.append(minf(0.8, float(ev["dur"]) * 0.4))
		_v_tau.append(1.0)
	_v_peak.append(peak)
	_v_gl.append(1.0 - 0.6 * maxf(pan, 0.0))
	_v_gr.append(1.0 - 0.6 * maxf(-pan, 0.0))
	_v_kind.append(float(kind))



## Render + cache a blip; unknown kinds -> click.
func _synth_stream(kind: String) -> AudioStream:
	if _synth_cache.has(kind):
		return _synth_cache[kind]
	var samples := PackedFloat32Array()
	if kind == "open":
		samples = _synth_sweep(420.0, 950.0, 0.13)
	elif kind == "close":
		samples = _synth_sweep(900.0, 380.0, 0.13)
	elif kind == "confirm":
		samples = _synth_chime([659.25, 880.0], 0.07)
	elif kind == "save" or kind == "chime":
		samples = _synth_chime([523.25, 659.25, 783.99], 0.1)
	elif kind == "error":
		samples = _synth_buzz()
	elif kind == "click":
		samples = _synth_click()
	else:
		samples = _synth_click()
	var stream := _to_wav(samples)
	_synth_cache[kind] = stream
	return stream


func _synth_click() -> PackedFloat32Array:
	var n: int = int(0.025 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var e: float = exp(-t / 0.0045)
		out[i] = (_noise_rng.randf_range(-0.5, 0.5) + sin(TAU * 1600.0 * t) * 0.8) * e * 0.7
	return out


func _synth_sweep(f0: float, f1: float, dur: float) -> PackedFloat32Array:
	var n: int = int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	for i in n:
		var x: float = float(i) / n
		var freq: float = f0 * pow(f1 / f0, x)
		phase += TAU * freq / SAMPLE_RATE
		var t: float = float(i) / SAMPLE_RATE
		out[i] = sin(phase) * exp(-t / (dur * 0.7)) * 0.8
	return out


func _synth_chime(freqs: Array, step: float) -> PackedFloat32Array:
	var n: int = int((step * freqs.size() + 0.2) * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in freqs.size():
		var start: int = int(k * step * SAMPLE_RATE)
		var f: float = float(freqs[k])
		for i in range(start, n):
			var t: float = float(i - start) / SAMPLE_RATE
			out[i] += (sin(TAU * f * t) + 0.35 * sin(TAU * 2.0 * f * t)) * exp(-t / 0.09) * 0.55
	return out


func _synth_buzz() -> PackedFloat32Array:
	var beep: int = int(0.09 * SAMPLE_RATE)
	var gap: int = int(0.05 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(beep * 2 + gap)
	for i in beep:
		var t: float = float(i) / SAMPLE_RATE
		var e: float = exp(-t / 0.035)
		var v: float = (0.6 if fposmod(196.0 * t, 1.0) < 0.5 else -0.6) + sin(TAU * 196.0 * t) * 0.5
		out[i] = v * e * 0.7
		out[beep + gap + i] = v * e * 0.7
	return out


## Sustained soft tone for the hold-to-close charge (pitch = progress).
func _synth_holdtone() -> PackedFloat32Array:
	var n: int = int(1.0 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in n:
		var t: float = float(i) / SAMPLE_RATE
		out[i] = (sin(TAU * 330.0 * t) + 0.25 * sin(TAU * 660.0 * t)) * minf(1.0, t / 0.02) * 0.35
	return out


var _noise_rng := RandomNumberGenerator.new()


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


func _ensure_audio_buses() -> void:
	for bus_name: String in ["Music", "Voice", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")
