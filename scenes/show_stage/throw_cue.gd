class_name ThrowCue extends Node
## The player's hand on the throw. While a cue is open the stage shows a
## reticle on the glass floor that follows the cursor (or the stick), and a
## prompt over the case. Press and hold with the mouse, a finger, Space /
## Enter, or a gamepad face button; the length of the hold is the power, and
## the point under the cursor at release is where the stone is aimed.
##
## Nothing about the outcome is chosen here. The cue only returns an aim
## point, a power and a fistful of entropy (release time in microseconds
## mixed with the cursor position) so that no two throws are ever the same
## — the stone still decides by the face it comes to rest on.

signal released

const HOLD_FULL := 1.1
const POWER_MIN := 0.8
const POWER_MAX := 1.5
const STICK_SPEED := 2.2

## Centre of the glass floor (world) and the half size of the aimable area.
var floor_center := Vector3.ZERO
var half_extent := Vector2(1.2, 0.6)
var camera: Camera3D = null
var aim := Vector3.ZERO
var holding := false
var _hold_time := 0.0
var _done := false
var _manual := false
var _stick := Vector2.ZERO
var _pointer_seen := false
var _last_pointer := Vector2.ZERO
var _reticle: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _prompt: Label3D = null
var _prompt_text := ""
var _entropy := 0


func _ready() -> void:
	set_process_input(false)
	set_process(false)


func is_open() -> bool:
	return is_processing_input()


## Open the cue and wait for a release (or [param timeout] seconds, after
## which the stone is thrown for the player). Returns
## {aim, power, entropy, manual}.
func wait(text: String, timeout: float) -> Dictionary:
	_prompt_text = text
	_done = false
	_manual = false
	holding = false
	_hold_time = 0.0
	_pointer_seen = false
	aim = floor_center
	_build_visuals()
	set_process(true)
	set_process_input(true)
	var waited := 0.0
	while not _done and waited < timeout:
		await get_tree().process_frame
		if not is_inside_tree():
			break
		waited += get_process_delta_time()
	set_process_input(false)
	set_process(false)
	_clear_visuals()
	if not _done:
		# Nobody threw: the case throws for the player, from wherever the
		# cursor happened to be, with a hold nobody timed.
		_hold_time = randf_range(0.2, 0.9)
		_mix_entropy()
	var power := lerpf(POWER_MIN, POWER_MAX, clampf(_hold_time / HOLD_FULL, 0.0, 1.0))
	return {"aim": aim, "power": power, "entropy": _entropy, "manual": _manual}


func _process(delta: float) -> void:
	if _stick.length() > 0.15:
		aim.x += _stick.x * STICK_SPEED * delta
		aim.z += _stick.y * STICK_SPEED * delta
	elif _pointer_seen:
		_aim_from_pointer(_last_pointer)
	aim.x = clampf(aim.x, floor_center.x - half_extent.x, floor_center.x + half_extent.x)
	aim.z = clampf(aim.z, floor_center.z - half_extent.y, floor_center.z + half_extent.y)
	aim.y = floor_center.y
	if holding:
		_hold_time += delta
	if is_instance_valid(_reticle):
		_reticle.global_position = Vector3(aim.x, floor_center.y + 0.015, aim.z)
		var charge := clampf(_hold_time / HOLD_FULL, 0.0, 1.0)
		_reticle.scale = Vector3.ONE * (1.0 + 0.6 * charge)
		var mat := _reticle.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = 1.5 + 4.0 * charge
			mat.albedo_color = Color(1.0, 0.95 - 0.6 * charge, 0.45 - 0.3 * charge, 0.9)
	if is_instance_valid(_ring):
		_ring.rotation.y += delta * 1.4
		_ring.visible = holding


func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed := false
	var released_now := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_last_pointer = mb.position
		_pointer_seen = true
		pressed = mb.pressed
		released_now = not mb.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_last_pointer = (event as InputEventMouseMotion).position
		_pointer_seen = true
		_stick = Vector2.ZERO
		return
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_last_pointer = st.position
		_pointer_seen = true
		pressed = st.pressed
		released_now = not st.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_last_pointer = (event as InputEventScreenDrag).position
		_pointer_seen = true
		return
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			if k.echo:
				return
			pressed = k.pressed
			released_now = not k.pressed
		elif k.keycode == KEY_LEFT or k.keycode == KEY_A:
			_stick.x = -1.0 if k.pressed else 0.0
			_pointer_seen = false
			return
		elif k.keycode == KEY_RIGHT or k.keycode == KEY_D:
			_stick.x = 1.0 if k.pressed else 0.0
			_pointer_seen = false
			return
		elif k.keycode == KEY_UP or k.keycode == KEY_W:
			_stick.y = -1.0 if k.pressed else 0.0
			_pointer_seen = false
			return
		elif k.keycode == KEY_DOWN or k.keycode == KEY_S:
			_stick.y = 1.0 if k.pressed else 0.0
			_pointer_seen = false
			return
		else:
			return
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.button_index != JOY_BUTTON_A and jb.button_index != JOY_BUTTON_B and jb.button_index != JOY_BUTTON_X:
			return
		pressed = jb.pressed
		released_now = not jb.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_LEFT_X:
			_stick.x = jm.axis_value if absf(jm.axis_value) > 0.15 else 0.0
			_pointer_seen = false
		elif jm.axis == JOY_AXIS_LEFT_Y:
			_stick.y = jm.axis_value if absf(jm.axis_value) > 0.15 else 0.0
			_pointer_seen = false
		return
	else:
		return
	if pressed and not holding:
		holding = true
		_hold_time = 0.0
	elif released_now and holding:
		holding = false
		_manual = true
		_done = true
		_mix_entropy()
		released.emit()


## Where the cursor's ray meets the glass floor plane.
func _aim_from_pointer(px: Vector2) -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var origin := camera.project_ray_origin(px)
	var dir := camera.project_ray_normal(px)
	var plane := Plane(Vector3.UP, floor_center.y)
	var hit: Variant = plane.intersects_ray(origin, dir)
	var p: Vector3
	if hit == null:
		# Ray never reaches the floor height: take its point at the case.
		var t := (floor_center.z - origin.z) / dir.z if absf(dir.z) > 0.001 else 8.0
		p = origin + dir * maxf(t, 0.0)
	else:
		p = hit
	aim = Vector3(p.x, floor_center.y, p.z)


func _mix_entropy() -> void:
	var t := Time.get_ticks_usec()
	var h := hash(Vector2(_last_pointer.x, _last_pointer.y)) ^ hash(_hold_time) ^ hash(aim)
	_entropy = int((t ^ (h << 7) ^ (t >> 13)) & 0x7fffffff)


func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _build_visuals() -> void:
	_clear_visuals()
	var parent := get_parent()
	if parent == null:
		return
	var torus := TorusMesh.new()
	torus.inner_radius = 0.12
	torus.outer_radius = 0.17
	torus.rings = 24
	torus.ring_segments = 8
	_reticle = MeshInstance3D.new()
	_reticle.name = "ThrowReticle"
	_reticle.mesh = torus
	_reticle.material_override = _unshaded(Color(1.0, 0.95, 0.45, 0.9))
	_reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(_reticle)
	_reticle.global_position = Vector3(aim.x, floor_center.y + 0.015, aim.z)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.26
	ring_mesh.outer_radius = 0.29
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.name = "ThrowChargeRing"
	_ring.mesh = ring_mesh
	_ring.material_override = _reticle.material_override
	_ring.visible = false
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle.add_child(_ring)

	_prompt = Label3D.new()
	_prompt.name = "ThrowPrompt"
	_prompt.text = _prompt_text
	_prompt.font_size = 40
	_prompt.outline_size = 10
	_prompt.pixel_size = 0.006
	_prompt.modulate = Color(1.0, 0.95, 0.6)
	_prompt.outline_modulate = Color(0.02, 0.04, 0.1, 0.95)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.render_priority = 5
	parent.add_child(_prompt)
	_prompt.global_position = floor_center + Vector3(0.0, 1.85, 0.0)
	var tw := _prompt.create_tween().set_loops(0)
	tw.tween_property(_prompt, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_prompt, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func _clear_visuals() -> void:
	for n in [_reticle, _prompt]:
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	_reticle = null
	_ring = null
	_prompt = null
