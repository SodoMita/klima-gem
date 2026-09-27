extends Node
## Fair-throw check on the authored stage: throws both gems for real, then
## verifies each reported word is the crown face that physically faces the
## sky, the stone was not moved after it settled, and it stayed in the box.
## Saves shots to tests/render_samples/joker/ when a rasterizer is present.
const OUT := "res://tests/render_samples/joker"
var _stage: ShowStage
var _fail := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_stage = load("res://scenes/show_stage/show_stage.tscn").instantiate()
	add_child(_stage)
	await get_tree().create_timer(0.5).timeout
	await _shot("00_empty")
	var counts := {}
	var runs := int(OS.get_environment("JOKER_RUNS")) if OS.get_environment("JOKER_RUNS") != "" else 2
	for run in runs:
		_shoot_during(run)
		var faces: Array = await _stage.throw_gems(RandomNumberGenerator.new())
		if faces.size() != 2:
			_err("throw returned %s" % [faces])
			continue
		for gi in 2:
			var gem: FlatTopGem = _stage._gems[gi]
			var up := gem.up_face()
			if up != int(faces[gi]):
				_err("gem %d reported %d but face %d is up" % [gi, faces[gi], up])
			var p := gem.global_position - ShowStage.BOX_CENTER
			if absf(p.x) > ShowStage.BOX_HALF.x or absf(p.z) > ShowStage.BOX_HALF.z or gem.global_position.y < ShowStage.STAGE_TOP - 0.05:
				_err("gem %d left the box at %s" % [gi, gem.global_position])
			counts["%d:%d" % [gi, up]] = int(counts.get("%d:%d" % [gi, up], 0)) + 1
		print("RUN %d faces=%s words=%s/%s" % [run, faces, ShowStage.PARTS[faces[0]], ShowStage.MODS[faces[1]]])
		await _shot("%02d_settled" % (run + 1))
	print("DISTRIBUTION ", counts)
	_stage.place_gems_settled("", 3, "", 5)
	await get_tree().create_timer(0.3).timeout
	for gi in 2:
		var want := 3 if gi == 0 else 5
		if _stage._gems[gi].up_face() != want:
			_err("restore pose shows %d not %d" % [_stage._gems[gi].up_face(), want])
	await _shot("99_restored")
	print("JOKER THROW: ", "FAIL" if _fail else "PASS")
	get_tree().quit(1 if _fail else 0)


func _shoot_during(run: int) -> void:
	if run != 0:
		return
	await get_tree().create_timer(0.35).timeout
	await _shot("01a_flight")
	# Close-up happens after the first stone settles.
	while is_instance_valid(_stage) and (_stage._cam_tween == null or not _stage._cam_tween.is_valid()):
		await get_tree().process_frame
	await get_tree().create_timer(0.9).timeout
	await _shot("01b_closeup")


func _err(msg: String) -> void:
	_fail = true
	push_error("JOKER: " + msg)
	print("ERROR: ", msg)


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/" + name + ".png"))
