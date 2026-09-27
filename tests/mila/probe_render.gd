extends SceneTree
## Mila-x7q bisect probe: instance the show stage, optionally change one render
## knob, render 40 frames, self-screenshot to /tmp/probe_shot.png, quit.
## Usage: godot --path . --rendering-driver opengl3 -s res://tests/mila/probe_render.gd -- [flags]
## Flags: --glow-off --shadows-off --hide-crowd --opaque --env-off --no-billboard --show-only=NODENAME
var _frames := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ps: PackedScene = load("res://scenes/show_stage/show_stage.tscn")
	var st = ps.instantiate()
	root.add_child(st)
	root.content_scale_size = Vector2i(1280, 720)
	if "--env-off" in args:
		var env := _find_env(st)
		if env != null:
			env.environment = null
			print("environment removed")
	elif "--glow-off" in args:
		var env := _find_env(st)
		if env != null and env.environment != null:
			env.environment.glow_enabled = false
			print("glow disabled")
	if "--shadows-off" in args: _walk_shadows(st)
	if "--hide-crowd" in args:
		for path in ["Audience/Crowd", "Audience/Glowsticks", "StarCloth/Stars"]:
			var n := st.get_node_or_null(path)
			if n != null:
				n.hide(); print("hidden ", path)
	if "--opaque" in args: _walk_opaque(st)
	for a in args:
		if a.begins_with("--show-only="):
			_show_only(st, a.trim_prefix("--show-only="))
	print("probe ready, args=", args)

func _find_env(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment: return n
	for c in n.get_children():
		var r := _find_env(c)
		if r != null: return r
	return null

func _walk_shadows(n: Node) -> void:
	if n is DirectionalLight3D or n is SpotLight3D or n is OmniLight3D:
		n.shadow_enabled = false
	for c in n.get_children(): _walk_shadows(c)

func _walk_opaque(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = mi.material_override.duplicate()
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			mi.material_override = m
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(s)
				if sm is StandardMaterial3D and sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					var d: StandardMaterial3D = sm.duplicate()
					d.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					mi.mesh.surface_set_material(s, d)
	for c in n.get_children(): _walk_opaque(c)

func _show_only(st: Node, keep_csv: String) -> void:
	var keep := keep_csv.split(",")
	_hide_except(st, keep, [])

func _hide_except(n: Node, keep: PackedStringArray, path: Array) -> void:
	for c in n.get_children():
		var p := path.duplicate(); p.append(c.name)
		var inside := false
		for k in keep:
			if String(c.name) == k or p.has(k):
				inside = true
		if c is VisualInstance3D and not inside and keep.size() > 0:
			var hit := false
			for k in keep:
				if String(c.name).begins_with(k): hit = true
			if not hit: (c as VisualInstance3D).hide()
		_hide_except(c, keep, p)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 10:
		var st := root.get_node_or_null("ShowStage")
		if st != null:
			for path in ["StarCloth/Stars", "Audience/Crowd", "Audience/Glowsticks"]:
				var mi := st.get_node_or_null(path) as MultiMeshInstance3D
				if mi != null and mi.multimesh != null:
					print("MM ", path, " count=", mi.multimesh.instance_count, " buf=", mi.multimesh.buffer.size(), " T0=", mi.multimesh.get_instance_transform(0).origin)
	if _frames == 40:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/probe_shot.png")
		print("shot saved ", img.get_size())
		quit()
	return false
