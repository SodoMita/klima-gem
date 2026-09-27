extends Node
## Regression tests for the five defects the human named on the Klima Gem
## show. Each one fails on the build that was reviewed:
##
##   1. the stage only looked right under a rasterizer  -> framing checks
##   2. the gems were thrown by tween, physics was "Dummy" -> physics checks
##   3. the words floated free of the gem facets            -> facet-fit checks
##   4. narration colons were read as speaker names          -> colon lint
##   5. no portrait stood on the stage (Ren, and no guest)   -> guest checks
##
## Run: GODOT_BIN=/path/to/godot bash tests/stage_integrity_test.sh
## Prints "STAGE INTEGRITY TESTS: PASS" / "FAIL" and exits accordingly.

const ShowStageScript := preload("res://scenes/show_stage/show_stage.gd")
const FlatTopGemScript := preload("res://scenes/show_stage/flat_top_gem.gd")

const DIALOGUE_PATH := "res://dialogue/klima_gem_show.dialogue"

var failures: int = 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		failures += 1
		printerr("  FAIL: %s" % label)


func check_near(actual: float, expected: float, label: String, eps := 0.01) -> void:
	check(absf(actual - expected) <= eps, "%s (%.4f ~ %.4f)" % [label, actual, expected])


func _ready() -> void:
	get_tree().create_timer(180.0, true, false, true).timeout.connect(_on_watchdog)
	_test_physics_is_on()
	_test_facet_words_are_welded()
	_test_dialogue_colons()
	await _test_gem_throw_is_physics()
	await _test_portrait_on_stage()
	if failures == 0:
		print("STAGE INTEGRITY TESTS: PASS")
		get_tree().quit(0)
	else:
		print("STAGE INTEGRITY TESTS: FAIL (%d)" % failures)
		get_tree().quit(1)


func _on_watchdog() -> void:
	printerr("STAGE INTEGRITY TESTS: watchdog timeout")
	print("STAGE INTEGRITY TESTS: FAIL (watchdog)")
	get_tree().quit(1)


# ------------------------------------------------------------ 1 - physics on

func _test_physics_is_on() -> void:
	print("-- physics --")
	var engine_3d := str(ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT"))
	var engine_2d := str(ProjectSettings.get_setting("physics/2d/physics_engine", "DEFAULT"))
	check(engine_3d != "Dummy", "3D physics engine is real (got '%s')" % engine_3d)
	check(engine_2d != "Dummy", "2D physics engine is real (got '%s')" % engine_2d)
	check(ProjectSettings.get_setting("physics/3d/default_gravity", 0.0) > 0.0, "gravity is not zero")


# ----------------------------------------------------- 2 - words on the faces

func _facet_triangle(gem: FlatTopGem, i: int) -> Array:
	return gem.facet_corners(i)


func _test_facet_words_are_welded() -> void:
	print("-- gems: words welded to their facets --")
	var gem: FlatTopGem = FlatTopGemScript.new()
	gem.girdle_radius = 0.5
	gem.table_radius = 0.26
	gem.crown_height = 0.17
	gem.pavilion_height = 0.44
	gem.set_words(PackedStringArray(["HANDS", "GLOWING", "HEART", "TINY", "BACK", "BOUNCY", "VOICE", "MAGNET"]))
	add_child(gem)
	await get_tree().process_frame
	check(gem.face_labels.size() == 8, "eight word labels are built")

	var font := FlatTopGemScript._font()
	var facet_base := 2.0 * gem.girdle_radius * sin(PI / 8.0)
	var worn := 0
	for i in gem.face_labels.size():
		var label := gem.face_labels[i]
		var corners := _facet_triangle(gem, i)
		var centre: Vector3 = ((corners[0] + corners[1]) * 0.5).lerp(corners[2], 0.19)
		var normal := gem._face_normal(i)
		var geometric: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized()
		check(normal.dot(geometric) > 0.999, "face %d label uses the actual facet normal" % i)
		var off_plane: float = absf((label.position - corners[0]).dot(geometric))
		var from_centre: float = (label.position - centre).length()
		if off_plane <= 0.005 and from_centre <= 0.005:
			worn += 1
		else:
			printerr("      face %d: off-plane %.4f, %.4f from the ink centre" % [i, off_plane, from_centre])
		var facing: float = label.transform.basis.z.normalized().dot(normal)
		check(facing > 0.999, "face %d label points OUT of its own facet" % i)
		var text_px := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
		var half_w := (text_px.x + 2.0 * label.outline_size) * label.pixel_size * 0.5
		var half_h := (text_px.y + 2.0 * label.outline_size) * label.pixel_size * 0.5
		var inside := true
		for dx in [-1.0, 1.0]:
			for dy in [-1.0, 1.0]:
				var pt: Vector3 = label.position + label.basis.x * (dx * half_w) + label.basis.y * (dy * half_h)
				var v0: Vector3 = corners[1] - corners[0]
				var v1: Vector3 = corners[2] - corners[0]
				var v2: Vector3 = pt - corners[0]
				var d00 := v0.dot(v0)
				var d01 := v0.dot(v1)
				var d11 := v1.dot(v1)
				var d20 := v2.dot(v0)
				var d21 := v2.dot(v1)
				var denom := d00 * d11 - d01 * d01
				var v := (d11 * d20 - d01 * d21) / denom
				var w := (d00 * d21 - d01 * d20) / denom
				inside = inside and v >= -0.0001 and w >= -0.0001 and v + w <= 1.0001
		check(inside, "face %d '%s' entire ink and outline fit within its triangle" % [i, label.text])
	check(worn == 8, "all eight words sit on their own facet")

	# The facing fade must pick the face the gem was told to show. This is the
	# bug that put the neighbouring word in the light.
	for cam_az in [0.0, 1.6, 3.0, -2.2, PI]:
		var wrong := 0
		for face in 8:
			gem.snap_settled(Vector3.ZERO, face, cam_az)
			if gem.front_face_for_azimuth(cam_az) != face:
				wrong += 1
				printerr("      cam %.2f: settled on face %d, front face reads %d"
					% [cam_az, face, gem.front_face_for_azimuth(cam_az)])
		check(wrong == 0, "at camera azimuth %.2f the announced face is the one in the light" % cam_az)
	gem.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------- 3 - dialogue colons

## Dialogue Manager splits a line on the first ": ", so a colon inside the
## text must be written "\:". Speaker prefixes, labels, commands, conditions,
## choices and gotos are not text and are left alone.
func _test_dialogue_colons() -> void:
	print("-- dialogue: no unescaped colons in text --")
	var file := FileAccess.open(DIALOGUE_PATH, FileAccess.READ)
	if file == null:
		check(false, "dialogue file readable")
		return
	var bad: Array[String] = []
	var line_no := 0
	while not file.eof_reached():
		var raw := file.get_line()
		line_no += 1
		var text := raw.strip_edges()
		if text == "" or text.begins_with("#"):
			continue
		if text.begins_with("~") or text.begins_with("=>") or text.begins_with("do ") \
				or text.begins_with("if ") or text.begins_with("elif ") or text.begins_with("else") \
				or text.begins_with("- ") or text.begins_with("\\t- ") or text.begins_with("%") \
				or text.begins_with("["):
			continue
		# Strip "{condition}" style prefixes and "%n" weighted variants.
		while text.begins_with("%") or text.begins_with("["):
			var close := text.find("]") if text.begins_with("[") else -1
			if close >= 0:
				text = text.substr(close + 1).strip_edges()
			else:
				break
		# A leading "Name: " is the speaker, not text.
		var first := text.find(": ")
		if first > 0 and not text.substr(0, first).contains("\\"):
			text = text.substr(first + 2)
		var search := 0
		while true:
			var at := text.find(": ", search)
			if at < 0:
				break
			if at == 0 or text[at - 1] != "\\":
				bad.append("line %d: %s" % [line_no, raw.strip_edges().substr(0, 90)])
			search = at + 1
	check(bad.is_empty(), "every colon inside dialogue text is escaped")
	for b in bad:
		printerr("      %s" % b)


# --------------------------------------------------- 4 - the throw is physics

func _test_gem_throw_is_physics() -> void:
	print("-- the throw --")
	var stage: Node3D = (load("res://scenes/show_stage/show_stage.tscn") as PackedScene).instantiate()
	add_child(stage)
	await get_tree().process_frame
	check(stage.has_method("_build_colliders"), "the stage builds colliders")
	var platform := stage.get_node_or_null("Physics/PlatformBody") as StaticBody3D
	check(platform != null, "the stage floor is a StaticBody3D")
	if platform != null:
		var shape := platform.get_child(0) as CollisionShape3D
		check(shape != null and shape.shape is CylinderShape3D, "the floor carries a real collision shape")
		check(platform.collision_layer == 1, "the floor is on the world layer")

	var gem: FlatTopGem = FlatTopGemScript.new()
	gem.physical = true
	gem.set_words(ShowStageScript.PARTS)
	stage.add_child(gem)
	await get_tree().process_frame
	check(gem is RigidBody3D, "a gem is a RigidBody3D")
	check(gem.shape != null and gem.shape.shape is ConvexPolygonShape3D, "a gem carries a convex hull collider")
	check(gem.collision_layer == 2 and gem.collision_mask == 1, "gems collide with the world, not with each other")

	# Launch it straight up and let gravity bring it back: a tween cannot do this.
	gem.physical = true
	gem.freeze = false
	gem.position = Vector3(0.0, 3.0, 0.0)
	gem.throw_with_velocity(Vector3(0.0, 3.0, 0.0), Vector3(0.0, 3.0, 0.0), Vector3(2.0, 3.0, 1.0))
	var peak := gem.position.y
	var fell := gem.position.y
	for i in 60:
		await get_tree().physics_frame
		peak = maxf(peak, gem.global_position.y)
		fell = gem.global_position.y
	check(peak > 3.2, "the body rises under its own impulse (peak %.2f)" % peak)
	check(fell < peak, "and gravity brings it back down (%.2f < %.2f)" % [fell, peak])
	check(gem.linear_velocity.length() > 0.0 or gem.sleeping, "the body is being integrated by the physics server")

	# A full ceremonial throw is physics-random: no faces are requested, the
	# stones decide, and both still come home to their marks.
	gem.queue_free()  # the isolated physics probe was not in stage._gems
	stage.clear_gems()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var faces: Array = await stage.throw_gems(rng)
	check(faces.size() == 2, "the throw reads two faces off the landing")
	if faces.size() == 2:
		check(int(faces[0]) >= 0 and int(faces[0]) < 8, "the part face is a legal face (%s)" % faces[0])
		check(int(faces[1]) >= 0 and int(faces[1]) < 8, "the mod face is a legal face (%s)" % faces[1])
	check(stage._gems.size() == 2, "two gems come back")
	for i in stage._gems.size():
		var g: FlatTopGem = stage._gems[i]
		var slot: Vector3 = ShowStageScript.GEM_SLOT_PART if i == 0 else ShowStageScript.GEM_SLOT_MOD
		check(g.settled, "gem %d reports itself settled" % i)
		check(g.global_position.distance_to(slot) < 0.12,
			"gem %d stands on its mark within a hand's width (%.2f)" % [i, g.global_position.distance_to(slot)])
	if stage._gems.size() == 2 and faces.size() == 2:
		check(stage._gems[0].front_face() == int(faces[0]) or stage._gems[0].front_face() == -1,
			"the part gem shows the face it landed on")
	# The deterministic staging helper still exists for framing shots.
	stage.clear_gems()
	await stage.throw_gems_fixed(1, 7)
	check(stage._gems.size() == 2, "the fixed staging throw brings two gems")
	# Interrupt a physical flight with a rewind. A stale throw must never
	# resume after the restore and create a third gem or word plaque.
	var rng_rewind := RandomNumberGenerator.new()
	rng_rewind.seed = 777
	stage.throw_gems(rng_rewind)
	await get_tree().create_timer(0.2).timeout
	stage.place_gems_settled("HANDS", 0, "GIANT", 0)
	await get_tree().create_timer(0.9).timeout
	check(stage._gems.size() == 2 and stage._gems[0].word_at(0) == "HANDS",
		"rewind mid-flight cancels the old throw without replacing the new gems")
	var live_gems := 0
	for child in stage.get_children():
		if child is FlatTopGem and child.build_words:
			live_gems += 1
	check(live_gems == 2, "rewind mid-flight leaves no abandoned gem visible")
	stage.queue_free()
	await get_tree().process_frame


# ------------------------------------------------- 5 - one sprite, on stage

func _test_portrait_on_stage() -> void:
	print("-- the guest --")
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	main._start("show_start")
	await get_tree().create_timer(0.8).timeout
	var stage := get_tree().get_first_node_in_group("show_stage") as Node3D
	check(stage != null, "the stage is in the tree")
	var director := get_node_or_null("/root/ShowDirector")
	var balloon: Node = director._balloon() if director != null else null
	check(balloon != null, "the director can find the dialogue balloon")
	check(stage.characters_parent() != null, "the stage has a Characters parent for portraits")

	director.enter_ren()
	await get_tree().create_timer(0.3).timeout
	var held: Node3D = stage.characters_parent()
	check(held.get_child_count() == 0, "Ren is a voice: his entrance stands no portrait on the stage")

	director.aurora_enters()
	await get_tree().create_timer(0.6).timeout
	check(stage.aurora_quad != null and is_instance_valid(stage.aurora_quad), "the guest's portrait is spawned")
	if stage.aurora_quad != null:
		check(held.get_child_count() == 1, "exactly one portrait stands on the stage")
		check(stage.aurora_quad.get_parent() == held, "the portrait is parented under World3D/Characters")
		check(stage.aurora_quad.global_position.distance_to(ShowStageScript.AURORA_MARK) < 0.01,
			"the guest stands on her mark")
		var quad := stage.aurora_quad as Sprite3DQuad
		check(quad.texture != null, "the portrait has a texture")
		check(quad.world_height > 0.5, "the portrait is a standing height")

	# The postcard for the review: the guest must be inside the broadcast frame.
	var cam: Camera3D = stage.camera()
	var p: Vector2 = cam.unproject_position(stage.aurora_quad.global_position + Vector3(0, 0.9, 0))
	check(p.x > 0.0 and p.x < 1280.0 and p.y > 0.0 and p.y < 720.0, "the guest lands inside the camera frame")
	# Rewind the REAL dialogue balloon across arrival and a settled gem round.
	# These used to delete the restored quad after GameState spawned it, or
	# leave queued old quads/gems in the scene until the next render frame.
	var gs := get_node("/root/GameState")
	gs.show_aurora_key = "aurora_serious"
	gs.show_part = "EYES"
	gs.show_mod = "GLOWING"
	gs.show_part_face = 1
	gs.show_mod_face = 7
	gs.show_props_round = 1
	var with_guest: Dictionary = gs.snapshot()
	var idx: int = balloon.history_cursor
	check(idx >= 0, "a dialogue history line exists for rewind")
	if idx >= 0:
		for n in 3:
			balloon.history[idx]["state"] = with_guest.duplicate(true)
			await balloon.rollback_to(idx)
			check(held.get_child_count() == 1 and stage.aurora_quad.get_parent() == held,
				"rewind %d leaves exactly one live on-stage guest" % n)
			check(stage._gems.size() == 2 and stage._chip != null and stage._props.get_child_count() > 0,
				"rewind %d rebuilds gems, chip and trial" % n)
			var visible_gems := 0
			var visible_chips := 0
			var visible_props := 0
			for child in stage.get_children():
				if child is FlatTopGem and child.build_words:
					visible_gems += 1
				if child.name == "ModChip":
					visible_chips += 1
				if child.name == "Props":
					visible_props += 1
			check(visible_gems == 2 and visible_chips == 1 and visible_props == 1,
				"rewind %d has no overlapping old show furniture" % n)
		gs.show_aurora_key = ""
		gs.show_part = ""
		gs.show_mod = ""
		gs.show_part_face = -1
		gs.show_mod_face = -1
		gs.show_props_round = 0
		balloon.history[idx]["state"] = gs.snapshot()
		await balloon.rollback_to(idx)
		check(held.get_child_count() == 0 and stage.aurora_quad == null,
			"rewinding before arrival removes the guest")
		check(stage._gems.is_empty() and stage._chip == null,
			"rewinding before the gem round removes the gems and chip")
	balloon._restore_panic_place({"state": with_guest.duplicate(true), "bg": "none", "left": "none", "right": "none", "focus": ""})
	check(held.get_child_count() == 1 and stage._gems.size() == 2,
		"panic-place restore keeps guest and gems after motion replay")

	# Held skip must not relatch after release at a choice (or after toolbar
	# toggles it off); the next selected line may NOT re-enable skip itself.
	balloon._set_skip_active(true)
	balloon._resume_skip_after_choice = true
	balloon._set_skip_active(false)
	check(not balloon.skip_mode and not balloon._resume_skip_after_choice,
		"releasing held skip at a choice clears its resume intent")
	balloon._set_skip_active(true)
	balloon._resume_skip_after_choice = true
	balloon._toggle_skip()
	check(not balloon.skip_mode and not balloon._resume_skip_after_choice,
		"turning skip off in toolbar cannot resume after the choice")

	main.queue_free()
	await get_tree().process_frame
