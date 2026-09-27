extends Node
## Dubstep audio tests: the C generator (native/audio_gen/ag_dubstep.c) through
## the AudioGen extension, the AudioDirector stage-music path, the per-event
## sound bank and gem collision sounds. Headless-safe: no audio device needed.

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
	_test_event_sounds()
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
			"dub_render", "dub_release", "dub_active", "render_dub_sfx", "dub_sfx_frames"]:
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
	# an event must change the next second of music
	gen.call("dub_event", 1)  # drop
	var buf2 := PackedVector2Array()
	buf2.resize(22050)
	gen.call("dub_render", buf2)
	var e2 := 0.0
	for i: int in buf2.size():
		e2 += absf(buf2[i].x)
	ok(e2 > 0.0, "engine keeps rendering after a drop")
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


func _test_event_sounds() -> void:
	var a := AudioDirector
	var before: int = a.sfx_played
	a.play_event("gem_hit", 0.9)
	ok(a.sfx_played == before + 1, "play_event counts")
	ok(a.last_sfx == "gem_hit", "play_event records the key")
	if a.has_dubstep_engine():
		ok(a.last_sfx_source == "dubstep", "gem_hit comes from the C generator")
		ok(a.dub_sfx_rendered > 0, "one-shot rendered and cached")
		var rendered: int = a.dub_sfx_rendered
		a.play_event("gem_hit", 0.9)
		ok(a.dub_sfx_rendered == rendered, "same energy bucket reuses the cache")
		a.play_event("gem_hit", 0.1)
		ok(a.dub_sfx_rendered > rendered, "a softer hit is its own sound")
	a.play_event("click")  # unknown to the dub bank -> old path, no crash
	ok(a.last_sfx == "click", "unknown keys fall back to play_sfx")


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
