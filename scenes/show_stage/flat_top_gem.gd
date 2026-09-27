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

## Facet triangles are narrow; the word is sized to this share of the facet's
## base edge so it never spills onto a neighbouring face.
const WORD_FIT := 0.60
## How much of the facet's height a whole word may use (keeps the fit sane
## for short words like "TINY").
const WORD_HEIGHT_LIMIT := 0.28

@export var girdle_radius := 0.5
@export var table_radius := 0.26
@export var crown_height := 0.17
@export var pavilion_height := 0.44
@export var gem_color := Color(0.55, 0.85, 1.0, 0.62)
@export var word_color := Color(0.94, 0.99, 1.0)
static var _outline_color := Color(0.02, 0.05, 0.12, 0.95)
## Star pips and prize chips are the same silhouette without the words.
@export var build_words := true
## Only the throwable gems carry colliders and gravity.
@export var physical := false
## Text stamped flat on the table (the fully flat top of the stone).
## The show uses "GEM\nMEGA" on the shapeshift stone and "GEM\nMILK" on the
## body-part stone, so a gem read from above still names itself.
@export var top_text := ""

static var word_font: Font = null

var words: PackedStringArray = []
var face_labels: Array[Label3D] = []
## The same eight words, repeated on the crown trapezoids (the UPPER side
## faces). A gem on the floor is read on its upper faces long before the
## pavilion is visible, so the word has to live up there too.
var crown_labels: Array[Label3D] = []
## The word stamped flat on the table.
var top_label: Label3D = null
## The Dress: mesh + words live under this child, and ALL presentation
## rotation (spin, wobble, the settle turn) is applied to it. The physics
## server owns the body's own transform and drops euler order on a frozen
## body, which tipped the stone before it yawed and turned the faced facet
## into a sliver. (Rosa's fix, ported.)
var dress: Node3D = null
var body: MeshInstance3D = null
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
	dress = Node3D.new()
	dress.name = "Dress"
	dress.rotation_order = EULER_ORDER_XYZ
	add_child(dress)
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
	if dress == null:
		return
	if spinning:
		dress.rotation.y += _spin_speed * delta
	_wobble_time += delta
	if not spinning and not _is_body_awake():
		# A tiny breathing tilt, so a settled gem still feels alive on camera.
		dress.rotation.x = 0.05 * sin(_wobble_time * 1.7)
		dress.rotation.z = 0.04 * sin(_wobble_time * 1.13 + 1.3)
	_fade_faces()


func _is_body_awake() -> bool:
	return physical and not freeze and not sleeping


func word_at(face: int) -> String:
	return words[face % SIDES]


## Azimuth of face [param i]'s outward normal, relative to this node's yaw.
func _face_normal(i: int) -> Vector3:
	var a := face_azimuth(i)
	var mid := Vector3(cos(a), 0.0, sin(a))
	# The outward normal of (girdle[i], girdle[i+1], apex). The apex is
	# BELOW the rim, so this plane's outward normal slopes DOWN, not up.
	var apothem := girdle_radius * cos(PI / float(SIDES))
	return (mid * pavilion_height - Vector3.UP * apothem).normalized()


## The facet triangle that carries word [param i], in local space: the girdle
## edge at the top, the point at the bottom.
func facet_corners(i: int) -> Array[Vector3]:
	var a := TAU * float(i) / float(SIDES)
	var b := TAU * float(i + 1) / float(SIDES)
	return [
		Vector3(cos(a) * girdle_radius, 0.0, sin(a) * girdle_radius),
		Vector3(cos(b) * girdle_radius, 0.0, sin(b) * girdle_radius),
		Vector3(0.0, -pavilion_height, 0.0),
	]


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

	# Pavilion: eight word-bearing triangles, girdle edge down to the point.
	for i in SIDES:
		_tri(st, girdle[i], girdle[(i + 1) % SIDES], apex)
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
	mat.metallic = 0.85
	mat.roughness = 0.06
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


func _build_labels() -> void:
	if not build_words:
		return
	var font := _font()
	var base_size := 96
	var facet_base := 2.0 * girdle_radius * sin(PI / float(SIDES))
	var target_width := facet_base * WORD_FIT
	var facet_height := sqrt(pavilion_height * pavilion_height + pow(girdle_radius * cos(PI / float(SIDES)), 2))
	var max_height := facet_height * WORD_HEIGHT_LIMIT
	for i in SIDES:
		var label := Label3D.new()
		label.text = words[i]
		label.font = font
		label.font_size = base_size
		label.outline_size = 18
		label.modulate = word_color
		label.outline_modulate = _outline_color
		# Only the front-facing facet's word is rendered; putting it in front
		# of its own translucent depth pre-pass prevents punched-out glyphs.
		label.no_depth_test = true
		# Opaque pre-pass: back-face words are depth-rejected by the near
		# facets instead of ghosting through the stone. The facing fade
		# (modulate alpha) is what keeps seven of the eight words off the
		# screen, so the settled gem reads as one named face.
		label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		label.render_priority = 2
		label.shaded = false
		label.double_sided = false
		# Fit the whole word inside the triangle it names.
		var text_px := font.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, base_size)
		# The glyph's OUTLINE also takes space; budget its full bounding box.
		var ink_width := text_px.x + 2.0 * label.outline_size
		var ink_height := text_px.y + 2.0 * label.outline_size
		var px := target_width / maxf(ink_width, 1.0)
		# ...and never let it grow taller than the facet is deep.
		var height_units := ink_height * px
		if height_units > max_height:
			px *= max_height / height_units
		label.pixel_size = px
		_label_base_pixel_size.append(px)

		var corners := facet_corners(i)
		# At the centroid a horizontal word can only occupy 2/3 of the
		# base if it has zero height. Move its centre up the facet so its
		# entire rectangular ink+outline box fits BETWEEN the sloping sides.
		var centre := ((corners[0] + corners[1]) * 0.5).lerp(corners[2], 0.19)
		var normal := _face_normal(i)
		var pos := centre + normal * 0.003  # depth bias only; same plane
		# Label3D draws into its -Z half-space looking down +Z; aiming the -Z
		# axis at the inverted normal turns the glyphs outward through the
		# facet, and UP is re-resolved against the facet's own slope.
		var basis := Basis.looking_at(-normal, Vector3.UP)
		label.transform = Transform3D(basis, pos)
		dress.add_child(label)
		face_labels.append(label)

		_build_crown_label(i, font, base_size)

	_build_top_label(font, base_size)


## The UPPER side face (crown trapezoid) i: girdle[i], girdle[i+1],
## table[i+1], table[i]. It carries the same word as the pavilion facet under
## it, so the stone names itself whether you read it from the house or from
## above.
func crown_corners(i: int) -> Array[Vector3]:
	var a := TAU * float(i) / float(SIDES)
	var b := TAU * float(i + 1) / float(SIDES)
	return [
		Vector3(cos(a) * girdle_radius, 0.0, sin(a) * girdle_radius),
		Vector3(cos(b) * girdle_radius, 0.0, sin(b) * girdle_radius),
		Vector3(cos(b) * table_radius, crown_height, sin(b) * table_radius),
		Vector3(cos(a) * table_radius, crown_height, sin(a) * table_radius),
	]


func _crown_normal(i: int) -> Vector3:
	var c := crown_corners(i)
	var n := (c[1] - c[0]).cross(c[3] - c[0]).normalized()
	# Point it outward, away from the gem's axis.
	var a := face_azimuth(i)
	if n.dot(Vector3(cos(a), 0.0, sin(a))) < 0.0:
		n = -n
	return n


func _build_crown_label(i: int, font: Font, base_size: int) -> void:
	var c := crown_corners(i)
	var normal := _crown_normal(i)
	var centroid := (c[0] + c[1] + c[2] + c[3]) * 0.25
	var label := Label3D.new()
	label.name = "CrownWord%d" % i
	label.text = words[i]
	label.font = font
	label.font_size = base_size
	label.outline_size = 18
	label.modulate = word_color
	label.outline_modulate = _outline_color
	label.shaded = false
	label.double_sided = false
	label.render_priority = 2
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	# Fit inside the trapezoid: the short (table) edge is the binding width,
	# and the slant height is the binding height.
	var short_edge := c[2].distance_to(c[3])
	var slant := ((c[3] + c[2]) * 0.5).distance_to((c[0] + c[1]) * 0.5)
	var text_px := font.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, base_size)
	var px := (short_edge * WORD_FIT) / maxf(text_px.x, 1.0)
	var height_units := text_px.y * px
	var max_height := slant * 0.7
	if height_units > max_height:
		px *= max_height / height_units
	label.pixel_size = px
	label.transform = Transform3D(Basis.looking_at(-normal, Vector3.UP), centroid + normal * 0.006)
	dress.add_child(label)
	crown_labels.append(label)


## The table stamp: two short lines lying flat on the top of the stone,
## readable from the house camera looking down at the set.
func _build_top_label(font: Font, base_size: int) -> void:
	if top_text.is_empty():
		return
	var label := Label3D.new()
	label.name = "TopStamp"
	label.text = top_text
	label.font = font
	label.font_size = base_size
	label.outline_size = 18
	label.modulate = word_color
	label.outline_modulate = _outline_color
	label.shaded = false
	label.double_sided = false
	label.render_priority = 3
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var widest := 1.0
	for line in top_text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, base_size).x)
	# The table is an octagon of circumradius table_radius; its inscribed
	# square is table_radius * 2 * cos(PI/8) / sqrt(2) wide. Stay inside it.
	var fits := table_radius * 2.0 * cos(PI / float(SIDES)) / sqrt(2.0)
	var px := (fits * 0.92) / widest
	var lines := float(top_text.split("\n").size())
	var text_h := font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, base_size).y * lines * px
	if text_h > fits * 0.92:
		px *= (fits * 0.92) / text_h
	label.pixel_size = px
	# Glyphs project up through the table; the reading direction runs toward
	# the back of the stone so the house camera reads it right way up.
	label.transform = Transform3D(
		Basis.looking_at(Vector3.DOWN, Vector3.BACK),
		Vector3(0.0, crown_height + 0.005, 0.0)
	)
	dress.add_child(label)
	top_label = label


## Fade each word by how squarely its facet faces the camera, so a settled
## gem reads as one named face rather than eight overlapping ones. Measured by
## azimuth, not by the dot product: the pavilion normals lean 44 degrees up,
## so a dot with a nearly level camera never comes close to 1 and every face
## looked "front".
func _fade_faces() -> void:
	if face_labels.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - global_position
	var cam_az := atan2(to_cam.z, to_cam.x)
	_front_face = front_face_for_azimuth(cam_az)
	for i in face_labels.size():
		var delta := _azimuth_off(i, cam_az)
		# 1.0 out to 20 degrees off the view axis (which is where the front
		# face always sits on an octagon), gone by 36 degrees, so the
		# 45-degree neighbours draw nothing at all.
		var a := clampf((0.62 - delta) / 0.27, 0.0, 1.0)
		var label := face_labels[i]
		var c := word_color
		c.a = a
		label.modulate = c
		# The outline does NOT follow modulate's alpha in Label3D, so a hidden
		# word would still smear its dark border across the facet. Fade it too.
		var o := _outline_color
		o.a *= a
		label.outline_modulate = o
		if i < crown_labels.size():
			# The upper face carries the same word and the same fade, so the
			# stone always shows exactly one word, twice: side and crown.
			var cl := crown_labels[i]
			cl.modulate = c
			cl.outline_modulate = o


## How far, in radians, face [param i]'s outward normal is from a camera at
## azimuth [param cam_az]. A yaw of +y carries face azimuth a to a - y (Godot
## turns clockwise seen from above), which is the convention
## [method lift_to] settles with.
func _azimuth_off(i: int, cam_az: float) -> float:
	var yaw := rotation.y + (dress.rotation.y if dress != null else 0.0)
	return absf(wrapf(face_azimuth(i) - yaw - cam_az, -PI, PI))


## The face a camera at azimuth [param cam_az] is looking at squarest.
func front_face_for_azimuth(cam_az: float) -> int:
	var best := 99.0
	var best_i := 0
	for i in face_labels.size():
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
		if i < crown_labels.size():
			crown_labels[i].text = words[i]


func start_spinning(speed := 2.6) -> void:
	spinning = true
	_spin_speed = speed
	_kill_hover()


# ------------------------------------------------------------------ physics

## Real throw: leave [param from] with this velocity and this spin, under
## gravity, and let the stage decide where it lands.
func throw_with_velocity(from: Vector3, velocity: Vector3, spin: Vector3, start_rotation := Vector3.ZERO) -> void:
	_kill_hover()
	spinning = false
	settled = false
	collision_layer = 2
	collision_mask = 1
	if is_instance_valid(shape):
		shape.set_deferred("disabled", false)
	freeze = false
	sleeping = false
	# Fairness: the stone leaves the hand in whatever attitude it was picked
	# up in. Always starting level (rotation zero) biases which facets meet
	# the floor first, and a biased tumble is a rigged show.
	rotation = start_rotation
	if dress != null:
		dress.rotation = Vector3.ZERO
	global_position = from
	linear_velocity = velocity
	angular_velocity = spin
	# A brand-new body needs the transform before the first integration step.
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)


## Wait until the gem has stopped moving (or [param timeout] runs out).
## Returns true when it came to rest on its own.
## The window is generous on purpose: the stones must be allowed to stop on
## their own, not be caught mid-tumble by an impatient timer (a timer that
## fires early is another way of rigging the outcome).
func wait_until_rest(timeout := 7.0, speed := 0.22) -> bool:
	var waited := 0.0
	var calm_frames := 0
	while waited < timeout:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if freeze:
			break
		if linear_velocity.length() < speed and angular_velocity.length() < 0.7:
			calm_frames += 1
			if calm_frames >= 12:
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
	var current := wrapf(dress.rotation.y, 0.0, TAU)
	# The body keeps whatever attitude physics left it in on its own axes;
	# the show turns the DRESS, in a clean XYZ euler frame.
	var target_yaw := face_azimuth(face) - cam_azimuth - rotation.y
	# Land approaching from one full dramatic turn away.
	var wanted := wrapf(target_yaw - current, 0.0, TAU) + TAU
	var from := position
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position", target, duration)
	tw.tween_property(dress, "rotation:y", current + wanted, duration)
	tw.tween_property(dress, "rotation:x", 0.0, duration * 0.6)
	tw.tween_property(dress, "rotation:z", 0.0, duration * 0.6)
	tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await tw.finished
	position = target
	dress.rotation = Vector3(0.0, wrapf(dress.rotation.y, 0.0, TAU), 0.0)
	rotation = Vector3.ZERO
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


## Instant placement for restores: no physics, no tween, just the truth.
func snap_settled(target: Vector3, face: int, cam_azimuth: float) -> void:
	_kill_hover()
	spinning = false
	settled = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(shape):
		shape.set_deferred("disabled", true)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	position = target
	rotation = Vector3.ZERO
	if dress != null:
		dress.rotation = Vector3(0.0, wrapf(face_azimuth(face) - cam_azimuth, 0.0, TAU), 0.0)


## A bright beat when the word is announced: the gem swells and flashes.
func flash_reveal() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.22, 0.16)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.4)
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
