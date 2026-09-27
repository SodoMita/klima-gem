extends Node
## AuroraPartsRig: nine aligned part layers answer the BODY PART gem directly.
## The named part — and only the named part — scales, tints, fades or droops,
## around its own pivot; repeats compound (x2 doubled, x3+ gold); expressions
## swap the face layers; resets and rewinds return every layer to identity.

const RIG_SCRIPT := preload("res://scenes/show_stage/aurora_parts.gd")
const ShowStageScript := preload("res://scenes/show_stage/show_stage.gd")
const PARTS_DIR := "res://assets/characters/parts/"
const EXPECTED_PARTS := ["BACK", "LEGS", "SKIN", "HAIR", "MILK", "HANDS", "EYES", "VOICE", "HEART"]

var failures := 0


func check(ok: bool, detail: String) -> void:
	if ok:
		print("  ok: ", detail)
	else:
		failures += 1
		printerr("  FAIL: ", detail)


func _ready() -> void:
	var rig: AuroraPartsRig = RIG_SCRIPT.new()
	add_child(rig)
	rig.setup()
	check(rig.get_child_count() == 9, "nine part layers are built")
	var prev_z := -1.0
	var order_ok := rig.get_child_count() == 9
	for i in EXPECTED_PARTS.size():
		var quad := rig.part_quad(EXPECTED_PARTS[i])
		if quad == null:
			order_ok = false
			break
		var z: float = quad.position.z
		check(z > prev_z, "%s layer sits in front of the previous one" % EXPECTED_PARTS[i])
		prev_z = z
	check(order_ok, "every body-part word owns a layer")

	# world_height fans out to every layer (the legacy reset protocol expects it).
	rig.world_height = 2.0
	var heights_ok := true
	for part in EXPECTED_PARTS:
		if not is_equal_approx((rig.part_quad(part) as Sprite3DQuad).world_height, 2.0):
			heights_ok = false
	check(heights_ok, "world_height reaches all nine layers")
	rig.world_height = ShowStageScript.AURORA_BASE_HEIGHT

	# GIANT HANDS: hands grow around their shoulder pivot, nothing else moves.
	rig.set_part_mods({"HANDS": "GIANT"})
	var hands := rig.part_quad("HANDS") as Sprite3DQuad
	var eyes := rig.part_quad("EYES") as Sprite3DQuad
	var legs := rig.part_quad("LEGS") as Sprite3DQuad
	check(is_equal_approx(hands.scale.x, 1.45), "GIANT HANDS scales the hands layer 1.45x")
	check(not is_equal_approx(hands.position.y, 0.0), "GIANT grows around the part pivot, not the feet")
	check(eyes.scale.x == 1.0 and legs.scale.x == 1.0, "other parts keep their size")
	check(eyes.modulate.a > 0.99, "other parts keep their alpha")

	# TINY LEGS: only legs shrink.
	rig.set_part_mods({"LEGS": "TINY"})
	check(is_equal_approx(legs.scale.x, 0.62), "TINY LEGS shrinks just the legs")
	check(is_equal_approx(hands.scale.x, 1.0), "hands return to natural when their shift is gone")

	# GLASS MILK: translucent bust, opaque everything else.
	rig.set_part_mods({"MILK": "GLASS"})
	var milk := rig.part_quad("MILK") as Sprite3DQuad
	check(milk.modulate.a < 0.5, "GLASS turns the named layer translucent")
	check(legs.modulate.a > 0.99, "GLASS does not wash other parts")

	# Global modulate composes with per-part tints (legacy tint protocol).
	rig.set_part_mods({"MILK": "GLASS"})
	rig.modulate = Color(1, 1, 1, 0.8)
	check(absf(milk.modulate.a - 0.45 * 0.8) < 0.01, "rig modulate multiplies the part tint")
	check(absf(legs.modulate.a - 0.8) < 0.01, "rig modulate reaches untinted parts")
	rig.modulate = Color(1, 1, 1, 1)

	# Stacks compound like the edge math: x2 doubles, x3+ also warms to gold.
	rig.set_part_mods({"HANDS": "GIANT"}, {"GIANT": 1})
	var base_scale: float = hands.scale.x
	rig.set_part_mods({"HANDS": "GIANT"}, {"GIANT": 2})
	check(hands.scale.x > base_scale + 0.2, "a shift applied twice doubles its transform")
	rig.set_part_mods({"HANDS": "GIANT"}, {"GIANT": 3})
	check(hands.scale.x > 1.9, "a mastered shift (x3) transforms harder")
	check(hands.modulate.r > 1.05 and hands.modulate.b < 1.0, "a mastered shift warms toward gold")

	# Two different parts keep two different shifts at once.
	rig.set_part_mods({"HANDS": "GIANT", "EYES": "GLOWING"}, {"GIANT": 1, "GLOWING": 1})
	check(hands.scale.x > 1.4 and eyes.modulate.g > 1.05,
		"HANDS GIANT and EYES GLOWING read at the same time")

	# Expressions swap the face layers only.
	rig.set_part_mods({})
	rig.set_expression("aurora_sad")
	check(eyes.texture.resource_path.ends_with("eyes_sad.webp"), "sad swaps the EYES layer art")
	check(legs.texture.resource_path.ends_with("legs.webp"), "sad does not touch the legs art")
	rig.set_expression("gorgeous")
	check(eyes.texture.resource_path.ends_with("eyes_gorgeous.webp"), "gorgeous swaps the EYES layer art")
	rig.set_expression("blush")
	check(eyes.texture.resource_path.ends_with("eyes.webp"), "an expression without variants keeps the natural face")

	# Stage wiring: per-part, not whole-body; reset returns identity.
	var stage: ShowStage = load("res://scenes/show_stage/show_stage.tscn").instantiate()
	add_child(stage)
	stage.free_aurora_actor()
	rig.get_parent().remove_child(rig)
	stage.characters_parent().add_child(rig)
	rig.position = ShowStageScript.AURORA_MARK
	stage.set_actor("aurora", rig)
	stage.apply_body_mods({"LEGS": "GIANT"})
	check(is_equal_approx(legs.scale.x, 1.45), "stage routes the shift onto the LEGS layer")
	check(is_equal_approx(rig.world_height, ShowStageScript.AURORA_BASE_HEIGHT),
		"layered body keeps her height (no whole-body blowup)")
	stage.apply_body_mods({"LEGS": "GIANT", "HAIR": "STICKY"})
	var hair := rig.part_quad("HAIR") as Sprite3DQuad
	check(hair.modulate.g > 1.1 and is_equal_approx(legs.scale.x, 1.45),
		"a second part carries a second shift alongside the first")
	stage.reset_aurora_fx()
	check(legs.scale.x == 1.0 and hair.modulate == Color(1, 1, 1, 1),
		"reset_aurora_fx returns every layer to identity")
	check(is_equal_approx(rig.world_height, ShowStageScript.AURORA_BASE_HEIGHT),
		"reset keeps the standing height protocol")

	# Replacement discipline: freeing via the stage never leaves two Auroras.
	var rig2: AuroraPartsRig = RIG_SCRIPT.new()
	stage.characters_parent().add_child(rig2)
	rig2.setup()
	stage.free_aurora_actor()
	check(stage.aurora_quad == null, "free_aurora_actor clears the guest reference")
	var left := 0
	for child in stage.characters_parent().get_children():
		if child == rig:
			left += 1
	check(left == 0 and rig.get_parent() == null, "the replaced rig is detached immediately")
	rig2.queue_free()

	print("AURORA PARTS RIG: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
