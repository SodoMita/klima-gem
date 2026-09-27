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
## Result index for a stone that comes to rest on its table.
const TOP_FACE := 8
## Geometric index of the table in [method local_face_normal].
const TABLE_FACE := 16
## Words float this far off their face (coplanar quads z-fight).
const WORD_LIFT := 0.004
## Table label frame: +Z up out of the table, text reading along +X.
const TOP_BASIS := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

## Facet triangles are narrow; the word is sized to this share of the facet's
## base edge so it never spills onto a neighbouring face.
const WORD_FIT := 0.60
## How much of the facet's height a whole word may use (keeps the fit sane
## for short words like "TINY").
const WORD_HEIGHT_LIMIT := 0.28

@export var girdle_radius := 0.5
@export var table_radius := 0.11
@export var crown_height := 0.22
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
## The word on the flat table: MILK on the body-part gem, MEGA on the
## modification gem.
var top_word := ""
var face_labels: Array[Label3D] = []
var crown_labels: Array[Label3D] = []
var top_label: Label3D = null
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
	return word_for(face)


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
	# A glass stone is seen through: the far facets show through the near
	# ones, so both sides of every face are drawn (back-face culling made
	# the gem read as a hollow, single-sided shell).
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	body.material_override = mat
	body.mesh = mesh
	add_child(body)


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
	# Sector i carries its word on BOTH faces of that sector: pavilion facet
	# i (below the girdle) and crown facet i (above it). The two are nearly
	# antipodal, so whichever of them the stone rests on, its twin looks up
	# at the lights with the same word. The table carries the top word.
	for i in SIDES:
		face_labels.append(_make_face_label(words[i], facet_corners(i), false))
	for i in SIDES:
		crown_labels.append(_make_face_label(words[i], crown_corners(i), true))
	top_label = _make_top_label(top_word)


## The crown trapezoid of sector [param i]: girdle edge, then table edge.
func crown_corners(i: int) -> Array[Vector3]:
	var a := TAU * float(i) / float(SIDES)
	var b := TAU * float(i + 1) / float(SIDES)
	return [
		Vector3(cos(a) * girdle_radius, 0.0, sin(a) * girdle_radius),
		Vector3(cos(b) * girdle_radius, 0.0, sin(b) * girdle_radius),
		Vector3(cos(b) * table_radius, crown_height, sin(b) * table_radius),
		Vector3(cos(a) * table_radius, crown_height, sin(a) * table_radius),
	]


func _new_label(text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = _font()
	label.font_size = 96
	label.outline_size = 16
	label.modulate = word_color
	label.outline_modulate = _outline_color
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.render_priority = 2
	label.shaded = false
	label.double_sided = false
	return label


## Pixel size that fits [param text] into a w x h rectangle (world units).
func _fit_px(label: Label3D, w: float, h: float) -> float:
	var sz := _font().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
	var ink_w := sz.x + 2.0 * label.outline_size
	var ink_h := sz.y + 2.0 * label.outline_size
	return minf(w / maxf(ink_w, 1.0), h / maxf(ink_h, 1.0))


## A word lying IN the plane of a facet and inside its outline. The facet is
## given base edge first (corners 0 and 1), then its far edge (a point for a
## pavilion triangle, the table edge for a crown trapezoid). The label's
## local +Y runs from the base toward the far edge, +Z is the outward normal.
func _make_face_label(text: String, corners: Array[Vector3], is_crown: bool) -> Label3D:
	var label := _new_label(text)
	var base_mid := (corners[0] + corners[1]) * 0.5
	var far_mid: Vector3 = (corners[2] + corners[3]) * 0.5 if is_crown else corners[2]
	var base_w := corners[0].distance_to(corners[1])
	var far_w: float = corners[2].distance_to(corners[3]) if is_crown else 0.0
	var slant := base_mid.distance_to(far_mid)
	var up := (far_mid - base_mid) / slant
	var across := (corners[1] - corners[0]).normalized()
	var normal := across.cross(up).normalized()
	var centroid := Vector3.ZERO
	for c in corners:
		centroid += c
	centroid /= float(corners.size())
	if normal.dot(centroid) < 0.0:
		normal = -normal
		across = -across
	# The word's band: centred t_c of the way up the slant, height h.
	var t_c := 0.40 if is_crown else 0.22
	var h := slant * (0.30 if is_crown else 0.20)
	var t_top := t_c + 0.5 * h / slant
	var w_at_top := lerpf(base_w, far_w, t_top) * 0.86
	label.pixel_size = _fit_px(label, w_at_top, h)
	label.set_meta("fit_w", w_at_top)
	label.set_meta("fit_h", h)
	var pos := base_mid + up * slant * t_c + normal * WORD_LIFT
	label.transform = Transform3D(Basis(across, up, normal), pos)
	add_child(label)
	return label


func _make_top_label(text: String) -> Label3D:
	var label := _new_label(text)
	# Fit the word across the table: as wide as the octagon's inscribed
	# circle, no taller than the table is deep. (The table is small so a
	# table rest stays rare; the word uses all of it.)
	var r_in := table_radius * cos(PI / float(SIDES)) * 0.96
	var sz := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
	var ink_w := sz.x + 2.0 * label.outline_size
	var ink_h := sz.y + 2.0 * label.outline_size
	label.pixel_size = minf(2.0 * r_in / maxf(ink_w, 1.0), 2.0 * r_in * 0.9 / maxf(ink_h, 1.0))
	label.transform = Transform3D(TOP_BASIS, Vector3(0.0, crown_height + WORD_LIFT, 0.0))
	add_child(label)
	return label


## Every word label faded by how squarely its face looks at the camera: back
## faces vanish, the faces turned to the house read clearly.
func _fade_faces() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var labels: Array[Label3D] = []
	labels.append_array(face_labels)
	labels.append_array(crown_labels)
	if is_instance_valid(top_label):
		labels.append(top_label)
	for label in labels:
		var n := (label.global_basis.z).normalized()
		var to_cam := (cam.global_position - label.global_position).normalized()
		# Faces turned away vanish; anything the camera can see at all
		# keeps its word, fading in as the face squares up.
		var a := clampf((n.dot(to_cam) - 0.02) / 0.26, 0.0, 1.0)
		var c := word_color
		c.a = a
		label.modulate = c
		var o := _outline_color
		o.a *= a
		label.outline_modulate = o
		label.visible = a > 0.01


## Outward normal of a face in this gem's local space. Geometric faces 0..7
## are the pavilion facets, 8..15 the crown facets, TABLE_FACE (16) the table.
## (Results are different: 0..7 name a sector, TOP_FACE (8) the table.)
func local_face_normal(face: int) -> Vector3:
	if face == TABLE_FACE:
		return Vector3.UP
	if face >= SIDES and face < 2 * SIDES:
		var c := crown_corners(face - SIDES)
		var n := (c[1] - c[0]).cross(c[3] - c[0]).normalized()
		return n if n.dot(c[0] + c[2]) > 0.0 else -n
	var p := facet_corners(face)
	var pn := (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	return pn if pn.dot(p[0] + p[1] + p[2]) > 0.0 else -pn


## The fair reading. Whatever face the stone RESTS on names the result:
## pavilion or crown facet of sector i gives word i (its twin face is then
## looking up), the table gives the top word. Returns 0..7, or TOP_FACE.
func resting_face() -> int:
	var down_local := (global_basis.inverse() * Vector3.DOWN).normalized()
	var best := -2.0
	var best_face := 0
	for f in 2 * SIDES:
		var d := local_face_normal(f).dot(down_local)
		if d > best:
			best = d
			best_face = f
	if local_face_normal(TABLE_FACE).dot(down_local) > best:
		return TOP_FACE
	return best_face % SIDES


## The label that presents result [param face]: the crown word for a sector,
## the table word for the top.
func label_for(face: int) -> Label3D:
	if face == TOP_FACE:
		return top_label
	if face < 0 or face >= crown_labels.size():
		return null
	# A sector carries its word twice: on the pavilion facet (below the
	# girdle) and on the crown facet (above it). A stone may rest on either
	# — the under-view reads whichever of the two is actually lying on the
	# glass, i.e. the one whose face points down.
	var crown := crown_labels[face]
	if face < face_labels.size() and is_inside_tree():
		var pav := face_labels[face]
		if pav.global_basis.z.y < crown.global_basis.z.y:
			return pav
	return crown


## World basis that turns result [param face] squarely toward a viewer along
## [param to_viewer], text upright.
func presentation_basis(face: int, to_viewer: Vector3) -> Basis:
	var label := label_for(face)
	var f: Basis = TOP_BASIS if label == null else label.transform.basis
	f = f.orthonormalized()
	var z_t := to_viewer.normalized()
	var y_t := (Vector3.UP - z_t * Vector3.UP.dot(z_t)).normalized()
	var x_t := y_t.cross(z_t)
	return Basis(x_t, y_t, z_t) * f.inverse()


## Basis that lays the stone down with result [param face]'s facet against
## the glass floor — the pose a real throw leaves it in — text pointing away
## from the house so it reads upright from below.
func rest_basis(face: int) -> Basis:
	var label: Label3D = top_label if face == TOP_FACE else (crown_labels[face] if face >= 0 and face < crown_labels.size() else null)
	var f: Basis = TOP_BASIS if label == null else label.transform.basis
	f = f.orthonormalized()
	var z_t := Vector3.DOWN
	var y_t := Vector3.FORWARD
	var x_t := y_t.cross(z_t)
	return Basis(x_t, y_t, z_t) * f.inverse()


## Instant restore: the stone lies on [param target] (a point on the glass
## floor) with [param face] down, exactly as physics would have left it.
func snap_rest(target: Vector3, face: int) -> void:
	_freeze_as_scenery()
	settled = true
	var t := Transform3D(rest_basis(face), target)
	if is_inside_tree():
		global_transform = t
	else:
		transform = t


func word_for(face: int) -> String:
	if face == TOP_FACE:
		return top_word
	return words[face % SIDES]


func set_words(new_words: PackedStringArray) -> void:
	for i in mini(new_words.size(), SIDES):
		words[i] = new_words[i]
		if i < face_labels.size():
			face_labels[i].text = words[i]
		if i < crown_labels.size():
			crown_labels[i].text = words[i]
	if new_words.size() > SIDES:
		top_word = new_words[SIDES]
		if is_instance_valid(top_label):
			top_label.text = top_word


func start_spinning(speed := 2.6) -> void:
	spinning = true
	_spin_speed = speed
	_kill_hover()


# ------------------------------------------------------------------ physics

## Real throw: leave [param from] with this velocity and this spin, under
## gravity, and let the stage decide where it lands.
func throw_with_velocity(from: Vector3, velocity: Vector3, spin: Vector3, orientation := Basis.IDENTITY) -> void:
	_kill_hover()
	spinning = false
	settled = false
	collision_layer = 2
	collision_mask = 1
	if is_instance_valid(shape):
		shape.set_deferred("disabled", false)
	freeze = false
	sleeping = false
	global_transform = Transform3D(orientation, from)
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
## its mark and turn result [param face] squarely toward [param viewer]
## (a world position, normally the house camera). The result was already
## read from the resting stone; this is presentation only.
func lift_to(target: Vector3, face: int, viewer: Vector3, duration := 1.1) -> void:
	_freeze_as_scenery()
	var from_q := global_basis.get_rotation_quaternion()
	var to_q := presentation_basis(face, viewer - target).get_rotation_quaternion()
	var from_p := global_position
	var tw := create_tween()
	tw.tween_method(_lift_step.bind(from_p, target, from_q, to_q), 0.0, 1.0, duration)
	tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await tw.finished
	if not is_inside_tree():
		return
	global_transform = Transform3D(Basis(to_q), target)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	settled = true
	_start_hover()


func _lift_step(t: float, from_p: Vector3, to_p: Vector3, from_q: Quaternion, to_q: Quaternion) -> void:
	if not is_inside_tree():
		return
	var p := from_p.lerp(to_p, t) + Vector3.UP * (0.35 * sin(PI * t))
	global_transform = Transform3D(Basis(from_q.slerp(to_q, t)), p)


func _freeze_as_scenery() -> void:
	_kill_hover()
	spinning = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	# Once presented, the hero prop is scenery: no collider to shove it.
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(shape):
		shape.set_deferred("disabled", true)


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
func snap_settled(target: Vector3, face: int, viewer: Vector3) -> void:
	_freeze_as_scenery()
	settled = true
	var t := Transform3D(presentation_basis(face, viewer - target), target)
	if is_inside_tree():
		global_transform = t
	else:
		transform = t


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
	if face < 0 or face > TOP_FACE or not is_instance_valid(body):
		return
	# Flash the gem's light, NEVER enlarge the word past its triangular face.
	var mat := body.material_override as StandardMaterial3D
	var tw := create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 2.6, 0.16)
	tw.tween_property(mat, "emission_energy_multiplier", 0.7, 0.35)
	await tw.finished
