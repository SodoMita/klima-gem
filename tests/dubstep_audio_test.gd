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
	_test_fallback_dubstep()
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

## Regression for GitHub Pages (web build, no GDExtension): stage scenes must
## produce real dubstep-like audio out of the GDScript fallback, not the rift
## pad/pluck score. Also covers the new event one-shot fallback path.
func _test_fallback_dubstep() -> void:
	var a := AudioDirector
	a.procedural_enabled = true
	# Pretend the C engine is not loaded.
	var saved_dub: Object = a._dub
	a._dub = null
	# Stage scene should start the fallback engine, NOT the rift pad score.
	a.play_dubstep("stage")
	ok(a._dub_fallback, "fallback flag is on when the C engine is absent")
	ok(a.music_source == "dubstep", "stage still routes through dubstep source")
	ok(a.dub_scene == "stage", "stage scene recorded under fallback")
	ok(a._dub_active, "fallback engine marked active")
	# Push a few frames of audio and confirm it actually contains signal.
	var astream := AudioStreamGenerator.new()
	astream.mix_rate = a.SAMPLE_RATE
	astream.buffer_length = 0.25
	# Drive the pump directly: pick_best_music and friends expect the
	# autoload's own generator, so re-use it.
	var frames: int = 2048
	if a._push.size() != frames:
		a._push.resize(frames)
	a._pump_dubstep_fallback()
	var peak := 0.0
	var energy := 0.0
	for i: int in a._push.size():
		var v: float = absf(a._push[i].x)
		peak = maxf(peak, v)
		energy += v
	ok(peak > 0.02, "fallback renders non-silent dubstep (peak %.3f)" % peak)
	ok(energy / float(frames) > 0.001, "fallback has audible body (avg %.4f)" % (energy / float(frames)))

	# Variant differences: chill is calmer than groove.
	a.play_dubstep("stage_chill")
	var quiet_peak := 0.0
	var quiet_energy := 0.0
	for _i in 4:
		a._pump_dubstep_fallback()
	for i: int in a._push.size():
		var v: float = absf(a._push[i].x)
		quiet_peak = maxf(quiet_peak, v)
		quiet_energy += v
	a.play_dubstep("stage_groove")
	var hot_peak := 0.0
	var hot_energy := 0.0
	for _i in 4:
		a._pump_dubstep_fallback()
	for i: int in a._push.size():
		var v: float = absf(a._push[i].x)
		hot_peak = maxf(hot_peak, v)
		hot_energy += v
	ok(hot_peak + 0.0001 >= quiet_peak or hot_energy >= quiet_energy, "groove is at least as loud as chill (hot=%.3f quiet=%.3f)" % [hot_peak, quiet_peak])

	# music_event arms the fallback layer.
	a.music_event("drop")
	ok(a._dub_event_kind == a.DUB_EVENTS["drop"], "drop arms the fallback event layer")
	ok(a._dub_event_dur > 0.0, "drop event has positive duration")
	a._pump_dubstep_fallback()
	a.music_event("not_an_event")
	ok(a._dub_event_kind == a.DUB_EVENTS["drop"], "unknown events do not arm the fallback")

	# set_music_intensity updates the target under fallback.
	a.set_music_intensity(0.2, 0.1)
	ok(is_equal_approx(a._dub_intensity_target, 0.2), "intensity target updated under fallback")

	# play_event under fallback produces a stream and counts it.
	var before_sfx: int = a.sfx_played
	a.play_event("gem_hit", 0.9)
	ok(a.sfx_played == before_sfx + 1, "fallback play_event counts")
	ok(a.last_sfx_source == "dubstep_fallback", "fallback reports its source (got %s)" % a.last_sfx_source)
	ok(a.last_sfx == "gem_hit", "fallback recorded the last event")

	# play_collision also nudges the stab layer.
	a.play_collision("gem_hit", 0.95)
	ok(a._dub_event_kind == a.DUB_EVENTS["stab"], "loud collision arms stab under fallback")

	# Cleanup: stop, restore the saved engine reference.
	a._stop_dubstep(0.05)
	ok(not a._dub_fallback, "fallback flag cleared on stop")
	ok(a.music_source != "dubstep", "music source cleared on stop")
	a._dub = saved_dub

