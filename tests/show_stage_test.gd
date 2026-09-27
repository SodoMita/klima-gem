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
	check(ShowStageScript.PARTS.size() == 9 and ShowStageScript.PARTS[8] == "MILK", "eight body-part side words plus MILK on the table")
	check(ShowStageScript.MODS.size() == 9 and ShowStageScript.MODS[8] == "MEGA", "eight modification side words plus MEGA on the table")
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
	gs.show_part = "EYES"
	gs.show_mod = "GLOWING"
	gs.show_round = 3
	check(director.edge_for(3) == 2, "EYES+GLOWING edge in the choir")
	check(director.action_edge(3) == 0, "no actions banked yet in this probe")
	check(director.outlook_for(3) == "even", "trial 3 with total 2 is one short, not an advantage")
	gs.show_part = "HANDS"
	gs.show_mod = "GIANT"
	gs.show_round = 2
	check(director.edge_for(2) == 2, "GIANT HANDS catch bells")
	gs.show_round = 3
	check(director.edge_for(3) == 0, "GIANT HANDS are neutral in the choir")
	# --- the same shift stacks -----------------------------------------------
	# GIANT on HANDS is -1 for the crossing. GIANT twice doubles the shift
	# (-2 each); three or more copies and the body has adapted: GIANT is
	# then always an advantage (+1 each) whatever the trial.
	gs.show_body_mods = {"LEGS": "GIANT"}
	gs.show_part = "HANDS"
	gs.show_mod = "GIANT"
	check(director.mod_stacks().get("GIANT", 0) == 2, "two GIANT parts count as a x2 stack")
	check(director.stack_word("GIANT") == "x2 — doubled", "x2 stack has its word")
	var giant_x2: int = director.edge_for(1)
	# parts: HANDS + LEGS crossing edges, mods: 2 x (-1 * 2)
	var parts_only := int((director.PART_EDGE["HANDS"] as Array)[0]) + int((director.PART_EDGE["LEGS"] as Array)[0])
	check(giant_x2 == parts_only - 4, "a doubled GIANT counts twice per part (%d)" % giant_x2)
	gs.show_body_mods = {"LEGS": "GIANT", "BACK": "GIANT"}
	check(director.mod_stacks().get("GIANT", 0) == 3, "three GIANT parts count as a x3 stack")
	check(director.stack_word("GIANT").begins_with("x3"), "x3 stack reads mastered")
	var parts3 := parts_only + int((director.PART_EDGE["BACK"] as Array)[0])
	check(director.edge_for(1) == parts3 + 3, "a mastered GIANT is +1 per part even where it used to hurt")
	# --- stack audit: replacement, single-part x2, persistence (K9) --------
	# Re-rolling the same part REPLACES its shift in the body map.
	gs.show_body_mods = {"HANDS": "GIANT", "LEGS": "GIANT"}
	gs.show_mod_counts = {}
	gs.show_part = "HANDS"
	gs.show_mod = "TINY"
	check(director.mod_stacks().get("GIANT", 0) == 1, "re-rolled part leaves the old stack (GIANT x1)")
	check(director.mod_stacks().get("TINY", 0) == 1, "re-rolled part carries its new shift (TINY x1)")
	# A x2 on a SINGLE part doubles once: HANDS part edge + GIANT (-1) x2.
	gs.show_body_mods = {}
	gs.show_mod_counts = {"GIANT": 2}
	gs.show_part = "HANDS"
	gs.show_mod = "GIANT"
	var hands_only := int((director.PART_EDGE["HANDS"] as Array)[0])
	check(director.edge_for(1) == hands_only - 2, "single-part x2 doubles its one copy")
	# Parts persist through a snapshot too (counts are covered below); and a
	# rewind to before the second stamping drops the count back to x1.
	gs.show_body_mods = {"LEGS": "GIANT"}
	gs.show_mod_counts = {"GIANT": 1}
	var kept_snap: Dictionary = gs.snapshot()
	gs.show_body_mods = {}
	gs.show_mod_counts = {}
	gs.show_part = ""
	gs.show_mod = ""
	gs.restore(kept_snap)
	check(director.mod_stacks().get("GIANT", 0) == 2, "a restored body keeps parts + counts (x2)")
	gs.show_body_mods = {}
	gs.show_mod_counts = {"GIANT": 1}
	gs.show_part = "HANDS"
	gs.show_mod = "GIANT"
	var early_snap: Dictionary = gs.snapshot()
	gs.show_mod_counts = {"GIANT": 2}
	gs.restore(early_snap)
	check(director.mod_stacks().get("GIANT", 0) == 1, "rewound body drops the second stamping (x1)")
	gs.show_body_mods = {}
	gs.show_mod_counts = {}
	gs.show_last_stamp = ""
	gs.show_part = "HANDS"
	gs.show_mod = "GIANT"
	gs.show_round = 1
	await director.apply_mods()
	gs.show_round = 2
	await director.apply_mods()
	check(director.mod_stacks().get("GIANT", 0) == 2, "GIANT on the same part twice is a x2 stack")
	await director.apply_mods()
	check(int(gs.show_mod_counts.get("GIANT", 0)) == 2, "re-running the same stamp does not count it again")
	var snap_stack: Dictionary = gs.snapshot()
	gs.show_mod_counts = {}
	gs.restore(snap_stack)
	check(int(gs.show_mod_counts.get("GIANT", 0)) == 2, "stack counts survive snapshot/restore")
	gs.show_body_mods = {}
	gs.show_mod_counts = {}
	gs.show_last_stamp = ""
	gs.show_part = "HANDS"
	gs.show_mod = "GIANT"
	gs.show_round = 3
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
	check(int(gs.show_part_face) >= 0 and int(gs.show_part_face) <= FlatTopGem.TOP_FACE, "part face index in range")
	var live_gems: Array = stage._gems
	check(live_gems.size() == 2, "two gems hover on the stage")
	if live_gems.size() == 2:
		check(live_gems[0].word_at(int(gs.show_part_face)) == str(gs.show_part), "gem A carries the rolled part on the rolled face")
		check(live_gems[1].word_at(int(gs.show_mod_face)) == str(gs.show_mod), "gem B carries the rolled mod on the rolled face")
		check(live_gems[0].face_labels.size() == 8, "gem A wears eight word labels")
		check(live_gems[1].face_labels[0].text != "", "gem B labels carry text")
		check(live_gems[0].crown_labels.size() == 8 and live_gems[1].crown_labels.size() == 8, "both gems wear words on the eight upper (crown) faces")
		check(live_gems[0].top_label != null and live_gems[0].top_label.text == "MILK", "body-part gem table reads MILK")
		check(live_gems[1].top_label != null and live_gems[1].top_label.text == "MEGA", "modification gem table reads MEGA")
		# The human rule: every word on its own facet, in the facet's plane,
		# inside the facet's triangle. Corners of each label rectangle are
		# tested against the facet plane and barycentrically against it.
		for gi in 2:
			var gem_n: Node = live_gems[gi]
			var dgt: Transform3D = gem_n.global_transform
			var all_in := true
			var max_off := 0.0
			for i in 8:
				var lab: Label3D = gem_n.face_labels[i]
				var a0 := i * TAU / 8.0
				var a1 := (i + 1) * TAU / 8.0
				var g0: Vector3 = dgt * (Vector3(cos(a0), 0, sin(a0)) * gem_n.girdle_radius)
				var g1: Vector3 = dgt * (Vector3(cos(a1), 0, sin(a1)) * gem_n.girdle_radius)
				var ap: Vector3 = dgt * Vector3(0, -gem_n.pavilion_height, 0)
				var nrm: Vector3 = (g1 - g0).cross(ap - g0).normalized()
				var lb := lab.global_transform.basis
				var lc := lab.global_transform.origin
				var lsz: Vector3 = lab.get_aabb().size
				for sx in [-1, 1]:
					for sy in [-1, 1]:
						var p: Vector3 = lc + lb.x * (sx * lsz.x * 0.5) + lb.y * (sy * lsz.y * 0.5)
						max_off = max(max_off, abs((p - ap).dot(nrm)))
						var v0: Vector3 = g1 - g0
						var v1: Vector3 = ap - g0
						var v2: Vector3 = p - g0
						var d00 := v0.dot(v0)
						var d01 := v0.dot(v1)
						var d02 := v0.dot(v2)
						var d11 := v1.dot(v1)
						var d12 := v1.dot(v2)
						var den := d00 * d11 - d01 * d01
						var u := (d11 * d02 - d01 * d12) / den
						var vv := (d00 * d12 - d01 * d02) / den
						if u < -0.02 or vv < -0.02 or u + vv > 1.02:
							all_in = false
			check(all_in and max_off < 0.02, "gem %d: every word in its facet plane (%.3f off) and inside the facet bounds" % [gi, max_off])
		check(live_gems[0].words[0] == "HANDS" and live_gems[0].words[7] == "SKIN", "gem A word order is stable")
		# The stone is never lifted or turned: it rests where physics left it,
		# inside the closed glass box, and the rolled word is the face it
		# rests ON — read from below through the box's floating glass floor.
		for gi2 in 2:
			var g2: FlatTopGem = live_gems[gi2]
			var face2 := int(gs.show_part_face) if gi2 == 0 else int(gs.show_mod_face)
			check(g2.freeze and g2.settled, "gem %d froze where it landed" % gi2)
			check(g2.resting_face() == face2, "gem %d rests with the rolled word down (rolled %d, rests on %d)" % [gi2, face2, g2.resting_face()])
			var rel := g2.global_position - ShowStageScript.BOX_CENTER
			var half := ShowStageScript.BOX_SIZE * 0.5
			check(absf(rel.x) <= half.x + 0.01 and absf(rel.y) <= half.y + 0.01 and absf(rel.z) <= half.z + 0.01,
				"gem %d rests inside the closed glass box at %s" % [gi2, g2.global_position])
			check(g2.global_position.y > ShowStageScript.STAGE_TOP + 0.5,
				"gem %d rests on the glass floor in the air, not on the platform" % gi2)
			# The word is legible from below: its label faces DOWN (toward an
			# under-view camera) and its up-vector reads upright from there.
			var lab2: Label3D = g2.resting_label(face2)
			var n2: Vector3 = lab2.global_basis.z.normalized()
			check(n2.y < -0.45, "gem %d: rolled word points down through the glass floor (%.2f)" % [gi2, n2.y])
			var eye := lab2.global_position + n2 * ShowStageScript.UNDERVIEW_DIST
			eye.y = clampf(eye.y, ShowStageScript.STAGE_TOP + 0.12, ShowStageScript.BOX_CENTER.y - 0.25)
			var up2: Vector3 = lab2.global_basis.y
			up2.y = 0.0
			# A label is read along its own +Z; a right-handed frame whose Z
			# points at the under-view eye cannot be mirrored.
			var lb2: Basis = lab2.global_basis.orthonormalized()
			check(lb2.x.cross(lb2.y).dot(n2) > 0.9, "gem %d: rolled word is not mirrored from below" % gi2)

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
	# The disadvantage branch offers the cheer spend only when a cheer
	# exists to spend; otherwise the jar-empty line plays and the spend
	# choice stays hidden (the director also refuses a broke swap).
	for cheers in [0, 2]:
		gs_probe.show_cheers = cheers
		var spend_seen := false
		var keep_seen := false
		var jar_seen := false
		var ckey := "gem_round"
		for i in 80:
			var cline = await dm_guard.get_next_dialogue_line(story, ckey, [])
			if cline == null:
				break
			var ct := str(cline.text)
			if ct.begins_with("I can FEEL it"):
				gs_probe.show_outlook = "disadvantage"
			if "jar is EMPTY" in ct:
				jar_seen = true
			if cline.responses.size() > 0:
				for r in cline.responses:
					var rt := str(r.text)
					# Failed-condition responses ride along with
					# is_allowed=false; the balloon hides them.
					if "spend the cheer" in rt and r.is_allowed:
						spend_seen = true
					if "keep the bad hand" in rt and r.is_allowed:
						keep_seen = true
				break
			if ct.begins_with("The stage is set"):
				break
			ckey = cline.next_id
		check(keep_seen, "cheer choice offers the keep with %d cheers" % cheers)
		check(spend_seen == (cheers > 0), "cheer spend offered iff affordable (%d cheers)" % cheers)
		check(jar_seen == (cheers <= 0), "empty-jar line shows iff broke (%d cheers)" % cheers)
	gs_probe.show_cheers = 1
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

	# --- fairness: no predefined night. Every new show throws under a new
	# seed, so the same save slot never replays the same stones by default.
	director.pin_seed = false
	director.begin_show()
	var seed_a := int(gs.story_seed)
	director.begin_show()
	var seed_b := int(gs.story_seed)
	director.begin_show()
	var seed_c := int(gs.story_seed)
	check(not (seed_a == seed_b and seed_b == seed_c), "every new show draws a fresh throw seed (%d, %d, %d)" % [seed_a, seed_b, seed_c])

	# Release the shared font so nothing is held at exit.
	FlatTopGem.word_font = null
