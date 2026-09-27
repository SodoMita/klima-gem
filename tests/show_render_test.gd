extends Node
## Rendered verification of the Klima Gem show. Boots the real main scene
## (title card over the live studio), plays the show like a player would,
## and saves a screenshot at every production beat. Needs a rasterizer:
## run it under sway headless with the pixman compositor and Mesa llvmpipe
## (see tests/show_render_test.sh). Prints "SHOW RENDER TEST: PASS" and
## exits 0 when the expected shots exist.

const OUT_DIR := "res://tests/render_samples/show"

var _main: Node
var _shot_taken := {}


func _ready() -> void:
	# The budget is for the full show; if the booted story does not reach END
	# in time we still judge the shots we did get, rather than failing the run
	# on a timeout (the seeded playthrough is covered headlessly by
	# tests/show_stage_test.sh).
	get_tree().create_timer(300.0, true, false, true).timeout.connect(_on_watchdog)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# The throw is real physics now, so the beats take wall-clock time that a
	# high time scale cannot compress.
	Engine.time_scale = 3.0
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	get_tree().create_timer(0.8, true, false, true).timeout.connect(_capture_title)
	_drive()
	_watch()


func _on_watchdog() -> void:
	print("SHOW RENDER TEST: watchdog reached, judging the shots taken so far")
	_save_state_shot("99_watchdog")
	_judge()


func _stage() -> Node3D:
	return get_tree().get_first_node_in_group("show_stage") as Node3D


func _balloon() -> Node:
	return get_tree().root.get_node_or_null("VNBalloon")


func _capture_title() -> void:
	await _shot("01_title")


func _shot(shot_name: String) -> void:
	if _shot_taken.has(shot_name):
		return
	_shot_taken[shot_name] = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot_name])
	img.save_png(path)
	print("  shot: %s" % shot_name)


func _save_state_shot(shot_name: String) -> void:
	if _shot_taken.has(shot_name):
		return
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_webp(ProjectSettings.globalize_path("%s/%s.webp" % [OUT_DIR, shot_name]), false)


## Keep pressing the show forward like an impatient player.
var _nudges := 0

func _drive() -> void:
	while is_inside_tree():
		await get_tree().create_timer(0.3, true, false, true).timeout
		var balloon := _balloon()
		if balloon == null or not is_instance_valid(balloon):
			# The title card is up: knock.
			_nudges += 1
			var ev := InputEventAction.new()
			ev.action = &"dialogue_advance"
			ev.pressed = true
			Input.parse_input_event(ev)
			if _nudges > 10 and is_instance_valid(_main) and not _shot_taken.has("started"):
				_shot_taken["started"] = true
				_main._start("show_start")
			continue
		if not _shot_taken.has("started"):
			_shot_taken["started"] = true
		if not balloon.is_waiting_for_input:
			continue
		var line = balloon.dialogue_line
		if line == null:
			continue
		var responses: Array = line.responses
		if responses.size() > 0:
			# Rotate through choices across the run, so several paths get seen.
			var pick := _shot_taken.size() % responses.size()
			balloon.next(responses[pick].next_id)
		else:
			balloon.next(line.next_id)


## Snap a screenshot the first time each production beat appears.
func _watch() -> void:
	while is_inside_tree():
		await get_tree().create_timer(0.25, true, false, true).timeout
		var stage := _stage()
		if stage == null or not is_instance_valid(stage):
			continue
		var balloon := _balloon()

		if not _shot_taken.has("02_throw") and stage._gems.size() == 2:
			await _shot("02_throw")
		if not _shot_taken.has("03_words") and is_instance_valid(stage._plaque_part) \
				and is_instance_valid(stage._plaque_mod) \
				and stage._plaque_part.get_meta("landed", false) \
				and stage._plaque_mod.get_meta("landed", false):
			await _shot("03_words")
		if not _shot_taken.has("04_chip") and is_instance_valid(stage._chip):
			await _shot("04_chip")
		var props_up: int = stage._props.get_child_count() if is_instance_valid(stage._props) else 0
		if props_up > 0:
			match int(_gs().show_round):
				1:
					if not _shot_taken.has("05_crossing"):
						await _shot("05_crossing")
				2:
					if not _shot_taken.has("06_bells"):
						await _shot("06_bells")
				3:
					if not _shot_taken.has("07_choir"):
						await _shot("07_choir")
		if not _shot_taken.has("08_stamp") and is_instance_valid(stage._stamp):
			await _shot("08_stamp")
		if balloon == null or not is_instance_valid(balloon):
			continue
		if not balloon.visible and _shot_taken.has("08_stamp"):
			await _shot("09_finale")
			break
	_judge()


## The core production beats must all have been photographed.
func _judge() -> void:
	var expected := ["01_title", "02_throw", "03_words", "04_chip", "05_crossing", "08_stamp"]
	var missing: Array[String] = []
	for key in expected:
		if not _shot_taken.has(key):
			missing.append(key)
	if missing.is_empty():
		print("SHOW RENDER TEST: PASS (%d shots)" % _shot_taken.size())
		get_tree().quit(0)
	else:
		printerr("SHOW RENDER TEST: missing shots: " + ", ".join(missing))
		print("SHOW RENDER TEST: FAIL")
		get_tree().quit(1)


func _gs() -> Node:
	return get_node("/root/GameState")
