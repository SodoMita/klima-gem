class_name ShowStage extends Node3D
## The KLIMA GEM television studio: a real 3D stage built from Godot
## geometry — no painted backdrop, no imported image. A round platform under
## a cloth of slow stars, lighting beams from the truss, an audience of
## silhouettes at the apron, and a slim pedestal where the word-gems hang.
##
## Framing is deliberate. The camera sits in the house at eye height; the set
## is composed so that every piece the audience must read — the sign, the
## word plaques, the gems, the trials — lands in the upper band of the frame
## that the dialogue balloon never covers. tests/render_check.gd measures the
## projected rectangles of those pieces on the live scene graph and fails if
## they leave the safe area or overlap each other.
##
## The stage owns every piece of show furniture: the two flat-topped gems,
## the modification chip, the challenge props (built and torn down on cue),
## the star pips on the star cloth, and the per-challenge choreography. All
## randomness that matters comes in from ShowDirector / GameState so a
## playthrough stays deterministic; purely cosmetic scatter uses this node's
## own fixed-seed generator.
##
## The throw is real physics: the gems are RigidBody3D, the platform and the
## pedestal are StaticBody3D colliders, and the gems leave the guest's hand
## under an impulse. See [method throw_gems].

const FlatTopGemScript := preload("res://scenes/show_stage/flat_top_gem.gd")

const PARTS: PackedStringArray = ["HANDS", "EYES", "LEGS", "VOICE", "HAIR", "BACK", "HEART", "SKIN"]
const MODS: PackedStringArray = ["GIANT", "TINY", "STICKY", "BOUNCY", "GLASS", "MAGNET", "HEAVY", "GLOWING"]
const CHALLENGE_NAMES: PackedStringArray = ["THE CROSSING", "BELL BARRAGE", "ECHO CHOIR"]

const MOD_COLORS := {
	"GIANT": Color(1.0, 0.8, 0.25),
	"TINY": Color(0.65, 0.85, 1.0),
	"STICKY": Color(0.55, 1.0, 0.6),
	"BOUNCY": Color(1.0, 0.6, 0.3),
	"GLASS": Color(0.85, 0.95, 1.0),
	"MAGNET": Color(0.8, 0.55, 1.0),
	"HEAVY": Color(0.55, 0.55, 0.68),
	"GLOWING": Color(0.7, 1.0, 0.95),
}

# ------------------------------------------------------------------- layout

const STAGE_TOP := 0.5
const STAGE_RADIUS := 3.05

## The house camera. Eye height in the front row, a small downward tilt, a
## longish lens: a broadcast shot, not a fisheye survey of the set.
const CAM_POS := Vector3(0.0, 2.2, 9.4)
const CAM_PITCH_DEG := -8.0
const CAM_FOV := 45.0

## Where the guest stands: stage right, forward of the pedestal so she reads
## over it rather than behind it. Ren is a voice on the microphone and never
## takes a visible mark, so there is no second portrait on this stage.
const AURORA_MARK := Vector3(2.05, STAGE_TOP, 2.0)
const AURORA_BASE_HEIGHT := 1.68
const REN_MARK := Vector3(-2.05, STAGE_TOP, 2.0)

## The altar stands upstage, fully ON the platform (it used to hang off the
## downstage edge at z = 3.3, half of it in mid-air).
const PEDESTAL_Z := -2.35
const PEDESTAL_HEAD := 1.55
## Gem stations: the shapeshift (modification) gem hangs on the LEFT, the
## body-part gem on the RIGHT. Their settled words fly onward to the
## presentation slots, same sides, higher up.
const GEM_SLOT_MOD := Vector3(-0.62, 2.16, PEDESTAL_Z)
const GEM_SLOT_PART := Vector3(0.62, 2.16, PEDESTAL_Z)
## The presented words hang over the platform, not out above the audience.
const PRESENT_POS_MOD := Vector3(-2.15, 2.25, 0.2)
const PRESENT_POS_PART := Vector3(2.15, 2.25, 0.2)

## After a stone has been read it dollies forward to its reveal mark, out in
## front of the set where the house camera can fill the frame with it.
const GEM_REVEAL_MOD := Vector3(-1.35, 2.05, 4.3)
const GEM_REVEAL_PART := Vector3(1.35, 2.05, 4.3)

## The star board is three prize gems standing on the altar, so the reward
## for a cleared trial lands somewhere the audience is already looking.
const PIP_BASE := Vector3(-0.42, 1.63, PEDESTAL_Z + 0.15)
const PIP_STEP := Vector3(0.42, 0.0, 0.0)

## Where each thrown gem is aimed on the stage floor. Different landing spots
## keep the two bodies from shoving each other around.
## Both landing marks sit inside the throw box (see THROW_BOX_*), so a gem
## can never be thrown off the stage or out of the world.
const LAND_PART := Vector3(0.35, STAGE_TOP + 1.15, 1.45)
const LAND_MOD := Vector3(-1.25, STAGE_TOP + 1.15, 1.05)

## The closed throw box: a glass case downstage-left with four walls, a lid
## and the stage floor for a bottom. Everything thrown stays inside it.
## The case is LIFTED off the platform and has a glass floor of its own, so
## the underside of a landed stone is visible: the reveal camera dives under
## the box and reads the face lying on the glass.
const THROW_BOX_CENTER := Vector3(-0.5, STAGE_TOP + 1.15, 1.3)
const THROW_BOX_HALF := Vector3(1.35, 0.0, 0.95)
const THROW_BOX_HEIGHT := 1.5
const THROW_BOX_WALL := 0.06

## Where the reveal camera sits to read the underside of the case.
const UNDER_CAM_POS := Vector3(-0.5, STAGE_TOP + 0.18, 3.05)

## Below this line the dialogue balloon covers the frame, so nothing the
## audience has to read may be placed there.
const SAFE_AREA_BOTTOM := 0.60

var aurora_quad: Node3D = null

var _cosmetic := RandomNumberGenerator.new()
var _gems: Array[FlatTopGem] = []
## Invalidates an in-flight throw when a rewind/restore clears the gems.
var _gem_epoch := 0
var _plaque_mod: Node3D = null
var _plaque_part: Node3D = null
var _props: Node3D = null
var _chip: Node3D = null
var _chip_label: Label3D = null
var _stamp: Label3D = null
var _pips: Array[MeshInstance3D] = []
var _stones: Array[MeshInstance3D] = []
var _bells: Array[MeshInstance3D] = []
var _pads: Array[MeshInstance3D] = []
var _podiums: Array[Node3D] = []
var _key_light: OmniLight3D = null
var _salvo_timer: Timer = null
var _salvo_left := 0
var _salvo_success := true
var _confetti: Node3D = null
var _confetti_data: Array = []
var _confetti_time := 0.0
var _chip_time := 0.0
var _aurora_bob: Tween = null
var _fx_orbs: Array[Node3D] = []
var _chip_home := Vector3.ZERO
var _set_root: Node3D = null
var _camera: Camera3D = null


func _ready() -> void:
	add_to_group("show_stage")
	_cosmetic.seed = 20260927
	_apply_camera()
	_build_environment()
	_build_world_containers()
	_build_hall()
	_build_set()
	_build_star_cloth()
	_build_beams()
	_build_audience()
	_build_pedestal()
	_build_colliders()
	_build_throw_box()
	_build_marks()
	_build_pips()
	_props = get_node_or_null("Props") as Node3D
	if _props == null:
		_props = Node3D.new()
		_props.name = "Props"
		add_child(_props)


func _apply_camera() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		add_child(_camera)
	_camera.position = CAM_POS
	_camera.rotation_degrees = Vector3(CAM_PITCH_DEG, 0.0, 0.0)
	_camera.fov = CAM_FOV
	_camera.current = true
	_camera.far = 60.0


func camera() -> Camera3D:
	return _camera


func _process(delta: float) -> void:
	_chip_time += delta
	if is_instance_valid(_chip):
		_chip.rotation.y += 0.9 * delta
		_chip.position.y = _chip_home.y + 0.05 * sin(_chip_time * 1.6)
	for plaque in [_plaque_mod, _plaque_part]:
		if is_instance_valid(plaque) and plaque.has_meta("home") and plaque.get_meta("landed"):
			var home: Vector3 = plaque.get_meta("home")
			plaque.position.y = home.y + 0.04 * sin(_chip_time * 1.8 + (0.0 if plaque == _plaque_part else 1.7))
	_tick_confetti(delta)


func set_actor(alias: String, quad: Node3D) -> void:
	# Only the guest is ever stood on this stage; "ren" is a voice, and a
	# stray portrait for him would be a second sprite the show does not need.
	if alias == "aurora":
		aurora_quad = quad


## Parent for standing portraits (the StageDirector's quads, or anything else
## that wants to stand on the stage floor).
func characters_parent() -> Node3D:
	return get_node_or_null("World3D/Characters") as Node3D


## Where the modification chip hangs: on the guest, at chest height, a step
## forward of her so it never fights with her portrait for the same depth.
func chip_anchor() -> Vector3:
	var base := AURORA_MARK
	if is_instance_valid(aurora_quad):
		base = (aurora_quad as Node3D).global_position
	return base + Vector3(0.0, 0.66, 0.5)


## The host's entrance cue. Ren is not rendered — this only gives his mark a
## wash of key light, so the stage reacts to him taking the floor.
func host_entrance() -> void:
	if _key_light == null:
		return
	var tw := create_tween()
	tw.tween_property(_key_light, "light_energy", 2.0, 0.5)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_key_light, "light_energy", 1.35, 0.9)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func aurora_hand() -> Vector3:
	var base := AURORA_MARK
	if is_instance_valid(aurora_quad):
		base = (aurora_quad as Node3D).global_position
	return base + Vector3(0.28, AURORA_BASE_HEIGHT * 0.74, -0.22)


# ---------------------------------------------------------------- stage build

func _mesh_instance(mesh: Mesh, mat: StandardMaterial3D, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _mat(albedo: Color, rough := 0.8, metal := 0.0, emission := Color(0, 0, 0), energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	if emission != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _label(text: String, size: int, color: Color, outline: Color, px := 0.008) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = FlatTopGemScript._font()
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_modulate = outline
	l.outline_size = size / 8
	l.shaded = false
	return l


func _build_environment() -> void:
	if get_node_or_null("WorldEnvironment") != null:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.29, 0.52)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


## Stands the moving parts under stable names: the stage manager's own
## containers, so portraits and props never land under the show furniture.
func _build_world_containers() -> void:
	if get_node_or_null("World3D") != null:
		return
	var world := Node3D.new()
	world.name = "World3D"
	add_child(world)
	var chars := Node3D.new()
	chars.name = "Characters"
	world.add_child(chars)


func _build_hall() -> void:
	if get_node_or_null("HouseFloor") != null:
		return
	# The house floor the audience sits on.
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(40.0, 0.1, 20.0)
	var floor_mi := _mesh_instance(floor_mesh, _mat(Color(0.015, 0.02, 0.05), 0.95), self)
	floor_mi.position = Vector3(0, -0.05, 5.0)


## The set proper: the round platform and its glowing rim, and the dark wings
## that keep the eye on the stage. Nothing is placed where it would crop
## against the camera frame — the arena is the whole picture.
func _build_set() -> void:
	var authored := get_node_or_null("Set") as Node3D
	if authored != null:
		_set_root = authored
		return
	_set_root = Node3D.new()
	_set_root.name = "Set"
	add_child(_set_root)

	var platform := CylinderMesh.new()
	platform.top_radius = STAGE_RADIUS
	platform.bottom_radius = STAGE_RADIUS + 0.18
	platform.height = STAGE_TOP
	platform.radial_segments = 64
	var plat_mi := _mesh_instance(platform, _mat(Color(0.07, 0.08, 0.17), 0.55, 0.25), _set_root)
	plat_mi.name = "Platform"
	plat_mi.position = Vector3(0, STAGE_TOP * 0.5, 0)

	var rim := TorusMesh.new()
	rim.inner_radius = STAGE_RADIUS - 0.05
	rim.outer_radius = STAGE_RADIUS + 0.07
	rim.rings = 64
	var rim_mi := _mesh_instance(rim, _mat(Color(0.2, 0.5, 0.8), 0.3, 0.6, Color(0.3, 0.75, 1.0), 1.7), _set_root)
	rim_mi.name = "Rim"
	rim_mi.position = Vector3(0, STAGE_TOP, 0)

	# A soft inlay disc so the floor is not one flat colour: the show's floor
	# plan, drawn as a ring of faint wedges.
	var inlay := CylinderMesh.new()
	inlay.top_radius = STAGE_RADIUS * 0.62
	inlay.bottom_radius = STAGE_RADIUS * 0.62
	inlay.height = 0.02
	inlay.radial_segments = 48
	var inlay_mi := _mesh_instance(inlay, _mat(Color(0.09, 0.11, 0.22), 0.7), _set_root)
	inlay_mi.position = Vector3(0, STAGE_TOP + 0.005, 0.35)
	var inlay_rim := TorusMesh.new()
	inlay_rim.inner_radius = STAGE_RADIUS * 0.62 - 0.02
	inlay_rim.outer_radius = STAGE_RADIUS * 0.62 + 0.02
	inlay_rim.rings = 48
	var ir_mi := _mesh_instance(inlay_rim, _mat(Color(0.3, 0.6, 0.9), 0.4, 0.5, Color(0.25, 0.6, 0.95), 0.9), _set_root)
	ir_mi.position = Vector3(0, STAGE_TOP + 0.01, 0.35)

	# Wings: dark masses at the far left and right, well outside the frame's
	# readable area, so the studio has depth without crowding the shot.
	var wing_mat := _mat(Color(0.03, 0.035, 0.085), 0.9, 0.1, Color(0.06, 0.12, 0.28), 0.18)
	for sx in [-1.0, 1.0]:
		var wing := BoxMesh.new()
		wing.size = Vector3(1.2, 4.2, 3.4)
		var wm := _mesh_instance(wing, wing_mat, _set_root)
		wm.position = Vector3(4.6 * sx, 2.1, 1.6)
		var drape := BoxMesh.new()
		drape.size = Vector3(0.16, 3.6, 1.9)
		var dm := _mesh_instance(drape, _mat(Color(0.13, 0.06, 0.24), 0.75, 0.2), _set_root)
		dm.position = Vector3(4.02 * sx, 1.8, 2.6)


## The back wall: a star cloth and the show sign, with the prize board below.
func _build_star_cloth() -> void:
	var cloth := get_node_or_null("StarCloth") as Node3D
	if cloth != null:
		if cloth.get_node_or_null("Stars") != null:
			return
	else:
		cloth = Node3D.new()
		cloth.name = "StarCloth"
		add_child(cloth)

	if cloth.get_node_or_null("Backdrop") == null:
		var backdrop := BoxMesh.new()
		backdrop.size = Vector3(18.0, 7.4, 0.2)
		var bm := _mesh_instance(backdrop, _mat(Color(0.035, 0.045, 0.115), 0.9), cloth)
		bm.name = "Backdrop"
		bm.position = Vector3(0, 3.2, -3.9)

	var star_mm := MultiMesh.new()
	star_mm.transform_format = MultiMesh.TRANSFORM_3D
	star_mm.mesh = SphereMesh.new()
	(star_mm.mesh as SphereMesh).radius = 0.032
	(star_mm.mesh as SphereMesh).height = 0.064
	star_mm.instance_count = 64
	for i in 64:
		var pos := Vector3(_cosmetic.randf_range(-8.6, 8.6), _cosmetic.randf_range(0.8, 6.8), -3.78)
		star_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * _cosmetic.randf_range(0.6, 1.5)), pos))
	var star_mi := MultiMeshInstance3D.new()
	star_mi.name = "Stars"
	star_mi.multimesh = star_mm
	var star_mat := _mat(Color(0.8, 0.92, 1.0), 1.0, 0.0, Color(0.75, 0.9, 1.0), 1.7)
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mi.material_override = star_mat
	cloth.add_child(star_mi)

	# The sign. The only thing on the back wall: the tagline lives on the
	# title card, and a second line of type up here only collided with the
	# word plaques.
	if cloth.get_node_or_null("Sign") != null:
		return
	var sign := _label("KLIMA GEM", 160, Color(0.6, 0.92, 1.0), Color(0.02, 0.07, 0.18, 0.95), 0.0072)
	sign.name = "Sign"
	sign.position = Vector3(0, 3.62, -3.8)
	cloth.add_child(sign)


## Lighting beams: additive cones that fade as they fall, so the stage is lit
## by something the audience can see.
func _build_beams() -> void:
	if get_node_or_null("Beams") != null:
		_key_light = get_node_or_null("KeyLight") as OmniLight3D
		return
	var beams := Node3D.new()
	beams.name = "Beams"
	add_child(beams)

	var beam_shader := Shader.new()
	beam_shader.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 beam_color : source_color = vec4(0.55, 0.80, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.22;
void fragment() {
	// Densest where the cone is deepest (top), and softest at the silhouette
	// so the beam has no hard tube edge.
	float depth = clamp(1.0 - UV.y, 0.0, 1.0);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = beam_color.rgb;
	ALPHA = strength * mix(0.35, 1.0, depth) * mix(0.30, 1.0, facing);
}
"""
	for sx in [-1.0, 0.0, 1.0]:
		var rig := Node3D.new()
		beams.add_child(rig)
		rig.position = Vector3(1.72 * sx, 0.0, 1.15)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.92
		cone.height = 3.9
		cone.radial_segments = 28
		cone.cap_top = false
		cone.cap_bottom = false
		var cmi := _mesh_instance(cone, _mat(Color(1, 1, 1), 1.0), rig)
		cmi.name = "Beam"
		var bm := ShaderMaterial.new()
		bm.shader = beam_shader
		bm.set_shader_parameter("beam_color", Color(0.58, 0.82, 1.0) if sx != 0.0 else Color(0.86, 0.92, 1.0))
		bm.set_shader_parameter("strength", 0.075 if sx != 0.0 else 0.10)
		cmi.material_override = bm
		cmi.position = Vector3(0, 3.1, 0)
		rig.rotation_degrees = Vector3(-6.0, 0, 4.0 * sx)
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lamp := CylinderMesh.new()
		lamp.top_radius = 0.11
		lamp.bottom_radius = 0.15
		lamp.height = 0.34
		var lmi := _mesh_instance(lamp, _mat(Color(0.15, 0.16, 0.24), 0.4, 0.8, Color(0.6, 0.85, 1.0), 1.2), rig)
		lmi.position = Vector3(0, 5.1, 0)

	# Truss across the top, out of frame but lighting the beams.
	var truss_mat := _mat(Color(0.1, 0.11, 0.2), 0.4, 0.7)
	for z in [-0.4, 2.4]:
		var beam := BoxMesh.new()
		beam.size = Vector3(8.4, 0.12, 0.12)
		var bmi := _mesh_instance(beam, truss_mat, beams)
		bmi.position = Vector3(0, 5.3, z)

	_key_light = OmniLight3D.new()
	_key_light.name = "KeyLight"
	_key_light.position = Vector3(0, 4.4, 3.4)
	_key_light.light_color = Color(1.0, 0.96, 0.88)
	_key_light.light_energy = 1.35
	_key_light.omni_range = 12.0
	add_child(_key_light)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 3.4, -3.2)
	rim.light_color = Color(0.5, 0.75, 1.0)
	rim.light_energy = 1.0
	rim.omni_range = 11.0
	add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(3.2, 1.8, 4.4)
	fill.light_color = Color(0.72, 0.62, 1.0)
	fill.light_energy = 0.7
	fill.omni_range = 9.0
	add_child(fill)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 24, 0)
	sun.light_color = Color(0.75, 0.82, 1.0)
	sun.light_energy = 0.18
	add_child(sun)


func _build_audience() -> void:
	if get_node_or_null("Audience") != null:
		return
	var crowd := Node3D.new()
	crowd.name = "Audience"
	add_child(crowd)
	var cap := CapsuleMesh.new()
	cap.radius = 0.19
	cap.height = 0.92
	var body_mm := MultiMesh.new()
	body_mm.transform_format = MultiMesh.TRANSFORM_3D
	body_mm.mesh = cap
	var spots: Array[Vector3] = []
	var count := 0
	for row in 3:
		var z := 5.5 + 0.8 * row
		var y := 0.26 + 0.26 * row
		var n := 10 - row
		for i in n:
			var x := -4.8 + 9.6 * float(i) / float(n - 1) + _cosmetic.randf_range(-0.25, 0.25)
			spots.append(Vector3(x, y, z + _cosmetic.randf_range(-0.2, 0.2)))
			count += 1
	body_mm.instance_count = count
	for i in count:
		body_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))
	var body_mi := MultiMeshInstance3D.new()
	body_mi.multimesh = body_mm
	# Silhouettes: darker than the hall, so the stage stays the brightest thing.
	body_mi.material_override = _mat(Color(0.02, 0.025, 0.065), 0.95)
	crowd.add_child(body_mi)

	# Glowsticks: little unshaded colour bars held up in the dark.
	var stick := BoxMesh.new()
	stick.size = Vector3(0.032, 0.22, 0.032)
	var stick_mm := MultiMesh.new()
	stick_mm.transform_format = MultiMesh.TRANSFORM_3D
	stick_mm.mesh = stick
	stick_mm.use_colors = true
	var stick_colors := [Color(0.4, 0.9, 1.0), Color(1.0, 0.5, 0.85), Color(1.0, 0.85, 0.4), Color(0.6, 1.0, 0.6)]
	stick_mm.instance_count = 26
	for i in 26:
		var base := spots[_cosmetic.randi_range(0, spots.size() - 1)]
		var t := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, _cosmetic.randf_range(-0.5, 0.5)), base + Vector3(_cosmetic.randf_range(-0.26, 0.26), 0.36, 0.1))
		stick_mm.set_instance_transform(i, t)
		stick_mm.set_instance_color(i, stick_colors[_cosmetic.randi_range(0, stick_colors.size() - 1)])
	var stick_mi := MultiMeshInstance3D.new()
	stick_mi.multimesh = stick_mm
	var stick_mat := StandardMaterial3D.new()
	stick_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stick_mat.vertex_color_use_as_albedo = true
	stick_mi.material_override = stick_mat
	crowd.add_child(stick_mi)


## A slim column the gems are thrown toward and then lifted above: the show's
## only piece of furniture, centred so the two word slots hang either side.
func _build_pedestal() -> void:
	if get_node_or_null("Pedestal") != null:
		return
	var ped := Node3D.new()
	ped.name = "Pedestal"
	add_child(ped)
	var column := CylinderMesh.new()
	column.top_radius = 0.24
	column.bottom_radius = 0.34
	column.height = 1.05
	column.radial_segments = 10
	var col_mi := _mesh_instance(column, _mat(Color(0.045, 0.05, 0.12), 0.22, 0.85, Color(0.1, 0.22, 0.45), 0.3), ped)
	col_mi.name = "Column"
	col_mi.position = Vector3(0, STAGE_TOP + 0.525, PEDESTAL_Z)
	# A lit band around the neck, so the altar reads as built rather than as
	# one extruded shape.
	var band := CylinderMesh.new()
	band.top_radius = 0.275
	band.bottom_radius = 0.275
	band.height = 0.05
	band.radial_segments = 10
	var band_mi := _mesh_instance(band, _mat(Color(0.5, 0.85, 1.0), 0.15, 0.4, Color(0.45, 0.8, 1.0), 1.1), ped)
	band_mi.name = "NeckBand"
	band_mi.position = Vector3(0, STAGE_TOP + 0.9, PEDESTAL_Z)
	var base := CylinderMesh.new()
	base.top_radius = 0.5
	base.bottom_radius = 0.58
	base.height = 0.12
	base.radial_segments = 24
	var base_mi := _mesh_instance(base, _mat(Color(0.06, 0.07, 0.16), 0.35, 0.8), ped)
	base_mi.name = "Base"
	base_mi.position = Vector3(0, STAGE_TOP + 0.06, PEDESTAL_Z)
	var plate := CylinderMesh.new()
	plate.top_radius = 0.46
	plate.bottom_radius = 0.40
	plate.height = 0.09
	plate.radial_segments = 24
	var plate_mi := _mesh_instance(plate, _mat(Color(0.06, 0.07, 0.16), 0.2, 0.85, Color(0.2, 0.42, 0.8), 0.4), ped)
	plate_mi.name = "Plate"
	plate_mi.position = Vector3(0, PEDESTAL_HEAD - 0.045, PEDESTAL_Z)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.24
	ring.bottom_radius = 0.24
	ring.height = 0.025
	ring.radial_segments = 24
	var ring_mi := _mesh_instance(ring, _mat(Color(0.4, 0.8, 1.0), 0.2, 0.5, Color(0.45, 0.85, 1.0), 0.9), ped)
	ring_mi.name = "HeadGlow"
	ring_mi.position = Vector3(0, PEDESTAL_HEAD + 0.015, PEDESTAL_Z)


## Static bodies for everything a thrown gem can land on, plus a net far
## below the house floor so a wild throw can never fall out of the world.
func _build_colliders() -> void:
	if get_node_or_null("Physics") != null:
		return
	var physics := Node3D.new()
	physics.name = "Physics"
	add_child(physics)

	var platform_body := StaticBody3D.new()
	platform_body.name = "PlatformBody"
	physics.add_child(platform_body)
	var platform_shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = STAGE_RADIUS
	cyl.height = STAGE_TOP
	platform_shape.shape = cyl
	platform_body.add_child(platform_shape)
	platform_body.position = Vector3(0, STAGE_TOP * 0.5, 0)
	platform_body.physics_material_override = _gem_physics_material(0.5)
	platform_body.collision_layer = 1
	platform_body.collision_mask = 0

	var pedestal_body := StaticBody3D.new()
	pedestal_body.name = "PedestalBody"
	physics.add_child(pedestal_body)
	var pedestal_shape := CollisionShape3D.new()
	var plate_shape := CylinderShape3D.new()
	plate_shape.radius = 0.5
	plate_shape.height = 0.12
	pedestal_shape.shape = plate_shape
	pedestal_body.add_child(pedestal_shape)
	pedestal_body.position = Vector3(0, PEDESTAL_HEAD - 0.06, PEDESTAL_Z)
	pedestal_body.physics_material_override = _gem_physics_material(0.45)
	pedestal_body.collision_layer = 1
	pedestal_body.collision_mask = 0

	var net := StaticBody3D.new()
	net.name = "SafetyNet"
	physics.add_child(net)
	var net_shape := CollisionShape3D.new()
	var net_box := BoxShape3D.new()
	net_box.size = Vector3(60.0, 0.5, 40.0)
	net_shape.shape = net_box
	net.add_child(net_shape)
	net.position = Vector3(0, -6.0, 4.0)
	net.collision_layer = 1
	net.collision_mask = 0


## The closed throw box. Four glass walls, a glass lid and the stage floor:
## a sealed case the gems are thrown inside, so no stone can ever skid off
## the platform, roll into the audience or fall out of the world. The panes
## are see-through — the throw is the act, and the house must watch it.
func _build_throw_box() -> void:
	if get_node_or_null("ThrowBox") != null:
		return
	var box := Node3D.new()
	box.name = "ThrowBox"
	add_child(box)

	var glass := _mat(Color(0.55, 0.82, 1.0, 0.13), 0.08, 0.2, Color(0.25, 0.55, 0.9), 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame_mat := _mat(Color(0.1, 0.14, 0.28), 0.25, 0.85, Color(0.3, 0.7, 1.0), 0.8)

	var hx := THROW_BOX_HALF.x
	var hz := THROW_BOX_HALF.z
	var h := THROW_BOX_HEIGHT
	var c := THROW_BOX_CENTER
	var walls := [
		# offset, size (the lid last)
		[Vector3(0, h * 0.5, -hz), Vector3(hx * 2.0, h, THROW_BOX_WALL)],
		[Vector3(0, h * 0.5, hz), Vector3(hx * 2.0, h, THROW_BOX_WALL)],
		[Vector3(-hx, h * 0.5, 0), Vector3(THROW_BOX_WALL, h, hz * 2.0)],
		[Vector3(hx, h * 0.5, 0), Vector3(THROW_BOX_WALL, h, hz * 2.0)],
		[Vector3(0, h, 0), Vector3(hx * 2.0, THROW_BOX_WALL, hz * 2.0)],
		# The glass FLOOR: the case hangs in the air, so a landed stone can be
		# read from underneath through this pane.
		[Vector3(0, 0, 0), Vector3(hx * 2.0, THROW_BOX_WALL, hz * 2.0)],
	]
	var names := ["WallBack", "WallFront", "WallLeft", "WallRight", "Lid", "Floor"]
	for i in walls.size():
		var offset: Vector3 = walls[i][0]
		var size: Vector3 = walls[i][1]
		var body := StaticBody3D.new()
		body.name = names[i]
		body.position = c + offset
		body.collision_layer = 1
		body.collision_mask = 0
		body.physics_material_override = _gem_physics_material(0.24)
		box.add_child(body)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		var mesh := BoxMesh.new()
		mesh.size = size
		var mi := _mesh_instance(mesh, glass, body)
		mi.name = "Pane"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# A lit frame so the case reads as an object and not as a smudge.
	for corner in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz)]:
		var post := BoxMesh.new()
		post.size = Vector3(0.05, h, 0.05)
		var pmi := _mesh_instance(post, frame_mat, box)
		pmi.position = c + corner + Vector3(0, h * 0.5, 0)
		# ...and a slim leg carrying the case up off the platform, so the
		# audience can see daylight (and the gem's underside) beneath it.
		var leg := BoxMesh.new()
		var leg_h: float = THROW_BOX_CENTER.y - STAGE_TOP
		leg.size = Vector3(0.05, leg_h, 0.05)
		var lmi := _mesh_instance(leg, frame_mat, box)
		lmi.position = Vector3(c.x + corner.x, STAGE_TOP + leg_h * 0.5, c.z + corner.z)


## The reveal camera: it lives under the lifted case and looks straight up
## through the glass floor at the stone lying on it.
func under_camera() -> Camera3D:
	var cam := get_node_or_null("UnderCam") as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.name = "UnderCam"
		cam.fov = 38.0
		cam.far = 40.0
		cam.position = UNDER_CAM_POS
		add_child(cam)
	return cam


## Dive under the glass and read the stone from below: the face lying on the
## floor pane is the face the show calls, and the audience watches it being
## read instead of taking the host's word for it.
func reveal_from_below(gem: FlatTopGem, hold := 1.5) -> void:
	var cam := under_camera()
	var target := gem.global_position if is_instance_valid(gem) else THROW_BOX_CENTER
	cam.position = Vector3(target.x, STAGE_TOP + 0.14, target.z + 1.5)
	cam.look_at(target, Vector3.UP)
	var house := _camera
	cam.current = true
	var tw := create_tween()
	tw.tween_property(cam, "position", Vector3(target.x, STAGE_TOP + 0.2, target.z + 0.95), hold)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if is_instance_valid(house):
		house.current = true


## Let the player throw. The stone waits until the audience (that is, the
## player) says go: space, enter, a click, a screen touch, a gamepad button
## or a shove of the left stick. How long the cue is held becomes the power
## of the throw, so a flick is a gentle toss and a hold is a hard one.
## Returns the power multiplier; a player who does nothing gets an automatic
## throw at full power after [param timeout] seconds.
func wait_for_throw_cue(timeout := 6.0) -> float:
	var prompt := _make_throw_prompt()
	var waited := 0.0
	var held := 0.0
	var started := false
	while waited < timeout:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		waited += dt
		var down := _throw_cue_down()
		if down:
			started = true
			held += dt
			if is_instance_valid(prompt):
				prompt.text = "THROW!"
			if held >= 0.9:
				break
		elif started:
			break
	if is_instance_valid(prompt):
		prompt.queue_free()
	if not started:
		return 1.0
	# 0 s (a flick) .. 0.9 s (a shove): 0.8x .. 1.45x.
	return lerpf(0.8, 1.45, clampf(held / 0.9, 0.0, 1.0))


## Any of the throw inputs, without touching the project's InputMap: mouse,
## space/enter, touchscreen, gamepad face button or left stick X.
func _throw_cue_down() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER):
		return true
	if Input.is_joy_button_pressed(0, JOY_BUTTON_A) or Input.is_joy_button_pressed(0, JOY_BUTTON_B):
		return true
	if absf(Input.get_joy_axis(0, JOY_AXIS_LEFT_X)) > 0.5:
		return true
	if DisplayServer.is_touchscreen_available() and Input.is_action_pressed(&"ui_accept"):
		return true
	return false


func _make_throw_prompt() -> Label3D:
	var prompt := _label("THROW: click / space / stick", 78, Color(1.0, 0.92, 0.6), Color(0.05, 0.03, 0.0, 0.95), 0.0032)
	prompt.name = "ThrowPrompt"
	prompt.position = THROW_BOX_CENTER + Vector3(0.0, THROW_BOX_HEIGHT + 0.35, 0.0)
	add_child(prompt)
	return prompt


## Is [param p] inside the sealed case? Tests use this to prove that a thrown
## gem can never leave the box.
func throw_box_contains(p: Vector3, slack := 0.05) -> bool:
	var d := p - THROW_BOX_CENTER
	return (absf(d.x) <= THROW_BOX_HALF.x + slack
		and absf(d.z) <= THROW_BOX_HALF.z + slack
		and d.y >= -slack and d.y <= THROW_BOX_HEIGHT + slack)


## Where a gem is released: inside the box, just under the lid, on its own
## side. The hand mimes the throw outside; the stone flies in the case.
func throw_origin(is_part: bool) -> Vector3:
	var side := 0.62 if is_part else -0.62
	return THROW_BOX_CENTER + Vector3(side, THROW_BOX_HEIGHT - 0.42, 0.34)


func _gem_physics_material(bounce: float) -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.bounce = bounce
	pm.friction = 0.8
	return pm


func _build_marks() -> void:
	if get_node_or_null("Marks") != null:
		return
	var marks := Node3D.new()
	marks.name = "Marks"
	add_child(marks)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.42
	disc.height = 0.015
	var mi := _mesh_instance(disc, _mat(Color(1.0, 0.55, 0.85), 0.3, 0.4, Color(1.0, 0.55, 0.85), 0.9), marks)
	mi.name = "AuroraMark"
	mi.position = AURORA_MARK + Vector3(0, 0.012, 0)


func _build_pips() -> void:
	if get_node_or_null("StarPips") != null:
		return
	var pips := Node3D.new()
	pips.name = "StarPips"
	add_child(pips)
	for i in 3:
		var pip := FlatTopGemScript.new()
		pip.name = "Pip%d" % i
		pip.build_words = false
		pip.gem_color = Color(0.16, 0.18, 0.26, 0.8)
		pip.girdle_radius = 0.17
		pip.table_radius = 0.085
		pip.crown_height = 0.07
		pip.pavilion_height = 0.19
		pip.position = PIP_BASE + PIP_STEP * float(i)
		pip.rotation_degrees = Vector3(0, -18, 0)
		pips.add_child(pip)
		_pips.append(pip.body)


func set_stars(stars: int) -> void:
	for i in _pips.size():
		var pip := _pips[i]
		if pip == null or not is_instance_valid(pip):
			continue
		var mat := pip.material_override as StandardMaterial3D
		if i < stars:
			mat.albedo_color = Color(1.0, 0.85, 0.35, 0.9)
			mat.emission = Color(1.0, 0.8, 0.3)
			mat.emission_energy_multiplier = 1.8
		else:
			mat.albedo_color = Color(0.16, 0.18, 0.26, 0.8)
			mat.emission = Color(0.1, 0.1, 0.16)
			mat.emission_energy_multiplier = 0.6


# ------------------------------------------------------------------- gems

func _make_gem(slot: Vector3, color: Color, word_list: PackedStringArray, physical := true) -> FlatTopGem:
	var gem: FlatTopGem = FlatTopGemScript.new()
	gem.gem_color = color
	gem.physical = physical
	# The flat top names the stone: the body-part gem is GEM MILK, the
	# shapeshift gem is GEM MEGA.
	gem.top_text = "GEM\nMILK" if word_list == PARTS else "GEM\nMEGA"
	gem.set_words(word_list)
	# Waiting inside the sealed case, under the lid, out of the shot's way.
	gem.position = THROW_BOX_CENTER + Vector3(0.0, THROW_BOX_HEIGHT - 0.3, 0.0)
	add_child(gem)
	_gems.append(gem)
	return gem


func clear_gems() -> void:
	_gem_epoch += 1
	for gem in _gems:
		if is_instance_valid(gem):
			gem.hide()
			if gem.get_parent() != null:
				gem.get_parent().remove_child(gem)
			gem.queue_free()
	_gems.clear()
	_clear_plaque(true)
	_clear_plaque(false)


## Velocity that carries a body from [param from] to [param to] in
## [param flight] seconds under the project's gravity.
func _arc_velocity(from: Vector3, to: Vector3, flight: float) -> Vector3:
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var delta := to - from
	var horizontal := Vector2(delta.x, delta.z) / flight
	var vy := (delta.y + 0.5 * gravity * flight * flight) / flight
	return Vector3(horizontal.x, vy, horizontal.y)


## The signature throw, physics-random. Both gems leave the guest's hand as
## real rigid bodies under impulses drawn from [param rng] — landing spot,
## flight time and spin all vary — tumble across the stage, bounce off the
## platform, and come to rest. Whatever face lands front-most IS the word:
## the show reads it off the settled stone, lifts the gem onto its mark
## keeping that face to the camera, and returns [part_face, mod_face].
## Nothing is pre-rolled; the stones decide.
## [param interactive] lets the player throw the stones themselves (click,
## space, touch or stick); the hold becomes the power. Tests pass false.
func throw_gems(rng: RandomNumberGenerator, interactive := false) -> Array:
	clear_gems()
	# The word lists sit on the faces in order.
	# Shapeshift (modification) gem hangs on the LEFT, body-part gem on the RIGHT.
	var gem_part := _make_gem(GEM_SLOT_PART, Color(0.5, 0.85, 1.0, 0.62), PARTS)
	var gem_mod := _make_gem(GEM_SLOT_MOD, Color(1.0, 0.55, 0.85, 0.62), MODS)
	var epoch := _gem_epoch

	# The body part goes first, thrown long across the stage; it gets its own
	# landing, its own reveal, and its own word before the second stone flies.
	# Every await is epoch-guarded: a rewind clears the gems mid-flight, and
	# this choreography must stop when its stones are gone.
	var power := 1.0
	if interactive:
		power = await wait_for_throw_cue()
		if epoch != _gem_epoch:
			return []
	var part_face := await _throw_one_physics(gem_part, LAND_PART, true, rng, epoch, power)
	if epoch != _gem_epoch or part_face < 0:
		return []
	await get_tree().create_timer(0.25).timeout
	if epoch != _gem_epoch:
		return []
	var power_mod := 1.0
	if interactive:
		power_mod = await wait_for_throw_cue()
		if epoch != _gem_epoch:
			return []
	var mod_face := await _throw_one_physics(gem_mod, LAND_MOD, false, rng, epoch, power_mod)
	if epoch != _gem_epoch or mod_face < 0:
		return []
	await get_tree().create_timer(0.3).timeout
	if epoch != _gem_epoch:
		return []
	return [part_face, mod_face]


## Deterministic staging for tests and framing shots: a real impulse throw
## that lands, then lifts the REQUESTED faces to the camera. Gameplay never
## calls this — the show calls throw_gems() and reads the landing.
func throw_gems_fixed(part_face: int, mod_face: int) -> void:
	clear_gems()
	var gem_part := _make_gem(GEM_SLOT_PART, Color(0.5, 0.85, 1.0, 0.62), PARTS)
	var gem_mod := _make_gem(GEM_SLOT_MOD, Color(1.0, 0.55, 0.85, 0.62), MODS)
	var epoch := _gem_epoch
	await _throw_one(gem_part, LAND_PART, part_face, true, epoch)
	if epoch != _gem_epoch:
		return
	await get_tree().create_timer(0.25).timeout
	if epoch != _gem_epoch:
		return
	await _throw_one(gem_mod, LAND_MOD, mod_face, false, epoch)
	if epoch != _gem_epoch:
		return
	await get_tree().create_timer(0.3).timeout


## One full physics-random throw: leave the hand under a seeded impulse,
## land, rest, READ the face that landed front-most, lift onto the mark
## keeping it, flash it, present the word, and fly it to its slot.
## Returns the face index the stones chose, or -1 when a rewind cancelled
## the flight (the gems were cleared under it — see _gem_epoch).
func _throw_one_physics(gem: FlatTopGem, land: Vector3, is_part: bool, rng: RandomNumberGenerator, epoch: int, power := 1.0) -> int:
	var from := throw_origin(is_part)
	_pulse_lights(2.2)
	# Every throw is its own throw: the landing spot, the flight time and the
	# spin come from the story RNG, so the same seed replays the same night
	# while no two stones in one night fly alike.

	# A short flight is a fast one: the stone is launched hard across the
	# small case instead of lobbed, which is what a thrown gem looks like.
	var flight := clampf((0.34 if is_part else 0.31) / maxf(power, 0.3) + rng.randf_range(-0.04, 0.04), 0.18, 0.55)
	var target := land + Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.28, 0.28))
	# Spin is drawn on every axis with a random SIGN: a spin that always turns
	# the same way lands the same family of faces, which is a rigged stone.
	var spin := Vector3(
		rng.randf_range(11.0, 20.0) * power * (1.0 if rng.randf() < 0.5 else -1.0),
		rng.randf_range(12.0, 22.0) * power * (1.0 if rng.randf() < 0.5 else -1.0),
		rng.randf_range(11.0, 20.0) * power * (1.0 if rng.randf() < 0.5 else -1.0)
	)
	# ...and the stone leaves the hand in a random attitude, so no facet is
	# ever "the one nearest the floor" by construction.
	var attitude := Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
	gem.throw_with_velocity(from, _arc_velocity(from, target, flight), spin, attitude)
	# Wait on the STAGE rather than on the body: on rewind the body is
	# freed, and a suspended method on it would resume into a dead instance.
	# The window is long: the stones must stop on their own inside the case.
	await _wait_throw_rest(gem, epoch)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return -1
	_pulse_lights(1.9)
	# The word is the face LYING ON THE GLASS: the show reads the stone from
	# underneath, through the floor of the case, where the audience can see
	# it too. Nothing is chosen for it.
	var face := gem.bottom_face()
	await reveal_from_below(gem)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return -1
	var cam_az := _camera_azimuth()
	await gem.lift_to(GEM_REVEAL_PART if is_part else GEM_REVEAL_MOD, face, cam_az, 1.05)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return -1
	await gem.flash_face(face)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return -1
	await gem.flash_reveal()
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return -1
	await present_word(gem, face, is_part)
	return face


## One full throw: leave the hand, land, rest, lift onto the mark, flash the
## named face, present the word, and fly it to its presentation slot.
func _throw_one(gem: FlatTopGem, land: Vector3, face: int, is_part: bool, epoch: int) -> void:
	var from := throw_origin(is_part)
	_pulse_lights(2.2)
	# Gravity does the rest: this is a real impulse, not a tween.
	gem.throw_with_velocity(
		from,
		_arc_velocity(from, land, 0.62 if is_part else 0.56),
		Vector3(7.0, 9.5, 4.5) * (1.0 if is_part else -0.8)
	)
	# Wait on the STAGE rather than on the body: on rewind the body is
	# freed, and a suspended method on it would resume into a dead instance.
	await _wait_throw_rest(gem, epoch)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return
	_pulse_lights(1.9)
	await gem.lift_to(GEM_REVEAL_PART if is_part else GEM_REVEAL_MOD, face, _camera_azimuth(), 1.05)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return
	await gem.flash_face(face)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return
	await gem.flash_reveal()
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return
	await present_word(gem, face, is_part)


func _wait_throw_rest(gem: FlatTopGem, epoch: int) -> void:
	var elapsed := 0.0
	var calm_frames := 0
	# Seven seconds, not three: the stones are allowed to come to rest on
	# their own inside the closed case; a short timer would cut the tumble
	# short and decide the word for them.
	while elapsed < 7.0 and epoch == _gem_epoch and is_instance_valid(gem):
		await get_tree().physics_frame
		if epoch != _gem_epoch or not is_instance_valid(gem):
			return
		elapsed += get_physics_process_delta_time()
		if gem.freeze:
			return
		if gem.linear_velocity.length() < 0.22 and gem.angular_velocity.length() < 0.7:
			calm_frames += 1
			if calm_frames >= 12:
				return
		else:
			calm_frames = 0


## Instant version for rollback / saves: gems appear already settled.
func place_gems_settled(part_word: String, part_face: int, mod_word: String, mod_face: int) -> void:
	clear_gems()
	var az := _camera_azimuth()
	var gem_part := _make_gem(GEM_SLOT_PART, Color(0.5, 0.85, 1.0, 0.62), PARTS)
	var gem_mod := _make_gem(GEM_SLOT_MOD, Color(1.0, 0.55, 0.85, 0.62), MODS)
	gem_part.snap_settled(GEM_REVEAL_PART, part_face, az)
	gem_mod.snap_settled(GEM_REVEAL_MOD, mod_face, az)
	place_word_plaque(PARTS[part_face], true)
	place_word_plaque(MODS[mod_face], false)


## The glowing copy of a settled word, presented high beside the stage.
## [param is_part] true = body part (right slot), false = shapeshift (left).
func present_word(gem: FlatTopGem, face: int, is_part: bool) -> void:
	var plaque := _make_word_plaque(gem.word_at(face), is_part)
	add_child(plaque)
	var from: Vector3 = gem.face_labels[face].global_position
	var to := PRESENT_POS_PART if is_part else PRESENT_POS_MOD
	plaque.global_position = from
	plaque.scale = Vector3.ONE * 0.22
	var tw := create_tween()
	tw.tween_method(_plaque_arc.bind(plaque, from, to), 0.0, 1.0, 0.85)
	tw.parallel().tween_property(plaque, "scale", Vector3.ONE, 0.85)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	if is_instance_valid(plaque):
		plaque.set_meta("home", to)
		plaque.set_meta("landed", true)
	if is_part:
		_plaque_part = plaque
	else:
		_plaque_mod = plaque


func _plaque_arc(t: float, plaque: Node3D, from: Vector3, to: Vector3) -> void:
	if is_instance_valid(plaque):
		plaque.global_position = from.lerp(to, t) + Vector3.UP * (0.22 * sin(PI * t))


## Instant variant for restores: the word simply hangs in its slot.
func place_word_plaque(word: String, is_part: bool) -> void:
	_clear_plaque(is_part)
	var plaque := _make_word_plaque(word, is_part)
	add_child(plaque)
	plaque.position = PRESENT_POS_PART if is_part else PRESENT_POS_MOD
	plaque.set_meta("home", plaque.position)
	plaque.set_meta("landed", true)
	if is_part:
		_plaque_part = plaque
	else:
		_plaque_mod = plaque


func _clear_plaque(is_part: bool) -> void:
	var plaque := _plaque_part if is_part else _plaque_mod
	if is_instance_valid(plaque):
		if plaque.get_parent() != null:
			plaque.get_parent().remove_child(plaque)
		plaque.queue_free()
	if is_part:
		_plaque_part = null
	else:
		_plaque_mod = null


## A word plaque: the glowing copy of the rolled word plus its additive halo.
func _make_word_plaque(word: String, is_part: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "WordPlaque"
	var label := Label3D.new()
	label.text = word
	label.font = FlatTopGemScript._font()
	label.font_size = 170
	label.pixel_size = 0.0009
	label.outline_size = 30
	label.render_priority = 3
	if is_part:
		label.modulate = Color(0.82, 0.97, 1.0)
		label.outline_modulate = Color(0.16, 0.72, 1.0)
	else:
		label.modulate = Color(1.0, 0.86, 0.97)
		label.outline_modulate = Color(1.0, 0.46, 0.85)
	root.add_child(label)
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.15, 0.34)
	halo.mesh = quad
	halo.position = Vector3(0, 0.0, -0.02)
	var hm := ShaderMaterial.new()
	hm.shader = _halo_shader()
	hm.set_shader_parameter("glow_color", Color(0.30, 0.72, 1.0) if is_part else Color(0.95, 0.42, 0.80))
	hm.set_shader_parameter("strength", 0.34)
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	return root


## A soft radial glow behind a presented word, so the plaque reads as light
## rather than as a rectangle with a hard edge.
func _halo_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 glow_color : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.3;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(vec2(uv.x, uv.y * 1.7));
	float a = clamp(1.0 - d, 0.0, 1.0);
	ALBEDO = glow_color.rgb;
	ALPHA = a * a * strength;
}
"""
	return sh


func _camera_azimuth() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = _camera
	if cam == null:
		return PI * 0.5  # the house camera sits on the +Z axis
	return FlatTopGem.azimuth_of(cam.global_position - gem_center())


func gem_center() -> Vector3:
	return (GEM_SLOT_PART + GEM_SLOT_MOD) * 0.5


## Quick physics-random re-throw of one gem (the producer's mercy): it goes
## back in the air under a fresh seeded impulse and the new word is whatever
## face lands front-most. Returns the face the stones chose.
func rethrow_gem(which: int, rng: RandomNumberGenerator, interactive := false) -> int:
	if which < 0 or which >= _gems.size() or not is_instance_valid(_gems[which]):
		return -1
	var gem := _gems[which]
	var is_part := which == 0
	var epoch := _gem_epoch
	var power := 1.0
	if interactive:
		power = await wait_for_throw_cue()
		if epoch != _gem_epoch:
			return -1
	return await _throw_one_physics(gem, LAND_PART if is_part else LAND_MOD, is_part, rng, epoch, power)


## Deterministic single re-throw for tests: lands, then lifts the REQUESTED
## face. Gameplay never calls this.
func rethrow_gem_fixed(which: int, face: int) -> void:
	if which < 0 or which >= _gems.size() or not is_instance_valid(_gems[which]):
		return
	var gem := _gems[which]
	var is_part := which == 0
	await _throw_one(gem, LAND_PART if is_part else LAND_MOD, face, is_part, _gem_epoch)


# --------------------------------------------------------- modification chip

func _glyph_part(part: String, color: Color, parent: Node3D) -> void:
	var mat := _mat(color, 0.3, 0.2, color, 1.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match part:
		"HANDS":
			var palm := _mesh_instance(BoxMesh.new(), mat, parent)
			(palm.mesh as BoxMesh).size = Vector3(0.15, 0.05, 0.16)
			for f in 4:
				var finger := _mesh_instance(BoxMesh.new(), mat, parent)
				(finger.mesh as BoxMesh).size = Vector3(0.028, 0.12, 0.028)
				finger.position = Vector3(-0.054 + 0.036 * f, 0.08, 0.02)
			var thumb := _mesh_instance(BoxMesh.new(), mat, parent)
			(thumb.mesh as BoxMesh).size = Vector3(0.028, 0.09, 0.028)
			thumb.position = Vector3(0.085, 0.03, 0.0)
			thumb.rotation_degrees = Vector3(0, 0, -32)
		"EYES":
			for sx in [-1.0, 1.0]:
				var eye := _mesh_instance(SphereMesh.new(), mat, parent)
				(eye.mesh as SphereMesh).radius = 0.045
				(eye.mesh as SphereMesh).height = 0.09
				eye.position = Vector3(0.055 * sx, 0.02, 0)
		"LEGS":
			for sx in [-1.0, 1.0]:
				var leg := _mesh_instance(CapsuleMesh.new(), mat, parent)
				(leg.mesh as CapsuleMesh).radius = 0.032
				(leg.mesh as CapsuleMesh).height = 0.2
				leg.position = Vector3(0.045 * sx, -0.03, 0)
		"VOICE":
			for i in 3:
				var ring := _mesh_instance(TorusMesh.new(), mat, parent)
				(ring.mesh as TorusMesh).inner_radius = 0.05 + 0.045 * i
				(ring.mesh as TorusMesh).outer_radius = 0.068 + 0.045 * i
				ring.scale = Vector3(1, 1, 1)
				ring.rotation_degrees = Vector3(90, 0, 0)
				ring.position = Vector3(0, -0.06 - 0.035 * i, 0)
		"HAIR":
			var cone := _mesh_instance(CylinderMesh.new(), mat, parent)
			(cone.mesh as CylinderMesh).top_radius = 0.004
			(cone.mesh as CylinderMesh).bottom_radius = 0.075
			(cone.mesh as CylinderMesh).height = 0.17
			cone.position = Vector3(0, 0.04, 0)
			for sx in [-1.0, 1.0]:
				var strand := _mesh_instance(BoxMesh.new(), mat, parent)
				(strand.mesh as BoxMesh).size = Vector3(0.02, 0.14, 0.02)
				strand.position = Vector3(0.05 * sx, -0.02, 0.02)
				strand.rotation_degrees = Vector3(0, 0, 14 * sx)
		"BACK":
			var slab := _mesh_instance(BoxMesh.new(), mat, parent)
			(slab.mesh as BoxMesh).size = Vector3(0.17, 0.19, 0.035)
			slab.rotation_degrees = Vector3(8, 0, 0)
		"HEART":
			for sx in [-1.0, 1.0]:
				var lobe := _mesh_instance(SphereMesh.new(), mat, parent)
				(lobe.mesh as SphereMesh).radius = 0.05
				(lobe.mesh as SphereMesh).height = 0.1
				lobe.position = Vector3(0.035 * sx, 0.045, 0)
			var tip := _mesh_instance(PrismMesh.new(), mat, parent)
			(tip.mesh as PrismMesh).size = Vector3(0.14, 0.13, 0.1)
			tip.rotation_degrees = Vector3(0, 45, 0)
			tip.position = Vector3(0, -0.045, 0)
		"SKIN":
			var aura := _mesh_instance(SphereMesh.new(), mat, parent)
			(aura.mesh as SphereMesh).radius = 0.1
			(aura.mesh as SphereMesh).height = 0.2
			var aura_mat := aura.material_override as StandardMaterial3D
			aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			aura_mat.albedo_color.a = 0.4


## The applied modification, floating beside the guest: a bright ring, the
## body-part glyph, and the pairing written out underneath.
## Card art for each shapeshift, generated for this show and stored as packed
## lossless WebP. The card is raised beside the guest when the pairing is
## stamped on her, so the audience sees what she was just turned into.
const MOD_ART_DIR := "res://assets/mods/"


func mod_art(mod: String) -> Texture2D:
	var path := MOD_ART_DIR + mod.to_lower() + ".webp"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Raise the modification card: the case-specific CG for this shapeshift,
## on a lit frame at the guest's shoulder.
func show_mod_card(mod: String) -> void:
	if is_instance_valid(_mod_card):
		_mod_card.queue_free()
	_mod_card = null
	var tex := mod_art(mod)
	if tex == null:
		return
	var color: Color = MOD_COLORS.get(mod, Color(0.8, 0.9, 1.0))
	_mod_card = Node3D.new()
	_mod_card.name = "ModCard"
	add_child(_mod_card)
	var frame := BoxMesh.new()
	frame.size = Vector3(1.18, 1.18, 0.04)
	var fmi := _mesh_instance(frame, _mat(Color(0.05, 0.07, 0.16), 0.35, 0.4, color * 0.6, 1.0), _mod_card)
	fmi.name = "Frame"
	var art := Sprite3D.new()
	art.name = "Art"
	art.texture = tex
	art.pixel_size = 1.06 / float(maxi(tex.get_width(), 1))
	art.shaded = false
	art.position = Vector3(0, 0, 0.03)
	_mod_card.add_child(art)
	var caption := _label(mod, 78, color, Color(0.02, 0.04, 0.1, 0.95), 0.0022)
	caption.name = "Caption"
	caption.position = Vector3(0, -0.72, 0.03)
	_mod_card.add_child(caption)
	_mod_card.position = AURORA_MARK + Vector3(-1.15, 1.55, 0.25)
	_mod_card.scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(_mod_card, "scale", Vector3.ONE, 0.45)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func clear_mod_card() -> void:
	if is_instance_valid(_mod_card):
		_mod_card.queue_free()
	_mod_card = null


var _mod_card: Node3D = null


func apply_mod_chip(part: String, mod: String, at: Vector3) -> void:
	clear_mod_chip()
	show_mod_card(mod)
	var color: Color = MOD_COLORS.get(mod, Color(0.8, 0.9, 1.0))
	_chip = Node3D.new()
	_chip.name = "ModChip"
	add_child(_chip)
	var ring := _mesh_instance(TorusMesh.new(), _mat(color, 0.3, 0.2, color, 1.9), _chip)
	(ring.mesh as TorusMesh).inner_radius = 0.17
	(ring.mesh as TorusMesh).outer_radius = 0.21
	ring.rotation_degrees = Vector3(90, 0, 0)
	_glyph_part(part, color, _chip)
	_chip_label = _label("%s  x  %s" % [part, mod], 92, Color(0.95, 0.98, 1.0), Color(0.03, 0.05, 0.12, 0.95), 0.0015)
	_chip_label.position = Vector3(0, -0.3, 0)
	_chip.add_child(_chip_label)
	_chip_home = at
	_chip.position = at
	_chip.scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(_chip, "scale", Vector3.ONE, 0.5)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_lights(2.0)


## The kept-modifications rail: one small plaque per modification the guest
## has been given, stacked beside her mark. Body modifications are permanent
## in this show, so the audience must be able to count them.
func apply_mod_rail(mods: Array) -> void:
	if is_instance_valid(_mod_rail):
		_mod_rail.queue_free()
	_mod_rail = null
	var live: Array = []
	for m in mods:
		if str(m) != "":
			live.append(str(m))
	if live.is_empty():
		return
	_mod_rail = Node3D.new()
	_mod_rail.name = "ModRail"
	add_child(_mod_rail)
	var base := AURORA_MARK + Vector3(0.95, 0.95, -0.15)
	for i in live.size():
		var parts := str(live[i]).split(":")
		var part := parts[0]
		var mod := parts[1] if parts.size() > 1 else ""
		var color: Color = MOD_COLORS.get(mod, Color(0.8, 0.9, 1.0))
		var row := Node3D.new()
		row.name = "Kept%d" % i
		row.position = base + Vector3(0.0, 0.34 * float(i), 0.0)
		_mod_rail.add_child(row)
		var tab := BoxMesh.new()
		tab.size = Vector3(0.9, 0.24, 0.04)
		var tab_mi := _mesh_instance(tab, _mat(Color(0.05, 0.07, 0.16), 0.4, 0.3, color * 0.5, 0.7), row)
		tab_mi.name = "Tab"
		var text := _label("%s %s" % [part, mod], 80, color, Color(0.02, 0.04, 0.1, 0.95), 0.0016)
		text.name = "Text"
		text.position = Vector3(0, 0, 0.035)
		row.add_child(text)


var _mod_rail: Node3D = null


func clear_mod_chip() -> void:
	clear_mod_card()
	if is_instance_valid(_chip):
		if _chip.get_parent() != null:
			_chip.get_parent().remove_child(_chip)
		_chip.queue_free()
	_chip = null
	_chip_label = null


## Whole-body readings of the roll, applied to the guest's standing portrait.
func apply_aurora_fx(part: String, mod: String) -> void:
	if not is_instance_valid(aurora_quad):
		return
	if "world_height" in aurora_quad:
		var giant_body: bool = part in ["LEGS", "BACK", "HEART", "SKIN"]
		var target := AURORA_BASE_HEIGHT
		if giant_body and mod == "GIANT":
			target = 2.16
		elif giant_body and mod == "TINY":
			target = 1.28
		aurora_quad.set("world_height", target)
	var tint := Color(1, 1, 1, 1)
	match mod:
		"GLASS": tint = Color(1.1, 1.3, 1.6, 0.55)
		"GLOWING": tint = Color(1.25, 1.45, 1.75, 1.0)
		"HEAVY": tint = Color(0.6, 0.58, 0.7, 1.0)
		"MAGNET": tint = Color(1.12, 0.85, 1.3, 1.0)
		"STICKY": tint = Color(0.82, 1.15, 0.88, 1.0)
		"TINY": tint = Color(0.85, 0.95, 1.1, 1.0)
	if "modulate" in aurora_quad:
		aurora_quad.set("modulate", tint)
	if _aurora_bob != null and _aurora_bob.is_valid():
		_aurora_bob.kill()
		_aurora_bob = null
	if mod == "BOUNCY" and is_instance_valid(aurora_quad):
		var home_y: float = (aurora_quad as Node3D).position.y
		_aurora_bob = create_tween()
		_aurora_bob.tween_property(aurora_quad, "position:y", home_y + 0.22, 0.42)
		_aurora_bob.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_aurora_bob.tween_property(aurora_quad, "position:y", home_y, 0.42)
		_aurora_bob.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_aurora_bob.set_loops(0)


func _clear_aurora_bob() -> void:
	if _aurora_bob != null and _aurora_bob.is_valid():
		_aurora_bob.kill()
		_aurora_bob = null
	if is_instance_valid(aurora_quad):
		aurora_quad.position.y = AURORA_MARK.y


func reset_aurora_fx() -> void:
	_clear_aurora_bob()
	if is_instance_valid(aurora_quad) and "world_height" in aurora_quad:
		aurora_quad.set("world_height", AURORA_BASE_HEIGHT)
		aurora_quad.set("modulate", Color(1, 1, 1, 1))


# -------------------------------------------------------------- challenges

func clear_props() -> void:
	_stop_salvo()
	if is_instance_valid(_props):
		if _props.get_parent() != null:
			_props.get_parent().remove_child(_props)
		_props.queue_free()
	_props = get_node_or_null("Props") as Node3D
	if _props == null:
		_props = Node3D.new()
		_props.name = "Props"
		add_child(_props)
	_stones.clear()
	_bells.clear()
	_pads.clear()
	_podiums.clear()
	_fx_orbs.clear()
	if is_instance_valid(aurora_quad):
		reset_aurora_fx()


## Challenge 1 — THE CROSSING: a tear opens across the back of the stage;
## four floating stones are the only way over.
func build_crossing() -> void:
	var tear := BoxMesh.new()
	tear.size = Vector3(4.9, 0.05, 1.4)
	var tm := _mesh_instance(tear, _mat(Color(0.05, 0.015, 0.1), 1.0, 0.0, Color(0.28, 0.06, 0.5), 0.9), _props)
	tm.name = "Tear"
	tm.position = Vector3(0, STAGE_TOP + 0.03, CROSSING_Z)
	var heights := [0.98, 1.18, 1.18, 0.98]
	for i in 4:
		var stone := BoxMesh.new()
		stone.size = Vector3(0.62, 0.09, 0.62)
		var mi := _mesh_instance(stone, _mat(Color(0.2, 0.55, 0.5), 0.5, 0.3, Color(0.2, 0.75, 0.65), 0.5), _props)
		mi.name = "Stone%d" % i
		mi.position = Vector3(-1.83 + 1.22 * i, heights[i], CROSSING_Z)
		_stones.append(mi)
		_pop_in(mi)


## Challenge 2 — BELL BARRAGE: a polite little cannon at stage left and three
## golden bells on a rack, stage right.
func build_bells() -> void:
	var rack_mat := _mat(Color(0.1, 0.11, 0.2), 0.4, 0.7)
	var post := BoxMesh.new()
	post.size = Vector3(0.09, 1.1, 0.09)
	var pm := _mesh_instance(post, rack_mat, _props)
	pm.position = Vector3(1.75, STAGE_TOP + 0.55, BELL_Z)
	var arm := BoxMesh.new()
	arm.size = Vector3(1.15, 0.07, 0.07)
	var am := _mesh_instance(arm, rack_mat, _props)
	am.position = Vector3(1.75, STAGE_TOP + 1.04, BELL_Z)
	for i in 3:
		var bell := CylinderMesh.new()
		bell.top_radius = 0.13
		bell.bottom_radius = 0.19
		bell.height = 0.24
		var mi := _mesh_instance(bell, _mat(Color(1.0, 0.82, 0.35), 0.25, 0.8, Color(0.9, 0.7, 0.25), 0.7), _props)
		mi.name = "Bell%d" % i
		mi.position = Vector3(1.75 - 0.38 + 0.38 * i, STAGE_TOP + 1.24, BELL_Z)
		_bells.append(mi)
		_pop_in(mi)
	var base := BoxMesh.new()
	base.size = Vector3(0.34, 0.26, 0.34)
	var bm := _mesh_instance(base, rack_mat, _props)
	bm.position = Vector3(-2.05, STAGE_TOP + 0.13, -0.5)
	var aim := Node3D.new()
	aim.name = "Cannon"
	_props.add_child(aim)
	aim.position = Vector3(-2.05, STAGE_TOP + 0.45, -0.5)
	aim.look_at(Vector3(1.75, STAGE_TOP + 1.24, BELL_Z), Vector3.UP)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.085
	barrel.bottom_radius = 0.1
	barrel.height = 0.55
	var bami := _mesh_instance(barrel, _mat(Color(0.75, 0.3, 0.4), 0.35, 0.7, Color(0.8, 0.3, 0.4), 0.5), aim)
	bami.rotation_degrees = Vector3(90, 0, 0)
	bami.position = Vector3(0, 0, 0.3)
	aim.set_meta("muzzle", Vector3(0, 0, 0.6))


## Challenge 3 — ECHO CHOIR: four podiums, four pads, one remembered melody.
func build_choir() -> void:
	var hues := [Color(0.4, 0.85, 1.0), Color(1.0, 0.55, 0.85), Color(1.0, 0.85, 0.4), Color(0.55, 1.0, 0.6)]
	for i in 4:
		var podium := Node3D.new()
		podium.name = "Podium%d" % i
		_props.add_child(podium)
		var post := CylinderMesh.new()
		post.top_radius = 0.07
		post.bottom_radius = 0.09
		post.height = 0.95
		var pm := _mesh_instance(post, _mat(Color(0.1, 0.11, 0.2), 0.4, 0.7), podium)
		pm.position = Vector3(-2.15 + 1.43 * i, STAGE_TOP + 0.475, CHOIR_Z)
		var pad := CylinderMesh.new()
		pad.top_radius = 0.28
		pad.bottom_radius = 0.28
		pad.height = 0.05
		var mi := _mesh_instance(pad, _mat(hues[i], 0.3, 0.3, hues[i], 0.35), podium)
		mi.name = "Pad%d" % i
		mi.position = Vector3(-2.15 + 1.43 * i, STAGE_TOP + 1.0, CHOIR_Z)
		_pads.append(mi)
		_podiums.append(podium)
		_pop_in(podium)


const CROSSING_Z := -1.55
const BELL_Z := -1.0
const CHOIR_Z := -1.45


func _pop_in(node: Node3D) -> void:
	var final := node.scale
	node.scale = final * 0.05
	var tw := create_tween()
	tw.tween_property(node, "scale", final, 0.4)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The staged attempt. Success and failure are already decided (seeded roll in
## ShowDirector); this choreography only performs them.
func play_challenge(round_no: int, success: bool, pattern: Array) -> void:
	match round_no:
		1: await _play_crossing(success)
		2: await _play_bells(success)
		3: await _play_choir(success, pattern)
	_show_result(success)
	await get_tree().create_timer(1.0).timeout


func _play_crossing(success: bool) -> void:
	if not is_instance_valid(aurora_quad):
		await get_tree().create_timer(1.2).timeout
		return
	var quad := aurora_quad as Node3D
	var start := Vector3(-2.45, STAGE_TOP, CROSSING_Z)
	var goal := Vector3(2.45, STAGE_TOP, CROSSING_Z)
	quad.position = start
	var hops := 4
	for i in hops:
		var stone_pos: Vector3 = _stones[i].position if i < _stones.size() else Vector3(-1.83 + 1.22 * i, 1.1, CROSSING_Z)
		var fail_here := (not success) and i == 2
		await _hop(quad, stone_pos + Vector3(0, 0.08, 0.12), fail_here)
		if fail_here:
			# The stone dips, flickers red, and she slides back down.
			var mat := _stones[i].material_override as StandardMaterial3D
			if mat != null:
				var flick := create_tween()
				for k in 3:
					flick.tween_property(mat, "emission", Color(1, 0.15, 0.1), 0.12)
					flick.tween_property(mat, "emission", Color(0.3, 0.05, 0.05), 0.12)
				await flick.finished
			var back := create_tween()
			back.tween_property(quad, "position", start, 0.7)
			back.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			await back.finished
			return
		if i < _stones.size():
			var smat := _stones[i].material_override as StandardMaterial3D
			if smat != null:
				smat.emission_energy_multiplier = 1.8
	await _hop(quad, goal, false)
	var home := create_tween()
	home.tween_property(quad, "position", AURORA_MARK, 0.8)
	home.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await home.finished


func _hop(quad: Node3D, to: Vector3, falter: bool) -> void:
	var from := quad.position
	var tw := create_tween()
	tw.tween_method(
		func(t: float) -> void:
			var p := from.lerp(to, t)
			p.y += (0.34 if not falter else 0.12) * sin(PI * t)
			quad.position = p,
		0.0, 1.0, 0.55
	)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _play_bells(success: bool) -> void:
	if is_instance_valid(aurora_quad):
		aurora_quad.position = Vector3(0.15, STAGE_TOP, 2.6)
	_salvo_left = 3 if success else 4
	_salvo_success = success
	_start_salvo()
	var total := 3.4 if success else 3.8
	await get_tree().create_timer(total).timeout
	_stop_salvo()
	if success:
		for bell in _bells:
			var mat := bell.material_override as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = 2.2
			var tw := create_tween()
			tw.tween_property(bell, "scale", Vector3.ONE * 1.25, 0.16)
			tw.tween_property(bell, "scale", Vector3.ONE, 0.3)
			await tw.finished
	if is_instance_valid(aurora_quad):
		var home := create_tween()
		home.tween_property(aurora_quad, "position", AURORA_MARK, 0.8)
		home.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await home.finished


func _start_salvo() -> void:
	if _salvo_timer != null and is_instance_valid(_salvo_timer):
		_salvo_timer.stop()
	_salvo_timer = Timer.new()
	_salvo_timer.wait_time = 0.85
	_salvo_timer.timeout.connect(_fire_orb)
	_props.add_child(_salvo_timer)
	_salvo_timer.start()


func _stop_salvo() -> void:
	if _salvo_timer != null and is_instance_valid(_salvo_timer):
		_salvo_timer.stop()
		_salvo_timer.queue_free()
	_salvo_timer = null


func _fire_orb() -> void:
	if _salvo_left <= 0:
		return
	_salvo_left -= 1
	var aim: Node3D = null
	for child in _props.get_children():
		if child.has_meta("muzzle"):
			aim = child
			break
	if aim == null:
		return
	var orb := _mesh_instance(SphereMesh.new(), _mat(Color(1.0, 0.6, 0.3), 0.3, 0.2, Color(1.0, 0.55, 0.25), 2.0), _props)
	(orb.mesh as SphereMesh).radius = 0.09
	(orb.mesh as SphereMesh).height = 0.18
	var muzzle: Vector3 = aim.get_meta("muzzle")
	orb.position = aim.to_global(muzzle)
	_fx_orbs.append(orb)
	var target := Vector3.ZERO
	var hit := _salvo_success
	if hit and not _bells.is_empty():
		var bell := _bells[_cosmetic.randi_range(0, _bells.size() - 1)]
		target = bell.global_position if is_instance_valid(bell) else Vector3(1.75, 1.74, BELL_Z)
	else:
		# A miss: the orb sails under the rack and dies on the floor.
		target = Vector3(1.3 + _cosmetic.randf_range(-0.5, 0.5), STAGE_TOP + 0.05, -0.2)
	var from := orb.position
	var tw := create_tween()
	tw.tween_method(_orb_arc.bind(orb, from, target), 0.0, 1.0, 0.75)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(
		func() -> void:
			if not is_instance_valid(orb):
				return
			if hit and not _bells.is_empty() and is_instance_valid(_props):
				var nearest := _bells[0]
				for bell in _bells:
					if bell.global_position.distance_to(orb.position) < nearest.global_position.distance_to(orb.position):
						nearest = bell
				var pulse := create_tween()
				pulse.tween_property(nearest, "scale", Vector3.ONE * 1.3, 0.12)
				pulse.tween_property(nearest, "scale", Vector3.ONE, 0.25)
			else:
				var om := orb.material_override as StandardMaterial3D
				if om != null:
					om.albedo_color = Color(0.4, 0.35, 0.35)
					om.emission_energy_multiplier = 0.2
				var sink := create_tween()
				sink.tween_property(orb, "scale", Vector3.ONE * 0.3, 0.5)
			_fx_orbs.erase(orb)
			orb.queue_free()
	)


func _star_arc(t: float, chip: Node3D, pip_target: Vector3) -> void:
	if is_instance_valid(chip):
		chip.position = Vector3(0, 2.16, 3.3).lerp(pip_target, t) + Vector3.UP * (1.1 * sin(PI * t))


func _orb_arc(t: float, orb: Node3D, from: Vector3, target: Vector3) -> void:
	if is_instance_valid(orb):
		orb.position = from.lerp(target, t) + Vector3.UP * (0.9 * sin(PI * t))


func _play_choir(success: bool, pattern: Array) -> void:
	if is_instance_valid(aurora_quad):
		aurora_quad.position = AURORA_MARK
	for step in pattern:
		var idx := int(step) % maxi(_pads.size(), 1)
		if _pads.is_empty():
			break
		var pad := _pads[idx]
		var mat := pad.material_override as StandardMaterial3D
		var tw := create_tween()
		if mat != null:
			tw.parallel().tween_property(mat, "emission_energy_multiplier", 2.4, 0.16)
			tw.parallel().tween_property(mat, "emission_energy_multiplier", 0.5, 0.3)
		tw.tween_property(pad, "scale", Vector3.ONE * 1.2, 0.16)
		tw.tween_property(pad, "scale", Vector3.ONE, 0.3)
		_spawn_note(pad.global_position + Vector3(0, 0.1, 0))
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(0.7).timeout
	if success:
		for pad in _pads:
			var mat := pad.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = Color(1.0, 0.95, 0.75)
				mat.emission = Color(1.0, 0.9, 0.6)
				mat.emission_energy_multiplier = 2.0
			_spawn_note(pad.global_position + Vector3(0, 0.1, 0))
		if is_instance_valid(aurora_quad):
			var sway := create_tween()
			sway.tween_property(aurora_quad, "position:x", AURORA_MARK.x + 0.08, 0.4)
			sway.tween_property(aurora_quad, "position:x", AURORA_MARK.x, 0.4)
			await sway.finished
	else:
		var last := _pads[int(pattern[pattern.size() - 1]) % _pads.size()] if not pattern.is_empty() else _pads[0]
		var mat := last.material_override as StandardMaterial3D
		if mat != null:
			var flick := create_tween()
			for k in 3:
				flick.tween_property(mat, "emission", Color(1, 0.15, 0.1), 0.14)
				flick.tween_property(mat, "emission", Color(0.4, 0.08, 0.08), 0.14)
			await flick.finished


func _spawn_note(at: Vector3) -> void:
	var note := Label3D.new()
	note.text = "~"
	note.font = FlatTopGemScript._font()
	note.font_size = 140
	note.pixel_size = 0.006
	note.modulate = Color(0.85, 0.95, 1.0, 0.95)
	note.outline_size = 12
	note.outline_modulate = Color(0.05, 0.1, 0.2, 0.9)
	note.position = at
	_props.add_child(note)
	var tw := create_tween()
	tw.tween_property(note, "position:y", at.y + 0.8, 1.1)
	tw.parallel().tween_property(note, "modulate:a", 0.0, 1.1)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.finished.connect(note.queue_free)


# ------------------------------------------------------------------ results

func _show_result(success: bool) -> void:
	if is_instance_valid(_stamp):
		_stamp.queue_free()
	_stamp = _label("CLEAR!" if success else "MISS...", 150, Color(1.0, 0.85, 0.3) if success else Color(0.65, 0.75, 0.95), Color(0.03, 0.05, 0.12, 0.95), 0.008)
	_stamp.name = "ResultStamp"
	_stamp.position = Vector3(0, 2.75, 1.4)
	add_child(_stamp)
	_stamp.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(_stamp, "scale", Vector3.ONE, 0.35)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(_stamp, "modulate:a", 0.0, 0.5)
	tw.finished.connect(_stamp.queue_free)
	_pulse_lights(2.6 if success else 1.2)


## A star flies from the pedestal to the pips on the star cloth (or a dud
## drops off the apron). Call after set_stars() so the pip already shows the
## result.
func fly_star(earned: bool, star_index: int) -> void:
	var pip_target := PIP_BASE + PIP_STEP * float(clampi(star_index, 0, 2))
	var chip := FlatTopGemScript.new()
	chip.build_words = false
	chip.gem_color = Color(1.0, 0.85, 0.35, 0.95) if earned else Color(0.4, 0.4, 0.48, 0.9)
	chip.girdle_radius = 0.17
	chip.table_radius = 0.085
	chip.crown_height = 0.07
	chip.pavilion_height = 0.19
	chip.scale = Vector3.ONE * 0.9
	chip.position = Vector3(0, 2.16, 3.3)
	add_child(chip)
	var tw := create_tween()
	if earned:
		tw.tween_method(_star_arc.bind(chip, pip_target), 0.0, 1.0, 0.95)
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		tw.tween_property(chip, "position", Vector3(0.3, 0.05, 4.4), 0.9)
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	var out := create_tween()
	out.tween_property(chip, "scale", Vector3.ONE * 0.05, 0.25)
	await out.finished
	chip.queue_free()


## Golden rain for a perfect show.
func confetti_burst() -> void:
	if is_instance_valid(_confetti):
		_confetti.queue_free()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var piece := BoxMesh.new()
	piece.size = Vector3(0.05, 0.012, 0.08)
	mm.mesh = piece
	mm.use_colors = true
	var colors := [Color(1, 0.85, 0.35), Color(0.4, 0.9, 1.0), Color(1, 0.5, 0.85), Color(0.6, 1, 0.6)]
	mm.instance_count = 90
	_confetti_data.clear()
	for i in 90:
		_confetti_data.append({
			"x": _cosmetic.randf_range(-2.7, 2.7),
			"z": _cosmetic.randf_range(-1.0, 3.0),
			"fall": _cosmetic.randf_range(0.55, 1.15),
			"spin": _cosmetic.randf_range(-4.0, 4.0),
			"phase": _cosmetic.randf_range(0.0, 3.8),
			"color": colors[_cosmetic.randi_range(0, colors.size() - 1)],
		})
		mm.set_instance_color(i, _confetti_data[i]["color"])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat(Color(1, 1, 1), 0.4, 0.0, Color(0.9, 0.9, 0.9), 0.4)
	_confetti = Node3D.new()
	add_child(_confetti)
	_confetti.add_child(mi)
	_confetti_time = 0.0


func _tick_confetti(delta: float) -> void:
	if not is_instance_valid(_confetti):
		return
	_confetti_time += delta
	var mi := (_confetti.get_child(0) as MultiMeshInstance3D)
	var mm := mi.multimesh
	for i in mm.instance_count:
		var d: Dictionary = _confetti_data[i]
		var y := 4.4 - fmod(_confetti_time * float(d["fall"]) + float(d["phase"]), 4.4)
		var t := Transform3D(
			Basis.IDENTITY.rotated(Vector3.UP, _confetti_time * float(d["spin"])),
			Vector3(float(d["x"]) + 0.25 * sin(_confetti_time * 1.7 + float(d["phase"])), y, float(d["z"]))
		)
		mm.set_instance_transform(i, t)
	if _confetti_time > 9.0:
		_confetti.queue_free()
		_confetti = null


func _pulse_lights(peak: float) -> void:
	if _key_light == null:
		return
	var tw := create_tween()
	tw.tween_property(_key_light, "light_energy", peak, 0.14)
	tw.tween_property(_key_light, "light_energy", 1.35, 0.5)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------- full reset

func reset_show() -> void:
	apply_mod_rail([])
	clear_mod_card()
	clear_gems()
	clear_props()
	clear_mod_chip()
	set_stars(0)
	reset_aurora_fx()
	if is_instance_valid(_stamp):
		_stamp.queue_free()
		_stamp = null
