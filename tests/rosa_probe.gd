extends Node
## Rosa's diagnostic probe. Lives as a child of a copy of main.tscn so every
## node path matches the shipped game. Drives the show the way a player does
## (balloon.next on each waiting line) and saves screenshots + a scene-graph
## audit at each production beat, so defects can be SEEN, not argued about.
##
## Env knobs:
##   ROSA_TS      time_scale (default 2.0)
##   ROSA_CAM     "x,y,z,pitchdeg,fov" override of the stage camera
##   ROSA_SHOTS   comma list of beat names to capture (default all)

const OUT_DIR := "res://tests/render_samples/rosa"

var _shots := {}
var _want := {}


func _ready() -> void:
	get_tree().create_timer(240.0, true, false, true).timeout.connect(_on_watchdog)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	Engine.time_scale = float(OS.get_environment("ROSA_TS") if OS.get_environment("ROSA_TS") != "" else "2.0")
	for s in OS.get_environment("ROSA_SHOTS").split(","):
		if s.strip_edges() != "":
			_want[s.strip_edges()] = true
	var cam := OS.get_environment("ROSA_CAM")
	if cam != "":
		var p := cam.split(",")
		call_deferred("_move_camera", Vector3(float(p[0]), float(p[1]), float(p[2])), float(p[3]), float(p[4]))
	await get_tree().create_timer(1.0, true, false, true).timeout
	_shot("00_title")
	_drive()
	_watch()


func _on_watchdog() -> void:
	printerr("ROSA PROBE: watchdog timeout")
	print("ROSA PROBE: DONE (watchdog)")
	get_tree().quit(0)


func _move_camera(pos: Vector3, pitch: float, fov: float) -> void:
	var cam := _camera()
	if cam == null:
		return
	cam.position = pos
	cam.rotation_degrees = Vector3(pitch, 0, 0)
	cam.fov = fov
	print("ROSA CAM OVERRIDE: %s pitch=%f fov=%f" % [pos, pitch, fov])


func _camera() -> Camera3D:
	var st := _stage()
	if st == null:
		return null
	return st.get_node_or_null("Camera3D") as Camera3D


func _balloon() -> Node:
	var cs := get_tree().current_scene
	if cs != null:
		var b := cs.get_node_or_null("VNBalloon")
		if b != null:
			return b
	return get_tree().root.get_node_or_null("VNBalloon")


func _stage() -> Node3D:
	return get_tree().get_first_node_in_group("show_stage") as Node3D


func _gs() -> Node:
	return get_node("/root/GameState")


func _shot(shot_name: String) -> void:
	if _shots.has(shot_name):
		return
	if not _want.is_empty() and not _want.has(shot_name):
		return
	_shots[shot_name] = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot_name]))
	print("  shot: %s" % shot_name)


func _audit(tag: String) -> void:
	var st := _stage()
	var balloon := _balloon()
	print("AUDIT %s: balloon=%s motion=%s sprites=%d phys3d=%s" % [
		tag,
		"yes" if balloon != null else "null",
		str(balloon.get_node_or_null("MotionDirector") != null) if balloon != null else "-",
		(balloon.sprites.size() if balloon != null and "sprites" in balloon else -1),
		str(ProjectSettings.get_setting("physics/3d/physics_engine"))])
	if st == null:
		return
	var bodies := 0
	var colliders := 0
	var quads: Array[String] = []
	var stack: Array[Node] = [st]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is RigidBody3D:
			bodies += 1
		if n is CollisionShape3D:
			colliders += 1
		if String(n.name).begins_with("Sprite3D"):
			quads.append(String(n.name))
		for c in n.get_children():
			stack.append(c)
	print("AUDIT %s: rigidbodies=%d colshapes=%d quads=%s aurora=%s gems=%d props=%d" % [
		tag, bodies, colliders, str(quads),
		str(is_instance_valid(st.aurora_quad)),
		st._gems.size(), (st._props.get_child_count() if is_instance_valid(st._props) else -1)])
	for i in st._gems.size():
		var g: Node3D = st._gems[i]
		var nl: Array[String] = []
		for l in g.face_labels:
			nl.append("%s@%s" % [l.text, str(l.position).replace(" ", "").replace("(", "").replace(")", "")])
		print("AUDIT %s: gem%d pos=%s rotY=%f labels=%s" % [tag, i, str(g.position), g.rotation.y, str(nl)])


func _drive() -> void:
	var started := false
	var knocks := 0
	while is_inside_tree():
		await get_tree().create_timer(0.25, true, false, true).timeout
		var balloon := _balloon()
		if balloon == null or not is_instance_valid(balloon):
			if not started:
				knocks += 1
				var ev := InputEventAction.new()
				ev.action = &"dialogue_advance"
				ev.pressed = true
				Input.parse_input_event(ev)
				if knocks == 8:
					var cs := get_tree().current_scene
					if cs != null and cs.has_method("_start"):
						print("ROSA: input never reached the title; starting directly")
						cs._start("show_start")
			continue
		started = true
		var line = balloon.dialogue_line
		if line == null:
			continue
		# Finish the reveal from outside instead of using skip mode, which
		# owns its own auto-advance and would race this driver.
		if balloon.dialogue_label.is_typing:
			balloon.dialogue_label.skip_typing()
			await get_tree().process_frame
			continue
		var responses: Array = line.responses
		if responses.size() > 0:
			if balloon.responses_menu.visible:
				print("LINE %s | %s" % [str(line.character), str(line.text).left(60)])
				print("CHOICE x%d -> pick 0" % responses.size())
				balloon.responses_menu.response_selected.emit(responses[0])
				await get_tree().process_frame
			continue
		if not balloon.is_waiting_for_input:
			continue
		print("LINE %s | %s" % [str(line.character), str(line.text).left(60)])
		balloon.next(line.next_id)
		await get_tree().process_frame


## Screenshot on stage-state beats, same vocabulary as the render test.
func _watch() -> void:
	var advanced := 0
	while is_inside_tree():
		await get_tree().create_timer(0.25, true, false, true).timeout
		var st := _stage()
		if st == null or not is_instance_valid(st):
			continue
		if st._gems.size() == 2 and advanced == 0:
			advanced = 1
			_shot("01_throw")
			_audit("throw")
		if is_instance_valid(st._plaque_part) and is_instance_valid(st._plaque_mod) \
				and st._plaque_part.get_meta("landed", false) and st._plaque_mod.get_meta("landed", false) and advanced == 1:
			advanced = 2
			_shot("02_words")
			_audit("words")
		if is_instance_valid(st._chip) and advanced == 2:
			advanced = 3
			_shot("03_chip")
			_audit("chip")
		var props_up: int = st._props.get_child_count() if is_instance_valid(st._props) else 0
		if props_up > 0:
			match int(_gs().show_round):
				1:
					_shot("04_crossing")
					_audit("crossing")
				2:
					_shot("05_bells")
				3:
					_shot("06_choir")
		if is_instance_valid(st._stamp):
			_shot("07_stamp")
			_audit("stamp")
		var balloon := _balloon()
		if balloon != null and is_instance_valid(balloon) and not balloon.visible and advanced >= 3:
			_shot("08_finale")
			_audit("finale")
			print("ROSA PROBE: DONE")
			get_tree().quit(0)
			return
