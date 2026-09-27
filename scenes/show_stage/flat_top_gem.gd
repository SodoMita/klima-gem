class_name FlatTopGem extends Node3D
## A Klima Gem: a diamond whose top is fully flat — an octagonal table where
## the octahedron's point used to be. Eight slanted pavilion faces, one word
## per face. The gem throws, spins, and settles so the rolled face fronts the
## camera. Pure geometry: the mesh is built here, no painted textures.

const SIDES := 8

@export var girdle_radius := 0.23
@export var table_radius := 0.12
@export var crown_height := 0.13
@export var pavilion_height := 0.36
@export var gem_color := Color(0.55, 0.85, 1.0, 0.62)
@export var word_color := Color(0.92, 0.99, 1.0)
## Star pips and prize chips are the same silhouette without the words.
@export var build_words := true

static var word_font: Font = null

var words: PackedStringArray = []
var face_labels: Array[Label3D] = []
var body: MeshInstance3D = null
var spinning := false
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
	_build_mesh()
	_build_labels()


func _process(delta: float) -> void:
	if spinning:
		rotation.y += _spin_speed * delta
	_wobble_time += delta
	if not spinning:
		# A tiny breathing tilt, so a settled gem still feels alive on camera.
		rotation.x = 0.055 * sin(_wobble_time * 1.7)
		rotation.z = 0.045 * sin(_wobble_time * 1.13 + 1.3)
	_update_label_facing()


## Exactly one word is drawn at a time: the face that most looks at the
## camera. Far-side and neighbour words stay hidden, so nothing ghosts
## through the stone (depth pre-passes are not reliable under the
## compatibility renderer) and the words hand over crisply while spinning.
func _update_label_facing() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := (cam.global_position - global_position).normalized()
	var best := -1
	var best_dot := 0.25
	for i in face_labels.size():
		var facing: float = face_labels[i].global_transform.basis.z.dot(to_cam)
		if facing > best_dot:
			best_dot = facing
			best = i
	for i in face_labels.size():
		face_labels[i].visible = i == best


func word_at(face: int) -> String:
	return words[face % SIDES]


func _face_normal(i: int) -> Vector3:
	var a := face_azimuth(i)
	var mid := Vector3(cos(a), 0.0, sin(a))
	# The pavilion leans outward as it drops, so the normal tips upward a little.
	var slope := atan2(pavilion_height, girdle_radius * cos(PI / float(SIDES)))
	return (mid * cos(slope) + Vector3.UP * sin(slope)).normalized()


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
	# Depth pre-pass: the near facets write depth, so the far-side words stop
	# ghosting through the stone mirrored.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.cull_mode = BaseMaterial3D.CULL_BACK
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
	var label_size := int(girdle_radius * 300.0)
	for i in SIDES:
		var label := Label3D.new()
		label.text = words[i]
		label.font = _font()
		label.font_size = maxi(label_size, 64)
		label.outline_size = maxi(label_size / 5, 12)
		label.modulate = word_color
		label.outline_modulate = Color(0.03, 0.08, 0.16, 0.9)
		label.pixel_size = 0.0032
		label.no_depth_test = false
		# Opaque pre-pass: back-face words are depth-rejected by the near
		# facets instead of ghosting through the stone.
		label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		label.render_priority = 2

		var a := face_azimuth(i)
		var mid := Vector3(cos(a), 0.0, sin(a))
		var pos := mid * (girdle_radius * 0.62) + Vector3.DOWN * (pavilion_height * 0.55)
		pos += mid.normalized() * 0.012  # lift the text just off the facet

		var basis := Basis.looking_at(-_face_normal(i), Vector3.UP)
		label.transform = Transform3D(basis, pos)
		add_child(label)
		face_labels.append(label)


func set_words(new_words: PackedStringArray) -> void:
	for i in mini(new_words.size(), SIDES):
		words[i] = new_words[i]
		if i < face_labels.size():
			face_labels[i].text = words[i]


func start_spinning(speed := 2.6) -> void:
	spinning = true
	_spin_speed = speed
	_kill_hover()


## Fly an arc from [param from] to [param to] while flipping forward, then
## leave the gem hovering where it landed. Returns when the flight ends.
func launch(from: Vector3, to: Vector3, flips := 2.0, flight := 0.95) -> void:
	_kill_hover()
	spinning = false
	var tw := create_tween()
	tw.tween_method(_fly_step.bind(from, to, flips), 0.0, 1.0, flight)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	rotation.x = 0.0


func _fly_step(t: float, from: Vector3, to: Vector3, flips: float) -> void:
	position = from.lerp(to, t) + Vector3.UP * (0.85 * sin(PI * t))
	rotation.x = -TAU * flips * t
	rotation.z = 0.0


## Slow the spin and turn [param face] toward [param cam_azimuth] (radians,
## azimuth of the camera seen from the gem). Extra full turns sell the decay.
func settle_facing(face: int, cam_azimuth: float, duration := 1.25) -> void:
	spinning = false
	var target_yaw := face_azimuth(face) - cam_azimuth
	# Land approaching from one full dramatic turn away.
	var current := wrapf(rotation.y, 0.0, TAU)
	var wanted := wrapf(target_yaw - current, 0.0, TAU)
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", current + wanted + TAU, duration)
	tw.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await tw.finished
	rotation.y = wrapf(rotation.y, 0.0, TAU)
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
