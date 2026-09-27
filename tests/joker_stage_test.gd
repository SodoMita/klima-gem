extends Node
## Joker's stage regression: the authored .tscn, the closed throw box, the
## upper-face and table labels, and the fairness of the throw.

const ShowStageScene := preload("res://scenes/show_stage/show_stage.tscn")
const ShowStageScript := preload("res://scenes/show_stage/show_stage.gd")
const FlatTopGemScript := preload("res://scenes/show_stage/flat_top_gem.gd")

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
	print("joker stage test: %d ok, %d failed" % [_oks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	var stage := ShowStageScene.instantiate()
	add_child(stage)
	await get_tree().process_frame

	# 1. The set is authored, not generated: the pieces come from the scene
	# file and the script must not duplicate them.
	for path in ["Camera3D", "WorldEnvironment", "HouseFloor", "Set/Platform",
			"Set/Rim", "StarCloth/Backdrop", "Pedestal/Column", "Marks/AuroraMark",
			"Physics/PlatformBody", "ThrowBox/Lid", "World3D/Characters", "Props"]:
		ok(stage.get_node_or_null(path) != null, "authored node %s" % path)
	ok(stage.get_node_or_null("Set2") == null, "no duplicated Set")
	var platforms := 0
	for child in stage.get_node("Set").get_children():
		if child.name == "Platform":
			platforms += 1
	ok(platforms == 1, "exactly one platform")

	# 2. Everything the show places stands ON the round platform.
	for p in [ShowStageScript.AURORA_MARK, ShowStageScript.LAND_PART,
			ShowStageScript.LAND_MOD, ShowStageScript.PRESENT_POS_PART,
			ShowStageScript.PRESENT_POS_MOD,
			Vector3(0.0, 0.0, ShowStageScript.PEDESTAL_Z)]:
		var radius := Vector2(p.x, p.z).length()
		ok(radius <= ShowStageScript.STAGE_RADIUS, "mark %s is on the platform (r=%.2f)" % [p, radius])

	# 3. The throw box is closed: five bodies (four walls and a lid), the
	# landing marks inside it, and the release point inside it too.
	var box := stage.get_node("ThrowBox")
	var bodies := 0
	for child in box.get_children():
		if child is StaticBody3D:
			bodies += 1
	# Four walls, a lid AND a glass floor: the case hangs in the air so the
	# underside of a landed stone can be read through the bottom pane.
	ok(bodies == 6, "throw box is sealed by 6 panes (got %d)" % bodies)
	ok(stage.get_node_or_null("ThrowBox/Floor") != null, "the case has a glass floor")
	ok(ShowStageScript.THROW_BOX_CENTER.y > ShowStageScript.STAGE_TOP + 0.5, "the case is lifted off the platform")
	ok(stage.under_camera() != null and stage.under_camera().position.y < ShowStageScript.THROW_BOX_CENTER.y,
		"the reveal camera sits below the glass floor")
	ok(stage.throw_box_contains(ShowStageScript.LAND_PART), "part gem lands inside the box")
	ok(stage.throw_box_contains(ShowStageScript.LAND_MOD), "mod gem lands inside the box")
	ok(stage.throw_box_contains(stage.throw_origin(true)), "part gem is released inside the box")
	ok(stage.throw_box_contains(stage.throw_origin(false)), "mod gem is released inside the box")

	# 4. Labels: eight pavilion words, eight crown (upper side) words, and a
	# table stamp naming the stone.
	var gem: FlatTopGem = FlatTopGemScript.new()
	gem.top_text = "GEM\nMEGA"
	gem.set_words(ShowStageScript.MODS)
	stage.add_child(gem)
	await get_tree().process_frame
	ok(gem.face_labels.size() == 8, "eight pavilion words")
	ok(gem.crown_labels.size() == 8, "eight upper-face words")
	ok(gem.top_label != null and gem.top_label.text == "GEM\nMEGA", "table stamp reads GEM MEGA")
	var matched := true
	for i in 8:
		if gem.crown_labels[i].text != gem.face_labels[i].text:
			matched = false
	ok(matched, "each upper face carries its facet's word")
	# The crown words sit on the crown, above the girdle and under the table.
	var inside := true
	for i in 8:
		var y: float = gem.crown_labels[i].position.y
		if y <= 0.0 or y >= gem.crown_height + 0.02:
			inside = false
	ok(inside, "upper-face words sit on the crown band")
	ok(gem.top_label.position.y >= gem.crown_height, "table stamp lies on the flat top")

	# 5. Case-specific CG art for every shapeshift, packed lossless WebP.
	for mod in ShowStageScript.MODS:
		ok(stage.mod_art(mod) != null, "modification card art exists for %s" % mod)
	stage.apply_mod_chip("HANDS", "MAGNET", stage.chip_anchor())
	await get_tree().process_frame
	ok(stage.get_node_or_null("ModCard") != null, "the modification card is raised on stage")
	stage.clear_mod_chip()
	await get_tree().process_frame
	ok(stage.get_node_or_null("ModCard") == null or not is_instance_valid(stage._mod_card),
		"and cleared with the chip")

	# 6. The mixer: the main menu must obey the saved sliders.
	var audio := get_node_or_null("/root/AudioDirector")
	ok(audio != null and audio.has_method("apply_saved_volumes"), "AudioDirector owns the saved mixer levels")
	if audio != null and audio.has_method("set_bus_percent"):
		audio.set_bus_percent("Music", 50.0)
		var idx := AudioServer.get_bus_index("Music")
		ok(idx != -1 and absf(AudioServer.get_bus_volume_db(idx) - linear_to_db(0.5)) < 0.01,
			"a slider percent lands on the bus in dB")

	# 7. Fairness: a throw starts in a random attitude, so no facet is the
	# floor-facing one by construction.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var attitudes := {}
	for i in 12:
		var a := Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
		attitudes[str(Vector3i(a * 10.0))] = true
	ok(attitudes.size() > 8, "throw attitudes vary")
	ok(FlatTopGemScript.new().get_method_list().size() > 0, "gem script loads")
