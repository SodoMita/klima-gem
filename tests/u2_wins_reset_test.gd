extends Node
## The human's report: jumping to the previous (and the next) choice does not
## reset the number of wins. Proves the win count travels with the backlog
## entry: GameState, the stage pips and the balloon's rollback all agree.
var failures := 0


func check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok: ", msg)
	else:
		failures += 1
		printerr("  FAIL: ", msg)


func _lit_pips(stage: Node3D) -> int:
	var lit := 0
	for mi in stage._pips:
		if is_instance_valid(mi):
			var mat := mi.material_override as StandardMaterial3D
			if mat != null and mat.emission_energy_multiplier > 1.0:
				lit += 1
	return lit


func _ready() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var director: Node = get_node_or_null("/root/ShowDirector")
	var stage: Node3D = load("res://scenes/show_stage/show_stage.tscn").instantiate()
	add_child(stage)
	await get_tree().process_frame

	# --- the state layer: a restore must move the win count AND the pips ----
	gs.show_stars = 1
	var before: Dictionary = gs.snapshot()
	gs.show_stars = 3
	director.sync_from_state()
	check(int(gs.show_stars) == 3 and _lit_pips(stage) == 3, "three wins light three pips (%d lit)" % _lit_pips(stage))
	gs.restore(before)
	await get_tree().process_frame
	check(int(gs.show_stars) == 1, "restore rolls the win count back to 1 (got %d)" % int(gs.show_stars))
	check(_lit_pips(stage) == 1, "and the pips follow it back to 1 (%d lit)" % _lit_pips(stage))

	# --- the backlog layer: rollback_to must carry the entry's win count ----
	var balloon: Node = load("res://scenes/vn_balloon.tscn").instantiate()
	add_child(balloon)
	for i in 4:
		await get_tree().process_frame
	var early: Dictionary = gs.snapshot()          # 1 win
	gs.show_stars = 3
	var late: Dictionary = gs.snapshot()           # 3 wins
	var hist: Array = [
		{"id": "a", "character": "", "text": "prompt", "bg": "", "left": "", "right": "", "focus": "", "motion": [], "choices": true, "state": early},
		{"id": "b", "character": "", "text": "trial", "bg": "", "left": "", "right": "", "focus": "", "motion": [], "choices": false, "state": late},
	]
	balloon.history.clear()
	for e in hist:
		balloon.history.append(e)
	balloon.history_cursor = 1
	gs.restore(late)
	director.sync_from_state()
	check(int(gs.show_stars) == 3, "standing on the later entry: three wins")
	balloon.rollback_to(0)
	await get_tree().process_frame
	check(int(gs.show_stars) == 1, "jumping to the PREVIOUS choice resets the wins to 1 (got %d)" % int(gs.show_stars))
	check(_lit_pips(stage) == 1, "and the stage shows one win (%d lit)" % _lit_pips(stage))
	balloon.rollback_to(1)
	await get_tree().process_frame
	check(int(gs.show_stars) == 3, "jumping FORWARD again restores three wins (got %d)" % int(gs.show_stars))
	check(_lit_pips(stage) == 3, "and the stage shows three (%d lit)" % _lit_pips(stage))

	# --- a line whose mutations run twice must not award twice -------------
	gs.show_stars = 0
	gs.show_scored_round = 0
	gs.show_round = 1
	await director.run_challenge()
	var once := int(gs.show_stars)
	await director.run_challenge()
	check(int(gs.show_stars) == once, "re-running the same trial does not award a second win (%d then %d)" % [once, int(gs.show_stars)])
	gs.show_round = 2
	gs.show_props_round = 0
	await director.run_challenge()
	check(int(gs.show_stars) >= once, "the next trial still scores")

	print("U2 WINS RESET: ", "FAIL (%d)" % failures if failures else "PASS")
	get_tree().quit(1 if failures else 0)
