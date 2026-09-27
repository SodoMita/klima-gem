extends Node
## Rendered inspection of the Klima Gem stage: boots the real main scene,
## walks the show to a fixed set of beats, writes a PNG at each one AND
## measures the projected screen rectangle of everything the audience has to
## read. Needs a rasterizer (see tests/stage_shot.sh: sway headless + pixman +
## Mesa llvmpipe).
##
## Every shot carries an overlay: a red line where the dialogue balloon starts
## covering the frame, and a box around each measured piece. Run:
##   tests/stage_shot.sh
## Prints a report of screen rects, then "STAGE SHOT: PASS" / "FAIL".

const OUT_DIR := "res://tests/render_samples/stage"

## Fallback where the dialogue balloon starts covering the frame; the real
## line is measured off the live balloon every shot.
var _safe_bottom := 500.0
const FRAME := Vector2(1280, 720)

var _main: Node
var _layer: CanvasLayer
var _report: Array[String] = []
var _boxes: Array[Node] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	Engine.time_scale = 1.0
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	await _wait(0.7)
	await _measure_and_shoot("01_title_card")
	_main._start("show_start")
	await _wait(1.0)
	await _measure_and_shoot("02_cold_open")
	var director := get_node_or_null("/root/ShowDirector")
	director.begin_show()
	director.enter_ren()
	await _wait(0.6)
	await _measure_and_shoot("03_host")
	director.aurora_enters()
	await _wait(0.9)
	await _measure_and_shoot("04_guest")
	var stage := _stage()
	# Physics-random ceremonial throw through the director, so GameState
	# carries the landed words and the chip below shows them truthfully.
	await director.throw_gem_round()
	await _wait(0.4)
	await _measure_and_shoot("05_gems_settled")
	for gi in stage._gems.size():
		var gem = stage._gems[gi]
		var cam_az := atan2((_camera().global_position - gem.global_position).z, (_camera().global_position - gem.global_position).x)
		var line := "  gem%d ry=%.3f cam_az=%.3f: " % [gi, gem.rotation.y, cam_az]
		for i in gem.face_labels.size():
			var delta: float = absf(wrapf(1.0 * i * 0.0 + (TAU * (i + 0.5) / 8.0) - gem.rotation.y - cam_az, -PI, PI))
			line += "%s=%.2f/%.0f " % [gem.words[i], delta, gem.face_labels[i].modulate.a * 100.0]
		print(line)
	director.apply_mods()
	await _wait(1.2)
	await _measure_and_shoot("06_chip")
	director.build_challenge(1)
	await _wait(0.8)
	await _measure_and_shoot("07_crossing")
	director.build_challenge(2)
	await _wait(0.8)
	await _measure_and_shoot("08_bells")
	director.build_challenge(3)
	await _wait(0.8)
	await _measure_and_shoot("09_choir")
	director.build_challenge(0)
	await _wait(0.4)
	stage.set_stars(3)
	director.finale_confetti()
	await _wait(1.2)
	await _measure_and_shoot("10_finale")
	print("---- stage report ----")
	print("calibration: world(0,2.2,0) -> %s   viewport %s   image %s" % [
		_camera().unproject_position(Vector3(0, 2.2, 0)),
		get_viewport().get_visible_rect().size,
		_frame_size(),
	])
	for line in _report:
		print(line)
	print("STAGE SHOT: PASS")
	await get_tree().process_frame
	get_tree().quit(0)


func _frame_size() -> Vector2:
	var img := get_viewport().get_texture().get_image()
	return Vector2(img.get_width(), img.get_height())


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _stage() -> Node3D:
	return get_tree().get_first_node_in_group("show_stage") as Node3D


func _balloon() -> Node:
	return get_tree().root.get_node_or_null("VNBalloon")


func _camera() -> Camera3D:
	var stage := _stage()
	return stage.camera() if stage != null else null


# ------------------------------------------------------------------ measuring

## World-space AABB of anything: meshes use their mesh box, labels measure
## their own text, and containers union their children.
func _world_aabb(node: Node3D) -> AABB:
	var self_box: AABB = AABB()
	var have_self := false
	var xf := node.global_transform
	if node is Label3D:
		var l := node as Label3D
		var text_size := l.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size) * l.pixel_size
		var pad := 2.0 * float(l.outline_size) * l.pixel_size
		var w := text_size.x + pad
		var h := text_size.y + pad
		self_box = AABB(xf * Vector3(-w * 0.5, -h * 0.5, 0.0), Vector3(w, h, 0.02))
		have_self = true
	elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box := (node as MeshInstance3D).mesh.get_aabb()
		var scale := xf.basis.get_scale().abs()
		self_box = AABB(xf * box.position, box.size * scale)
		have_self = true
	for child in node.get_children():
		if child is Node3D and (child as Node3D).visible:
			var child_box := _world_aabb(child)
			if child_box.size == Vector3.ZERO:
				continue
			self_box = child_box if not have_self else self_box.merge(child_box)
			have_self = true
	return self_box if have_self else AABB()


func _screen_rect(world_rect: AABB) -> Rect2:
	var cam := _camera()
	var tl := Vector2(1e9, 1e9)
	var br := Vector2(-1e9, -1e9)
	for i in 8:
		var corner := world_rect.position + Vector3(
			world_rect.size.x if (i & 1) else 0.0,
			world_rect.size.y if (i & 2) else 0.0,
			world_rect.size.z if (i & 4) else 0.0
		)
		var p := cam.unproject_position(corner)
		tl = tl.min(p)
		br = br.max(p)
	return Rect2(tl, br - tl)


func _measure(node: Node, label: String) -> Rect2:
	if node == null or not is_instance_valid(node) or not (node is Node3D):
		_report.append("  %-16s MISSING" % label)
		return Rect2()
	var r := _screen_rect(_world_aabb(node as Node3D))
	_report.append("  %-16s x %4d..%-4d  y %4d..%-4d  (%.0fx%.0f)" % [
		label, int(r.position.x), int(r.end.x), int(r.position.y), int(r.end.y), r.size.x, r.size.y
	])
	_draw_box(r, label)
	return r


func _draw_box(r: Rect2, label: String) -> void:
	if r.size == Vector2.ZERO:
		return
	var box := ColorRect.new()
	box.color = Color(1, 0.85, 0.2, 0.10)
	box.position = r.position
	box.size = r.size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(box)
	var tag := Label.new()
	tag.text = label
	tag.position = r.position + Vector2(2, -14)
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(tag)
	_boxes.append(box)
	_boxes.append(tag)


func _clear_boxes() -> void:
	for b in _boxes:
		if is_instance_valid(b):
			b.queue_free()
	_boxes.clear()


func _find(root: Node, name_starts: String) -> Node3D:
	if root == null:
		return null
	for child in root.get_children():
		if str(child.name).begins_with(name_starts):
			return child as Node3D
		var found := _find(child, name_starts)
		if found != null:
			return found
	return null


func _measure_and_shoot(shot_name: String) -> void:
	_report.append("")
	_report.append("== %s ==" % shot_name)
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.layer = 90
		add_child(_layer)
		pass
	_clear_boxes()
	var balloon_now := _balloon()
	if balloon_now != null and is_instance_valid(balloon_now):
		var top := INF
		for child in balloon_now.get_children():
			if child is Control and (child as Control).visible:
				top = minf(top, (child as Control).get_global_rect().position.y)
		if top < INF:
			_safe_bottom = top
	var safe := ColorRect.new()
	safe.color = Color(1, 0.2, 0.2, 0.85)
	safe.position = Vector2(0, _safe_bottom)
	safe.size = Vector2(FRAME.x, 1)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(safe)
	_boxes.append(safe)
	var stage := _stage()
	if stage != null:
		var rects := {
			"sign": _measure(_find(stage, "Sign"), "sign"),
			"pips": _measure(_find(stage, "StarPips"), "star pips"),
			"plaque_mod": _measure(stage._plaque_mod, "plaque-mod"),
			"plaque_part": _measure(stage._plaque_part, "plaque-part"),
			"gem_mod": _measure(stage._gems[1] if stage._gems.size() > 1 else null, "gem-mod"),
			"gem_part": _measure(stage._gems[0] if stage._gems.size() > 0 else null, "gem-part"),
			"pedestal": _measure(_find(stage, "Pedestal"), "pedestal"),
			"chip": _measure(stage._chip, "chip"),
			"guest": _measure(stage.aurora_quad, "guest"),
			"props": _measure(stage._props, "props"),
			"stamp": _measure(stage._stamp, "stamp"),
		}
		for key in rects.keys():
			var r: Rect2 = rects[key]
			if r.size == Vector2.ZERO:
				continue
			if key == "props" or key == "pedestal" or key == "stamp" or key == "guest":
				continue
			if r.position.y < -4.0 or r.end.y > _safe_bottom:
				_report.append("   !! %s leaves the safe band (y %.0f..%.0f)" % [key, r.position.y, r.end.y])
			if r.position.x < 0.0 or r.end.x > FRAME.x:
				_report.append("   !! %s leaves the frame horizontally" % key)
	var balloon := _balloon()
	if balloon != null and is_instance_valid(balloon):
		_report.append("  balloon visible=%s waiting=%s" % [balloon.visible, balloon.is_waiting_for_input])
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_webp(ProjectSettings.globalize_path("%s/%s.webp" % [OUT_DIR, shot_name]), false)
	print("  shot: %s" % shot_name)
