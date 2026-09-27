extends Node
## Klima Gem show controller. The dialogue file talks to the stage through
## this node (unqualified mutations like `do throw_gem_round()` resolve here
## via `using ShowDirector`). It holds no story state of its own: every
## persistent fact lives on GameState, so the balloon's rollback, saves and
## the panic screen re-dress the whole show for free. On every GameState
## restore this controller rebuilds the stage from that state — instantly,
## without replaying the choreography.
##
## You play AS Aurora. Ren hosts (voice only, never rendered); Aurora is the
## only portrait on the stage and every choice is her action. Trial success
## is deterministic: her action stats plus the gems' situational edge, no
## dice. The gems themselves are physics-random: the stones leave her hand
## under seeded impulses and whatever face lands front-most is the word.

const ShowStageScript := preload("res://scenes/show_stage/show_stage.gd")

const ROLL_BASE := 0.5    # a fair coin at zero edge (odds display only)
const ROLL_STEP := 0.16   # each +/-1 of combined edge moves the odds this much

## How each body part leans each trial: [crossing, bells, choir].
## Every word is mixed: each helps (+1) at least one trial and hinders (-1)
## at least one other. Nothing is generally good or bad — the same HANDS
## that fumble the floating stones catch the bells, and HEAVY that sinks the
## crossing steadies the aim. Columns sum to zero: every trial is fair.
const PART_EDGE := {
	"HANDS": [-1, 1, 0],
	"EYES": [1, -1, 1],
	"LEGS": [1, 0, -1],
	"VOICE": [-1, 0, 1],
	"HAIR": [0, -1, 1],
	"BACK": [1, -1, 0],
	"HEART": [0, 1, -1],
	"SKIN": [-1, 1, -1],
	# The table word, rarer than any side: a stone resting on its top.
	"MILK": [1, -1, 1],
}

## How each modification leans each trial. Same rule: every shapeshift is an
## upside somewhere and a downside somewhere else.
const MOD_EDGE := {
	"GIANT": [-1, 1, 0],
	"TINY": [1, -1, 0],
	"STICKY": [-1, 1, 0],
	"BOUNCY": [1, -1, 0],
	"GLASS": [0, -1, 1],
	"MAGNET": [0, 1, -1],
	"HEAVY": [-1, 1, -1],
	"GLOWING": [1, -1, 1],
	"MEGA": [1, 1, -1],
}

## Visual-only randomness for the choir melody. Not saved: a restore rebuilds
## the choir pads without replaying the tune.
var _pattern: Array = []

# Async scene animations can finish after rollback/load has restored GameState.
# Never let those old continuations commit into the newly restored timeline.
var _state_epoch: int = 0
## Tests pin the story seed; players never do.
var pin_seed := false


func _is_current(epoch: int, st: Node) -> bool:
	return epoch == _state_epoch and is_instance_valid(st) and st.is_inside_tree() and stage() == st


func _ready() -> void:
	# GameState is an earlier autoload; this is safe deferred either way.
	call_deferred("_connect_state")


func _connect_state() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("state_restored") and not gs.state_restored.is_connected(_on_state_restored):
		gs.state_restored.connect(_on_state_restored)


func _gs() -> Node:
	return get_node_or_null("/root/GameState")


func stage() -> ShowStage:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("show_stage") as ShowStage


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

# ------------------------------------------------------------------- audio
## Every beat of the show gets a sound out of the C dubstep generator, and the
## floor music follows the tension. Silent while the balloon replays history.

func _audio() -> Node:
	return get_node_or_null("/root/AudioDirector")


## One event sound. energy 0..1 (how hard the moment lands).
func snd(key: String, energy: float = 0.8) -> void:
	if replaying():
		return
	var a := _audio()
	if a != null and a.has_method("play_event"):
		a.play_event(key, energy)


## A cue for the live score: riser | drop | impact | fill | stab | break.
func music_cue(name: String) -> void:
	if replaying():
		return
	var a := _audio()
	if a != null and a.has_method("music_event"):
		a.music_event(name)


## How hard the floor should push right now.
func music_heat(level: float, fade: float = 0.6) -> void:
	if replaying():
		return
	var a := _audio()
	if a != null and a.has_method("set_music_intensity"):
		a.set_music_intensity(level, fade)


## Stage music: active dubstep, not the calm festival score.
func start_stage_music(key: String = "stage") -> void:
	if replaying():
		return
	var a := _audio()
	if a != null and a.has_method("play_dubstep"):
		a.play_dubstep(key)


func begin_show() -> void:
	_state_epoch += 1
	var gs := _gs()
	if gs != null:
		# Unless a test pinned it, every new show throws under a new seed.
		if not pin_seed and gs.has_method("fresh_seed"):
			gs.fresh_seed()
		gs.show_body_mods = {}
		gs.show_mod_counts = {}
		gs.show_last_stamp = ""
		gs.show_round = 0
		gs.show_ren_key = ""
		gs.show_aurora_key = ""
		gs.show_stars = 0
		gs.show_scored_round = 0
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


## Combined word edge for a trial: what the gems say about this trial.
## Situational only — every word helps somewhere and hinders somewhere.
func edge_for(round_no: int) -> int:
	var gs := _gs()
	if gs == null or str(gs.show_part) == "" or str(gs.show_mod) == "":
		return 0
	var idx := clampi(round_no, 1, 3) - 1
	# Every modification she still carries counts, not only tonight's pair:
	# a body keeps what the gems gave it.
	var total := 0
	var mods := body_mods()
	var stacks := mod_stacks()
	for part in mods:
		total += int((PART_EDGE.get(str(part), [0, 0, 0]) as Array)[idx])
		var mod := str(mods[part])
		var e := int((MOD_EDGE.get(mod, [0, 0, 0]) as Array)[idx])
		var n := int(stacks.get(mod, 1))
		# The same shift landing again compounds: a second copy doubles its
		# effect; from the third copy on the body has adapted to it and the
		# shift is always an advantage, whatever the trial.
		if n >= 3:
			e = maxi(absi(e), 1)
		elif n == 2:
			e *= 2
		total += e
	return total


## How many body parts carry each shift right now: {"GIANT": 2, ...}.
func mod_stacks() -> Dictionary:
	var stacks := {}
	var mods := body_mods()
	for part in mods:
		var mod := str(mods[part])
		stacks[mod] = int(stacks.get(mod, 0)) + 1
	# Applications outrank parts: GIANT stamped on HANDS twice is a x2 even
	# though only one part carries it now.
	var gs := _gs()
	if gs != null and "show_mod_counts" in gs:
		var counts: Dictionary = gs.show_mod_counts
		for mod in counts:
			stacks[str(mod)] = maxi(int(stacks.get(str(mod), 0)), int(counts[mod]))
	return stacks


## Human-readable stack note for the balloon: "" until a shift repeats.
func stack_word(mod: String) -> String:
	var n := int(mod_stacks().get(mod, 0))
	if n >= 3:
		return "x%d — mastered" % n
	if n == 2:
		return "x2 — doubled"
	return ""


## Kept modifications plus the current pair (one mod per body part).
func body_mods() -> Dictionary:
	var gs := _gs()
	if gs == null:
		return {}
	var mods: Dictionary = (gs.show_body_mods as Dictionary).duplicate() if "show_body_mods" in gs else {}
	if str(gs.show_part) != "" and str(gs.show_mod) != "":
		mods[str(gs.show_part)] = str(gs.show_mod)
	return mods


## What Aurora's own actions contribute to a trial: the stats she built by
## playing. The Crossing tests composure (bond with Ren) and confidence
## (trust); Bell Barrage tests confidence and punch (power); the Echo Choir
## tests bond and memory (insight). Words set the situation, actions decide.
func action_edge(round_no: int) -> int:
	var gs := _gs()
	if gs == null:
		return 0
	match clampi(round_no, 1, 3):
		1:
			return int(gs.get_bond("ren")) + int(gs.trust)
		2:
			return int(gs.trust) + int(gs.power)
		3:
			return int(gs.get_bond("ren")) + int(gs.insight)
	return 0


## The full account for a trial: gems plus actions. This is what the trial
## is decided on — no dice anywhere.
func total_for(round_no: int) -> int:
	return edge_for(round_no) + action_edge(round_no)


## What the board tells the audience before a trial. Uses the SAME threshold
## the trial is decided on (success = total >= trial number): on pace to
## clear reads advantage, one short reads even, worse reads disadvantage.
## A bare sign check would call trial 3 with total +2 an "advantage" while
## the trial itself fails it — the board must never disagree with the judge.
func outlook_for(round_no: int) -> String:
	var need := clampi(round_no, 1, 3)
	var total := total_for(round_no)
	if total >= need:
		return "advantage"
	if total >= need - 1:
		return "even"
	return "disadvantage"


## One word for the dialogue: what the odds are doing to the guest.
func outlook_word(round_no: int) -> String:
	match outlook_for(round_no):
		"advantage":
			return "an ADVANTAGE"
		"disadvantage":
			return "a DISADVANTAGE"
	return "a fair draw"


## Display odds for tests/debug. The show itself does not roll: trials are
## decided deterministically by total_for() against the trial number.
func success_chance(round_no: int) -> float:
	return clampf(ROLL_BASE + ROLL_STEP * float(total_for(round_no)), 0.15, 0.85)


# ------------------------------------------------------------------ actors

## The presenter takes the stage. Ren is a voice on the microphone and is
## never rendered: one standing portrait (the guest) is all this stage needs,
## so this cue only turns the light up on his mark.
func enter_ren() -> void:
	start_stage_music("stage")
	music_heat(0.55, 0.8)
	snd("airhorn", 0.7)
	music_cue("fill")
	var gs := _gs()
	if gs != null:
		gs.show_ren_key = "ren"
	var st := stage()
	if st != null and st.has_method("host_entrance") and not replaying():
		st.host_entrance()


## The guest takes hers, wide-eyed.
func aurora_enters() -> void:
	snd("gem_spawn", 0.7)
	set_aurora_expression("serious", true)


## Swap the guest's portrait; applied modifications stay applied.
func set_aurora_expression(emotion: String, fresh := false) -> void:
	var key := emotion if emotion.begins_with("aurora") else "aurora_" + emotion
	var gs := _gs()
	if gs != null:
		gs.show_aurora_key = key
		if int(gs.show_round) >= 3:
			if emotion in ["gorgeous", "happy"]:
				on_show_victory()
			elif emotion == "sad":
				on_show_defeat()
	if replaying():
		return
	_spawn_actor("aurora", key, ShowStageScript.AURORA_MARK, ShowStageScript.AURORA_BASE_HEIGHT)
	var st := stage()
	if not fresh and st != null and gs != null and not body_mods().is_empty():
		st.apply_body_mods(body_mods())


func _spawn_actor(alias: String, tex_key: String, at: Vector3, height: float) -> void:
	var motion := _motion()
	var balloon := _balloon()
	var st := stage()
	if motion == null or balloon == null or st == null:
		return
	if alias == "aurora" and AURORA_PARTS_RIG.parts_available() and st.has_method("free_aurora_actor"):
		# Nine layer quads, so every kept shift sits on its own body part.
		# Same spawn discipline as motion.spawn_quad: replace atomically.
		st.free_aurora_actor()
		var rig: AuroraPartsRig = AURORA_PARTS_RIG.new()
		rig.name = "Sprite3D_aurora"
		st.characters_parent().add_child(rig)
		rig.setup()
		rig.world_height = height
		rig.position = at
		rig.set_expression(tex_key)
		st.set_actor(alias, rig)
		var worn := body_mods()
		if not worn.is_empty():
			var gsv := _gs()
			rig.set_part_mods(worn, (gsv.show_mod_counts as Dictionary) if gsv != null and "show_mod_counts" in gsv else {})
		return
	var tex: Texture2D = balloon.sprites.get(tex_key)
	if tex == null:
		push_warning("ShowDirector: no portrait key '%s'" % tex_key)
		return
	# Keep Aurora's expression, face and original silhouette while wearing
	# the body-shift sprite. Only the existing portrait quad changes texture.
	var gs := _gs()
	if alias == "aurora" and gs != null:
		tex = _modded_aurora_texture(tex_key, tex, gs.show_body_mods)
	var quad: Node3D = motion.spawn_quad(alias, tex, st.characters_parent(), height, true, at)
	st.set_actor(alias, quad)


## Full-body transformation sprites are generated from Aurora's real VN
## expressions by tools/generate_aurora_mod_sprites.py. No second character,
## icon card or opaque JPEG is ever drawn in the shot.
const AURORA_MOD_SPRITES := "res://assets/characters/mods/"

## Aurora's body, layered by gem part: when assets/characters/parts exists the
## standing guest is an AuroraPartsRig whose NINE layers answer the BODY PART
## gem directly (GIANT HANDS grows only her hands). The full-body plates above
## remain the fallback for a build without the part art.
const AURORA_PARTS_RIG := preload("res://scenes/show_stage/aurora_parts.gd")


func _modded_aurora_texture(key: String, original: Texture2D, mods: Dictionary) -> Texture2D:
	if original == null or not key.begins_with("aurora_") or mods.is_empty():
		return original
	var mod := ""
	var gs := _gs()
	if gs != null and mods.has(str(gs.show_part)):
		mod = str(mods[str(gs.show_part)])
	else:
		# The current roll has not been applied yet: keep the last shift
		# Aurora earned, rather than showing a future word before its cue.
		var parts: Array = mods.keys()
		mod = str(mods[parts[parts.size() - 1]])
	var path := AURORA_MOD_SPRITES + key + "_" + mod.to_lower() + ".webp"
	if not ResourceLoader.exists(path):
		return original
	var variant := load(path) as Texture2D
	return variant if variant != null else original


func _refresh_aurora_sprite() -> void:
	var gs := _gs()
	var st := stage()
	var balloon := _balloon()
	if gs == null or st == null or balloon == null:
		return
	if st.aurora_quad is AuroraPartsRig:
		var rig := st.aurora_quad as AuroraPartsRig
		rig.set_expression(str(gs.show_aurora_key))
		rig.set_part_mods(body_mods(), (gs.show_mod_counts as Dictionary) if "show_mod_counts" in gs else {})
		return
	var quad := st.aurora_quad as Sprite3DQuad
	if quad == null:
		return
	var key := str(gs.show_aurora_key)
	var base: Texture2D = balloon.sprites.get(key)
	if base != null:
		quad.texture = _modded_aurora_texture(key, base, gs.show_body_mods)


# ------------------------------------------------------------ gem ceremony

## Throw both gems and read what the stones say. Nothing is pre-rolled: the
## stage throws with impulses drawn from the story RNG, the bodies land where
## physics puts them, and the faces that land front-most become the words.
## Same seed, same throw parameters, same landing — deterministic, but the
## words come from the simulation, never from a randi_range(0, 7).
func throw_gem_round() -> void:
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	var epoch := _state_epoch
	if replaying():
		# Off-screen jump: no flight, no cue, no reward ceremony. The faces
		# are drawn from the story RNG so the replayed night is still a
		# night, and the stage is re-dressed once when the replay lands.
		gs.show_part_face = gs.rng.randi_range(0, ShowStageScript.PARTS.size() - 1)
		gs.show_mod_face = gs.rng.randi_range(0, ShowStageScript.MODS.size() - 1)
		gs.show_part = ShowStageScript.PARTS[gs.show_part_face]
		gs.show_mod = ShowStageScript.MODS[gs.show_mod_face]
		return
	music_heat(0.7, 0.5)
	snd("throw", 0.8)
	var faces: Array = await st.throw_gems(gs.rng)
	if not _is_current(epoch, st) or faces.size() != 2:
		return
	if int(faces[0]) < 0 or int(faces[0]) >= ShowStageScript.PARTS.size() or int(faces[1]) < 0 or int(faces[1]) >= ShowStageScript.MODS.size():
		return
	gs.show_part_face = int(faces[0])
	gs.show_mod_face = int(faces[1])
	gs.show_part = ShowStageScript.PARTS[gs.show_part_face]
	gs.show_mod = ShowStageScript.MODS[gs.show_mod_face]


## Spend a crowd cheer: the modification gem goes back in the air, and the
## new word is whatever face lands front-most this time.
func swap_mod_gem() -> void:
	snd("scratch", 0.8)
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	if int(gs.show_cheers) <= 0:
		return
	var epoch := _state_epoch
	gs.show_cheers = int(gs.show_cheers) - 1
	gs.rerolls_used = int(gs.rerolls_used) + 1
	# The re-throw REPLACES the word: the stamp it made is taken back before
	# the new word is stamped, so a rerolled shift does not keep stacking.
	_unstamp_current(gs)
	if replaying():
		gs.show_mod_face = gs.rng.randi_range(0, ShowStageScript.MODS.size() - 1)
		gs.show_mod = ShowStageScript.MODS[gs.show_mod_face]
		st.place_word_plaque(str(gs.show_mod), false)
		await apply_mods()
		return
	var face: int = await st.rethrow_gem(1, gs.rng)
	if not _is_current(epoch, st) or int(face) < 0 or int(face) >= ShowStageScript.MODS.size():
		if int(face) < 0 and _is_current(epoch, st):
			gs.show_cheers = int(gs.show_cheers) + 1
			gs.rerolls_used = int(gs.rerolls_used) - 1
		return
	gs.show_mod_face = int(face)
	gs.show_mod = ShowStageScript.MODS[gs.show_mod_face]
	await apply_mods()


## Take back the stamp the current pairing made (if it made one): the
## rerolled word is gone, so its count and its slot on the body go too.
func _unstamp_current(gs: Node) -> void:
	var mod := str(gs.show_mod)
	var part := str(gs.show_part)
	if mod == "" or str(gs.show_last_stamp) == "":
		return
	if not str(gs.show_last_stamp).begins_with(part + "|" + mod + "|"):
		return
	var counts: Dictionary = (gs.show_mod_counts as Dictionary).duplicate()
	counts[mod] = maxi(int(counts.get(mod, 0)) - 1, 0)
	if int(counts[mod]) == 0:
		counts.erase(mod)
	gs.show_mod_counts = counts
	var kept: Dictionary = (gs.show_body_mods as Dictionary).duplicate()
	if str(kept.get(part, "")) == mod:
		kept.erase(part)
	gs.show_body_mods = kept
	gs.show_last_stamp = ""


## Stamp the pairing onto the guest: the floating chip, the portrait effects,
## and the freshly computed outlook for the trial about to run.
func apply_mods() -> void:
	snd("wobble_blip", 0.85)
	music_cue("stab")
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	gs.show_body_mods = body_mods()
	# Count the stamp once: the same line re-run by a rewind or a mercy
	# swap to a different word must not double it, but a mercy swap IS a
	# new stamp and a shift landing on the same part again still counts.
	var stamp := "%s|%s|%d|%d" % [str(gs.show_part), str(gs.show_mod), int(gs.show_round), int(gs.rerolls_used)]
	if str(gs.show_mod) != "" and str(gs.show_last_stamp) != stamp:
		gs.show_last_stamp = stamp
		var counts: Dictionary = (gs.show_mod_counts as Dictionary).duplicate()
		counts[str(gs.show_mod)] = int(counts.get(str(gs.show_mod), 0)) + 1
		gs.show_mod_counts = counts
	gs.show_outlook = outlook_for(int(gs.show_round))
	if replaying():
		return
	st.apply_mod_chip(str(gs.show_part), str(gs.show_mod), st.chip_anchor(), gs.show_body_mods)
	st.apply_body_mods(gs.show_body_mods)
	_refresh_aurora_sprite()
	await st.get_tree().create_timer(0.9).timeout


# ----------------------------------------------------------------- trials

## Dress the stage for trial [param round_no] and remember it for restores.
func build_challenge(round_no: int) -> void:
	snd("reveal", 0.7)
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	gs.show_props_round = clampi(round_no, 1, 3)
	_pattern = []
	var rounds := 5
	for i in rounds:
		_pattern.append(gs.rng.randi_range(0, 3))
	if replaying():
		# Props are choreography: a silent replay only walks the RNG and
		# remembers the round, or the set is built and torn down per line.
		return
	st.clear_props()
	match clampi(round_no, 1, 3):
		1: st.build_crossing()
		2: st.build_bells()
		3: st.build_choir()
	await st.get_tree().create_timer(0.7).timeout


## Decide without dice, then perform the result, award the star, and tear the
## props back down. The stage is clean when this returns. Success is Aurora's
## actions plus the gems' situational edge, against the trial number: trial 1
## needs a total of 1, trial 2 needs 2, trial 3 needs 3. The same choices
## with the same words always clear or miss the same way — the show is won
## by playing, not by rolling.
func run_challenge() -> void:
	var gs := _gs()
	var st := stage()
	if gs == null or st == null:
		return
	var epoch := _state_epoch
	var need := clampi(int(gs.show_round), 1, 3)
	var score := total_for(int(gs.show_round))
	gs.last_roll = float(score)
	gs.last_success = score >= need
	# A rollback re-runs the mutations of the line it lands on; without this
	# the same trial would award its star twice and the win count would not
	# go back when the player jumped to an earlier choice.
	var already_scored := int(gs.show_scored_round) == need
	if replaying():
		gs.show_scored_round = need
		if gs.last_success and not already_scored:
			gs.show_stars = int(gs.show_stars) + 1
		gs.show_props_round = 0
		return
	music_heat(0.95, 0.4)
	music_cue("riser")
	var a := _audio()
	if a != null and a.has_method("pick_best_music"):
		a.pick_best_music("challenge_run")
	await st.play_challenge(int(gs.show_round), bool(gs.last_success), _pattern)
	if not _is_current(epoch, st):
		return
	if gs.last_success:
		snd("correct", 1.0)
		music_cue("drop")
		if a != null and a.has_method("pick_best_music"):
			a.pick_best_music("challenge_victory")
	else:
		snd("wrong", 0.9)
		music_cue("impact")
		if a != null and a.has_method("pick_best_music"):
			a.pick_best_music("challenge_loss")
	music_heat(0.6, 1.2)
	gs.show_scored_round = need
	if gs.last_success and not already_scored:
		gs.show_stars = int(gs.show_stars) + 1
	st.set_stars(int(gs.show_stars))
	var star_index := int(gs.show_stars) - 1 if gs.last_success else int(gs.show_stars)
	await st.fly_star(bool(gs.last_success), star_index)
	if not _is_current(epoch, st):
		return
	st.clear_props()
	gs.show_props_round = 0


## Golden rain for a perfect show.

## Overall victory: 2 or 3 stars, golden confetti, triumphant dubstep
func on_show_victory() -> void:
	if replaying():
		return
	snd("win", 1.0)
	snd("airhorn", 0.85)
	var a := _audio()
	if a != null and a.has_method("pick_best_music"):
		a.pick_best_music("overall_victory")


## Overall defeat: 0 or 1 star, melancholic sub chill
func on_show_defeat() -> void:
	if replaying():
		return
	snd("lose", 0.85)
	var a := _audio()
	if a != null and a.has_method("pick_best_music"):
		a.pick_best_music("overall_loss")

func finale_confetti() -> void:
	on_show_victory()
	var st := stage()
	if st != null and not replaying():
		st.confetti_burst()


# ------------------------------------------------------------ silent replay

## True while the balloon is replaying the story to itself — a jump from
## the story map / choice list, a replay-from-start travel, a rewrite
## probe. Mutations run again off-screen at full speed, so the show must not
## throw stones, wait for the player's hand, hand out rewards, or build and
## strike props. State still moves; choreography is skipped; the stage is
## re-dressed from the finished state once the replay lands.
func replaying() -> bool:
	var balloon := _balloon()
	if balloon == null:
		return false
	# A story-map / route jump, or the "next choice" fast-forward: both run
	# the lines between here and there off-screen, so both skip the show.
	if ("_silent_travel" in balloon) and bool(balloon.get("_silent_travel")):
		return true
	if ("_seeking_choice" in balloon) and bool(balloon.get("_seeking_choice")):
		return true
	return false


var _was_replaying := false


func _process(_delta: float) -> void:
	var now := replaying()
	if now == _was_replaying:
		return
	_was_replaying = now
	if not now:
		sync_from_state()


# ---------------------------------------------------------------- restores

func _on_state_restored() -> void:
	sync_from_state()


## Rebuild the visible show from GameState — used after rollback, save-load
## and the panic screen. Nothing animates; everything is simply true again.
func sync_from_state() -> void:
	_state_epoch += 1
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
		# Rigs are not motion-tracked quads: detach them for real, or a rewind
		# to before the show leaves a ghost guest standing beside the new one.
		if st.has_method("free_aurora_actor"):
			st.free_aurora_actor()
		else:
			st.aurora_quad = null
	if str(gs.show_part) != "" and int(gs.show_part_face) >= 0:
		st.place_gems_settled(str(gs.show_part), int(gs.show_part_face), str(gs.show_mod), int(gs.show_mod_face))
		st.apply_mod_chip(str(gs.show_part), str(gs.show_mod), st.chip_anchor(), gs.show_body_mods)
	else:
		st.clear_gems()
		st.clear_mod_chip()
	if not body_mods().is_empty():
		st.apply_body_mods(body_mods())
	else:
		st.reset_aurora_fx()
	st.clear_props()
	if st.has_method("clear_result_stamp"):
		st.clear_result_stamp()
	match clampi(int(gs.show_props_round), 0, 3):
		1: st.build_crossing()
		2: st.build_bells()
		3: st.build_choir()
	st.set_stars(int(gs.show_stars))
