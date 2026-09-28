extends Node
## Dubstep audio tests: the C generator (native/audio_gen/ag_dubstep.c) through
## the AudioGen extension, the AudioDirector stage-music path, dynamic music
## switcher (pick_best_music), all event sounds (jump, shoot, bell_hit, choir
## pads, gem roll & plaque placement, challenge victory/loss, overall victory/loss)
## and gem collision sounds. Headless-safe: no audio device needed.

var checks := 0
var fails := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	await get_tree().process_frame
	_test_extension()
	_test_one_shots()
	_test_director_music()
	_test_music_picker()
	_test_event_sounds()
	_test_victory_loss_hooks()
	_test_baked_mode()
	await _test_mute_kill_switch()
	_test_generated_toggle()
	await _test_gem_collision()
	print("checks=%d fails=%d" % [checks, fails])
	if fails == 0:
		print("DUBSTEP AUDIO TESTS: PASS")
	else:
		print("DUBSTEP AUDIO TESTS: FAIL")
	get_tree().quit(1 if fails > 0 else 0)


func _test_extension() -> void:
	# The AudioGen GDExtension needs Godot 4.7. On an older engine the whole
	# C layer is absent: the fallbacks are still checked, the C checks skip.
	if not ClassDB.class_exists("AudioGen"):
		print("SKIP: AudioGen extension not loaded (needs Godot 4.7) - C checks skipped")
		return
	var gen: Object = ClassDB.instantiate("AudioGen")
	ok(gen != null, "AudioGen constructs")
	if gen == null:
		return
	for m: String in ["dub_start", "dub_set_intensity", "dub_event", "dub_trigger",
			"dub_render", "dub_release", "dub_active", "render_dub_sfx", "dub_sfx_frames", "dub_switch_mode"]:
		ok(gen.has_method(m), "AudioGen exposes %s" % m)
	gen.call("dub_start", 0, 140.0, 20260927.0, 22050.0)
	ok(bool(gen.call("dub_active")), "engine is active after dub_start")
	var buf := PackedVector2Array()
	buf.resize(22050)
	gen.call("dub_render", buf)
	var peak := 0.0
	var energy := 0.0
	for i: int in buf.size():
		var a: float = absf(buf[i].x)
		peak = maxf(peak, a)
		energy += a
	ok(peak > 0.05, "live dubstep renders audio (peak %.3f)" % peak)
	ok(peak <= 1.01, "live dubstep stays inside 0 dBFS")
	ok(energy / float(buf.size()) > 0.005, "live dubstep has body")

	# Test dynamic mode switching in C
	gen.call("dub_switch_mode", 4, 0.95, 0.1)  # AG_DUB_VARIANT_GROOVE
	gen.call("dub_event", 1)  # drop
	var buf2 := PackedVector2Array()
	buf2.resize(22050)
	gen.call("dub_render", buf2)
	var e2 := 0.0
	for i: int in buf2.size():
		e2 += absf(buf2[i].x)
	ok(e2 > 0.0, "engine keeps rendering after a switch to groove and drop")
	gen.call("dub_release", 0.05)
	var buf3 := PackedVector2Array()
	buf3.resize(22050)
	gen.call("dub_render", buf3)
	ok(not bool(gen.call("dub_active")), "release silences the engine")


func _test_one_shots() -> void:
	if not ClassDB.class_exists("AudioGen"):
		return
	var gen: Object = ClassDB.instantiate("AudioGen")
	gen.call("dub_start", 0, 140.0, 7.0, 22050.0)
	var quiet: Array[String] = []
	for key: String in AudioDirector.DUB_SFX.keys():
		var kind: int = int(AudioDirector.DUB_SFX[key])
		var frames: int = int(gen.call("dub_sfx_frames", kind))
		ok(frames > 200, "%s has a body (%d frames)" % [key, frames])
		var buf := PackedVector2Array()
		buf.resize(frames)
		var written: int = int(gen.call("render_dub_sfx", kind, buf, 0.9))
		ok(written > 0 and written <= frames, "%s renders" % key)
		var peak := 0.0
		for i: int in written:
			peak = maxf(peak, absf(buf[i].x))
		if peak <= 0.02:
			quiet.append(key)
	ok(quiet.is_empty(), "every event sound is audible (silent: %s)" % str(quiet))


func _test_director_music() -> void:
	var a := AudioDirector
	a.procedural_enabled = true
	# festival is the calm one and must stay on the pad/pluck score
	a.play_scene("festival")
	ok(a.music_source == "procedural", "festival stays on the calm score")
	ok(String(a.current_theme) == "festival", "festival theme selected")
	ok(a.dub_scene == "", "festival does not start the dubstep engine")

	# A phase pick straight out of the calm festival score must START the
	# engine (this is how the Echo Choir used to play in silence).
	a.pick_best_music("challenge_run")
	if a.has_dubstep_engine():
		ok(a.music_source == "dubstep", "a phase pick from festival starts the dubstep engine")
		ok(bool(a._dub.call("dub_active")), "the engine is actually running after the pick")
		ok(a.dub_intensity >= 0.85, "and the pick's intensity survived the start (%.2f)" % a.dub_intensity)
	a.play_scene("festival")

	# the show floor is active music
	a.play_dubstep("stage")
	if a.has_dubstep_engine():
		ok(a.music_source == "dubstep", "stage runs the dubstep engine")
		ok(a.dub_scene == "stage", "stage scene recorded")
		a.set_music_intensity(0.9, 0.1)
		ok(is_equal_approx(a.dub_intensity, 0.9), "intensity applied")
		var before: int = a.dub_events_sent
		a.music_event("riser")
		a.music_event("drop")
		ok(a.dub_events_sent == before + 2, "music events reach the engine")
		a.music_event("not_an_event")
		ok(a.dub_events_sent == before + 2, "unknown events are ignored")
		a.request_music("stage_trial")
		ok(a.dub_scene == "stage_trial", "#music=stage_trial switches variant")

	# going back to a scored scene releases the dubstep engine
	a.play_scene("classroom")
	ok(a.music_source == "procedural", "scene music takes over from dubstep")
	ok(a.dub_scene == "", "dubstep released on scene change")
	a.stop_music(0.05)


func _test_music_picker() -> void:
	var a := AudioDirector
	a.procedural_enabled = true

	# Test picking music across primary game states. The picker is RANDOM
	# within each phase's candidates (human: no fixed selection), so a pick
	# must land on one of them, in the right intensity band, and many picks
	# must not all land on the same one.
	var phases := {
		"gem_1_rolled": [0.6, 0.9], "both_revealed": [0.78, 1.0], "challenge_run": [0.85, 1.0],
		"challenge_victory": [0.8, 1.0], "challenge_loss": [0.3, 0.6],
		"overall_victory": [0.9, 1.0], "overall_loss": [0.2, 0.5],
	}
	for phase in phases:
		var allowed: Array = []
		for opt in a.PHASE_CHOICES[phase]:
			allowed.append(str(opt[0]))
		var seen := {}
		for i in 12:
			a.pick_best_music(phase)
			seen[a.dub_scene] = true
			ok(allowed.has(a.dub_scene), "%s picks one of its candidates (%s)" % [phase, a.dub_scene])
			var band: Array = phases[phase]
			ok(a.dub_intensity >= float(band[0]) - 0.001 and a.dub_intensity <= float(band[1]) + 0.001, "%s intensity in band (%.2f)" % [phase, a.dub_intensity])
		ok(allowed.size() < 2 or seen.size() > 1, "%s does not always pick the same variant" % phase)
	ok(a.PHASE_ALIASES.has("trial_win"), "phase aliases resolve the director's names")
	# Music seed is fresh per boot: two directors never share a score seed
	# unless pinned.
	ok(a.randomize_music_on_boot, "music seed is randomised at boot")
	# One-shots come in several takes.
	a._dub_cache.clear()
	var takes := {}
	for i in 24:
		var st := a._dub_stream("gem_hit", 0.8)
		if st != null:
			takes[st] = true
	ok(a._dub == null or takes.size() > 1, "gem_hit is rendered in more than one take (%d)" % takes.size())

	a.stop_music(0.05)


func _test_event_sounds() -> void:
	var a := AudioDirector
	# Check all specific newly added one-shots
	for sfx_key in ["jump", "shoot", "bell_hit", "pad_note", "plaque_place"]:
		ok(AudioDirector.DUB_SFX.has(sfx_key), "DUB_SFX includes %s" % sfx_key)
		var before: int = a.sfx_played
		a.play_event(sfx_key, 0.85)
		ok(a.sfx_played == before + 1, "play_event counts for %s" % sfx_key)
		ok(a.last_sfx == sfx_key, "play_event recorded %s" % sfx_key)


func _test_victory_loss_hooks() -> void:
	var sd := ShowDirector
	ok(sd.has_method("on_show_victory"), "ShowDirector has on_show_victory")
	ok(sd.has_method("on_show_defeat"), "ShowDirector has on_show_defeat")

	var a := AudioDirector
	var before: int = a.sfx_played

	sd.on_show_victory()
	ok(a.sfx_played > before, "on_show_victory triggers audio SFX")
	ok(a.dub_scene in ["stage_victory", "stage_groove"], "on_show_victory switches music to a victory variant (%s)" % a.dub_scene)

	before = a.sfx_played
	sd.on_show_defeat()
	ok(a.sfx_played > before, "on_show_defeat triggers audio SFX")
	ok(a.dub_scene in ["stage_defeat", "stage_chill"], "on_show_defeat switches music to a defeat variant (%s)" % a.dub_scene)

	a.stop_music(0.05)


## Chat msg 154: baked mode renders a variant once into a looped WAV and
## plays it through the loop players — zero per-frame DSP afterwards.
func _test_baked_mode() -> void:
	var a := AudioDirector
	if not a.has_dubstep_engine():
		print("SKIP: baked mode needs the AudioGen extension")
		return
	a.procedural_enabled = true
	a.set_music_mode("baked")
	ok(a.music_mode == "baked", "music_mode switches to baked")
	a.play_dubstep("stage")
	ok(a.music_source == "baked", "baked mode plays a baked loop, not the live engine")
	ok(a.dub_scene == "stage", "baked mode still records the dub scene")
	var loop_playing := false
	var wav_ok := false
	for p_name in ["LoopA", "LoopB"]:
		var p: AudioStreamPlayer = a.get_node(p_name)
		if p.playing and p.stream is AudioStreamWAV:
			loop_playing = true
			var wav: AudioStreamWAV = p.stream
			wav_ok = wav.stereo and wav.mix_rate == a.SAMPLE_RATE \
				and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.data.size() > 0
	ok(loop_playing, "a loop player carries the baked WAV")
	ok(wav_ok, "baked WAV is stereo, 48 kHz, forward-looped, non-empty")
	var cached: int = a._dub_cache.size()
	a.play_dubstep("stage")
	ok(a._dub_cache.size() == cached, "re-entering the scene reuses the baked cache")
	a.switch_dubstep("stage_trial", 0.9)
	ok(a.music_source == "baked" and a.dub_scene == "stage_trial", "baked switch changes variant")
	var before: int = a.dub_events_sent
	a.music_event("drop")
	ok(a.dub_events_sent == before + 1, "baked music events count (one-shot accent)")
	a.set_music_mode("live")
	a.play_dubstep("stage")
	ok(a.music_source == "dubstep", "live mode returns to the streaming engine")
	a.stop_music(0.05)


## Chat msg 154: volume 0 must stop the audio system, not just fade it.
func _test_mute_kill_switch() -> void:
	var a := AudioDirector
	if not a.has_dubstep_engine():
		print("SKIP: mute kill switch needs the AudioGen extension")
		return
	a.procedural_enabled = true
	a.set_music_mode("live")
	a.play_dubstep("stage")
	var gen: AudioStreamPlayer = a.get_node("ProceduralMusic")
	ok(gen.playing, "generator player runs while unmuted")
	a.set_bus_percent("Music", 0.0)
	ok(not gen.playing, "Music at 0 stops the generator player")
	var pushed: int = a.frames_pushed
	await get_tree().process_frame
	await get_tree().process_frame
	ok(a.frames_pushed == pushed, "no frames are rendered while muted")
	a.set_bus_percent("Music", 80.0)
	await get_tree().process_frame
	await get_tree().process_frame
	ok(a.frames_pushed > pushed, "unmuting resumes rendering")
	a.set_bus_percent("Master", 0.0)
	ok(not gen.playing, "Master at 0 also stops the generator")
	a.set_bus_percent("Master", 100.0)
	a.stop_music(0.05)


## Chat msg 154: the Generated-music toggle must also work DURING dubstep.
func _test_generated_toggle() -> void:
	var a := AudioDirector
	if not a.has_dubstep_engine():
		print("SKIP: toggle test needs the AudioGen extension")
		return
	a.procedural_enabled = true
	a.set_music_mode("live")
	a.play_dubstep("stage")
	ok(a.music_source == "dubstep", "dubstep runs before the toggle")
	a.set_procedural_enabled(false)
	ok(a.music_source == "loop", "toggle OFF during dubstep switches to the OGG loop")
	a.set_procedural_enabled(true)
	ok(a.music_source == "dubstep", "toggle ON returns to the dubstep engine")
	a.stop_music(0.05)


func _test_gem_collision() -> void:
	var root := Node3D.new()
	add_child(root)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 0.4, 6)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.2, 0)
	root.add_child(floor_body)

	var gem := FlatTopGem.new()
	gem.physical = true
	root.add_child(gem)
	gem.position = Vector3(0, 1.4, 0)
	gem.freeze = false
	var hits: Array[float] = []
	gem.collided.connect(func(energy: float, _settling: bool) -> void: hits.append(energy))
	for i: int in 240:
		await get_tree().physics_frame
		if gem.collision_sfx > 0 and gem.position.y < 0.4:
			break
	ok(gem.collision_sfx > 0, "a dropped gem makes a collision sound")
	ok(not hits.is_empty(), "collided signal carries the impact")
	if not hits.is_empty():
		ok(hits[0] > 0.0 and hits[0] <= 1.0, "impact energy is normalised (%.2f)" % hits[0])
	root.queue_free()
