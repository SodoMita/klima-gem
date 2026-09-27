class_name ShowStage extends Node3D
## The KLIMA GEM television studio. The set is AUTHORED in show_stage.tscn
## (platform, glass throw box, star cloth, beams, lights, audience, star
## pips, colliders); this script only animates it. Geometry only — no painted backdrop, no imported image. A round platform under
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
const ThrowCueScript := preload("res://scenes/show_stage/throw_cue.gd")

## Eight side words, then the word on the flat table (index 8 = TOP_FACE).
const PARTS: PackedStringArray = ["HANDS", "EYES", "LEGS", "VOICE", "HAIR", "BACK", "HEART", "SKIN", "MILK"]
const MODS: PackedStringArray = ["GIANT", "TINY", "STICKY", "BOUNCY", "GLASS", "MAGNET", "HEAVY", "GLOWING", "MEGA"]
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
	"MEGA": Color(1.0, 0.45, 0.4),
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
const AURORA_MARK := Vector3(2.25, STAGE_TOP, 1.5)
const AURORA_BASE_HEIGHT := 1.68
const REN_MARK := Vector3(-1.8, STAGE_TOP, 1.9)

const PEDESTAL_Z := 3.3
const PEDESTAL_HEAD := 1.55
## Gem stations: the shapeshift (modification) gem hangs on the LEFT, the
## body-part gem on the RIGHT. Their settled words fly onward to the
## presentation slots, same sides, higher up.
const GEM_SLOT_MOD := Vector3(-0.55, 1.42, 3.7)
const GEM_SLOT_PART := Vector3(0.55, 1.42, 3.7)
const PRESENT_POS_MOD := Vector3(-2.2, 1.95, 4.2)
const PRESENT_POS_PART := Vector3(2.2, 1.95, 4.2)

## The star board is three prize gems standing on the altar, so the reward
## for a cleared trial lands somewhere the audience is already looking.
const PIP_BASE := Vector3(-0.6, 2.78, -3.55)
const PIP_STEP := Vector3(0.6, 0.0, 0.0)

## Where each thrown gem is aimed on the stage floor. Different landing spots
## keep the two bodies from shoving each other around.
const LAND_PART := Vector3(0.55, STAGE_TOP, 1.2)
const LAND_MOD := Vector3(-0.55, STAGE_TOP, 1.2)

## The closed throw box: a glass case on the stage floor. Walls and lid are
## colliders, so no throw can ever leave the world. Inner size, floor centre.
## The glass box hangs in the air: its glass floor is BOX_LIFT above the
## platform, so the camera can slide underneath and read the face a stone
## rests on straight through the glass.
const BOX_LIFT := 1.1
const BOX_CENTER := Vector3(0.0, STAGE_TOP + BOX_LIFT, 1.2)
const UNDERVIEW_DIST := 0.85
const UNDERVIEW_HOLD := 1.4
const BOX_SIZE := Vector3(3.0, 1.4, 1.8)
## Longest the show waits for a stone to stop on its own.
const REST_TIMEOUT := 14.0
## Gem geometry scale on stage (a 1 m stone swallowed the frame).
const GEM_SCALE := 0.62
## How long the show waits for the player's hand before throwing for them.
const THROW_CUE_TIMEOUT := 8.0

## The player throws: aim with the cursor / finger / stick, hold for power.
## Off under a headless display (tests) — then the impulse is drawn from the
## story RNG alone. Tests may force it either way.
var interactive_throws := true

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
var _cam_tween: Tween = null
var _throw_cue: ThrowCue = null
## The last cue the player gave (aim, power, manual) — for tests and HUD.
var last_throw_cue: Dictionary = {}


func _ready() -> void:
	# The set itself is authored in show_stage.tscn; the script only finds
	# the pieces it animates.
	add_to_group("show_stage")
	_cosmetic.seed = 20260927
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera != null:
		_camera.make_current()
	_key_light = get_node_or_null("KeyLight") as OmniLight3D
	interactive_throws = DisplayServer.get_name() != "headless"
	_throw_cue = ThrowCueScript.new()
	_throw_cue.name = "ThrowCue"
	add_child(_throw_cue)
	_set_root = get_node_or_null("Set") as Node3D
	_props = get_node_or_null("Props") as Node3D
	if _props == null:
		_props = Node3D.new()
		_props.name = "Props"
		add_child(_props)
	var pips := get_node_or_null("StarPips")
	if pips != null:
		for pip in pips.get_children():
			if pip is FlatTopGem and is_instance_valid((pip as FlatTopGem).body):
				_pips.append((pip as FlatTopGem).body)

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
	gem.girdle_radius *= GEM_SCALE
	gem.table_radius *= GEM_SCALE
	gem.crown_height *= GEM_SCALE
	gem.pavilion_height *= GEM_SCALE
	gem.set_words(word_list)
	gem.position = slot + Vector3(0, 3.2, 0)  # starts above the truss, out of sight
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
func throw_gems(rng: RandomNumberGenerator) -> Array:
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
	var part_face := await _throw_one_physics(gem_part, LAND_PART, true, rng, epoch)
	if epoch != _gem_epoch or part_face < 0:
		return []
	await get_tree().create_timer(0.25).timeout
	if epoch != _gem_epoch:
		return []
	var mod_face := await _throw_one_physics(gem_mod, LAND_MOD, false, rng, epoch)
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
func _throw_one_physics(gem: FlatTopGem, land: Vector3, is_part: bool, rng: RandomNumberGenerator, epoch: int) -> int:
	_pulse_lights(2.2)
	# Released inside the closed box, up under the lid on Aurora's side, with
	# a random orientation, a random shove and a random spin. Nothing about
	# the result is chosen: the stone decides by the face it comes to rest on.
	var half := BOX_SIZE * 0.5
	# The player's hand: where the cursor points is where the stone is
	# aimed, and how long the button is held is how hard it flies. The
	# release instant and the cursor position are mixed into the impulse
	# generator, so no seed can pre-decide a throw the player makes.
	var cue := await _await_throw_cue(is_part, epoch)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return -1
	var r := RandomNumberGenerator.new()
	r.seed = int(rng.randi()) ^ int(cue.get("entropy", 0))
	var power: float = float(cue.get("power", 1.0))
	var from := BOX_CENTER + Vector3(
		r.randf_range(0.35, 0.8) * half.x, BOX_SIZE.y - 0.3, r.randf_range(-0.5, 0.5) * half.z)
	var target: Vector3
	if cue.has("aim"):
		var aim: Vector3 = cue["aim"]
		target = Vector3(
			clampf(aim.x, BOX_CENTER.x - half.x + 0.25, BOX_CENTER.x + half.x - 0.25),
			BOX_CENTER.y,
			clampf(aim.z, BOX_CENTER.z - half.z + 0.2, BOX_CENTER.z + half.z - 0.2))
	else:
		target = Vector3(
			r.randf_range(-0.8, 0.3) * half.x, BOX_CENTER.y, BOX_CENTER.z + r.randf_range(-0.6, 0.6) * half.z)
	# Harder throw: shorter flight (a flatter, faster arc) and more spin.
	var flight := r.randf_range(0.30, 0.42) / power
	var spin_max := 18.0 * power
	var spin := Vector3(r.randf_range(-spin_max, spin_max), r.randf_range(-spin_max, spin_max), r.randf_range(-spin_max, spin_max))
	var q := Quaternion(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1))
	_fast_settle(gem)
	if q.length() < 0.01:
		q = Quaternion.IDENTITY
	gem.throw_with_velocity(from, _arc_velocity(from, target, flight), spin, Basis(q.normalized()))
	# Wait on the STAGE rather than on the body: on rewind the body is
	# freed, and a suspended method on it would resume into a dead instance.
	await _wait_throw_rest(gem, epoch)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return -1
	var face := gem.resting_face()
	# The stone stays exactly where it stopped; the camera goes to it.
	gem.linear_velocity = Vector3.ZERO
	gem.angular_velocity = Vector3.ZERO
	gem.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	gem.freeze = true
	gem.settled = true
	_pulse_lights(1.9)
	await _underview(gem, face, epoch)
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
	var from := aurora_hand() + (Vector3(0.16, 0.04, -0.06) if is_part else Vector3(-0.14, 0.08, -0.02))
	_pulse_lights(2.2)
	# Gravity does the rest: this is a real impulse, not a tween.
	from = BOX_CENTER + Vector3(0.6 if is_part else -0.6, BOX_SIZE.y - 0.3, 0.0)
	gem.throw_with_velocity(from, _arc_velocity(from, land, 0.6), Vector3(7.0, 9.5, 4.5) * (1.0 if is_part else -0.8))
	# Wait on the STAGE rather than on the body: on rewind the body is
	# freed, and a suspended method on it would resume into a dead instance.
	await _wait_throw_rest(gem, epoch)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return
	_pulse_lights(1.9)
	await gem.lift_to(GEM_SLOT_PART if is_part else GEM_SLOT_MOD, face, _viewer_pos(), 1.05)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return
	await gem.flash_face(face)
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return
	await gem.flash_reveal()
	if epoch != _gem_epoch or not is_instance_valid(gem):
		return
	await present_word(gem, face, is_part)


## Open the player's throw cue over the case (or skip it when throws are
## not interactive). Returns the cue dictionary, {} when nothing was asked.
func _await_throw_cue(is_part: bool, epoch: int) -> Dictionary:
	if not interactive_throws or _throw_cue == null or not is_inside_tree():
		return {}
	_throw_cue.camera = _camera
	_throw_cue.floor_center = BOX_CENTER
	_throw_cue.half_extent = Vector2(BOX_SIZE.x * 0.5 - 0.25, BOX_SIZE.z * 0.5 - 0.2)
	var text := "AIM + HOLD TO THROW THE %s GEM" % ("BODY" if is_part else "SHIFT")
	var cue: Dictionary = await _throw_cue.wait(text, THROW_CUE_TIMEOUT)
	if epoch != _gem_epoch:
		return {}
	last_throw_cue = cue
	return cue


## Fly fast, stop fast: heavy damping and a dull bounce so a stone that has
## spent its energy quits rolling instead of creeping for seconds.
func _fast_settle(gem: FlatTopGem) -> void:
	gem.linear_damp = 0.9
	gem.angular_damp = 2.4
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.15
	pm.friction = 0.95
	gem.physics_material_override = pm


## The reveal: the camera slides under the floating glass floor and looks up,
## head-on, at the face the stone rests on — upright, never mirrored — then
## returns to the house shot.
func _underview(gem: FlatTopGem, face: int, epoch: int) -> void:
	var label := gem.label_for(face)
	if _camera == null or label == null:
		return
	var lb := label.global_basis.orthonormalized()
	var target := label.global_position
	var eye := target + lb.z * UNDERVIEW_DIST
	eye.y = minf(eye.y, BOX_CENTER.y - 0.25)
	eye.y = maxf(eye.y, STAGE_TOP + 0.12)
	var shot := Transform3D(Basis.looking_at(target - eye, lb.y), eye)
	var home := _camera.global_transform
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = create_tween()
	_cam_tween.tween_property(_camera, "global_transform", shot, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_interval(UNDERVIEW_HOLD)
	_cam_tween.tween_property(_camera, "global_transform", home, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _cam_tween.finished
	if epoch != _gem_epoch and _camera != null:
		_camera.global_transform = home


func _wait_throw_rest(gem: FlatTopGem, epoch: int) -> void:
	# Patient: the stone stops on its own. Calm means slow AND staying slow
	# for half a second (a gem balanced on an edge is slow for an instant).
	var elapsed := 0.0
	var calm := 0.0
	while elapsed < REST_TIMEOUT and epoch == _gem_epoch and is_instance_valid(gem):
		await get_tree().physics_frame
		if epoch != _gem_epoch or not is_instance_valid(gem):
			return
		var dt := get_physics_process_delta_time()
		elapsed += dt
		if gem.freeze:
			return
		if gem.sleeping:
			return
		if elapsed > 0.3 and gem.linear_velocity.length() < 0.05 and gem.angular_velocity.length() < 0.15:
			calm += dt
			if calm >= 0.3:
				return
		else:
			calm = 0.0


## Instant version for rollback / saves: gems appear already settled.
func place_gems_settled(part_word: String, part_face: int, mod_word: String, mod_face: int) -> void:
	clear_gems()
	var az := _viewer_pos()
	var gem_part := _make_gem(GEM_SLOT_PART, Color(0.5, 0.85, 1.0, 0.62), PARTS)
	var gem_mod := _make_gem(GEM_SLOT_MOD, Color(1.0, 0.55, 0.85, 0.62), MODS)
	gem_part.snap_settled(GEM_SLOT_PART, part_face, az)
	gem_mod.snap_settled(GEM_SLOT_MOD, mod_face, az)
	place_word_plaque(PARTS[part_face], true)
	place_word_plaque(MODS[mod_face], false)


## The glowing copy of a settled word, presented high beside the stage.
## [param is_part] true = body part (right slot), false = shapeshift (left).
func present_word(gem: FlatTopGem, face: int, is_part: bool) -> void:
	var plaque := _make_word_plaque(gem.word_at(face), is_part)
	add_child(plaque)
	var src := gem.label_for(face)
	var from: Vector3 = src.global_position if src != null else gem.global_position
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


func _viewer_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		cam = _camera
	if cam == null or not cam.is_inside_tree():
		return CAM_POS
	return cam.global_position


func gem_center() -> Vector3:
	return (GEM_SLOT_PART + GEM_SLOT_MOD) * 0.5


## Quick physics-random re-throw of one gem (the producer's mercy): it goes
## back in the air under a fresh seeded impulse and the new word is whatever
## face lands front-most. Returns the face the stones chose.
func rethrow_gem(which: int, rng: RandomNumberGenerator) -> int:
	if which < 0 or which >= _gems.size() or not is_instance_valid(_gems[which]):
		return -1
	var gem := _gems[which]
	var is_part := which == 0
	return await _throw_one_physics(gem, LAND_PART if is_part else LAND_MOD, is_part, rng, _gem_epoch)


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
		"MILK":
			# The table word: a little milk bottle — body, shoulder, cap.
			var bottle := _mesh_instance(CylinderMesh.new(), mat, parent)
			(bottle.mesh as CylinderMesh).top_radius = 0.05
			(bottle.mesh as CylinderMesh).bottom_radius = 0.055
			(bottle.mesh as CylinderMesh).height = 0.13
			var neck := _mesh_instance(CylinderMesh.new(), mat, parent)
			(neck.mesh as CylinderMesh).top_radius = 0.022
			(neck.mesh as CylinderMesh).bottom_radius = 0.05
			(neck.mesh as CylinderMesh).height = 0.05
			neck.position = Vector3(0, 0.09, 0)
			var cap := _mesh_instance(CylinderMesh.new(), mat, parent)
			(cap.mesh as CylinderMesh).top_radius = 0.026
			(cap.mesh as CylinderMesh).bottom_radius = 0.026
			(cap.mesh as CylinderMesh).height = 0.02
			cap.position = Vector3(0, 0.125, 0)


## The applied modification, floating beside the guest: a bright ring, the
## body-part glyph, and the pairing written out underneath.
func apply_mod_chip(part: String, mod: String, at: Vector3, kept: Dictionary = {}) -> void:
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
	# Every modification she carries, newest first. The label always faces
	# the house (a spinning label read mirrored half the time).
	var lines: PackedStringArray = ["%s  x  %s" % [part, mod]]
	for p in kept:
		if str(p) != part:
			lines.append("%s  x  %s" % [str(p), str(kept[p])])
	_chip_label = _label("\n".join(lines), 92, Color(0.95, 0.98, 1.0), Color(0.03, 0.05, 0.12, 0.95), 0.0015)
	_chip_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_chip_label.position = Vector3(0, -0.26, 0)
	_chip.add_child(_chip_label)
	_chip_home = at
	_chip.position = at
	_chip.set_meta("label", _chip_label)
	_chip.scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(_chip, "scale", Vector3.ONE, 0.5)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_lights(2.0)


func clear_mod_chip() -> void:
	if is_instance_valid(_chip):
		if _chip.get_parent() != null:
			_chip.get_parent().remove_child(_chip)
		_chip.queue_free()
	_chip = null
	_chip_label = null


## Whole-body readings of the roll, applied to the guest's standing portrait.
func apply_aurora_fx(part: String, mod: String) -> void:
	apply_body_mods({part: mod})


## Every modification Aurora has picked up this show, applied together: a
## body keeps what the gems gave it from trial to trial.
func apply_body_mods(mods: Dictionary) -> void:
	if not is_instance_valid(aurora_quad):
		return
	var target := AURORA_BASE_HEIGHT
	var tint := Color(1, 1, 1, 1)
	var bouncy := false
	for part in mods:
		var mod := str(mods[part])
		var giant_body: bool = str(part) in ["LEGS", "BACK", "HEART", "SKIN", "MILK"]
		if giant_body and (mod == "GIANT" or mod == "MEGA"):
			target *= 1.22 if mod == "GIANT" else 1.12
		elif giant_body and mod == "TINY":
			target *= 0.78
		match mod:
			"GLASS": tint *= Color(1.1, 1.3, 1.6, 0.55)
			"GLOWING": tint *= Color(1.25, 1.45, 1.75, 1.0)
			"HEAVY": tint *= Color(0.6, 0.58, 0.7, 1.0)
			"MAGNET": tint *= Color(1.12, 0.85, 1.3, 1.0)
			"STICKY": tint *= Color(0.82, 1.15, 0.88, 1.0)
			"TINY": tint *= Color(0.85, 0.95, 1.1, 1.0)
			"MEGA": tint *= Color(1.3, 0.95, 0.9, 1.0)
		if mod == "BOUNCY":
			bouncy = true
	target = clampf(target, 1.1, 2.4)
	if "world_height" in aurora_quad:
		aurora_quad.set("world_height", target)
	if "modulate" in aurora_quad:
		aurora_quad.set("modulate", tint)
	if _aurora_bob != null and _aurora_bob.is_valid():
		_aurora_bob.kill()
		_aurora_bob = null
	if bouncy and is_instance_valid(aurora_quad):
		var home_y: float = AURORA_MARK.y
		(aurora_quad as Node3D).position.y = home_y
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
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_stones.clear()
	_bells.clear()
	_pads.clear()
	_podiums.clear()
	_fx_orbs.clear()
	# Props come and go; the body modifications Aurora carries do not.


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
const CHOIR_Z := -2.35


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
	clear_gems()
	clear_props()
	clear_mod_chip()
	set_stars(0)
	reset_aurora_fx()
	if is_instance_valid(_stamp):
		_stamp.queue_free()
		_stamp = null
