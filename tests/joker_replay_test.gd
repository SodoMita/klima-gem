extends Node
## Jumping from the story map replays the dialogue to itself. The show must
## keep its STATE during that replay and skip all choreography: no thrown
## stones, no waiting for the player's cue, no props built and torn down —
## and, above all, no second copy of the set left behind.

const ShowStageScene := preload("res://scenes/show_stage/show_stage.tscn")


class FakeBalloon extends Node:
	## Only the flag the director reads.
	var _silent_travel := false


var _oks := 0
var _fails := 0


func ok(cond: bool, what: String) -> void:
	if cond:
		_oks += 1
		print("ok   %s" % what)
	else:
		_fails += 1
		printerr("FAIL %s" % what)


func _ready() -> void:
	await _run()
	print("joker replay test: %d ok, %d failed" % [_oks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	var stage := ShowStageScene.instantiate()
	add_child(stage)
	var balloon := FakeBalloon.new()
	balloon.name = "VNBalloon"
	# The root is mid-setup during _ready; defer the insert.
	get_tree().root.call_deferred("add_child", balloon)
	await get_tree().process_frame
	await get_tree().process_frame

	var director: Node = get_node("/root/ShowDirector")
	var gs: Node = get_node("/root/GameState")
	director.begin_show()
	ok(director.replaying() == false, "not replaying while the show is live")

	balloon._silent_travel = true
	await get_tree().process_frame
	ok(director.replaying(), "the director sees the silent travel")

	var started := Time.get_ticks_msec()
	director.next_round()
	await director.throw_gem_round()
	await director.apply_mods()
	await director.build_challenge(1)
	await director.run_challenge()
	var elapsed := Time.get_ticks_msec() - started

	# Fast: a replay walks dozens of lines, so a single replayed round must
	# not wait on a throw, a cue or a timer.
	ok(elapsed < 900, "a replayed round costs no wall clock (%d ms)" % elapsed)
	ok(str(gs.show_part) != "" and str(gs.show_mod) != "", "state still moves: %s x %s" % [gs.show_part, gs.show_mod])
	ok((gs.show_applied_mods as Array).size() >= 1, "the modification is remembered during replay")
	ok(stage._gems.is_empty(), "no stones were thrown during the replay")
	ok(stage.get_node_or_null("ModCard") == null, "no modification card raised during the replay")
	var props: Node = stage.get_node_or_null("Props")
	ok(props == null or props.get_child_count() == 0, "no challenge props built during the replay")

	# Landing: the moment the replay ends the stage must agree with the state.
	balloon._silent_travel = false
	await get_tree().process_frame
	await get_tree().process_frame
	ok(stage._gems.size() == 2, "the stage is re-dressed with both stones when the jump lands")
	ok(stage.get_node_or_null("ModCard") != null, "and the modification card comes back")
	var dupes := {}
	for child in stage.get_children():
		# The two stones are auto-named rigid bodies; they are counted above.
		if child is FlatTopGem or String(child.name).begins_with("@"):
			continue  # stones and the unnamed lighting rig
		var base := String(child.name).rstrip("0123456789")
		dupes[base] = int(dupes.get(base, 0)) + 1
	var worst := ""
	for key in dupes:
		if int(dupes[key]) > 1 and String(key) != "":
			worst = String(key)
	ok(worst == "", "nothing on the stage is duplicated after the jump (%s)" % worst)
