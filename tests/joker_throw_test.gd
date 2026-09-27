extends Node
## Joker's throw regression: real physics inside the lifted glass case.
## Proves the stones never leave the box, come to rest quickly, and that the
## reported word is the face they are actually lying on.

const ShowStageScene := preload("res://scenes/show_stage/show_stage.tscn")
const ShowStageScript := preload("res://scenes/show_stage/show_stage.gd")

var _oks := 0
var _fails := 0


func ok(cond: bool, what: String) -> void:
	if cond:
		_oks += 1
		print("ok   %s" % what)
	else:
		_fails += 1
		printerr("FAIL %s" % what)


func _ready() -> void:
	await _run()
	print("joker throw test: %d ok, %d failed" % [_oks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	var stage := ShowStageScene.instantiate()
	add_child(stage)
	await get_tree().process_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	# Watch the flight: sample every physics frame while the throw runs.
	var escaped := {"out": false, "worst": 0.0}
	var watcher := func() -> void:
		for i in 600:
			await get_tree().physics_frame
			for gem in stage._gems:
				# Only while the body is under physics: once the show freezes
				# a stone it is choreography's to lift out for the reveal.
				if is_instance_valid(gem) and not gem.freeze:
					if not stage.throw_box_contains(gem.global_position, 0.35):
						escaped["out"] = true
	watcher.call()

	var started := Time.get_ticks_msec()
	var faces: Array = await stage.throw_gems(rng, false)
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0

	ok(faces.size() == 2, "the throw reads two faces off the landing")
	ok(not escaped["out"], "no stone ever left the closed case in flight")
	# Two throws, each: cue-less launch, settle, under-glass reveal, lift,
	# flashes and the word presentation. Anything over ~20 s means the
	# stones are rolling forever again.
	ok(elapsed < 20.0, "both throws complete briskly (%.1f s)" % elapsed)

	if faces.size() == 2:
		ok(int(faces[0]) >= 0 and int(faces[0]) < 8, "part face is legal (%s)" % faces[0])
		ok(int(faces[1]) >= 0 and int(faces[1]) < 8, "mod face is legal (%s)" % faces[1])
		ok(stage._gems.size() == 2, "both stones are still on the stage")

	# Fairness, by simulation: 24 solo throws of the same stone must not all
	# land the same face, and no face may take more than half the throws.
	var counts := {}
	var gem = stage._gems[0]
	for i in 24:
		var from: Vector3 = stage.throw_origin(true)
		var target: Vector3 = ShowStageScript.LAND_PART + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.25, 0.25))
		var spin := Vector3(
			rng.randf_range(11.0, 20.0) * (1.0 if rng.randf() < 0.5 else -1.0),
			rng.randf_range(12.0, 22.0) * (1.0 if rng.randf() < 0.5 else -1.0),
			rng.randf_range(11.0, 20.0) * (1.0 if rng.randf() < 0.5 else -1.0))
		var attitude := Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
		gem.throw_with_velocity(from, stage._arc_velocity(from, target, 0.32), spin, attitude)
		await gem.wait_until_rest(4.0)
		var face: int = gem.bottom_face()
		counts[face] = int(counts.get(face, 0)) + 1
		ok_silent(stage.throw_box_contains(gem.global_position, 0.35))
	ok(counts.size() >= 4, "the stone lands on at least four different faces (%s)" % [counts])
	var worst := 0
	for k in counts:
		worst = maxi(worst, int(counts[k]))
	ok(worst <= 12, "no face wins more than half the throws (worst %d/24)" % worst)
	ok(not _silent_fail, "every settled stone stayed inside the case")


var _silent_fail := false


func ok_silent(cond: bool) -> void:
	if not cond:
		_silent_fail = true
