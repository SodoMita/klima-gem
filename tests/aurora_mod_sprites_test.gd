extends Node
## Aurora is one stage actor assembled from nine independent, direct-drawn
## layers. Every shift must alter only its selected body part and survive
## expression changes/save restore without producing combination plates.

const PARTS := ["HANDS", "EYES", "LEGS", "VOICE", "HAIR", "BACK", "HEART", "SKIN", "MILK"]
const MODS := ["GIANT", "TINY", "STICKY", "BOUNCY", "GLASS", "MAGNET", "HEAVY", "GLOWING", "MEGA"]
var failures := 0


func check(ok: bool, detail: String) -> void:
	if ok:
		print("  ok: ", detail)
	else:
		failures += 1
		printerr("  FAIL: ", detail)


func _actor_count(stage: ShowStage) -> int:
	var count := 0
	var parent := stage.characters_parent()
	if parent == null:
		return 0
	for child in parent.get_children():
		if child is Sprite3DQuad:
			count += 1
	return count


func _same_pose(a: Sprite3DQuad, b_scale: Vector3, b_position: Vector3, b_tint: Color) -> bool:
	return a.scale.is_equal_approx(b_scale) \
		and a.position.is_equal_approx(b_position) \
		and a.modulate.is_equal_approx(b_tint)


func _ready() -> void:
	var stage: ShowStage = load("res://scenes/show_stage/show_stage.tscn").instantiate()
	add_child(stage)
	var balloon: Node = load("res://scenes/vn_balloon.tscn").instantiate()
	add_child(balloon)
	for i in 3:
		await get_tree().process_frame
	var gs: Node = get_node_or_null("/root/GameState")
	var director: Node = get_node_or_null("/root/ShowDirector")
	check(gs != null and director != null, "show state and director are registered")
	if gs == null or director == null:
		get_tree().quit(1)
		return
	var saved: Dictionary = gs.snapshot()

	director.set_aurora_expression("serious", true)
	var host := stage.aurora_quad as Sprite3DQuad
	var body := stage.aurora_body()
	check(host != null and _actor_count(stage) == 1, "one Aurora actor stands on the stage")
	check(host != null and host.texture != null and host.texture.resource_path == "", "actor host has no old full-body plate")
	check(body != null and body.layer_count() == 9, "Aurora is assembled from all nine semantic layers")
	if body == null:
		get_tree().quit(1)
		return
	for part in PARTS:
		var layer := body.layer(part)
		check(layer != null, "%s has an independent layer" % part)
		if layer != null:
			check(layer.texture.resource_path.begins_with("res://assets/characters/parts/aurora/"), "%s uses fresh modular art" % part)

	# Exhaustively prove that each possible pairing changes its target and
	# leaves a neighboring body part byte-for-byte equivalent in transform/tint.
	for part_index in PARTS.size():
		var part: String = PARTS[part_index]
		var untouched: String = PARTS[(part_index + 1) % PARTS.size()]
		for mod in MODS:
			body.reset_mods()
			var target := body.layer(part)
			var other := body.layer(untouched)
			var target_scale := target.scale
			var target_position := target.position
			var target_tint := target.modulate
			var other_scale := other.scale
			var other_position := other.position
			var other_tint := other.modulate
			body.apply_mods({part: mod})
			check(not _same_pose(target, target_scale, target_position, target_tint), "%s %s visibly changes only its layer" % [part, mod])
			check(_same_pose(other, other_scale, other_position, other_tint), "%s %s leaves %s unchanged" % [part, mod, untouched])
			check(body.current_mod(part) == mod, "%s remembers its %s state" % [part, mod])
	body.reset_mods()

	# Exercise the real state/director path, not only the component API.
	gs.show_part = "EYES"
	gs.show_mod = "GLASS"
	gs.show_body_mods = {"EYES": "GLASS"}
	director.sync_from_state()
	host = stage.aurora_quad as Sprite3DQuad
	body = stage.aurora_body()
	check(body != null and body.current_mod("EYES") == "GLASS", "state restore applies GLASS to EYES")
	check(body != null and body.layer("LEGS").modulate.is_equal_approx(Color.WHITE), "GLASS EYES does not make LEGS transparent")
	check(_actor_count(stage) == 1, "part modification does not create another character")

	director.set_aurora_expression("happy")
	body = stage.aurora_body()
	check(body != null and body.expression == "happy", "expression changes use modular redraws")
	check(body != null and body.layer("EYES").texture.resource_path.ends_with("expressions/happy/eyes.webp"), "happy eyes replace only the EYES art")
	check(body != null and body.layer("VOICE").texture.resource_path.ends_with("expressions/happy/voice.webp"), "happy mouth replaces only the VOICE art")
	check(body != null and body.current_mod("EYES") == "GLASS", "expression swap retains the EYES shift")
	check(_actor_count(stage) == 1, "expression swap still has one Aurora actor")

	gs.show_part = "BACK"
	gs.show_mod = "MEGA"
	await director.apply_mods()
	body = stage.aurora_body()
	check(body != null and body.current_mod("EYES") == "GLASS", "previous part shift remains composed")
	check(body != null and body.current_mod("BACK") == "MEGA", "new BACK shift composes concurrently")
	check(gs.show_body_mods.has("EYES") and gs.show_body_mods.has("BACK"), "state stores both independent part shifts")

	gs.restore(saved)
	director.set_aurora_expression("serious", true)
	body = stage.aurora_body()
	check(body != null and body.mods().is_empty(), "rewind before shifts restores every layer")
	check(body != null and body.expression == "serious", "rewind restores the expression redraw")
	check(_actor_count(stage) == 1, "restore still has exactly one Aurora actor")
	print("AURORA MODULAR BODY: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
