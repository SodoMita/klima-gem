extends Node
## Visual proof of the under-view reveal: throws the stones, then saves a
## frame while the camera is under the glass floor and one of the house shot.
## Output goes to user://u2_shots (never into the repo).
const OUT := "user://u2_shots"
var _stage: ShowStage
var _got_under := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("U2 SHOTS: ", ProjectSettings.globalize_path(OUT))
	_stage = load("res://scenes/show_stage/show_stage.tscn").instantiate()
	add_child(_stage)
	await get_tree().create_timer(0.6).timeout
	await _shot("00_house")
	_watch()
	await _stage.throw_gems(RandomNumberGenerator.new())
	await get_tree().create_timer(1.0).timeout
	await _shot("03_house_settled")
	print("U2 SHOT: ", "PASS" if _got_under else "FAIL no under-view frame")
	get_tree().quit(0 if _got_under else 1)


func _watch() -> void:
	while is_instance_valid(_stage):
		await get_tree().process_frame
		var cam := _stage.camera()
		if cam != null and cam.global_position.y < _stage.BOX_CENTER.y - 0.3 and not _got_under:
			_got_under = true
			await _shot("01_underview_a")
			await get_tree().create_timer(0.5).timeout
			await _shot("02_underview_b")


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/" + tag + ".png"))
