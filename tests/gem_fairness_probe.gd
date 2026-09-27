extends SceneTree
## Fairness probe: 40 random throws in the closed box, tallies the resting
## result. Run: godot --headless --path . -s res://tests/gem_fairness_probe.gd
## Last run: sides ~9% each, table (MILK/MEGA) ~25%, 0 stones left the box.
func _initialize() -> void:
	Engine.time_scale = 6.0
	Engine.physics_ticks_per_second = 360
	Engine.max_physics_steps_per_frame = 64
	var st: ShowStage = (load("res://scenes/show_stage/show_stage.tscn") as PackedScene).instantiate()
	root.add_child(st)
	await process_frame
	var tally := {}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var slow := 0
	for n in 40:
		st.clear_gems()
		var g := st._make_gem(ShowStage.GEM_SLOT_PART, Color(0.5, 0.85, 1, 0.6), ShowStage.PARTS)
		await process_frame
		var t0 := Time.get_ticks_msec()
		var half := ShowStage.BOX_SIZE * 0.5
		# The very same launch the show uses, with a fake player cue: a
		# random aim on the glass and a random hold.
		var cue := {
			"aim": ShowStage.BOX_CENTER + Vector3(rng.randf_range(-1.0, 1.0) * half.x, 0.0, rng.randf_range(-1.0, 1.0) * half.z),
			"power": rng.randf_range(0.8, 1.5),
			"entropy": rng.randi(),
		}
		st.launch_gem(g, rng, cue)
		await st._wait_throw_rest(g, st._gem_epoch)
		var f := g.resting_face()
		var inside := absf(g.global_position.x - ShowStage.BOX_CENTER.x) < half.x + 0.05 and absf(g.global_position.z - ShowStage.BOX_CENTER.z) < half.z + 0.05
		tally[f] = int(tally.get(f, 0)) + 1
		print("throw ", n, " face ", f, " inside ", inside, " sleeping ", g.sleeping, " ms ", Time.get_ticks_msec() - t0)
	var out := 0
	print("TALLY ", tally)
	quit()
