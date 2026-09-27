extends Node
## One Aurora, no icon cards: each transformation uses a lossless transparent
## full-body sprite made from the SAME expression, including after save/load.

const EXPRESSIONS := ["serious", "surprised", "sad", "happy", "gorgeous"]
const MODS := ["GIANT", "TINY", "STICKY", "BOUNCY", "GLASS", "MAGNET", "HEAVY", "GLOWING", "MEGA"]
const ROOT := "res://assets/characters/"
var failures := 0


func check(ok: bool, detail: String) -> void:
	if ok:
		print("  ok: ", detail)
	else:
		failures += 1
		printerr("  FAIL: ", detail)


func _quad_count(stage: ShowStage) -> int:
	var count := 0
	var parent := stage.characters_parent()
	if parent == null:
		return 0
	for child in parent.get_children():
		if child is Sprite3DQuad:
			count += 1
	return count


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

	for expression in EXPRESSIONS:
		var base: Texture2D = load(ROOT + "aurora_%s.webp" % expression)
		check(base != null, "%s has an original Aurora expression" % expression)
		if base == null:
			continue
		for mod in MODS:
			var key := "aurora_%s_%s.webp" % [expression, mod.to_lower()]
			var path := ROOT + "mods/" + key
			var tex: Texture2D = load(path)
			check(tex != null, "%s has a full-body transformation sprite" % key)
			if tex != null:
				check(tex.get_size() == base.get_size(), "%s retains its expression's outline/aspect" % key)
				var img: Image = tex.get_image()
				check(img != null and img.get_pixel(0, 0).a < 0.02, "%s has a truly transparent background" % key)

	director.set_aurora_expression("serious", true)
	var quad := stage.aurora_quad as Sprite3DQuad
	check(quad != null and _quad_count(stage) == 1, "Aurora starts as one original portrait")
	gs.show_part = "EYES"
	gs.show_mod = "GLASS"
	gs.show_body_mods = {"EYES": "GLASS"}
	director.sync_from_state()
	quad = stage.aurora_quad as Sprite3DQuad
	check(quad != null and str(quad.texture.get_meta("aurora_base_key", "")).begins_with("aurora_serious"),
		"GLASS dresses Aurora herself, not a separate icon")
	check(quad != null and quad.texture.get_meta("aurora_body_mods", {}).get("EYES", "") == "GLASS",
		"GLASS on EYES lands on the eye layer, not on the whole body")
	check(_quad_count(stage) == 1, "GLASS keeps one and only one standing character")
	director.set_aurora_expression("happy")
	quad = stage.aurora_quad as Sprite3DQuad
	check(quad != null and str(quad.texture.get_meta("aurora_base_key", "")).begins_with("aurora_happy"),
		"a happy expression retains the GLASS transformation")
	check(_quad_count(stage) == 1, "expression swap does not duplicate Aurora")
	gs.show_part = "SKIN"
	gs.show_mod = "GLASS"
	gs.show_body_mods["SKIN"] = "GLASS"
	director.sync_from_state()
	quad = stage.aurora_quad as Sprite3DQuad
	check(quad != null and str(quad.texture.get_meta("aurora_base_key", "")).ends_with("aurora_happy_glass.webp"),
		"a shift on SKIN still wears the full-body plate as its layer")
	gs.show_body_mods.erase("SKIN")
	gs.show_part = "BACK"
	gs.show_mod = "MEGA"
	await director.apply_mods()
	quad = stage.aurora_quad as Sprite3DQuad
	check(quad != null and quad.texture.get_meta("aurora_body_mods", {}).get("BACK", "") == "MEGA",
		"a new shift lands on the new part, keeping Aurora's smile")
	check(gs.show_body_mods.has("EYES") and gs.show_body_mods.has("BACK"),
		"the previous GLASS shift is still carried alongside MEGA")

	gs.restore(saved)
	director.set_aurora_expression("serious", true)
	quad = stage.aurora_quad as Sprite3DQuad
	var original_tex: Texture2D = balloon.sprites.get("aurora_serious")
	check(quad != null and quad.texture == original_tex, "rewind to before the shift restores the original sprite")
	check(_quad_count(stage) == 1, "restore still has exactly one Aurora")
	print("AURORA MOD SPRITES: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
