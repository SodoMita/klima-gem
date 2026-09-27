class_name FlatTopGem extends RigidBody3D
## A Klima Gem: a diamond whose top is fully flat — an octagonal table where
## the octahedron's point used to be. Eight slanted pavilion faces, one word
## per face. Pure geometry: the mesh is built here, no painted textures.
##
## The gem is a real [RigidBody3D]. The throw is physics — an impulse, real
## gravity, real spin, real landing on the stage — and the show only takes
## over afterwards: the body freezes, lifts onto its mark, and turns the
## rolled face to the camera.
##
## Each word is welded to the facet that carries it: the label is placed at
## the facet's centroid, tipped to the facet's own slope, and scaled so the
## whole word fits inside the triangle it names. Faces turned away from the
## camera fade out, so a settled gem shows one word, not eight overlapped.

const SIDES := 8
## Best crown-face dot with UP below this = cocked landing, re-throw.
const COCKED_DOT := 0.55

## Facet triangles are narrow; the word is sized to this share of the facet's
## base edge so it never spills onto a neighbouring face.
const WORD_FIT := 0.82
## Word box centre, as a fraction of the crown facet's height.
const WORD_CENTRE := 0.42
## How much of the facet's height a whole word may use (keeps the fit sane
## for short words like "TINY").
const WORD_HEIGHT := 0.42
## Words float this far off their facet (coplanar quads z-fight).
const LABEL_LIFT := 0.006

@export var girdle_radius := 0.5
@export var table_radius := 0.27
@export var crown_height := 0.2
@export var pavilion_height := 0.44
@export var gem_color := Color(0.55, 0.85, 1.0, 0.62)
@export var word_color := Color(0.94, 0.99, 1.0)
static var _outline_color := Color(0.02, 0.05, 0.12, 0.95)
## Star pips and prize chips are the same silhouette without the words.
@export var build_words := true
## Only the throwable gems carry colliders and gravity.
@export var physical := false

static var word_font: Font = null

var words: PackedStringArray = []
var face_labels: Array[Label3D] = []
var body: MeshInstance3D = null
## Mesh + words; scaled for flashes so the rigid body itself never scales.
var dress: Node3D = null
## Brand word on the flat table: "MEGA" on one gem, "MILK" on the other.
@export var top_word := ""
@export var top_color := Color(1.0, 0.93, 0.55)
var top_label: Label3D = null
var shape: CollisionShape3D = null
## True once the gem has been thrown, landed and set on its mark.
var settled := false
var spinning := false
var _spin_speed := 2.6
var _wobble_time := 0.0
var _hover_tween: Tween = null
var _front_face := -1
var _label_base_pixel_size: Array[float] = []


static func _font() -> Font:
	if word_font == null:
		word_font = load("res://assets/fonts/DejaVuSerif-Bold.ttf")
	return word_font


## Face i spans girdle corners i..i+1; its outward normal points at azimuth
## (i + 0.5) * 45 degrees measured from +X toward +Z.
static func face_azimuth(i: int) -> float:
	return TAU * (float(i) + 0.5) / float(SIDES)


static func azimuth_of(dir: Vector3) -> float:
	return atan2(dir.z, dir.x)


func _init() -> void:
	words.resize(SIDES)
	# A gem that only ever stands still should not shove the stage around.
	set_meta("flat_top_gem", true)


func _ready() -> void:
	_build_mesh()
	_build_labels()
	_apply_physics()


func _apply_physics() -> void:
	mass = 1.6
	gravity_scale = 1.0
	linear_damp = 0.08
	angular_damp = 0.22
	physics_material_override = null
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.32
	pm.friction = 0.75
	physics_material_override = pm
	continuous_cd = true
	if physical:
		# Gems land on the world, never on each other: two hero props shoving
		# each other around on camera is chaos, not drama. They collide with
		# layer 1 (the stage, the pedestal, the safety net) only.
		collision_layer = 2
		collision_mask = 1
		var hull := ConvexPolygonShape3D.new()
		hull.points = _hull_points()
		shape = CollisionShape3D.new()
		shape.shape = hull
		add_child(shape)
		freeze = true
		# STATIC, not kinematic: a settled gem must never drift. Kinematic
		# freeze lets the server fight the node (stale velocity tracking
		# nudges the body off its mark in a flicker); static makes the node
		# authoritative and the mark exact.
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	else:
		# Pips, chips and stars are scenery: no body, no gravity, no cost.
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		set_physics_process(false)
		gravity_scale = 0.0


func _process(delta: float) -> void:
	if spinning:
		rotation.y += _spin_speed * delta
	_wobble_time += delta
	_fade_faces()


func _is_body_awake() -> bool:
	return physical and not freeze and not sleeping


func word_at(face: int) -> String:
	return words[face % SIDES]


## Outward normal of crown facet [param i] (the upper trapezoid between
## girdle edge i..i+1 and the table), in the gem's local frame.
func _face_normal(i: int) -> Vector3:
	var c := facet_corners(i)
	var n := (c[3] - c[0]).cross(c[1] - c[0]).normalized()
	if n.dot((c[0] + c[1] + c[2] + c[3]) * 0.25) < 0.0:
		n = -n
	return n


## Crown facet [param i] in local space: girdle i, girdle i+1, table i+1,
## table i. Words live here, on the UPPER side faces.
func facet_corners(i: int) -> Array[Vector3]:
	var a := TAU * float(i) / float(SIDES)
	var b := TAU * float(i + 1) / float(SIDES)
	return [
		Vector3(cos(a) * girdle_radius, 0.0, sin(a) * girdle_radius),
		Vector3(cos(b) * girdle_radius, 0.0, sin(b) * girdle_radius),
		Vector3(cos(b) * table_radius, crown_height, sin(b) * table_radius),
		Vector3(cos(a) * table_radius, crown_height, sin(a) * table_radius),
	]


## Outward normal of pavilion facet [param i] (lower triangle to the point).
func pavilion_normal(i: int) -> Vector3:
	var a := face_azimuth(i)
	var mid := Vector3(cos(a), 0.0, sin(a))
	var apothem := girdle_radius * cos(PI / float(SIDES))
	return (mid * pavilion_height - Vector3.UP * apothem).normalized()


## Local frame of the word on crown facet [param i]: +Z out of the facet,
## +Y up the facet toward the table, +X along the girdle edge.
func facet_label_basis(i: int) -> Basis:
	var c := facet_corners(i)
	var z := _face_normal(i)
	var up := ((c[2] + c[3]) * 0.5 - (c[0] + c[1]) * 0.5)
	var y := (up - z * up.dot(z)).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## The crown face whose outward normal points most toward the sky, and how
## squarely (dot with UP). This is the throw's result: the physics decides
## how the stone lies, and the word facing up is read. Nothing else.
func up_face_and_score() -> Array:
	var best := -2.0
	var best_i := 0
	var b := global_transform.basis.orthonormalized()
	for i in SIDES:
		var d := (b * _face_normal(i)).dot(Vector3.UP)
		if d > best:
			best = d
			best_i = i
	return [best_i, best]


func up_face() -> int:
	return int(up_face_and_score()[0])


## A cocked stone (resting on its table, or leaning on a wall) shows no
## clean upper face; the show re-throws it instead of guessing.
func is_cocked() -> bool:
	return float(up_face_and_score()[1]) < COCKED_DOT


## World transform of this gem resting on the floor point [param floor_point]
## with crown face [param face] up: it lies on the opposite pavilion facet,
## exactly as a thrown stone comes to rest. [param away] is the horizontal
## direction the word's top should point (away from the viewer).
func rest_transform(face: int, floor_point: Vector3, away: Vector3) -> Transform3D:
	var n := pavilion_normal((face + SIDES / 2) % SIDES)
	var axis := n.cross(Vector3.DOWN)
	var b := Basis.IDENTITY
	if axis.length() > 0.0001:
		b = Basis(axis.normalized(), n.angle_to(Vector3.DOWN))
	var ydir := b * facet_label_basis(face).y
	var flat := Vector2(ydir.x, ydir.z)
	var want := Vector2(away.x, away.z)
	if flat.length() > 0.001 and want.length() > 0.001:
		b = Basis(Vector3.UP, flat.angle() - want.angle()) * b
	var corner := facet_corners(0)[0]
	var lift := corner.dot(n)
	return Transform3D(b, floor_point + Vector3.UP * lift)


func _hull_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in SIDES:
		var a := TAU * float(i) / float(SIDES)
		pts.append(Vector3(cos(a) * girdle_radius, 0.0, sin(a) * girdle_radius))
		pts.append(Vector3(cos(a) * table_radius, crown_height, sin(a) * table_radius))
	pts.append(Vector3(0.0, -pavilion_height, 0.0))
	return pts


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # flat-shaded facets

	var girdle: Array[Vector3] = []
	var table: Array[Vector3] = []
	for i in SIDES:
		var a := TAU * float(i) / float(SIDES)
		girdle.append(Vector3(cos(a) * girdle_radius, 0.0, sin(a) * girdle_radius))
		table.append(Vector3(cos(a) * table_radius, crown_height, sin(a) * table_radius))
	var apex := Vector3(0.0, -pavilion_height, 0.0)

	# Pavilion: eight plain triangles, girdle edge down to the point.
	for i in SIDES:
		_tri(st, girdle[i], girdle[(i + 1) % SIDES], apex)
	# Crown: eight word-bearing trapezoids from girdle up to the table edge.
	for i in SIDES:
		_quad(st, girdle[i], girdle[(i + 1) % SIDES], table[(i + 1) % SIDES], table[i])
	# The table: the fully flat top, one octagon.
	for i in SIDES:
		var c := Vector3(0.0, crown_height, 0.0)
		_tri(st, c, table[i], table[(i + 1) % SIDES])

	st.generate_normals()
	var mesh := st.commit()

	body = MeshInstance3D.new()
	body.name = "Body"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = gem_color
	mat.metallic = 0.85
	mat.roughness = 0.06
	mat.emission_enabled = true
	mat.emission = gem_color * 0.55
	mat.emission_energy_multiplier = 0.7
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	body.material_override = mat
	body.mesh = mesh
	dress = Node3D.new()
	dress.name = "Dress"
	add_child(dress)
	dress.add_child(body)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_uv(Vector2(v.x, v.z) * 2.0 + Vector2(0.5, 0.5))
		st.add_vertex(v)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


func _build_labels() -> void:
	if not build_words:
		return
	var font := _font()
	var base_size := 96
	for i in SIDES:
		var label := _make_word_label(words[i], font, base_size)
		var c := facet_corners(i)
		var bottom_w := c[0].distance_to(c[1])
		var top_w := c[3].distance_to(c[2])
		var height := ((c[2] + c[3]) * 0.5).distance_to((c[0] + c[1]) * 0.5)
		# Word box centred 42% up the trapezoid, 40% of its height tall; its
		# top edge (the narrow side) bounds the width.
		var box_top := WORD_CENTRE + WORD_HEIGHT * 0.5
		var avail_w := (bottom_w + (top_w - bottom_w) * box_top) * WORD_FIT
		var px := _fit_px(label, font, base_size, avail_w, height * WORD_HEIGHT)
		label.pixel_size = px
		_label_base_pixel_size.append(px)
		var lb := facet_label_basis(i)
		var centre := ((c[0] + c[1]) * 0.5).lerp((c[2] + c[3]) * 0.5, WORD_CENTRE)
		label.transform = Transform3D(lb, centre + lb.z * LABEL_LIFT)
		dress.add_child(label)
		face_labels.append(label)
	# The table: one flat octagon, one brand word across it.
	if top_word != "":
		top_label = _make_word_label(top_word, font, base_size)
		top_label.modulate = top_color
		var inradius := table_radius * cos(PI / float(SIDES))
		top_label.pixel_size = _fit_px(top_label, font, base_size, inradius * 2.0 * 0.78, inradius * 0.7)
		var tb := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
		top_label.transform = Transform3D(tb, Vector3(0.0, crown_height + LABEL_LIFT, 0.0))
		dress.add_child(top_label)


func _make_word_label(text: String, font: Font, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = size
	label.outline_size = 18
	label.modulate = word_color
	label.outline_modulate = _outline_color
	label.shaded = false
	# One-sided: a word whose facet faces away is simply not drawn, so the
	# translucent stone never shows mirrored text from its far side.
	label.double_sided = false
	label.render_priority = 2
	label.outline_render_priority = 1
	return label


func _fit_px(label: Label3D, font: Font, size: int, max_w: float, max_h: float) -> float:
	var text_px := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var ink_w := text_px.x + 2.0 * label.outline_size
	var ink_h := text_px.y + 2.0 * label.outline_size
	return minf(max_w / maxf(ink_w, 1.0), max_h / maxf(ink_h, 1.0))


## Words fade as their facet turns edge-on to the camera, so grazing faces do
## not smear; the face turned to the lens (or to the sky, for the close-up)
## reads clean.
func _fade_faces() -> void:
	if face_labels.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var b := global_transform.basis.orthonormalized()
	var best := -2.0
	for i in face_labels.size():
		var n := b * _face_normal(i)
		var to_cam := (cam.global_position - face_labels[i].global_position).normalized()
		var d := n.dot(to_cam)
		if d > best:
			best = d
			_front_face = i
		var a := clampf((d - 0.08) / 0.3, 0.0, 1.0)
		var c := word_color
		c.a = a
		face_labels[i].modulate = c
		var o := _outline_color
		o.a *= a
		face_labels[i].outline_modulate = o


## Azimuth distance of face [param i] from [param cam_az] (upright gem).
func _azimuth_off(i: int, cam_az: float) -> float:
	return absf(wrapf(face_azimuth(i) - rotation.y - cam_az, -PI, PI))


## The face an upright gem shows a camera at azimuth [param cam_az].
func front_face_for_azimuth(cam_az: float) -> int:
	var best := 99.0
	var best_i := 0
	for i in SIDES:
		var delta := _azimuth_off(i, cam_az)
		if delta < best:
			best = delta
			best_i = i
	return best_i


## The face the camera is currently reading.
func front_face() -> int:
	return _front_face


func set_words(new_words: PackedStringArray) -> void:
	for i in mini(new_words.size(), SIDES):
		words[i] = new_words[i]
		if i < face_labels.size():
			face_labels[i].text = words[i]


func start_spinning(speed := 2.6) -> void:
	spinning = true
	_spin_speed = speed
	_kill_hover()


# ------------------------------------------------------------------ physics

## Real throw: leave [param from] with this velocity and this spin, under
## gravity, and let the stage decide where it lands.
func throw_with_velocity(from: Vector3, velocity: Vector3, spin: Vector3) -> void:
	_kill_hover()
	spinning = false
	settled = false
	collision_layer = 2
	collision_mask = 1
	if is_instance_valid(shape):
		shape.set_deferred("disabled", false)
	freeze = false
	sleeping = false
	rotation = Vector3.ZERO
	global_position = from
	linear_velocity = velocity
	angular_velocity = spin
	# A brand-new body needs the transform before the first integration step.
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)


## Wait until the gem has stopped moving (or [param timeout] runs out).
## Returns true when it came to rest on its own.
func wait_until_rest(timeout := 2.6, speed := 0.35) -> bool:
	var waited := 0.0
	var calm_frames := 0
	while waited < timeout:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if freeze:
			break
		if linear_velocity.length() < speed and angular_velocity.length() < 1.1:
			calm_frames += 1
			if calm_frames >= 4:
				return true
		else:
			calm_frames = 0
	return false


## The show takes the gem back off the floor: freeze the body, lift it onto
## its mark and turn [param face] to the camera. This is the only part of the
## throw that is choreography rather than physics.
func lift_to(target: Vector3, face: int, cam_azimuth: float, duration := 1.1) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	# Once lifted, the hero prop is scenery. Disable its collider so the
	# physics server cannot push it sideways off its presentation mark.
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(shape):
		shape.set_deferred("disabled", true)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	spinning = false
	var current := wrapf(rotation.y, 0.0, TAU)
	var target_yaw := face_azimuth(face) - cam_azimuth
	# Land approaching from one full dramatic turn away.
	var wanted := wrapf(target_yaw - current, 0.0, TAU) + TAU
	var from := position
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", target, duration)
	tw.tween_property(self, "rotation:y", current + wanted, duration)
	tw.tween_property(self, "rotation:x", 0.0, duration * 0.6)
	tw.tween_property(self, "rotation:z", 0.0, duration * 0.6)
	tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await tw.finished
	position = target
	rotation = Vector3(0.0, wrapf(rotation.y, 0.0, TAU), 0.0)
	# Push the final transform into the physics server too, so the body state
	# and the node agree and nothing nudges the gem off its mark afterwards.
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	settled = true
	_start_hover()


## Cheap television magic: the gem never actually rests on anything.
func _start_hover() -> void:
	_kill_hover()
	var home_y := position.y
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "position:y", home_y + 0.05, 1.1)
	_hover_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hover_tween.set_loops(0)
	_hover_tween.chain().tween_property(self, "position:y", home_y, 1.1)


func _kill_hover() -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null


## Instant placement for restores and tests: the stone lies on the floor
## point [param target] exactly as a throw that rolled [param face] leaves
## it — resting on the opposite pavilion facet, word to the sky, its top
## pointing away from a camera at azimuth [param cam_azimuth].
func snap_settled(target: Vector3, face: int, cam_azimuth: float) -> void:
	_kill_hover()
	spinning = false
	var away := -Vector3(cos(cam_azimuth), 0.0, sin(cam_azimuth))
	global_transform = rest_transform(face, target, away)
	freeze_in_place()


## Where the stone came to rest it stays: frozen STATIC on the spot the
## physics chose, never lifted, never turned.
func freeze_in_place() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	settled = true
	if physical:
		PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)


## A bright beat when the word is announced: the gem swells and flashes.
func flash_reveal() -> void:
	var tw := create_tween()
	tw.tween_property(dress, "scale", Vector3.ONE * 1.22, 0.16)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(dress, "scale", Vector3.ONE, 0.4)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


## A one-word pop on the facet that was just announced, so the eye catches
## which face of the stone is the named one.
func flash_face(face: int) -> void:
	if face < 0 or face >= face_labels.size() or not is_instance_valid(body):
		return
	# Flash the gem's light, NEVER enlarge the word past its triangular face.
	var mat := body.material_override as StandardMaterial3D
	var tw := create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 2.6, 0.16)
	tw.tween_property(mat, "emission_energy_multiplier", 0.7, 0.35)
	await tw.finished
