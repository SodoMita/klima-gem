extends Node
## Klima Gem show controller. The dialogue file talks to the stage through
## this node (unqualified mutations like `do throw_gem_round()` resolve here
## via `using ShowDirector`). It holds no story state of its own: every
## persistent fact lives on GameState, so the balloon's rollback, saves and
## the panic screen re-dress the whole show for free. On every GameState
## restore this controller rebuilds the stage from that state — instantly,
## without replaying the choreography.

const ShowStageScript := preload("res://scenes/show_stage/show_stage.gd")

const ROLL_BASE := 0.5    # a fair coin at zero edge
const ROLL_STEP := 0.16   # each +/-1 of combined edge moves the odds this much

## How each body part leans each trial: [crossing, bells, choir].
const PART_EDGE := {
	"HANDS": [0, 1, 0],
	"EYES": [1, 0, 1],
	"LEGS": [1, 0, 0],
	"VOICE": [0, 0, 1],
	"HAIR": [-1, 0, 0],
	"BACK": [0, -1, 0],
	"HEART": [0, 0, 1],
	"SKIN": [-1, 0, -1],
}

## How each modification leans each trial.
const MOD_EDGE := {
	"GIANT": [0, 1, 0],
	"TINY": [-1, -1, 0],
	"STICKY": [-1, 1, 0],
	"BOUNCY": [1, -1, 0],
	"GLASS": [0, 0, -1],
	"MAGNET": [0, 1, 0],
	"HEAVY": [-1, 0, -1],
	"GLOWING": [1, 0, 1],
}

## Visual-only randomness for the choir melody. Not saved: a restore rebuilds
## the choir pads without replaying the tune.
var _pattern: Array = []


func _ready() -> void:
	# GameState is an earlier autoload; this is safe deferred either way.
	call_deferred("_connect_state")


func _connect_state() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("state_restored") and not gs.state_restored.is_connected(_on_state_restored):
		gs.state_restored.connect(_on_state_restored)


func _gs() -> Node:
	return get_node_or_null("/root/GameState")


func stage() -> Node3D:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("show_stage") as Node3D


func _motion() -> Node:
	var balloon := _balloon()
	if balloon == null:
		return null
	return balloon.get_node_or_null("MotionDirector")


## The dialogue balloon is parented to whatever the current scene happens to
## be, not to /root — so asking /root for "VNBalloon" finds nothing once the
## game boots (the show ran for a whole review with no portrait on the stage
## because of exactly this). Search the tree for it instead.
func _balloon() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	var direct := tree.root.get_node_or_null("VNBalloon")
	if direct != null:
		return direct
	return _find_balloon(tree.root)


func _find_balloon(node: Node) -> Node:
	for child in node.get_children():
		if str(child.name).begins_with("VNBalloon") and "sprites" in child:
			return child
		if child.get_child_count() > 0:
			var found := _find_balloon(child)
			if found != null:
				return found
	return null


# ------------------------------------------------------------- show control

## Wipe the show state and the stage furniture. Call once, on the cold open.
func begin_show() -> void:
	var gs := _gs()
	if gs != null:
		gs.show_round = 0
		gs.show_ren_key = ""
		gs.show_aurora_key = ""
		gs.show_stars = 0
		gs.show_cheers = 1
		gs.show_part = ""
		gs.show_mod = ""
		gs.show_part_face = -1
		gs.show_mod_face = -1
		gs.show_outlook = ""
		gs.show_props_round = 0
		gs.rerolls_used = 0
		gs.last_roll = 0.0
		gs.last_success = false
	var st := stage()
	if st != null:
		st.reset_show()
	var motion := _motion()
	if motion != null:
		motion.remove_quad("aurora")
	if st != null:
		st.aurora_quad = null


func next_round() -> void:
	var gs := _gs()
	if gs != null:
		gs.show_round = int(gs.show_round) + 1


func challenge_name(round_no: int) -> String:
	var idx := clampi(round_no, 1, 3) - 1
	return ShowStageScript.CHALLENGE_NAMES[idx]


## Combined word edge for a trial: negative is a disadvantage, positive an
## advantage, zero a fair draw.
func edge_for(round_no: int) -> int:
	var gs := _gs()
	if gs == null or str(gs.show_part) == "" or str(gs.show_mod) == "":
		return 0
	var idx := clampi(round_no, 1, 3) - 1
	var part_edge: int = (PART_EDGE.get(str(gs.show_part), [0, 0, 0]) as Array)[idx]
	var mod_edge: int = (MOD_EDGE.get(str(gs.show_mod), [0, 0, 0]) as Array)[idx]
	return part_edge + mod_edge


func outlook_for(round_no: int) -> String:
	var edge := edge_for(round_no)
	if edge > 0:
		return "advantage"
	if edge < 0:
		return "disadvantage"
	return "even"


## One word for the dialogue: what the odds are doing to the guest.
func outlook_word(round_no: int) -> String:
	match outlook_for(round_no):
		"advantage":
			return "an ADVANTAGE"
		"disadvantage":
			return "a DISADVANTAGE"
	return "a fair draw"


func success_chance(round_no: int) -> float:
	return clampf(ROLL_BASE + ROLL_STEP * float(edge_for(round_no)), 0.15, 0.85)


# ------------------------------------------------------------------ actors

## The presenter takes the stage. Ren is a voice on the microphone and is
## never rendered: one standing portrait (the guest) is all this stage needs,
## so this cue only turns the light up on his mark.
func enter_ren() -> void:
	var gs := _gs()
	if gs != null:
		gs.show_ren_key = "ren"
	var st := stage()
	if st != null and st.has_method("host_entrance"):
		st.host_entrance()


## The guest takes hers, wide-eyed.
func aurora_enters() -> void:
	set_aurora_expression("serious", true)


## Swap the guest's portrait; applied modifications stay applied.
func set_aurora_expression(emotion: String, fresh := false) -> void:
	var key := emotion if emotion.begins_with("aurora") else "aurora_" + emotion
	var gs := _gs()
	if gs != null:
		gs.show_aurora_key = key
	_spawn_actor("aurora", key, ShowStageScript.AURORA_MARK, ShowStageScript.AURORA_BASE_HEIGHT)
	var st := stage()
	if not fresh and st != null and gs != null and str(gs.show_part) != "":
		st.apply_aurora_fx(str(gs.show_part), str(gs.show_mod))


func _spawn_actor(alias: String, tex_key: String, at: Vector3, height: float) -> void:
	var motion := _motion()
	var balloon := _balloon()
	var st := stage()
	if motion == null or balloon == null or st == null:
		return
	var tex: Texture2D = balloon.sprites.get(tex_key)
	if tex == null:
		push_warning("ShowDirector: no portrait key '%s'" % tex_key)
		return
	var quad: Node3D = motion.spawn_quad(alias, tex, st.characters_parent(), height, true, at)
	st.set_actor(alias, quad)


# ------------------------------------------------------------ gem ceremony

## Pick both words with the story RNG, then stage the whole throw.
func throw_gem_round() -> void:
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	gs.show_part_face = gs.rng.randi_range(0, 7)
	gs.show_mod_face = gs.rng.randi_range(0, 7)
	gs.show_part = ShowStageScript.PARTS[gs.show_part_face]
	gs.show_mod = ShowStageScript.MODS[gs.show_mod_face]
	await st.throw_gems(str(gs.show_part), int(gs.show_part_face), str(gs.show_mod), int(gs.show_mod_face))


## Spend a crowd cheer: the modification gem goes back in the air.
func swap_mod_gem() -> void:
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	gs.show_cheers = int(gs.show_cheers) - 1
	gs.rerolls_used = int(gs.rerolls_used) + 1
	gs.show_mod_face = gs.rng.randi_range(0, 7)
	gs.show_mod = ShowStageScript.MODS[gs.show_mod_face]
	await st.rethrow_gem(1, int(gs.show_mod_face), str(gs.show_mod))
	await apply_mods()


## Stamp the pairing onto the guest: the floating chip, the portrait effects,
## and the freshly computed outlook for the trial about to run.
func apply_mods() -> void:
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	gs.show_outlook = outlook_for(int(gs.show_round))
	st.apply_mod_chip(str(gs.show_part), str(gs.show_mod), st.chip_anchor())
	st.apply_aurora_fx(str(gs.show_part), str(gs.show_mod))
	await st.get_tree().create_timer(0.9).timeout


# ----------------------------------------------------------------- trials

## Dress the stage for trial [param round_no] and remember it for restores.
func build_challenge(round_no: int) -> void:
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	st.clear_props()
	match clampi(round_no, 1, 3):
		1: st.build_crossing()
		2: st.build_bells()
		3: st.build_choir()
	gs.show_props_round = clampi(round_no, 1, 3)
	_pattern = []
	var rounds := 5
	for i in rounds:
		_pattern.append(gs.rng.randi_range(0, 3))
	await st.get_tree().create_timer(0.7).timeout


## Decide with the seeded roll, then perform the result, award the star, and
## tear the props back down. The stage is clean when this returns.
func run_challenge() -> void:
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	var chance := success_chance(int(gs.show_round))
	gs.last_roll = gs.rng.randf()
	gs.last_success = gs.last_roll < chance
	await st.play_challenge(int(gs.show_round), bool(gs.last_success), _pattern)
	if gs.last_success:
		gs.show_stars = int(gs.show_stars) + 1
	st.set_stars(int(gs.show_stars))
	var star_index := int(gs.show_stars) - 1 if gs.last_success else int(gs.show_stars)
	await st.fly_star(bool(gs.last_success), star_index)
	st.clear_props()
	gs.show_props_round = 0


## Golden rain for a perfect show.
func finale_confetti() -> void:
	var st := stage()
	if st != null:
		st.confetti_burst()


# ---------------------------------------------------------------- restores

func _on_state_restored() -> void:
	sync_from_state()


## Rebuild the visible show from GameState — used after rollback, save-load
## and the panic screen. Nothing animates; everything is simply true again.
func sync_from_state() -> void:
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	if str(gs.show_aurora_key) != "":
		_spawn_actor("aurora", str(gs.show_aurora_key), ShowStageScript.AURORA_MARK, ShowStageScript.AURORA_BASE_HEIGHT)
	else:
		var motion := _motion()
		if motion != null:
			motion.remove_quad("aurora")
		st.aurora_quad = null
	if str(gs.show_part) != "" and int(gs.show_part_face) >= 0:
		st.place_gems_settled(str(gs.show_part), int(gs.show_part_face), str(gs.show_mod), int(gs.show_mod_face))
		st.apply_mod_chip(str(gs.show_part), str(gs.show_mod), st.chip_anchor())
		st.apply_aurora_fx(str(gs.show_part), str(gs.show_mod))
	else:
		st.clear_gems()
		st.clear_mod_chip()
		st.reset_aurora_fx()
	st.clear_props()
	match clampi(int(gs.show_props_round), 0, 3):
		1: st.build_crossing()
		2: st.build_bells()
		3: st.build_choir()
	st.set_stars(int(gs.show_stars))
