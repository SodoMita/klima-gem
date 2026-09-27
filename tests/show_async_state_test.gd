extends Node
## Controllable animation boundaries: exercise real director + GameState restore
## without depending on physics wall-clock timing or renderer availability.
class PausedStage extends Node3D:
	signal landed
	signal played
	signal awarded
	var clears := 0
	var flights := 0
	var throws := 0
	var faces: Array = [2, 3]
	var face := 4
	var aurora_quad: Node3D
	func throw_gems(_rng: RandomNumberGenerator, _interactive := false) -> Array:
		throws += 1
		await landed
		return faces
	func rethrow_gem(_which: int, _rng: RandomNumberGenerator, _interactive := false) -> int:
		throws += 1
		await landed
		return face
	func play_challenge(_round: int, _success: bool, _pattern: Array) -> void:
		await played
	func fly_star(_earned: bool, _index: int) -> void:
		flights += 1
		await awarded
	func clear_props() -> void:
		clears += 1
	func clear_gems() -> void: pass
	func clear_mod_chip() -> void: pass
	func clear_mod_card() -> void: pass
	func apply_mod_rail(_mods: Array) -> void: pass
	func apply_mod_chip(_part: String, _mod: String, _at: Vector3) -> void: pass
	func apply_aurora_fx(_part: String, _mod: String) -> void: pass
	func place_gems_settled(_pw: String, _pf: int, _mw: String, _mf: int) -> void: pass
	func chip_anchor() -> Vector3: return Vector3.ZERO
	func reset_aurora_fx() -> void: pass
	func set_stars(_stars: int) -> void: pass
	func build_crossing() -> void: pass
	func build_bells() -> void: pass
	func build_choir() -> void: pass
	func reset_show() -> void: pass

var failures := 0
func check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failures += 1
		printerr("  FAIL: " + message)

func _ready() -> void:
	var st := PausedStage.new()
	st.add_to_group("show_stage")
	add_child(st)
	var director: Node = get_node("/root/ShowDirector")
	var gs: Node = get_node("/root/GameState")
	await get_tree().process_frame
	director.begin_show()
	gs.show_aurora_key = ""
	gs.show_round = 1
	gs.trust = 10
	var baseline: Dictionary = gs.snapshot()

	# A stale completed throw must not overwrite restored blank gem state.
	director.throw_gem_round()
	gs.restore(baseline)
	st.landed.emit()
	check(gs.show_part == "" and gs.show_part_face == -1, "restore cancels pending pair commit")

	# A fresh throw still commits the actual returned faces.
	director.throw_gem_round()
	st.landed.emit()
	check(gs.show_part_face == 2 and gs.show_mod_face == 3, "current throw commits landed faces")
	gs.restore(baseline)
	st.faces = [-1, -1]
	director.throw_gem_round()
	st.landed.emit()
	check(gs.show_part_face == -1, "canceled-face sentinel is not a word index")

	director.swap_mod_gem()
	check(gs.show_cheers == 0, "reroll spends exactly one cheer")
	gs.restore(baseline)
	st.landed.emit()
	check(gs.show_mod_face == -1 and gs.show_cheers == 1 and gs.rerolls_used == 0, "restore cancels reroll result and restores currency")
	gs.show_cheers = 0
	var throws_before := st.throws
	await director.swap_mod_gem()
	check(st.throws == throws_before and gs.show_cheers == 0, "no-cheer reroll cannot launch or overspend")
	gs.restore(baseline)

	director.run_challenge()
	gs.restore(baseline)
	var clears_before := st.clears
	st.played.emit()
	check(gs.show_stars == 0 and st.flights == 0 and st.clears == clears_before, "restore during trial blocks award and prop teardown")

	director.run_challenge()
	st.played.emit()
	check(gs.show_stars == 1 and st.flights == 1, "current successful trial awards once")
	var next_scene: Dictionary = baseline.duplicate(true)
	next_scene["show_props_round"] = 2
	gs.restore(next_scene)
	clears_before = st.clears
	st.awarded.emit()
	check(gs.show_stars == 0 and gs.show_props_round == 2 and st.clears == clears_before, "restore during star flight preserves rebuilt props")

	gs.restore(baseline)
	director.run_challenge()
	st.played.emit()
	st.awarded.emit()
	check(gs.show_stars == 1 and gs.show_props_round == 0, "uninterrupted trial completes normally")
	print("ASYNC STATE TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
