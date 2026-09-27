class_name FlatTopGem extends RigidBody3D
## A Klima Gem: a diamond whose top is fully flat — an octagonal table where
## the octahedron's point used to be. Eight slanted pavilion faces, one word
## per face, each word GLUED to its facet: same plane, same centre, sized to
## fit the triangle it names.
##
## The gem is a real body: the throw is ballistic (gravity does the arc, the
## angular velocity does the tumble), then television magic freezes it and
## turns the rolled face to the camera. Pure geometry: the mesh is built here,
## no painted textures.

const SIDES := 8

## Prop-sized on purpose: a gem the camera can read the words on. A jewel
## small enough to pocket is a jewel whose eight words are four pixels high.
@export var girdle_radius := 0.72
@export var table_radius := 0.38
@export var crown_height := 0.32
@export var pavilion_height := 0.95
@export var gem_color := Color(0.55, 0.85, 1.0, 0.62)
@export var word_color := Color(0.92, 0.99, 1.0)
## Star pips and prize chips are the same silhouette without the words.
@export var build_words := true

static var word_font: Font = null

var words: PackedStringArray = []
var face_labels: Array[Label3D] = []
var body: MeshInstance3D = null
## Visual-only child: the reveal tip and the idle wobble live here, because a
## RigidBody3D's transform comes back from the physics server as a plain basis
## and silently drops rotation_order — a tip set on the body's euler lands at
## the wrong angle. Single-axis rotation on a plain node has no such order.
var dress: Node3D = null
var spinning := false
## Forward tip at the reveal: at this angle the faced pavilion facet looks
## straight into the house camera instead of at the floor.
var reveal_tilt := 0.0
var _spin_speed := 2.6
var _wobble_time := 0.0
var _hover_tween: Tween = null


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


func _ready() -> void:
	dress = Node3D.new()
	dress.name = "Dress"
	# The body itself only carries position: its transform round-trips through
	# the physics server as a bare basis and would drop any euler order we set.
	# Godot 4 defaults to YXZ, which tips before it yaws. XYZ on this plain node
	# composes as yaw, then the reveal tip about the world X axis, then the
	# wobble roll — verified column by column against the printed basis.
	dress.rotation_order = EULER_ORDER_XYZ
	add_child(dress)
	_build_mesh()
	_build_labels()
	_build_body()
	# Idle gems are dressed by hand (tweens, hover, settle); only the throw
	# hands the gem to the physics server.
	# Yaw first, then the reveal tip about the world X axis: with the default
	# XYZ order the tip is applied before the yaw and the faced facet misses
	# the lens by the yaw angle.
	freeze = true
	mass = 1.4
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.22
	pm.friction = 0.7
	physics_material_override = pm


func _build_body() -> void:
	var shape: Shape3D = null
	if body != null and body.mesh != null:
		shape = body.mesh.create_convex_shape()
	if shape == null:
		var s := SphereShape3D.new()
		s.radius = girdle_radius
		shape = s
	var col := CollisionShape3D.new()
	col.shape = shape
	col.name = "Collision"
	add_child(col)


func _process(delta: float) -> void:
	if dress == null:
		return
	if spinning:
		dress.rotation.y += _spin_speed * delta
	_wobble_time += delta
	if not spinning and freeze:
		# A tiny breathing tilt, so a settled gem still feels alive on camera.
		dress.rotation.x = reveal_tilt + 0.055 * sin(_wobble_time * 1.7)
		dress.rotation.z = 0.045 * sin(_wobble_time * 1.13 + 1.3)


func word_at(face: int) -> String:
	return words[face % SIDES]


## The pavilion is an inverted cone: its facets face outward and DOWNWARD
## (that is the whole trick of a diamond — the pavilion catches the room and
## throws it back up through the table). A normal that tips upward belongs to
## the crown, and labels laid in it float off the stone.
func _face_normal(i: int) -> Vector3:
	var a := face_azimuth(i)
	var mid := Vector3(cos(a), 0.0, sin(a))
	var r_cos := girdle_radius * cos(PI / float(SIDES))
	return (mid * pavilion_height + Vector3.DOWN * r_cos).normalized()


func _girdle_corner(i: int) -> Vector3:
	var a := TAU * float(i) / float(SIDES)
	return Vector3(cos(a) * girdle_radius, 0.0, sin(a) * girdle_radius)


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

	# Pavilion: eight word-bearing triangles, girdle edge down to the point.
	for i in SIDES:
		_tri(st, girdle[i], apex, girdle[(i + 1) % SIDES])
	# Crown: eight quiet trapezoids from girdle up to the table edge.
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
	mat.metallic = 0.55
	mat.roughness = 0.08
	mat.emission_enabled = true
	mat.emission = gem_color * 0.55
	mat.emission_energy_multiplier = 0.7
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	body.material_override = mat
	body.mesh = mesh
	dress.add_child(body)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_uv(Vector2(v.x, v.z) * 2.0 + Vector2(0.5, 0.5))
		st.add_vertex(v)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## One Label3D per pavilion facet, lying IN the facet: positioned at the
## triangle's centroid, lifted a hair along the facet normal, rotated into the
## facet plane, and scaled so the longest word still fits inside the triangle.
## A word that floats in front of the stone, or dangles below it near the
## apex, reads as a caption — not as a name the gem is carrying.
func _build_labels() -> void:
	if not build_words:
		return
	var apex := Vector3(0.0, -pavilion_height, 0.0)
	var edge_len := 2.0 * girdle_radius * sin(PI / float(SIDES))
	for i in SIDES:
		var label := Label3D.new()
		label.text = words[i]
		label.font = _font()
		label.font_size = 96
		label.outline_size = 14
		label.modulate = word_color
		label.outline_modulate = Color(0.03, 0.08, 0.16, 0.9)
		label.no_depth_test = false
		label.double_sided = false
		label.render_priority = 2
		label.shaded = false

		# On the facet plane, in its widest readable band: 62% of the way from
		# the apex up to the girdle edge. The centroid sits lower, where the
		# triangle has narrowed to a point's worth of room.
		var girdle_mid := (_girdle_corner(i) + _girdle_corner((i + 1) % SIDES)) * 0.5
		var band := apex + (girdle_mid - apex) * 0.62
		var normal := _face_normal(i)
		var pos := band + normal * 0.014

		# Basis in the facet plane, built from the triangle's own girdle edge:
		# +X along the facet's width, +Y up-slope, +Z out along the normal.
		# (Projecting a world up-vector onto the plane degenerates here — on a
		# steep pavilion it is nearly parallel to the normal and the residual
		# normalises to garbage, collapsing the label to a sliver.)
		var edge := (_girdle_corner((i + 1) % SIDES) - _girdle_corner(i)).normalized()
		var z_axis := normal
		var y_axis := z_axis.cross(edge)
		if y_axis.dot(girdle_mid - apex) < 0.0:
			y_axis = -y_axis
		var x_axis := y_axis.cross(z_axis)
		label.transform = Transform3D(Basis(x_axis, y_axis, z_axis), pos)

		# Fit the word inside the triangle at that band's width.
		var facet_w := edge_len * 0.62 * 0.80
		var px_w := maxf(_font().get_string_size(words[i], HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size).x, 1.0)
		label.pixel_size = facet_w / px_w
		dress.add_child(label)
		face_labels.append(label)


func set_words(new_words: PackedStringArray) -> void:
	for i in mini(new_words.size(), SIDES):
		words[i] = new_words[i]
		if i < face_labels.size():
			face_labels[i].text = words[i]
			var px_w := maxf(_font().get_string_size(words[i], HORIZONTAL_ALIGNMENT_CENTER, -1, face_labels[i].font_size).x, 1.0)
			face_labels[i].pixel_size = (2.0 * girdle_radius * sin(PI / float(SIDES)) * 0.62 * 0.80) / px_w


func start_spinning(speed := 2.6) -> void:
	spinning = true
	_spin_speed = speed
	_kill_hover()


## Throw the gem for real: gravity flies the arc, angular velocity tumbles it,
## the stage's colliders are there if it misses. When the flight time is up
## the gem freezes where the ballistics put it and television takes over.
## Returns when the flight ends.
func launch(from: Vector3, to: Vector3, flips := 2.0, flight := 0.95) -> void:
	_kill_hover()
	spinning = false
	rotation = Vector3.ZERO
	dress.rotation = Vector3.ZERO
	global_position = from
	freeze = false
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	# Ballistic solution: v0 = (to - from)/T - g_vec*T/2, with g_vec = (0,-g,0).
	linear_velocity = (to - from) / flight + Vector3.UP * (0.5 * g * flight)
	angular_velocity = Vector3.RIGHT * (TAU * flips / flight)
	# Ride the physics clock, not a wall-clock timer: the integrator and a
	# SceneTreeTimer disagree by a few frames, and a gem frozen four frames
	# short of its mark is a gem that visibly never arrived. Catch it when it
	# gets there (or when the flight budget runs out), then take the mark.
	var elapsed := 0.0
	while is_instance_valid(self) and elapsed < flight * 1.35:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var flat := Vector2(global_position.x - to.x, global_position.z - to.z).length()
		# Catch on the descent through the mark's height, close to the mark:
		# a per-frame distance test is finer than one physics step of travel
		# and can be stepped straight over.
		if linear_velocity.y < 0.0 and global_position.y <= to.y + 0.06 and flat < 0.65:
			break
		if global_position.distance_to(to) < 0.15:
			break
	if not is_instance_valid(self):
		return
	global_position = to
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reveal_tilt = 0.0
	# The tumble belonged to the flight; the settle starts from a clean yaw.
	rotation = Vector3.ZERO
	if dress != null:
		dress.rotation = Vector3.ZERO


## Slow the spin and turn [param face] toward [param cam_azimuth] (radians,
## azimuth of the camera seen from the gem). Extra full turns sell the decay.
func settle_facing(face: int, cam_azimuth: float, duration := 1.25) -> void:
	spinning = false
	# A positive rotation.y carries a face's azimuth the other way (Ry turns
	# +X toward -Z), so world azimuth = face_azimuth - rotation.y.
	var target_yaw := face_azimuth(face) - cam_azimuth
	# Land approaching from one full dramatic turn away.
	var current := wrapf(dress.rotation.y, 0.0, TAU)
	var wanted := wrapf(target_yaw - current, 0.0, TAU)
	var tw := create_tween()
	tw.tween_property(dress, "rotation:y", current + wanted + TAU, duration)
	tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await tw.finished
	dress.rotation.y = wrapf(dress.rotation.y, 0.0, TAU)
	_start_hover()


## Cheap television magic: the gem never actually rests on anything.
func _start_hover() -> void:
	_kill_hover()
	var home_y := position.y
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "position:y", home_y + 0.045, 1.1)
	_hover_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hover_tween.set_loops(0)
	_hover_tween.chain().tween_property(self, "position:y", home_y, 1.1)


func _kill_hover() -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null


## A bright beat when the word is announced: the gem swells and flashes.
func flash_reveal() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.22, 0.16)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.4)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
