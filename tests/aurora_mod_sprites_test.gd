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
		elif child is AuroraPartsRig:
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
	if AuroraPartsRig.parts_available():
		await _run_rig_checks(stage, director, gs, balloon, saved)
	else:
		await _run_plate_checks(stage, director, gs, balloon, saved)
	print("AURORA MOD SPRITES: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


## Nine-layer rig: the standing guest answers the BODY PART gem directly, and
## the old full-body plates stay packed as the asset-level fallback.
func _run_rig_checks(stage: ShowStage, director: Node, gs: Node, balloon: Node, saved: Dictionary) -> void:
	var rig := stage.aurora_quad as AuroraPartsRig
	check(rig != null, "Aurora stands as the layered parts rig")
	check(rig != null and rig.get_child_count() == 9, "rig carries one layer per body-part word")
	check(_quad_count(stage) == 1, "one standing guest, not one per part")
	gs.show_part = "EYES"
	gs.show_mod = "GLASS"
	gs.show_body_mods = {"EYES": "GLASS"}
	gs.show_mod_counts = {"GLASS": 1}
	director.sync_from_state()
	rig = stage.aurora_quad as AuroraPartsRig
	var eyes := rig.part_quad("EYES") if rig != null else null
	var hands := rig.part_quad("HANDS") if rig != null else null
	check(eyes != null and eyes.modulate.a < 0.5, "GLASS turns the EYES layer translucent")
	check(hands != null and hands.modulate.a > 0.99 and hands.scale.x == 1.0,
		"GLASS changes only the named part, hands untouched")
	check(_quad_count(stage) == 1, "GLASS keeps one and only one standing character")
	director.set_aurora_expression("happy")
	rig = stage.aurora_quad as AuroraPartsRig
	eyes = rig.part_quad("EYES") if rig != null else null
	check(eyes != null and eyes.texture != null and eyes.texture.resource_path.ends_with("eyes_happy.webp"),
		"a happy expression swaps the EYES layer, keeping the GLASS shift")
	check(rig != null and eyes != null and eyes.modulate.a < 0.5, "GLASS stays translucent after the expression swap")
	check(_quad_count(stage) == 1, "expression swap does not duplicate Aurora")
	gs.show_part = "BACK"
	gs.show_mod = "MEGA"
	await director.apply_mods()
	rig = stage.aurora_quad as AuroraPartsRig
	var back := rig.part_quad("BACK") if rig != null else null
	check(back != null and back.scale.x > 1.5, "MEGA grows the BACK layer around its own pivot")
	check(gs.show_body_mods.has("EYES") and gs.show_body_mods.has("BACK"),
		"the previous GLASS shift is still carried alongside MEGA")

	gs.restore(saved)
	director.set_aurora_expression("serious", true)
	rig = stage.aurora_quad as AuroraPartsRig
	eyes = rig.part_quad("EYES") if rig != null else null
	var original_tex: Texture2D = balloon.sprites.get("aurora_serious")
	check(original_tex != null, "the original painted portrait resource stays packed as fallback")
	check(eyes != null and eyes.modulate.a > 0.99 and rig != null and (rig.part_quad("BACK") as Sprite3DQuad).scale.x == 1.0,
		"rewind to before the shift restores every layer to identity")
	check(_quad_count(stage) == 1, "restore still has exactly one Aurora")


## Legacy single-quad path (kept for builds without the part art).
func _run_plate_checks(stage: ShowStage, director: Node, gs: Node, balloon: Node, saved: Dictionary) -> void:
	var quad := stage.aurora_quad as Sprite3DQuad
	check(quad != null and _quad_count(stage) == 1, "Aurora starts as one original portrait")
	gs.show_part = "EYES"
	gs.show_mod = "GLASS"
	gs.show_body_mods = {"EYES": "GLASS"}
	director.sync_from_state()
	quad = stage.aurora_quad as Sprite3DQuad
	check(quad != null and quad.texture.resource_path.ends_with("aurora_serious_glass.webp"),
		"GLASS dresses Aurora herself, not a separate icon")
	check(_quad_count(stage) == 1, "GLASS keeps one and only one standing character")
	director.set_aurora_expression("happy")
	quad = stage.aurora_quad as Sprite3DQuad
	check(quad != null and quad.texture.resource_path.ends_with("aurora_happy_glass.webp"),
		"a happy expression retains the GLASS transformation")
	check(_quad_count(stage) == 1, "expression swap does not duplicate Aurora")
	gs.show_part = "BACK"
	gs.show_mod = "MEGA"
	await director.apply_mods()
	quad = stage.aurora_quad as Sprite3DQuad
	check(quad != null and quad.texture.resource_path.ends_with("aurora_happy_mega.webp"),
		"a new shift replaces the sprite, keeping Aurora's smile")
	check(gs.show_body_mods.has("EYES") and gs.show_body_mods.has("BACK"),
		"the previous GLASS shift is still carried alongside MEGA")

	gs.restore(saved)
	director.set_aurora_expression("serious", true)
	quad = stage.aurora_quad as Sprite3DQuad
	var original_tex: Texture2D = balloon.sprites.get("aurora_serious")
	check(quad != null and quad.texture == original_tex, "rewind to before the shift restores the original sprite")
	check(_quad_count(stage) == 1, "restore still has exactly one Aurora")
