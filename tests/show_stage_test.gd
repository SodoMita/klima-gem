extends Node
## Headless test for the Klima Gem show: the flat-topped word gems, the edge
## tables, the throw ceremony, modification application, the three challenge
## builds + choreographies, star bookkeeping, snapshot/restore re-dressing,
## and a full seeded playthrough of the show dialogue down to END.
##
## Run: GODOT_BIN=/path/to/godot bash tests/show_stage_test.sh
## (or: godot --headless res://tests/show_stage_test.tscn)
##
## Prints "SHOW TESTS: PASS" and exits 0, or "SHOW TESTS: FAIL" and 1.

const ShowStageScene := preload("res://scenes/show_stage/show_stage.tscn")
const ShowStageScript := preload("res://scenes/show_stage/show_stage.gd")
const ShowDirectorScript := preload("res://autoloads/show_director.gd")

var failures: int = 0
var stage: Node3D
var director: Node


func _ready() -> void:
	# Real-time watchdog: SceneTreeTimer honours time_scale otherwise.
	get_tree().create_timer(240.0, true, false, true).timeout.connect(_on_watchdog)
	Engine.time_scale = 10.0
	_build_rig()
	await _run_tests()
	Engine.time_scale = 1.0
	if failures == 0:
		print("SHOW TESTS: PASS")
		get_tree().quit(0)
	else:
		print("SHOW TESTS: FAIL (%d failures)" % failures)
		get_tree().quit(1)


func _on_watchdog() -> void:
	printerr("SHOW TESTS: watchdog timeout")
	print("SHOW TESTS: FAIL (watchdog)")
	get_tree().quit(1)


func check_vec_close(actual: Vector3, expected: Vector3, label: String, eps := 0.08) -> void:
	var ok := actual.is_equal_approx(expected) or (absf(actual.x - expected.x) <= eps and absf(actual.z - expected.z) <= eps and absf(actual.y - expected.y) <= eps + 0.05)
	check(ok, "%s (%s ~ %s)" % [label, actual, expected])


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		failures += 1
		printerr("  FAIL: %s" % label)


func _build_rig() -> void:
	stage = ShowStageScene.instantiate()
	add_child(stage)
	director = ShowDirectorScript.new()
	director.name = "TestShowDirector"
	add_child(director)


func _run_tests() -> void:
	var gs: Node = get_node("/root/GameState")
	check(gs != null, "GameState autoload present")
	check(director.stage() == stage, "director finds the stage by group")

	# --- word lists and geometry -------------------------------------------
	check(ShowStageScript.PARTS.size() == 8, "eight body-part words")
	check(ShowStageScript.MODS.size() == 8, "eight modification words")
	for part in ShowStageScript.PARTS:
		check(director.PART_EDGE.has(part), "edge table covers part %s" % part)
	for mod in ShowStageScript.MODS:
		check(director.MOD_EDGE.has(mod), "edge table covers mod %s" % mod)
		var colors: Dictionary = stage.MOD_COLORS
		check(colors.has(mod), "color keyed for mod %s" % mod)

	# --- odds and outlook ----------------------------------------------------
	gs.show_part = "LEGS"
	gs.show_mod = "BOUNCY"
	gs.show_round = 1
	check(director.edge_for(1) == 2, "LEGS+BOUNCY favours the crossing")
	check(director.outlook_for(1) == "advantage", "outlook reads advantage")
	gs.show_part = "SKIN"
	gs.show_mod = "STICKY"
	check(director.edge_for(1) == -2, "SKIN+STICKY is a bad crossing hand")
	check(director.outlook_for(1) == "disadvantage", "outlook reads disadvantage")
	check(director.outlook_word(1) == "a DISADVANTAGE", "outlook word for dialogue")
	gs.show_part = "HANDS"
	gs.show_mod = "GIANT"
	gs.show_round = 2
	check(director.edge_for(2) == 2, "GIANT HANDS catch bells")
	gs.show_round = 3
	check(director.edge_for(3) == 0, "GIANT HANDS are neutral in the choir")
	var extremes := [director.edge_for(1), director.edge_for(2), director.edge_for(3)]
	for edge in extremes:
		check(director.success_chance(1) >= 0.15 and director.success_chance(1) <= 0.85, "chance stays clamped")

	# --- the throw ceremony --------------------------------------------------
	gs.story_seed = 1234
	gs._reseed()
	director.begin_show()
	check(int(gs.show_round) == 0 and int(gs.show_stars) == 0, "begin_show resets the state")
	director.next_round()
	check(int(gs.show_round) == 1, "next_round counts up")
	await director.throw_gem_round()
	check(str(gs.show_part) in ShowStageScript.PARTS, "rolled a legal body part: %s" % gs.show_part)
	check(str(gs.show_mod) in ShowStageScript.MODS, "rolled a legal modification: %s" % gs.show_mod)
	check(int(gs.show_part_face) >= 0 and int(gs.show_part_face) < 8, "part face index in range")
	var live_gems: Array = stage._gems
	check(live_gems.size() == 2, "two gems hover on the stage")
	if live_gems.size() == 2:
		check(live_gems[0].word_at(int(gs.show_part_face)) == str(gs.show_part), "gem A carries the rolled part on the rolled face")
		check(live_gems[1].word_at(int(gs.show_mod_face)) == str(gs.show_mod), "gem B carries the rolled mod on the rolled face")
		check(live_gems[0].face_labels.size() == 8, "gem A wears eight word labels")
		check(live_gems[1].face_labels[0].text != "", "gem B labels carry text")
		check(live_gems[0].words[0] == "HANDS" and live_gems[0].words[7] == "SKIN", "gem A word order is stable")
		check_vec_close(live_gems[0].position, ShowStageScript.GEM_SLOT_PART, "body-part gem hangs on the RIGHT")
		check_vec_close(live_gems[1].position, ShowStageScript.GEM_SLOT_MOD, "shapeshift gem hangs on the LEFT")

	# --- the glowing word presentation ---------------------------------------
	check(is_instance_valid(stage._plaque_part), "body-part word is presented")
	check(is_instance_valid(stage._plaque_mod), "shapeshift word is presented")
	if is_instance_valid(stage._plaque_part):
		check(stage._plaque_part.get_child(0).text == str(gs.show_part), "right plaque carries the part word")
		check_vec_close((stage._plaque_part as Node3D).global_position, ShowStageScript.PRESENT_POS_PART, "part word hangs in the RIGHT slot")
	if is_instance_valid(stage._plaque_mod):
		check(stage._plaque_mod.get_child(0).text == str(gs.show_mod), "left plaque carries the shapeshift word")
		check_vec_close((stage._plaque_mod as Node3D).global_position, ShowStageScript.PRESENT_POS_MOD, "shapeshift word hangs in the LEFT slot")

	# --- modification application -------------------------------------------
	await director.apply_mods()
	check(is_instance_valid(stage._chip), "modification chip is standing")
	check(stage._chip_label != null and "x" in stage._chip_label.text, "chip label pairs the words")
	check(str(gs.show_outlook) == director.outlook_for(1), "outlook stored for the dialogue")

	# --- the three trials ----------------------------------------------------
	for round_no in [1, 2, 3]:
		gs.show_round = round_no
		director._pattern = [0, 1, 2, 3, 0]
		await director.build_challenge(round_no)
		check(int(gs.show_props_round) == round_no, "trial %d props are standing" % round_no)
		var had_props: bool = stage._props.get_child_count() > 0
		check(had_props, "trial %d built stage objects" % round_no)
		await stage.play_challenge(round_no, true, director._pattern)
		check(true, "trial %d success choreography played" % round_no)
		await stage.play_challenge(round_no, false, director._pattern)
		check(true, "trial %d failure choreography played" % round_no)
		await director.run_challenge()
		check(int(gs.show_stars) >= 0 and int(gs.show_stars) <= 3, "stars in range after trial %d" % round_no)
		check(stage._props.get_child_count() == 0, "trial %d props torn back down" % round_no)

	# --- stars, pips, confetti -----------------------------------------------
	stage.set_stars(2)
	check(true, "star pips updated")
	await stage.fly_star(true, 2)
	await stage.fly_star(false, 2)
	stage.confetti_burst()
	await get_tree().create_timer(0.5).timeout
	check(is_instance_valid(stage._confetti), "confetti bursts")
	director.begin_show()
	await get_tree().create_timer(0.3).timeout
	check(stage._props.get_child_count() == 0, "begin_show strikes the stage")
	check(not is_instance_valid(stage._chip), "begin_show clears the chip")

	# --- snapshot / restore re-dresses the show -------------------------------
	director.next_round()
	await director.throw_gem_round()
	await director.apply_mods()
	await director.build_challenge(1)
	var snap: Dictionary = gs.snapshot()
	# Wreck the visible state...
	director.begin_show()
	await get_tree().create_timer(0.2).timeout
	check(stage._gems.size() == 0, "gems cleared before restore")
	check(stage._plaque_part == null and stage._plaque_mod == null, "word plaques cleared before restore")
	# ...then restore and demand the show back.
	gs.restore(snap)
	await get_tree().create_timer(0.2).timeout
	check(stage._gems.size() == 2, "restore brings both gems back settled")
	check(is_instance_valid(stage._plaque_part) and stage._plaque_part.get_child(0).text == str(gs.show_part), "restore re-presents the part word")
	check(is_instance_valid(stage._plaque_mod) and stage._plaque_mod.get_child(0).text == str(gs.show_mod), "restore re-presents the shapeshift word")
	check(is_instance_valid(stage._chip), "restore brings the chip back")
	check(stage._props.get_child_count() > 0, "restore rebuilds the standing trial props")
	check((stage.aurora_quad == null) or (stage.aurora_quad as Node3D).global_position.is_equal_approx(ShowStageScript.AURORA_MARK), "guest stands on her mark after restore")

	# --- the story compiles ----------------------------------------------------
	var raw: String = FileAccess.open("res://dialogue/klima_gem_show.dialogue", FileAccess.READ).get_as_text()
	var compile_result = DMCompiler.compile_string(raw, "show")
	check(compile_result.errors.size() == 0, "show dialogue compiles with zero errors (%d)" % compile_result.errors.size())
	for e in compile_result.errors:
		printerr("    dialogue error, line %s: %s" % [e.line_number, e.message])
	var story: Resource = load("res://dialogue/klima_gem_show.dialogue")
	check(story != null, "show dialogue resource loads")
	# The loaded artifact must match the source: a stale import silently runs
	# an old story. The combo-condition block is our canary.
	var gs_probe: Node = get_node("/root/GameState")
	gs_probe.show_part = "EYES"
	gs_probe.show_mod = "MAGNET"
	var dm_guard: Node = get_node("/root/DialogueManager")
	var guard_key := "gem_round"
	var combo_seen: Array = []
	for i in 30:
		var probe_line = await dm_guard.get_next_dialogue_line(story, guard_key, [])
		if probe_line == null:
			break
		var t := str(probe_line.text)
		if t.begins_with("When I try") or t.begins_with("I can see the infrastructure") or t.begins_with("My chest has a ballast"):
			combo_seen.append(t.substr(0, 20))
		if t.begins_with("The stage is set"):
			break
		guard_key = probe_line.next_id
	# A combo line must be gated on its exact roll: the walk throws for real
	# (mutations execute), so a line is allowed on screen only when the throw
	# produced its pairing.
	var rolled_combo := "%s+%s" % [gs_probe.show_part, gs_probe.show_mod]
	var combo_prefixes := {
		"VOICE+STICKY": "When I try to speak,",
		"EYES+GLOWING": "I can see the infras",
		"HEART+HEAVY": "My chest has a balla",
	}
	for combo: String in combo_prefixes:
		var prefix: String = combo_prefixes[combo]
		if combo == rolled_combo:
			check(combo_seen.has(prefix), "the rolled combo line shows (%s)" % [combo])
		else:
			check(not combo_seen.has(prefix), "combo line %s stays hidden when %s was rolled" % [prefix, rolled_combo])
	gs_probe.show_part = ""
	gs_probe.show_mod = ""
	if story != null:
		var states: PackedStringArray = story.using_states
		check(states.has("GameState") and states.has("ShowDirector"), "story declares both states")

	# --- a full seeded playthrough, every branch -------------------------------
	var dm: Node = get_node("/root/DialogueManager")
	check(dm != null, "DialogueManager present")
	if dm != null and story != null:
		var reached_end := true
		var picks := 0
		for branch in 4:
			var key := "show_start"
			var steps := 0
			while steps < 400:
				var line = await dm.get_next_dialogue_line(story, key, [])
				if line == null:
					break
				steps += 1
				if line.responses.size() > 0:
					var pick: int = (branch + picks) % int(line.responses.size())
					picks += 1
					key = line.responses[pick].next_id
				else:
					key = line.next_id
			check(steps < 400, "branch %d reached the end of the show (%d lines)" % [branch, steps])
			check(int(gs.show_stars) >= 0 and int(gs.show_stars) <= 3, "branch %d ends with a legal star count (%d)" % [branch, int(gs.show_stars)])
			check(str(gs.show_part) != "" and str(gs.show_mod) != "", "branch %d rolled words along the way" % branch)
		check(reached_end, "all seeded branches ran")

	# --- determinism: the same seed must roll the same words -------------------
	gs.story_seed = 777
	gs._reseed()
	director.begin_show()
	director.next_round()
	await director.throw_gem_round()
	var first_part := str(gs.show_part)
	var first_mod := str(gs.show_mod)
	gs.story_seed = 777
	gs._reseed()
	director.begin_show()
	director.next_round()
	await director.throw_gem_round()
	check(str(gs.show_part) == first_part and str(gs.show_mod) == first_mod, "same seed rolls the same gems")

	# Release the shared font so nothing is held at exit.
	FlatTopGem.word_font = null
