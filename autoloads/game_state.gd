extends Node
## Story state for Chrono Nexus. Dialogue files use `using GameState`.
## `snapshot` / `restore` are what the balloon's rollback and saves call.

signal stat_changed(stat_name: String, value: int)
signal bond_changed(character_id: String, value: int)
signal mind_read_unlocked(unlocked: bool)
## Emitted at the end of restore(); the Klima Gem stage re-dresses itself on it.
signal state_restored

@export var player_name: String = "Aurora"
@export var trust: int = 0
@export var insight: int = 0
@export var power: int = 0
@export var steadied_aurora: bool = false
@export var reached_for_kira: bool = false
@export var comforted_elara: bool = false
@export var teased_selene: bool = false
@export var supported_aurora: bool = false
@export var protected_nova: bool = false

## --- Klima Gem show state ------------------------------------------------
## Trial counter (0 before the first throw), stars won, crowd cheers left,
## the two rolled words and their face indices, the current outlook, which
## trial's props are standing, and the guest's current portrait key.
@export var show_round: int = 0
@export var show_stars: int = 0
@export var show_cheers: int = 1
@export var show_part: String = ""
@export var show_mod: String = ""
@export var show_part_face: int = -1
@export var show_mod_face: int = -1
@export var show_outlook: String = ""
@export var show_props_round: int = 0
## Which trial has already been scored. Rolling back restores this, so a line
## whose mutations run again on the way back cannot award a second win.
@export var show_scored_round: int = 0
@export var show_ren_key: String = ""
@export var show_aurora_key: String = ""
@export var rerolls_used: int = 0
## Body modifications Aurora keeps across trials: part word -> mod word.
@export var show_body_mods: Dictionary = {}
@export var last_roll: float = 0.0
@export var last_success: bool = false
## Fixed for the playthrough. A from-start replay uses this, not a fresh roll,
## so the same choices produce the same random results. Saves keep it inside
## each history snapshot.
@export var story_seed: int = 1
var rng := RandomNumberGenerator.new()

var bond: Dictionary = {}


func _ready() -> void:
	_reseed()
	# Dialogue Manager is a later autoload, so the first reseed cannot see it
	# yet. Seed ONLY its stream on the retry: re-seeding rng here resets the
	# whole story stream, which (when the deferred call lands mid-frame) made
	# two gem throws in one round draw identical numbers and land identically.
	call_deferred("_reseed_dialogue")


## A new show gets a new seed: throws are never the same night twice. The
## seed is saved in every snapshot, so rewinds and loads replay exactly.
func fresh_seed() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	story_seed = int(r.randi() & 0x7fffffff)
	_reseed()


func _reseed_dialogue() -> void:
	var manager := get_tree().root.get_node_or_null("DialogueManager")
	if manager != null and manager.has_method("reseed_randomizer"):
		manager.reseed_randomizer(story_seed)


func _reseed() -> void:
	rng.seed = story_seed
	seed(story_seed)
	var manager := get_tree().root.get_node_or_null("DialogueManager")
	if manager != null and manager.has_method("reseed_randomizer"):
		manager.reseed_randomizer(story_seed)


func can_read_mind(character_id: String) -> bool:
	# You play AS Aurora: a deep bond with Ren (or, for old saves, the
	# legacy aurora key) opens the quiet channel to the host's unspoken words.
	var who := character_id.to_lower()
	if who == "ren" and get_bond("ren") >= 5:
		return true
	if who == "aurora" and (get_bond("aurora") >= 5 or get_bond("ren") >= 5):
		return true
	if insight >= 10:
		return true
	return false


func get_bond(character_id: String) -> int:
	return int(bond.get(character_id.to_lower(), 0))


func add_bond(character_id: String, amount: int) -> void:
	character_id = character_id.to_lower()
	var new_value: int = get_bond(character_id) + amount
	bond[character_id] = new_value
	bond_changed.emit(character_id, new_value)
	if character_id in ["aurora", "ren"] and new_value >= 5:
		mind_read_unlocked.emit(true)


func add_trust(amount: int) -> void:
	trust += amount
	stat_changed.emit("trust", trust)


func add_insight(amount: int) -> void:
	insight += amount
	stat_changed.emit("insight", insight)
	if insight >= 10:
		mind_read_unlocked.emit(true)


func add_power(amount: int) -> void:
	power += amount
	stat_changed.emit("power", power)


func snapshot() -> Dictionary:
	var data := {
		"player_name": player_name,
		"trust": trust,
		"insight": insight,
		"power": power,
		"steadied_aurora": steadied_aurora,
		"reached_for_kira": reached_for_kira,
		"comforted_elara": comforted_elara,
		"teased_selene": teased_selene,
		"supported_aurora": supported_aurora,
		"protected_nova": protected_nova,
		"story_seed": story_seed,
		"bond": bond.duplicate(true),
		"show_round": show_round,
		"show_stars": show_stars,
		"show_cheers": show_cheers,
		"show_part": show_part,
		"show_mod": show_mod,
		"show_part_face": show_part_face,
		"show_mod_face": show_mod_face,
		"show_outlook": show_outlook,
		"show_props_round": show_props_round,
		"show_scored_round": show_scored_round,
		"show_ren_key": show_ren_key,
		"show_aurora_key": show_aurora_key,
		"rerolls_used": rerolls_used,
		"show_body_mods": show_body_mods.duplicate(true),
		"last_roll": last_roll,
		"last_success": last_success,
	}
	# Strings, not raw ints: a save is JSON, and a 64-bit RNG state does not survive a number.
	data["rng_state"] = str(rng.state)
	var manager := get_tree().root.get_node_or_null("DialogueManager")
	if manager != null:
		var stream = manager.get("_rng")
		if stream != null:
			data["dm_rng_state"] = str(stream.state)
	return data


func restore(data: Dictionary) -> void:
	player_name = str(data.get("player_name", "Aurora"))
	trust = int(data.get("trust", 0))
	insight = int(data.get("insight", 0))
	power = int(data.get("power", 0))
	steadied_aurora = bool(data.get("steadied_aurora", false))
	reached_for_kira = bool(data.get("reached_for_kira", false))
	comforted_elara = bool(data.get("comforted_elara", false))
	teased_selene = bool(data.get("teased_selene", false))
	supported_aurora = bool(data.get("supported_aurora", false))
	protected_nova = bool(data.get("protected_nova", false))
	show_round = int(data.get("show_round", 0))
	show_stars = int(data.get("show_stars", 0))
	show_cheers = int(data.get("show_cheers", 1))
	show_part = str(data.get("show_part", ""))
	show_mod = str(data.get("show_mod", ""))
	show_part_face = int(data.get("show_part_face", -1))
	show_mod_face = int(data.get("show_mod_face", -1))
	show_outlook = str(data.get("show_outlook", ""))
	show_props_round = int(data.get("show_props_round", 0))
	show_scored_round = int(data.get("show_scored_round", 0))
	show_ren_key = str(data.get("show_ren_key", ""))
	show_aurora_key = str(data.get("show_aurora_key", ""))
	rerolls_used = int(data.get("rerolls_used", 0))
	var kept: Variant = data.get("show_body_mods", {})
	show_body_mods = (kept as Dictionary).duplicate(true) if kept is Dictionary else {}
	last_roll = float(data.get("last_roll", 0.0))
	last_success = bool(data.get("last_success", false))
	if data.has("story_seed"):
		story_seed = int(data["story_seed"])
	var saved: Variant = data.get("bond", {})
	bond = (saved as Dictionary).duplicate(true) if saved is Dictionary else {}
	if data.has("rng_state"):
		rng.state = int(data["rng_state"])
	else:
		_reseed()
	if data.has("dm_rng_state"):
		var manager := get_tree().root.get_node_or_null("DialogueManager")
		if manager != null:
			var stream = manager.get("_rng")
			if stream != null:
				stream.state = int(data["dm_rng_state"])
	stat_changed.emit("trust", trust)
	stat_changed.emit("insight", insight)
	stat_changed.emit("power", power)
	state_restored.emit()


func reset() -> void:
	var seed_now := story_seed
	restore({})
	story_seed = seed_now
	_reseed()
