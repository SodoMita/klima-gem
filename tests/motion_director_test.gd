extends Node
## Headless test for the StageDirector motion system: tweens on 2D/3D
## objects, instant sets, NLA-style clip playback with crossfade, frame
## ranges (hold + loop), shake, tween stop and rollback replay.
##
## Run: GODOT_BIN=/path/to/godot bash tests/motion_director_test.sh
## (or: godot --headless res://tests/motion_director_test.tscn)
##
## Prints "MOTION TESTS: PASS" and exits 0, or "MOTION TESTS: FAIL" and 1.

var failures: int = 0
var motion: StageDirector
var rig: Node
var cube2d: Node2D
var panel: Control
var cube3d: Node3D
var player: AnimationPlayer
var tree: AnimationTree


func _ready() -> void:
	get_tree().create_timer(45.0).timeout.connect(_on_watchdog)
	_build_rig()
	await _run_tests()
	if failures == 0:
		print("MOTION TESTS: PASS")
		get_tree().quit(0)
	else:
		print("MOTION TESTS: FAIL (%d failures)" % failures)
		get_tree().quit(1)


func _on_watchdog() -> void:
	printerr("MOTION TESTS: watchdog timeout")
	print("MOTION TESTS: FAIL (watchdog)")
	get_tree().quit(1)


func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		failures += 1
		printerr("  FAIL: %s" % label)


func check_close(actual: float, expected: float, label: String, eps: float = 0.05) -> void:
	if absf(actual - expected) <= eps:
		print("  ok: %s (%.3f ~ %.3f)" % [label, actual, expected])
	else:
		failures += 1
		printerr("  FAIL: %s (got %.3f, expected %.3f ±%.3f)" % [label, actual, expected, eps])


func _build_rig() -> void:
	rig = Node.new()
	rig.name = "TestRoot"
	add_child(rig)
	cube2d = Node2D.new()
	cube2d.name = "Cube2D"
	rig.add_child(cube2d)
	panel = Control.new()
	panel.name = "Panel2D"
	rig.add_child(panel)
	cube3d = Node3D.new()
	cube3d.name = "Cube3D"
	rig.add_child(cube3d)
	player = AnimationPlayer.new()
	player.name = "Player"
	rig.add_child(player)
	player.add_to_group("motion_test")
	# "slide": Cube2D.position 0 -> 200 over 1.0 s, no loop.
	var slide := Animation.new()
	slide.length = 1.0
	slide.loop_mode = Animation.LOOP_NONE
	var t: int = slide.add_track(Animation.TYPE_VALUE)
	slide.track_set_path(t, NodePath("Cube2D:position"))
	slide.track_insert_key(t, 0.0, Vector2.ZERO)
	slide.track_insert_key(t, 1.0, Vector2(200, 0))
	var lib := AnimationLibrary.new()
	lib.add_animation("slide", slide)
	# "wave": Cube2D.rotation_degrees 0 -> 360 over 2.0 s, no loop.
	var wave := Animation.new()
	wave.length = 2.0
	wave.loop_mode = Animation.LOOP_NONE
	var w: int = wave.add_track(Animation.TYPE_VALUE)
	wave.track_set_path(w, NodePath("Cube2D:rotation_degrees"))
	wave.track_insert_key(w, 0.0, 0.0)
	wave.track_insert_key(w, 2.0, 360.0)
	lib.add_animation("wave", wave)
	player.add_animation_library("", lib)
	# AnimationTree track with a state machine, to test travel().
	tree = AnimationTree.new()
	tree.name = "Tree"
	var sm := AnimationNodeStateMachine.new()
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"slide"
	sm.add_node("idle", idle, Vector2(300, 100))
	sm.add_transition("Start", "idle", AnimationNodeStateMachineTransition.new())
	tree.tree_root = sm
	tree.anim_player = NodePath("../Player")
	# Kept inactive until the travel test: an active tree samples its state
	# every frame and would fight every tween on Cube2D.
	tree.active = false
	rig.add_child(tree)
	motion = StageDirector.new()
	motion.name = "MotionDirector"
	add_child(motion)
	motion.attach(self)


func _tag(tag: String) -> bool:
	return motion.apply_tag(tag)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run_tests() -> void:
	print("== registration ==")
	check(motion.is_motion_tag("tween=a:b=1"), "is_motion_tag recognises tween=")
	check(motion.is_motion_tag("nla=a:b"), "is_motion_tag recognises nla=")
	check(not motion.is_motion_tag("bg=classroom"), "is_motion_tag ignores #bg=")
	check(_tag("target=cube:TestRoot/Cube2D"), "register 2D alias")
	check(_tag("target=panel:TestRoot/Panel2D"), "register Control alias")
	check(_tag("target=cube3d:TestRoot/Cube3D"), "register 3D alias")
	check(_tag("nla_track=mover:TestRoot/Player"), "register AnimationPlayer track")
	check(_tag("nla_track=blend_tree:TestRoot/Tree"), "register AnimationTree track")
	check(not _tag("target=ghost:TestRoot/Nope"), "missing path is rejected")
	check(not _tag("nla_track=notplayer:TestRoot/Cube2D"), "non-player track is rejected")
	check(motion.resolve_target("cube") == cube2d, "alias resolves")

	print("== tweens ==")
	check(_tag("tween=cube:position=100 50:0.2:cubic:in_out"), "2D position tween accepted")
	check(cube2d.position != Vector2(100, 50), "tween is animated, not instant")
	await _wait(0.45)
	check(cube2d.position.distance_to(Vector2(100, 50)) < 0.5, "2D tween reached target")
	check(_tag("tween=cube:x=10:0.1?relative"), "relative x tween accepted")
	await _wait(0.3)
	check_close(cube2d.position.x, 110.0, "relative x added")
	check(_tag("tween=cube3d:position=1 2 3:0.2:sine"), "3D position tween accepted")
	check(_tag("tween=cube3d:rx=45:0.2"), "3D rotation_degrees.x shorthand")
	await _wait(0.45)
	check(cube3d.position.distance_to(Vector3(1, 2, 3)) < 0.01, "3D tween reached target")
	check_close(cube3d.rotation_degrees.x, 45.0, "3D rx shorthand applied", 0.5)
	check(_tag("tween=panel:position=10 20:0.1"), "Control position tween accepted")
	check(_tag("tween=panel:alpha=0.4:0.1"), "Control alpha shorthand accepted")
	await _wait(0.3)
	check(panel.position.distance_to(Vector2(10, 20)) < 0.5, "Control tween reached target")
	check_close(panel.modulate.a, 0.4, "alpha shorthand applied")
	check(not _tag("tween=ghost:x=1:0.1"), "tween on unknown target rejected")
	check(not _tag("tween=cube:nosuchprop=1:0.1"), "tween on bad property rejected")
	check(not _tag("tween=cube:x=1:fast"), "tween with bad duration rejected")

	print("== instant set ==")
	check(_tag("set=panel:modulate=ff8800"), "hex color set accepted")
	check(panel.modulate.is_equal_approx(Color.html("ff8800")), "hex color applied")
	check(_tag("set=panel:modulate=1 1 1 1"), "rgba components set applied")
	check(panel.modulate.is_equal_approx(Color(1, 1, 1, 1)), "rgba applied")
	check(_tag("set=cube:y=7"), "bare set is instant")
	check_close(cube2d.position.y, 7.0, "bare set applied")
	check(_tag("set=cube:y=-3?relative"), "relative set applied")
	check_close(cube2d.position.y, 4.0, "relative set added")

	print("== tween stop ==")
	_tag("tween=cube:x=500:5")
	await _wait(0.2)
	check(cube2d.position.x > 110.0, "long tween is moving")
	check(_tag("tween_stop=cube"), "tween_stop accepted")
	var frozen: float = cube2d.position.x
	await _wait(0.2)
	check_close(cube2d.position.x, frozen, "position frozen after stop", 0.5)

	print("== nla: play, crossfade, stop ==")
	check(_tag("nla=mover:slide?blend=0"), "nla play accepted")
	await _wait(0.1)
	check(player.is_playing(), "player is playing")
	check(player.current_animation == "slide", "current clip is slide")
	check(not _tag("nla=mover:nonexistent"), "unknown clip rejected")
	check(_tag("nla_stop=mover"), "nla_stop accepted")
	check(not player.is_playing(), "player stopped")

	print("== nla: frame range hold ==")
	# 30-45 at 30 fps == 1.0 s to 1.5 s of the 2.0 s "wave" clip.
	check(_tag("nla=mover:wave:30-45?fps=30&blend=0"), "frame range accepted")
	await _wait(0.05)
	check_close(player.current_animation_position, 1.0, "started at from-frame", 0.25)
	await _wait(0.75)
	check(not player.is_playing(), "held (paused) at end frame")
	check_close(player.current_animation_position, 1.5, "paused at to-frame", 0.05)

	print("== nla: frame range loop ==")
	# 0-30 at 30 fps == 0.0 s to 1.0 s, looped inside a 2.0 s clip.
	check(_tag("nla=mover:wave:0-30?fps=30&loop&blend=0"), "loop range accepted")
	await _wait(1.3)
	check(player.is_playing(), "still playing while looping")
	check(player.current_animation_position < 1.15, "looped back inside the range (pos %.2f)" % player.current_animation_position)
	check(_tag("nla_stop=mover"), "loop stopped")
	check(not player.is_playing(), "player stopped after loop")

	print("== nla: loop flag on a plain clip ==")
	check(_tag("nla=mover:slide?loop&blend=0"), "loop flag accepted")
	await _wait(1.4)
	check(player.is_playing(), "plain clip restarted by loop flag (pos %.2f)" % player.current_animation_position)
	check(_tag("nla_stop=mover"), "loop clip stopped")

	print("== nla: AnimationTree travel ==")
	# Note: a tree-driven player does not report is_playing()/current_animation;
	# the tree advances the clip itself and applies the pose. The observable
	# effect is the animated property and the state machine's current node.
	var before_travel: Vector2 = cube2d.position
	tree.active = true
	check(_tag("nla=blend_tree:idle"), "state travel accepted")
	await _wait(0.3)
	var pb: AnimationNodeStateMachinePlayback = tree.get("parameters/playback")
	check(pb != null and pb.get_current_node() == "idle", "state machine sits on 'idle' after travel")
	check(cube2d.position != before_travel, "tree is driving the slide clip (position moving)")
	tree.active = false
	await _wait(0.1)

	print("== shake ==")
	var base: Vector2 = cube2d.position
	check(_tag("shake=cube:20:0.3"), "shake accepted")
	await _wait(0.1)
	check(cube2d.position != base, "shake is displacing")
	await _wait(0.35)
	check(cube2d.position.distance_to(base) < 0.01, "shake landed back home")

	print("== rollback replay ==")
	motion.reset_all()
	check(cube2d.position.distance_to(Vector2.ZERO) < 0.01, "reset_all restored the 2D home")
	check(cube3d.position.distance_to(Vector3.ZERO) < 0.01, "reset_all restored the 3D home")
	check(panel.position.distance_to(Vector2.ZERO) < 0.01, "reset_all restored the Control home")
	check(panel.modulate.is_equal_approx(Color(1, 1, 1, 1)), "reset_all restored Control modulate")
	motion.replay_tags([
		"tween=cube:x=10:0.5?relative",
		"set=cube:y=4",
		"tween=cube:x=5:0.5?relative",
		"shake=cube:8:0.2",
		"nla=mover:slide?blend=0",
	])
	check_close(cube2d.position.x, 15.0, "relative tweens accumulated in replay")
	check_close(cube2d.position.y, 4.0, "set replayed")
	check(player.current_animation == "slide" and player.is_playing(), "nla clip replayed and playing")
	motion.reset_all()
	_tag("nla_stop=mover")
	check(cube2d.position.distance_to(Vector2.ZERO) < 0.01, "second reset restored home again")

	print("== delay option ==")
	check(_tag("tween=cube:x=50:0.15?delay=0.3"), "delayed tween accepted")
	await _wait(0.15)
	check_close(cube2d.position.x, 0.0, "still waiting during delay", 0.5)
	await _wait(0.45)
	check_close(cube2d.position.x, 50.0, "delayed tween completed")

	print("== yoyo / loops ==")
	_tag("tween=cube:x=10:0.1?relative&yoyo&loops=2")
	await _wait(0.7)
	check_close(cube2d.position.x, 50.0, "yoyo loops returned to the start value")

	await _balloon_integration()
	await _wait(0.1)


## The real balloon: MotionDirector node wiring, built-in aliases and the
## exact tags the story uses (Aurora's hover, the rift shake).
func _balloon_integration() -> void:
	print("== balloon integration ==")
	var packed: PackedScene = load("res://scenes/vn_balloon.tscn")
	if packed == null:
		failures += 1
		printerr("  FAIL: vn_balloon.tscn did not load")
		return
	var balloon: CanvasLayer = packed.instantiate() as CanvasLayer
	add_child(balloon)
	await get_tree().process_frame
	var director: StageDirector = balloon.get_node_or_null("%MotionDirector")
	check(director != null, "balloon has a MotionDirector node")
	if director == null:
		balloon.queue_free()
		return
	check(director.resolve_target("bg") is TextureRect, "built-in alias 'bg' resolves")
	check(director.resolve_target("left") is TextureRect, "built-in alias 'left' resolves")
	check(director.resolve_target("stage") is Control, "built-in alias 'stage' resolves")
	check(director.apply_tag("tween=right:position=0 -8:1.5:sine:in_out?relative&yoyo&loops=0"), "story hover tag applies")
	check(director.apply_tag("shake=stage:4:0.9"), "story rift-shake tag applies")
	var stage: Control = balloon.get_node("%Balloon/Stage")
	await _wait(0.15)
	check(stage.position != Vector2.ZERO, "stage is physically shaking")
	director.reset_all()
	check(stage.position == Vector2.ZERO, "reset_all put the stage home")
	balloon.queue_free()
