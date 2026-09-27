class_name ShowStage extends Node3D
## The KLIMA GEM television studio: a real 3D stage built from Godot
## geometry — no painted backdrop, no imported image. A raised round platform
## under a proscenium arch, curtains, a star cloth, a lighting truss, a live
## audience with glowsticks, and a pedestal where the word-gems hover.
##
## The stage owns every piece of show furniture: the two flat-topped gems,
## the modification chip, the challenge props (built and torn down on cue),
## the star pips on the proscenium pillar, and the per-challenge
## choreography. All randomness that matters comes in from ShowDirector /
## GameState so a playthrough stays deterministic; purely cosmetic scatter
## uses this node's own fixed-seed generator.

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

const STAGE_TOP := 0.5
const AURORA_MARK := Vector3(1.05, STAGE_TOP, 0.9)
const REN_MARK := Vector3(-1.15, STAGE_TOP, 1.1)
const AURORA_BASE_HEIGHT := 1.72
const GEM_SLOT_L := Vector3(-0.44, 1.78, 2.0)
const GEM_SLOT_R := Vector3(0.44, 1.78, 2.0)
const PIP_BASE := Vector3(-3.62, 3.42, 3.02)
const PIP_STEP := Vector3(0.42, 0.0, 0.06)

var aurora_quad: Node3D = null
var ren_quad: Node3D = null

var _cosmetic := RandomNumberGenerator.new()
var _gems: Array[FlatTopGem] = []
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
var _confetti: Node3D = null
var _confetti_data: Array = []
var _confetti_time := 0.0
var _chip_time := 0.0
var _aurora_bob: Tween = null
var _fx_orbs: Array[Node3D] = []


func _ready() -> void:
	add_to_group("show_stage")
	_cosmetic.seed = 20260927
	_build_environment()
	_build_hall()
	_build_set()
	_build_truss_and_lights()
	_build_audience()
	_build_pedestal()
	_build_marks()
	_build_pips()
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)


func _process(delta: float) -> void:
	_chip_time += delta
	if is_instance_valid(_chip):
		_chip.rotation.y += 0.9 * delta
		_chip.position.y = _chip_home.y + 0.05 * sin(_chip_time * 1.6)
	_tick_confetti(delta)


func set_actor(alias: String, quad: Node3D) -> void:
	if alias == "aurora":
		aurora_quad = quad
	elif alias == "ren":
		ren_quad = quad


## Parent for standing portraits (the StageDirector's quads, or anything else
## that wants to stand on the stage floor).
func characters_parent() -> Node3D:
	return get_node("World3D/Characters") as Node3D


func aurora_hand() -> Vector3:
	var base := AURORA_MARK
	if is_instance_valid(aurora_quad):
		base = (aurora_quad as Node3D).global_position
	return base + Vector3(0.25, AURORA_BASE_HEIGHT * 0.72, -0.18)


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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.016, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.32, 0.55)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_hall() -> void:
	# The house floor the audience sits on.
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(34.0, 0.1, 16.0)
	var floor_mi := _mesh_instance(floor_mesh, _mat(Color(0.015, 0.02, 0.05), 0.95), self)
	floor_mi.position = Vector3(0, -0.05, 4.0)


func _build_set() -> void:
	var set_root := Node3D.new()
	set_root.name = "Set"
	add_child(set_root)

	# Raised round platform with a glowing rim.
	var platform := CylinderMesh.new()
	platform.top_radius = 3.3
	platform.bottom_radius = 3.45
	platform.height = STAGE_TOP
	platform.radial_segments = 48
	var plat_mi := _mesh_instance(platform, _mat(Color(0.07, 0.08, 0.17), 0.55, 0.25), set_root)
	plat_mi.position = Vector3(0, STAGE_TOP * 0.5, 0)

	var rim := TorusMesh.new()
	rim.inner_radius = 3.26
	rim.outer_radius = 3.38
	var rim_mi := _mesh_instance(rim, _mat(Color(0.2, 0.5, 0.8), 0.3, 0.6, Color(0.3, 0.75, 1.0), 1.6), set_root)
	rim_mi.position = Vector3(0, STAGE_TOP, 0)

	# Proscenium: two pillars and a header, the TV frame of the show. They
	# stand close to the camera so the legs and header land just inside the
	# frame edges — a real broadcast sight-line, not a dollhouse view.
	var pillar_mat := _mat(Color(0.05, 0.07, 0.16), 0.45, 0.4, Color(0.12, 0.3, 0.6), 0.35)
	for sx in [-1.0, 1.0]:
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.62, 3.9, 0.62)
		var pm := _mesh_instance(pillar, pillar_mat, set_root)
		pm.position = Vector3(2.78 * sx, 1.9, 4.5)
	var header := BoxMesh.new()
	header.size = Vector3(6.2, 0.55, 0.62)
	var hm := _mesh_instance(header, pillar_mat, set_root)
	hm.position = Vector3(0, 3.78, 4.5)

	# Curtains: heavy violet side panels and a valance across the top.
	var curtain_mat := _mat(Color(0.16, 0.06, 0.3), 0.7, 0.25)
	for sx in [-1.0, 1.0]:
		var curtain := BoxMesh.new()
		curtain.size = Vector3(1.35, 3.4, 0.16)
		var cm := _mesh_instance(curtain, curtain_mat, set_root)
		cm.position = Vector3(2.32 * sx, 1.68, 4.0)
		cm.rotation_degrees = Vector3(0, -12.0 * sx, 0)
	var valance := BoxMesh.new()
	valance.size = Vector3(6.2, 0.5, 0.15)
	var vm := _mesh_instance(valance, curtain_mat, set_root)
	vm.position = Vector3(0, 3.3, 4.12)

	# Star cloth backdrop with the show sign.
	var backdrop := BoxMesh.new()
	backdrop.size = Vector3(14.0, 6.4, 0.2)
	var bm := _mesh_instance(backdrop, _mat(Color(0.045, 0.055, 0.14), 0.9), set_root)
	bm.position = Vector3(0, 3.0, -3.7)

	var star_mm := MultiMesh.new()
	star_mm.transform_format = MultiMesh.TRANSFORM_3D
	star_mm.mesh = SphereMesh.new()
	(star_mm.mesh as SphereMesh).radius = 0.032
	(star_mm.mesh as SphereMesh).height = 0.064
	star_mm.instance_count = 52
	for i in 52:
		var pos := Vector3(_cosmetic.randf_range(-6.7, 6.7), _cosmetic.randf_range(0.9, 6.0), -3.58)
		star_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * _cosmetic.randf_range(0.6, 1.5)), pos))
	var star_mi := MultiMeshInstance3D.new()
	star_mi.multimesh = star_mm
	var star_mat := _mat(Color(0.8, 0.92, 1.0), 1.0, 0.0, Color(0.75, 0.9, 1.0), 1.8)
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mi.material_override = star_mat
	set_root.add_child(star_mi)

	var sign := _label("KLIMA GEM", 160, Color(0.55, 0.9, 1.0), Color(0.02, 0.06, 0.16, 0.95), 0.009)
	sign.position = Vector3(0, 4.0, -3.55)
	set_root.add_child(sign)
	var sub := _label("TWO GEMS  -  THREE TRIALS", 54, Color(0.75, 0.85, 1.0, 0.9), Color(0.02, 0.05, 0.12, 0.9), 0.008)
	sub.position = Vector3(0, 3.35, -3.55)
	set_root.add_child(sub)

	var live_dot := _mesh_instance(SphereMesh.new(), _mat(Color(1, 0.25, 0.3), 0.4, 0.0, Color(1, 0.2, 0.25), 2.2), set_root)
	live_dot.mesh.radius = 0.04
	live_dot.mesh.height = 0.08
	live_dot.position = Vector3(2.42, 3.02, 4.42)
	var live := _label("LIVE", 60, Color(1, 0.4, 0.42), Color(0.1, 0.02, 0.03, 0.9), 0.006)
	live.position = Vector3(2.72, 3.02, 4.42)
	set_root.add_child(live)


func _build_truss_and_lights() -> void:
	var truss_mat := _mat(Color(0.1, 0.11, 0.2), 0.4, 0.7)
	for z in [-0.6, 1.7]:
		var beam := BoxMesh.new()
		beam.size = Vector3(7.6, 0.12, 0.12)
		var bmi := _mesh_instance(beam, truss_mat)
		bmi.position = Vector3(0, 4.85, z)
		for sx in [-1.0, 1.0]:
			var hang := BoxMesh.new()
			hang.size = Vector3(0.08, 0.85, 0.08)
			var hmi := _mesh_instance(hang, truss_mat)
			hmi.position = Vector3(3.6 * sx, 5.28, z)

	# Three spots with visible volumetric-ish cones aimed at the pedestal.
	var cone_mat := StandardMaterial3D.new()
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cone_mat.albedo_color = Color(0.55, 0.8, 1.0, 0.075)
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for sx in [-1.0, 0.0, 1.0]:
		var body := CylinderMesh.new()
		body.top_radius = 0.09
		body.bottom_radius = 0.13
		body.height = 0.34
		var bmi := _mesh_instance(body, _mat(Color(0.15, 0.16, 0.24), 0.4, 0.8, Color(0.6, 0.85, 1.0), 1.2))
		bmi.position = Vector3(1.9 * sx, 4.68, 1.7)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.07
		cone.bottom_radius = 1.35
		cone.height = 3.6
		cone.radial_segments = 24
		var cmi := _mesh_instance(cone, cone_mat)
		cmi.position = Vector3(1.9 * sx, 2.85, 1.7)
		cmi.rotation_degrees = Vector3(-16.0 * sx, 0, 0)

	_key_light = OmniLight3D.new()
	_key_light.position = Vector3(0, 4.5, 2.8)
	_key_light.light_color = Color(1.0, 0.96, 0.88)
	_key_light.light_energy = 1.5
	_key_light.omni_range = 11.0
	add_child(_key_light)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 3.2, -3.0)
	rim.light_color = Color(0.5, 0.75, 1.0)
	rim.light_energy = 1.1
	rim.omni_range = 10.0
	add_child(rim)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 24, 0)
	sun.light_color = Color(0.75, 0.82, 1.0)
	sun.light_energy = 0.22
	add_child(sun)


func _build_audience() -> void:
	var crowd := Node3D.new()
	crowd.name = "Audience"
	add_child(crowd)
	var cap := CapsuleMesh.new()
	cap.radius = 0.21
	cap.height = 1.05
	var body_mm := MultiMesh.new()
	body_mm.transform_format = MultiMesh.TRANSFORM_3D
	body_mm.mesh = cap
	var spots: Array[Vector3] = []
	var count := 0
	for row in 3:
		var z := 5.4 + 0.85 * row
		var y := 0.35 + 0.28 * row
		var n := 9 - row
		for i in n:
			var x := -4.6 + 9.2 * float(i) / float(n - 1) + _cosmetic.randf_range(-0.25, 0.25)
			spots.append(Vector3(x, y, z + _cosmetic.randf_range(-0.2, 0.2)))
			count += 1
	body_mm.instance_count = count
	for i in count:
		var t := Transform3D(Basis.IDENTITY, spots[i])
		body_mm.set_instance_transform(i, t)
	var body_mi := MultiMeshInstance3D.new()
	body_mi.multimesh = body_mm
	# Silhouettes: darker than the hall, so the stage stays the brightest thing.
	body_mi.material_override = _mat(Color(0.025, 0.03, 0.075), 0.95)
	crowd.add_child(body_mi)

	# Glowsticks: little unshaded color bars held up in the dark.
	var stick := BoxMesh.new()
	stick.size = Vector3(0.035, 0.24, 0.035)
	var stick_mm := MultiMesh.new()
	stick_mm.transform_format = MultiMesh.TRANSFORM_3D
	stick_mm.mesh = stick
	stick_mm.use_colors = true
	var stick_colors := [Color(0.4, 0.9, 1.0), Color(1.0, 0.5, 0.85), Color(1.0, 0.85, 0.4), Color(0.6, 1.0, 0.6)]
	stick_mm.instance_count = 26
	for i in 26:
		var base := spots[_cosmetic.randi_range(0, spots.size() - 1)]
		var t := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, _cosmetic.randf_range(-0.5, 0.5)), base + Vector3(_cosmetic.randf_range(-0.28, 0.28), 0.42, 0.12))
		stick_mm.set_instance_transform(i, t)
		stick_mm.set_instance_color(i, stick_colors[_cosmetic.randi_range(0, stick_colors.size() - 1)])
	var stick_mi := MultiMeshInstance3D.new()
	stick_mi.multimesh = stick_mm
	var stick_mat := StandardMaterial3D.new()
	stick_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stick_mat.vertex_color_use_as_albedo = true
	stick_mi.material_override = stick_mat
	crowd.add_child(stick_mi)


func _build_pedestal() -> void:
	var ped := Node3D.new()
	ped.name = "Pedestal"
	add_child(ped)
	var column := CylinderMesh.new()
	column.top_radius = 0.3
	column.bottom_radius = 0.38
	column.height = 0.85
	column.radial_segments = 8
	var col_mi := _mesh_instance(column, _mat(Color(0.09, 0.1, 0.22), 0.35, 0.6, Color(0.2, 0.45, 0.8), 0.5), ped)
	col_mi.position = Vector3(0, STAGE_TOP + 0.425, 2.0)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.27
	ring.bottom_radius = 0.27
	ring.height = 0.035
	ring.radial_segments = 24
	var ring_mi := _mesh_instance(ring, _mat(Color(0.4, 0.8, 1.0), 0.2, 0.5, Color(0.45, 0.85, 1.0), 2.0), ped)
	ring_mi.position = Vector3(0, STAGE_TOP + 0.87, 2.0)


func _build_marks() -> void:
	var marks := Node3D.new()
	marks.name = "Marks"
	add_child(marks)
	for spec in [[AURORA_MARK, Color(1.0, 0.55, 0.85)], [REN_MARK, Color(0.45, 0.85, 1.0)]]:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.4
		disc.bottom_radius = 0.4
		disc.height = 0.015
		var mi := _mesh_instance(disc, _mat(spec[1] as Color, 0.3, 0.4, spec[1] as Color, 0.9), marks)
		mi.position = (spec[0] as Vector3) + Vector3(0, 0.012, 0)


func _build_pips() -> void:
	var pips := Node3D.new()
	pips.name = "StarPips"
	add_child(pips)
	var caption := _label("STARS", 56, Color(0.8, 0.9, 1.0, 0.95), Color(0.02, 0.05, 0.12, 0.9), 0.006)
	caption.position = PIP_BASE + Vector3(PIP_STEP.x, 0.42, 0.15)
	pips.add_child(caption)
	for i in 3:
		var pip := FlatTopGemScript.new()
		pip.build_words = false
		pip.gem_color = Color(0.16, 0.18, 0.26, 0.8)
		pip.scale = Vector3.ONE * 0.52
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
			mat.emission_energy_multiplier = 1.6
		else:
			mat.albedo_color = Color(0.16, 0.18, 0.26, 0.8)
			mat.emission = Color(0.1, 0.1, 0.16)
			mat.emission_energy_multiplier = 0.6


# ------------------------------------------------------------------- gems

func _make_gem(slot: Vector3, color: Color, word_list: PackedStringArray) -> FlatTopGem:
	var gem: FlatTopGem = FlatTopGemScript.new()
	gem.gem_color = color
	gem.set_words(word_list)
	gem.position = slot + Vector3(0, 3.2, 0)  # starts above the truss, out of sight
	add_child(gem)
	_gems.append(gem)
	return gem


func clear_gems() -> void:
	for gem in _gems:
		if is_instance_valid(gem):
			gem.queue_free()
	_gems.clear()


## The signature throw: two gems arc from the guest's hand to the pedestal,
## tumble, then settle one after the other with the rolled word fronting the
## camera. Words are already decided; this only stages them.
func throw_gems(part_word: String, part_face: int, mod_word: String, mod_face: int) -> void:
	clear_gems()
	var from := aurora_hand()
	# The word lists sit on the faces in order; the announced face is the roll.
	var gem_a := _make_gem(GEM_SLOT_L, Color(0.5, 0.85, 1.0, 0.62), PARTS)
	var gem_b := _make_gem(GEM_SLOT_R, Color(1.0, 0.55, 0.85, 0.62), MODS)
	gem_a.position = from + Vector3(-0.1, 0.0, 0.0)
	gem_b.position = from + Vector3(0.14, 0.0, 0.0)

	gem_a.start_spinning(5.2)
	gem_b.start_spinning(4.4)
	# Both arcs run at once; the flight time is the same for the pair.
	gem_a.launch(from + Vector3(-0.1, 0.0, 0.0), GEM_SLOT_L, 2.0, 0.95)
	gem_b.launch(from + Vector3(0.14, 0.0, 0.0), GEM_SLOT_R, 2.0, 0.95)
	await get_tree().create_timer(0.95).timeout

	_pulse_lights(2.4)
	gem_a.start_spinning(2.6)
	gem_b.start_spinning(2.1)
	await get_tree().create_timer(0.55).timeout

	await gem_a.settle_facing(part_face, _camera_azimuth(), 1.25)
	await gem_a.flash_reveal()
	await get_tree().create_timer(0.45).timeout

	await gem_b.settle_facing(mod_face, _camera_azimuth(), 1.25)
	await gem_b.flash_reveal()
	await get_tree().create_timer(0.3).timeout


## Instant version for rollback / saves: gems appear already settled.
func place_gems_settled(part_word: String, part_face: int, mod_word: String, mod_face: int) -> void:
	clear_gems()
	var gem_a := _make_gem(GEM_SLOT_L, Color(0.5, 0.85, 1.0, 0.62), PARTS)
	var gem_b := _make_gem(GEM_SLOT_R, Color(1.0, 0.55, 0.85, 0.62), MODS)
	gem_a.rotation.y = FlatTopGem.face_azimuth(part_face) - _camera_azimuth()
	gem_b.rotation.y = FlatTopGem.face_azimuth(mod_face) - _camera_azimuth()


func _camera_azimuth() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return PI * 0.5  # the house camera sits on the +Z axis
	return FlatTopGem.azimuth_of(cam.global_position - gem_center())


func gem_center() -> Vector3:
	return (GEM_SLOT_L + GEM_SLOT_R) * 0.5


## Quick re-throw of just the modification gem (the producer's mercy).
func rethrow_gem(which: int, face: int, word: String) -> void:
	if which < 0 or which >= _gems.size() or not is_instance_valid(_gems[which]):
		return
	var gem := _gems[which]
	var from := aurora_hand()
	gem.start_spinning(6.0)
	await gem.launch(from, GEM_SLOT_R if which == 1 else GEM_SLOT_L, 1.5, 0.8)
	await gem.settle_facing(face, _camera_azimuth(), 1.0)
	await gem.flash_reveal()


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


var _chip_home := Vector3.ZERO


## The applied modification, floating beside the guest: a bright ring, the
## body-part glyph, and the pairing written out underneath.
func apply_mod_chip(part: String, mod: String, at: Vector3) -> void:
	clear_mod_chip()
	var color: Color = MOD_COLORS.get(mod, Color(0.8, 0.9, 1.0))
	_chip = Node3D.new()
	_chip.name = "ModChip"
	add_child(_chip)
	var ring := _mesh_instance(TorusMesh.new(), _mat(color, 0.3, 0.2, color, 1.9), _chip)
	(ring.mesh as TorusMesh).inner_radius = 0.17
	(ring.mesh as TorusMesh).outer_radius = 0.21
	ring.rotation_degrees = Vector3(90, 0, 0)
	_glyph_part(part, color, _chip)
	_chip_label = _label("%s  x  %s" % [part, mod], 92, Color(0.95, 0.98, 1.0), Color(0.03, 0.05, 0.12, 0.95), 0.0055)
	_chip_label.position = Vector3(0, -0.34, 0)
	_chip.add_child(_chip_label)
	_chip_home = at
	_chip.position = at
	_chip.scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(_chip, "scale", Vector3.ONE, 0.5)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_lights(2.0)


func clear_mod_chip() -> void:
	if is_instance_valid(_chip):
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
			target = 2.2
		elif giant_body and mod == "TINY":
			target = 1.3
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
		_props.queue_free()
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


## Challenge 1 — THE CROSSING: a tear opens across the stage; four floating
## stones are the only way over.
func build_crossing() -> void:
	var tear := BoxMesh.new()
	tear.size = Vector3(5.8, 0.05, 1.5)
	var tm := _mesh_instance(tear, _mat(Color(0.05, 0.015, 0.1), 1.0, 0.0, Color(0.28, 0.06, 0.5), 0.9), _props)
	tm.position = Vector3(0, STAGE_TOP + 0.03, 0.1)
	var heights := [0.72, 0.94, 1.14, 0.94]
	for i in 4:
		var stone := BoxMesh.new()
		stone.size = Vector3(0.72, 0.07, 0.72)
		var mi := _mesh_instance(stone, _mat(Color(0.2, 0.55, 0.5), 0.5, 0.3, Color(0.2, 0.75, 0.65), 0.5), _props)
		mi.position = Vector3(-2.1 + 1.4 * i, heights[i], 0.1)
		_stones.append(mi)
		_pop_in(mi)


## Challenge 2 — BELL BARRAGE: a polite little cannon and three golden bells.
func build_bells() -> void:
	var rack_mat := _mat(Color(0.1, 0.11, 0.2), 0.4, 0.7)
	var post := BoxMesh.new()
	post.size = Vector3(0.09, 1.2, 0.09)
	var pm := _mesh_instance(post, rack_mat, _props)
	pm.position = Vector3(1.9, STAGE_TOP + 0.6, -1.5)
	var arm := BoxMesh.new()
	arm.size = Vector3(1.2, 0.07, 0.07)
	var am := _mesh_instance(arm, rack_mat, _props)
	am.position = Vector3(1.9, STAGE_TOP + 1.14, -1.5)
	for i in 3:
		var bell := CylinderMesh.new()
		bell.top_radius = 0.13
		bell.bottom_radius = 0.19
		bell.height = 0.24
		var mi := _mesh_instance(bell, _mat(Color(1.0, 0.82, 0.35), 0.25, 0.8, Color(0.9, 0.7, 0.25), 0.7), _props)
		mi.position = Vector3(1.9 - 0.4 + 0.4 * i, STAGE_TOP + 1.34, -1.5)
		_bells.append(mi)
		_pop_in(mi)
	var base := BoxMesh.new()
	base.size = Vector3(0.34, 0.26, 0.34)
	var bm := _mesh_instance(base, rack_mat, _props)
	bm.position = Vector3(-2.1, STAGE_TOP + 0.13, -1.2)
	var aim := Node3D.new()
	_props.add_child(aim)
	aim.position = Vector3(-2.1, STAGE_TOP + 0.45, -1.2)
	aim.look_at(Vector3(1.9, STAGE_TOP + 1.3, -1.5), Vector3.UP)
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
		_props.add_child(podium)
		var post := CylinderMesh.new()
		post.top_radius = 0.07
		post.bottom_radius = 0.09
		post.height = 1.0
		var pm := _mesh_instance(post, _mat(Color(0.1, 0.11, 0.2), 0.4, 0.7), podium)
		pm.position = Vector3(-1.8 + 1.2 * i, STAGE_TOP + 0.5, -2.1)
		var pad := CylinderMesh.new()
		pad.top_radius = 0.26
		pad.bottom_radius = 0.26
		pad.height = 0.045
		var mi := _mesh_instance(pad, _mat(hues[i], 0.3, 0.3, hues[i], 0.35), podium)
		mi.position = Vector3(0, STAGE_TOP + 1.03, 0)
		_pads.append(mi)
		_podiums.append(podium)
		_pop_in(podium)


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
	var start := Vector3(-2.6, STAGE_TOP, 0.9)
	var goal := Vector3(2.6, STAGE_TOP, 0.9)
	quad.position = start
	var hops := 4
	for i in hops:
		var stone_pos: Vector3 = _stones[i].position if i < _stones.size() else Vector3(-2.1 + 1.4 * i, 0.9, 0.1)
		var fail_here := (not success) and i == 2
		await _hop(quad, stone_pos + Vector3(0, 0.07, 0.15), fail_here)
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
		aurora_quad.position = Vector3(0.2, STAGE_TOP, 1.3)
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


var _salvo_success := true


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


func _tick_salvo(_delta: float) -> void:
	pass  # the Timer drives the salvo


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
		target = bell.global_position if is_instance_valid(bell) else Vector3(1.9, 1.9, -1.5)
	else:
		# A miss: the orb sails under the rack and dies on the floor.
		target = Vector3(1.4 + _cosmetic.randf_range(-0.5, 0.5), STAGE_TOP + 0.05, -0.4)
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
		chip.position = Vector3(0, 1.9, 2.0).lerp(pip_target, t) + Vector3.UP * (1.1 * sin(PI * t))


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
	_stamp = _label("CLEAR!" if success else "MISS...", 150, Color(1.0, 0.85, 0.3) if success else Color(0.65, 0.75, 0.95), Color(0.03, 0.05, 0.12, 0.95), 0.01)
	_stamp.position = Vector3(0, 2.85, 1.35)
	add_child(_stamp)
	_stamp.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(_stamp, "scale", Vector3.ONE, 0.35)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(_stamp, "modulate:a", 0.0, 0.5)
	tw.finished.connect(_stamp.queue_free)
	_pulse_lights(2.6 if success else 1.2)


## A star flies from the pedestal to the pips on the pillar (or a dud drops
## off the apron). Call after set_stars() so the pip already shows the result.
func fly_star(earned: bool, star_index: int) -> void:
	var pip_target := PIP_BASE + PIP_STEP * float(clampi(star_index, 0, 2))
	var chip := FlatTopGemScript.new()
	chip.build_words = false
	chip.gem_color = Color(1.0, 0.85, 0.35, 0.95) if earned else Color(0.4, 0.4, 0.48, 0.9)
	chip.scale = Vector3.ONE * 0.4
	chip.position = Vector3(0, 1.9, 2.0)
	add_child(chip)
	var tw := create_tween()
	if earned:
		tw.tween_method(_star_arc.bind(chip, pip_target), 0.0, 1.0, 0.95)
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		tw.tween_property(chip, "position", Vector3(0.3, 0.05, 3.9), 0.9)
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
			"x": _cosmetic.randf_range(-2.8, 2.8),
			"z": _cosmetic.randf_range(-0.5, 2.4),
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
		var y := 4.4 - fmod(_confetti_time * float(d["fall"]) + float(d["phase"]), 4.2)
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
	tw.tween_property(_key_light, "light_energy", 1.5, 0.5)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------- full reset

func reset_show() -> void:
	clear_gems()
	clear_props()
	clear_mod_chip()
	set_stars(0)
	reset_aurora_fx()
	if is_instance_valid(_stamp):
		_stamp.queue_free()
		_stamp = null
