extends Node
## MultiMesh sanity regression test (Mila-x7q).
##
## A past editor save of scenes/show_stage/show_stage.tscn persisted the
## transform buffers of the star cloth / audience / glowstick MultiMeshes
## from uninitialized memory: denormals (1e-41..1e-44) mixed with wild
## values (3304, 99.125, 8e+26). On several GPUs those transforms smeared
## polygons across the whole view — the "exploded" 3D scene — and on others
## the over/underflow blanked the framebuffer. The buffers are no longer
## serialized and show_stage.gd dresses all three from a fixed seed in
## _ready. This test locks both facts in.
##
## Prints "MULTIMESH TESTS: PASS" and exits 0, or "FAIL" and 1.
## Run: GODOT_BIN=/path/to/godot bash tests/multimesh_sanity_test.sh

const ShowStageScene := preload("res://scenes/show_stage/show_stage.tscn")

var failures := 0

func _ready() -> void:
	# Watchdog so a hang fails instead of stalling CI for an hour.
	get_tree().create_timer(60.0).timeout.connect(_on_watchdog)
	await _test_packed_buffers_sane()
	await _test_dressed_buffers_sane()
	if failures == 0:
		print("MULTIMESH TESTS: PASS")
		get_tree().quit(0)
	else:
		print("MULTIMESH TESTS: FAIL (%d failures)" % failures)
		get_tree().quit(1)

func _on_watchdog() -> void:
	print("MULTIMESH TESTS: FAIL (watchdog)")
	get_tree().quit(1)

func _fail(msg: String) -> void:
	failures += 1
	printerr("FAIL: ", msg)

func _ok(msg: String) -> void:
	print("ok: ", msg)

func _scan_multimeshes(root: Node, label: String) -> void:
	var found := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			found += 1
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			var buf: PackedFloat32Array = mm.buffer
			var expected: int = mm.instance_count * (16 if mm.use_colors else 12)
			if buf.size() != expected and buf.size() != 0:
				_fail("%s/%s: buffer size %d != expected %d" % [label, n.name, buf.size(), expected])
				continue
			var bad := 0
			var maxabs := 0.0
			for f in buf:
				if is_nan(f) or is_inf(f):
					bad += 1
				else:
					maxabs = maxf(maxabs, absf(f))
			if bad > 0:
				_fail("%s/%s: %d NaN/INF floats in multimesh buffer" % [label, n.name, bad])
			elif buf.size() > 0 and maxabs > 1.0e6:
				_fail("%s/%s: wildcard float %f in multimesh buffer" % [label, n.name, maxabs])
			elif buf.size() > 0 and maxabs != 0.0 and maxabs < 1.0e-30:
				_fail("%s/%s: buffer is denormal garbage (maxabs %f)" % [label, n.name, maxabs])
			else:
				_ok("%s/%s: %d instances, %d floats, maxabs %.6f" % [label, n.name, mm.instance_count, buf.size(), maxabs])
		for c in n.get_children():
			stack.append(c)
	if found < 3:
		_fail("%s: expected at least 3 MultiMeshInstance3D (stars, crowd, glowsticks), found %d" % [label, found])

func _test_packed_buffers_sane() -> void:
	# Exactly what was serialized: instantiated, but not yet inside the tree,
	# so _ready has not dressed anything. Must already be garbage-free.
	var stage := ShowStageScene.instantiate()
	_scan_multimeshes(stage, "packed")
	stage.free()
	await get_tree().process_frame

func _test_dressed_buffers_sane() -> void:
	var stage := ShowStageScene.instantiate()
	add_child(stage)
	await get_tree().process_frame
	await get_tree().process_frame
	_scan_multimeshes(stage, "dressed")
	# Under the headless dummy renderer multimesh buffers never allocate, so
	# transform readback always lies (identity). What CAN be asserted here: the
	# script must have swapped every decorative multimesh for a fresh runtime
	# resource (resource_path is empty), which is what guarantees the seeded
	# dressing ran on real renderers.
	for path in ["StarCloth/Stars", "Audience/Crowd", "Audience/Glowsticks"]:
		var mi := stage.get_node_or_null(path) as MultiMeshInstance3D
		if mi == null or mi.multimesh == null:
			_fail("dressed: %s missing" % path)
		elif mi.multimesh.resource_path != "":
			_fail("dressed: %s still has the serialized multimesh (dressing did not swap it)" % path)
		else:
			_ok("dressed: %s swapped to runtime multimesh (count %d)" % [path, mi.multimesh.instance_count])
	stage.queue_free()
	await get_tree().process_frame
