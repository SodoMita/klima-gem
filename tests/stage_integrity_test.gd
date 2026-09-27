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
	get_tree().create_timer(420.0, true, false, true).timeout.connect(_on_watchdog)
	_test_physics_is_on()
	_test_facet_words_are_welded()
	_test_dialogue_colons()
	await _test_gem_throw_is_physics()
	await _test_portrait_on_stage()
	await _test_rewind_resets_stars()
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
		if off_plane <= 0.005 and from_centre <= 0.03:
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

	# Crown words: in their trapezoid's plane, inside it, facing out.
	check(gem.crown_labels.size() == 8, "eight crown (upper face) words are built")
	for i in gem.crown_labels.size():
		var cl := gem.crown_labels[i]
		var n := gem.local_face_normal(FlatTopGem.SIDES + i)
		check(cl.basis.z.normalized().dot(n) > 0.999, "crown %d word lies in its face plane" % i)
		var cc := gem.crown_corners(i)
		check(absf((cl.position - cc[0]).dot(n) - FlatTopGem.WORD_LIFT) < 0.001, "crown %d word sits on its face" % i)
		check(cl.text == gem.words[i], "crown %d carries the same word as pavilion %d" % [i, i])
	check(gem.top_label != null and gem.top_label.basis.z.normalized().dot(Vector3.UP) > 0.999, "the table word lies flat on the table")

	# Fair reading: rest the stone on each face and read it back.
	for f in 2 * FlatTopGem.SIDES + 1:
		var down_n: Vector3 = gem.local_face_normal(f)
		# Orient so that face's normal points straight down.
		var rest_basis := Basis(Vector3.RIGHT, PI) if f == FlatTopGem.TABLE_FACE else Basis(Quaternion(down_n, Vector3.DOWN))
		gem.global_transform = Transform3D(rest_basis, Vector3.ZERO)
		var want := FlatTopGem.TOP_FACE if f == 2 * FlatTopGem.SIDES else f % FlatTopGem.SIDES
		check(gem.resting_face() == want, "resting on face %d reads result %d (got %d)" % [f, want, gem.resting_face()])

	# Presentation turns the result's word squarely to any viewer.
	for viewer in [Vector3(0, 2.2, 9.4), Vector3(3, 1, 4), Vector3(-4, 3, 2)]:
		var wrong := 0
		for face in FlatTopGem.TOP_FACE + 1:
			gem.snap_settled(Vector3.ZERO, face, viewer)
			var lab := gem.label_for(face)
			if lab.global_basis.z.normalized().dot((viewer - lab.global_position).normalized()) < 0.98:
				wrong += 1
		check(wrong == 0, "every result word turns to the viewer at %s" % viewer)
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
	check(stage.get_node_or_null("ThrowBox") is StaticBody3D and stage.get_node_or_null("Physics/PlatformBody") is StaticBody3D, "the authored stage carries the closed box and floor colliders")
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
	# Outside the floating glass case (its lid is at y ~3.05 over the box).
	gem.position = Vector3(2.4, 3.0, -1.5)
	gem.throw_with_velocity(Vector3(2.4, 3.0, -1.5), Vector3(0.0, 3.0, 0.0), Vector3(2.0, 3.0, 1.0))
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
		check(int(faces[0]) >= 0 and int(faces[0]) <= FlatTopGem.TOP_FACE, "the part face is a legal face (%s)" % faces[0])
		check(int(faces[1]) >= 0 and int(faces[1]) <= FlatTopGem.TOP_FACE, "the mod face is a legal face (%s)" % faces[1])
	check(stage._gems.size() == 2, "two gems come back")
	for i in stage._gems.size():
		var g: FlatTopGem = stage._gems[i]
		check(g.settled, "gem %d reports itself settled" % i)
		var rel := g.global_position - ShowStageScript.BOX_CENTER
		var half := ShowStageScript.BOX_SIZE * 0.5
		check(absf(rel.x) <= half.x + 0.01 and absf(rel.y) <= half.y + 0.01 and absf(rel.z) <= half.z + 0.01,
			"gem %d rests where it landed, inside the closed glass box (%s)" % [i, g.global_position])
	if stage._gems.size() == 2 and faces.size() == 2:
		var lab0: Label3D = stage._gems[0].label_for(int(faces[0]))
		check(lab0 != null and lab0.global_basis.z.normalized().y < -0.45,
			"the part gem rests on the face it landed on, readable through the glass floor")
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


# ------------------------------------------ 6 - rewinding un-wins the trial

## Play the real balloon forward through the first trial (advancing like a
## player, taking the first allowed answer at every choice), then rewind to
## the line spoken BEFORE the trial ran and demand that the star count — in
## GameState and on the pips — is the count from before the trial.
func _test_rewind_resets_stars() -> void:
	print("-- rewind un-wins --")
	var main: Node = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	main._start("show_start")
	await get_tree().create_timer(0.8).timeout
	var director := get_node_or_null("/root/ShowDirector")
	var balloon: Node = director._balloon() if director != null else null
	check(balloon != null, "the balloon is running for the rewind test")
	if balloon == null:
		main.queue_free()
		return
	var gs := get_node("/root/GameState")
	var stage := get_tree().get_first_node_in_group("show_stage")
	if stage != null:
		stage.interactive_throws = false
	Engine.time_scale = 4.0
	var before_idx := -1
	var after_seen := false
	var stars_before := -1
	var steps := 0
	while steps < 1500 and not after_seen:
		steps += 1
		await get_tree().create_timer(0.05).timeout
		if not balloon.is_waiting_for_input:
			continue
		var line = balloon.dialogue_line
		if line == null:
			continue
		var text := str(line.text)
		if text.begins_with("(Actions, not luck"):
			before_idx = int(balloon.history_cursor)
			stars_before = int(gs.show_stars)
		if text.begins_with("A star peels off") or text.begins_with("I was SO close"):
			after_seen = true
			break
		if line.responses.size() > 0:
			var picked = null
			for r in line.responses:
				if r.is_allowed:
					picked = r
					break
			if picked != null:
				balloon.next(picked.next_id)
			continue
		balloon.next(line.next_id)
	Engine.time_scale = 1.0
	var last_line = balloon.dialogue_line
	print("    last line: ", (str(last_line.text).left(60) if last_line != null else "<none>"), " waiting=", balloon.is_waiting_for_input, " round=", gs.show_round)
	check(after_seen, "the balloon played through trial 1 (%d steps)" % steps)
	check(before_idx >= 0, "the pre-trial line is in the backlog")
	if after_seen and before_idx >= 0:
		var stars_after := int(gs.show_stars)
		check(stars_after == stars_before + (1 if bool(gs.last_success) else 0), "the trial's outcome moved the stars (%d -> %d)" % [stars_before, stars_after])
		await balloon.rollback_to(before_idx)
		await get_tree().create_timer(0.3).timeout
		check(int(gs.show_stars) == stars_before, "rewinding to before the trial resets the stars (%d, want %d)" % [int(gs.show_stars), stars_before])
		if stage != null:
			var lit := 0
			for pip in stage._pips:
				var mat := pip.material_override as StandardMaterial3D
				if mat != null and mat.emission_energy_multiplier > 1.0:
					lit += 1
			check(lit == stars_before, "the pips show the rewound count (%d lit, want %d)" % [lit, stars_before])
			check(not is_instance_valid(stage._stamp) or not stage._stamp.visible, "the CLEAR/MISS stamp is gone after the rewind")
	main.queue_free()
	await get_tree().process_frame
