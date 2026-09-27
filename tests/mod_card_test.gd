extends Node
## The eight case-specific transformation CGs and the MEGA table outcome:
## cards must be legible, stay clear of the glass box, and never duplicate
## when a rewind/load re-dresses the same stage multiple times in one frame.

const StageScene := preload("res://scenes/show_stage/show_stage.tscn")
const StageScript := preload("res://scenes/show_stage/show_stage.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok: ", what)
	else:
		failures += 1
		printerr("  FAIL: ", what)


func _card_count(stage: Node3D) -> int:
	var count := 0
	for child in stage.get_children():
		if child.name.begins_with("ModCard"):
			count += 1
	return count


func _ready() -> void:
	var stage: ShowStage = StageScene.instantiate()
	add_child(stage)
	await get_tree().process_frame
	var old_state: Dictionary = GameState.snapshot()
	var cam: Camera3D = stage.camera()
	var view: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = cam.unproject_position(StageScript.MOD_CARD_MARK)
	check(not cam.is_position_behind(StageScript.MOD_CARD_MARK), "the card faces the house camera")
	check(pos.x > view.x * 0.05 and pos.x < view.x * 0.95 and pos.y > view.y * 0.04 and pos.y < view.y * StageScript.SAFE_AREA_BOTTOM,
		"the card is inside the safe, unobscured broadcast frame: %s / %s" % [pos, view])
	check(StageScript.MOD_CARD_MARK.x + 0.575 < StageScript.BOX_CENTER.x - StageScript.BOX_SIZE.x * 0.5,
		"the card is beside, never inside, the glass throw box")

	for mod in StageScript.MODS:
		var tex: Texture2D = stage.mod_art(mod)
		check(tex != null, "%s has modification CG art (MEGA may borrow GIANT)" % mod)
		if tex != null:
			check(tex.get_width() >= 256 and tex.get_height() >= 256, "%s art has readable native resolution" % mod)
		stage.apply_mod_chip("HANDS", mod, stage.chip_anchor(), {"HANDS": mod})
		var card := stage.get_node_or_null("ModCard") as Node3D
		check(card != null and _card_count(stage) == 1, "%s raises exactly one card" % mod)
		if card != null:
			var sprite := card.get_node_or_null("Art") as Sprite3D
			var caption := card.get_node_or_null("Caption") as Label3D
			check(sprite != null and sprite.texture == tex, "%s card displays the matching CG" % mod)
			check(caption != null and caption.text == mod, "%s is captioned with its true face word" % mod)

	# Clearing and rebuilding three times in the SAME frame was the original
	# duplicate-on-load bug. Nothing is allowed to become "ModCard2".
	for i in 3:
		stage.apply_mod_chip("EYES", "GLOWING", stage.chip_anchor(), {"EYES": "GLOWING"})
		check(_card_count(stage) == 1, "same-frame card replacement %d leaves one card" % i)
	await get_tree().process_frame
	check(_card_count(stage) == 1, "only one card survives the deferred free")
	stage.clear_mod_chip()
	check(_card_count(stage) == 0, "clearing the modification removes its card immediately")

	# A save/rewind rebuild re-creates the correct card from GameState. The
	# clean snapshot returns to an empty stage without a ghost card.
	GameState.show_part = "EYES"
	GameState.show_mod = "GLOWING"
	GameState.show_part_face = 1
	GameState.show_mod_face = 7
	GameState.show_body_mods = {"EYES": "GLOWING"}
	ShowDirector.sync_from_state()
	check(_card_count(stage) == 1 and stage._mod_card.get_node("Caption").text == "GLOWING",
		"state restore dresses the current modification exactly once")
	ShowDirector.sync_from_state()
	check(_card_count(stage) == 1, "two same-frame restores never duplicate the card")
	GameState.restore(old_state)
	check(_card_count(stage) == 0, "rewinding before the roll clears the future card")

	print("MOD CARD TESTS: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
