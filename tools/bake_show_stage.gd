extends SceneTree
## Authoring tool, run once by hand, NOT at runtime:
##   godot --headless --path . -s res://tools/bake_show_stage.gd
## Builds the studio set and writes it to scenes/show_stage/show_stage.tscn.
## After baking, the .tscn is the source of truth: edit it in the editor.
## (Re-baking overwrites hand edits; keep this only for bulk re-layouts.)

const OUT := "res://scenes/show_stage/show_stage.tscn"


class Builder extends ShowStage:
	func _ready() -> void:
		pass

	func build() -> void:
		_cosmetic.seed = 20260927
		_apply_camera()
		_build_environment()
		_build_world_containers()
		_build_hall()
		_build_set()
		_build_star_cloth()
		_build_beams()
		_build_audience()
		_build_colliders()
		_build_marks()
		_build_pips()
		var props := Node3D.new()
		props.name = "Props"
		add_child(props)

	func _build_environment() -> void:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.012, 0.016, 0.045)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.22, 0.29, 0.52)
		env.ambient_light_energy = 0.55
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.glow_enabled = true
		env.glow_intensity = 0.45
		env.glow_bloom = 0.05
		var we := WorldEnvironment.new()
		we.environment = env
		add_child(we)


	## Stands the moving parts under stable names: the stage manager's own
	## containers, so portraits and props never land under the show furniture.
	func _build_world_containers() -> void:
		var world := Node3D.new()
		world.name = "World3D"
		add_child(world)
		var chars := Node3D.new()
		chars.name = "Characters"
		world.add_child(chars)


	func _build_hall() -> void:
		# The house floor the audience sits on.
		var floor_mesh := BoxMesh.new()
		floor_mesh.size = Vector3(40.0, 0.1, 20.0)
		var floor_mi := _mesh_instance(floor_mesh, _mat(Color(0.015, 0.02, 0.05), 0.95), self)
		floor_mi.position = Vector3(0, -0.05, 5.0)


	## The set proper: the round platform and its glowing rim, and the dark wings
	## that keep the eye on the stage. Nothing is placed where it would crop
	## against the camera frame — the arena is the whole picture.
	func _build_set() -> void:
		_set_root = Node3D.new()
		_set_root.name = "Set"
		add_child(_set_root)

		var platform := CylinderMesh.new()
		platform.top_radius = STAGE_RADIUS
		platform.bottom_radius = STAGE_RADIUS + 0.18
		platform.height = STAGE_TOP
		platform.radial_segments = 64
		var plat_mi := _mesh_instance(platform, _mat(Color(0.07, 0.08, 0.17), 0.55, 0.25), _set_root)
		plat_mi.name = "Platform"
		plat_mi.position = Vector3(0, STAGE_TOP * 0.5, 0)

		var rim := TorusMesh.new()
		rim.inner_radius = STAGE_RADIUS - 0.05
		rim.outer_radius = STAGE_RADIUS + 0.07
		rim.rings = 64
		var rim_mi := _mesh_instance(rim, _mat(Color(0.2, 0.5, 0.8), 0.3, 0.6, Color(0.3, 0.75, 1.0), 1.7), _set_root)
		rim_mi.name = "Rim"
		rim_mi.position = Vector3(0, STAGE_TOP, 0)

		# A soft inlay disc so the floor is not one flat colour: the show's floor
		# plan, drawn as a ring of faint wedges.
		var inlay := CylinderMesh.new()
		inlay.top_radius = STAGE_RADIUS * 0.62
		inlay.bottom_radius = STAGE_RADIUS * 0.62
		inlay.height = 0.02
		inlay.radial_segments = 48
		var inlay_mi := _mesh_instance(inlay, _mat(Color(0.09, 0.11, 0.22), 0.7), _set_root)
		inlay_mi.position = Vector3(0, STAGE_TOP + 0.005, 0.35)
		var inlay_rim := TorusMesh.new()
		inlay_rim.inner_radius = STAGE_RADIUS * 0.62 - 0.02
		inlay_rim.outer_radius = STAGE_RADIUS * 0.62 + 0.02
		inlay_rim.rings = 48
		var ir_mi := _mesh_instance(inlay_rim, _mat(Color(0.3, 0.6, 0.9), 0.4, 0.5, Color(0.25, 0.6, 0.95), 0.9), _set_root)
		ir_mi.position = Vector3(0, STAGE_TOP + 0.01, 0.35)

		# Wings: dark masses at the far left and right, well outside the frame's
		# readable area, so the studio has depth without crowding the shot.
		var wing_mat := _mat(Color(0.03, 0.035, 0.085), 0.9, 0.1, Color(0.06, 0.12, 0.28), 0.18)
		for sx in [-1.0, 1.0]:
			var wing := BoxMesh.new()
			wing.size = Vector3(1.2, 4.2, 3.4)
			var wm := _mesh_instance(wing, wing_mat, _set_root)
			wm.position = Vector3(4.6 * sx, 2.1, 1.6)
			var drape := BoxMesh.new()
			drape.size = Vector3(0.16, 3.6, 1.9)
			var dm := _mesh_instance(drape, _mat(Color(0.13, 0.06, 0.24), 0.75, 0.2), _set_root)
			dm.position = Vector3(4.02 * sx, 1.8, 2.6)


	## The back wall: a star cloth and the show sign, with the prize board below.
	func _build_star_cloth() -> void:
		var cloth := Node3D.new()
		cloth.name = "StarCloth"
		add_child(cloth)

		var backdrop := BoxMesh.new()
		backdrop.size = Vector3(18.0, 7.4, 0.2)
		var bm := _mesh_instance(backdrop, _mat(Color(0.035, 0.045, 0.115), 0.9), cloth)
		bm.name = "Backdrop"
		bm.position = Vector3(0, 3.2, -3.9)

		var star_mm := MultiMesh.new()
		star_mm.transform_format = MultiMesh.TRANSFORM_3D
		star_mm.mesh = SphereMesh.new()
		(star_mm.mesh as SphereMesh).radius = 0.032
		(star_mm.mesh as SphereMesh).height = 0.064
		star_mm.instance_count = 64
		for i in 64:
			var pos := Vector3(_cosmetic.randf_range(-8.6, 8.6), _cosmetic.randf_range(0.8, 6.8), -3.78)
			star_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * _cosmetic.randf_range(0.6, 1.5)), pos))
		var star_mi := MultiMeshInstance3D.new()
		star_mi.name = "Stars"
		star_mi.multimesh = star_mm
		var star_mat := _mat(Color(0.8, 0.92, 1.0), 1.0, 0.0, Color(0.75, 0.9, 1.0), 1.7)
		star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		star_mi.material_override = star_mat
		cloth.add_child(star_mi)

		# The sign. The only thing on the back wall: the tagline lives on the
		# title card, and a second line of type up here only collided with the
		# word plaques.
		var sign := _label("KLIMA GEM", 160, Color(0.6, 0.92, 1.0), Color(0.02, 0.07, 0.18, 0.95), 0.0072)
		sign.name = "Sign"
		sign.position = Vector3(0, 3.62, -3.8)
		cloth.add_child(sign)


	## Lighting beams: additive cones that fade as they fall, so the stage is lit
	## by something the audience can see.
	func _build_beams() -> void:
		var beams := Node3D.new()
		beams.name = "Beams"
		add_child(beams)

		var beam_shader := Shader.new()
		beam_shader.code = """
	shader_type spatial;
	render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
	uniform vec4 beam_color : source_color = vec4(0.55, 0.80, 1.0, 1.0);
	uniform float strength : hint_range(0.0, 1.0) = 0.22;
	void fragment() {
		// Densest where the cone is deepest (top), and softest at the silhouette
		// so the beam has no hard tube edge.
		float depth = clamp(1.0 - UV.y, 0.0, 1.0);
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		ALBEDO = beam_color.rgb;
		ALPHA = strength * mix(0.35, 1.0, depth) * mix(0.30, 1.0, facing);
	}
	"""
		for sx in [-1.0, 0.0, 1.0]:
			var rig := Node3D.new()
			beams.add_child(rig)
			rig.position = Vector3(1.72 * sx, 0.0, 1.15)
			var cone := CylinderMesh.new()
			cone.top_radius = 0.05
			cone.bottom_radius = 0.92
			cone.height = 3.9
			cone.radial_segments = 28
			cone.cap_top = false
			cone.cap_bottom = false
			var cmi := _mesh_instance(cone, _mat(Color(1, 1, 1), 1.0), rig)
			cmi.name = "Beam"
			var bm := ShaderMaterial.new()
			bm.shader = beam_shader
			bm.set_shader_parameter("beam_color", Color(0.58, 0.82, 1.0) if sx != 0.0 else Color(0.86, 0.92, 1.0))
			bm.set_shader_parameter("strength", 0.075 if sx != 0.0 else 0.10)
			cmi.material_override = bm
			cmi.position = Vector3(0, 3.1, 0)
			rig.rotation_degrees = Vector3(-6.0, 0, 4.0 * sx)
			cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var lamp := CylinderMesh.new()
			lamp.top_radius = 0.11
			lamp.bottom_radius = 0.15
			lamp.height = 0.34
			var lmi := _mesh_instance(lamp, _mat(Color(0.15, 0.16, 0.24), 0.4, 0.8, Color(0.6, 0.85, 1.0), 1.2), rig)
			lmi.position = Vector3(0, 5.1, 0)

		# Truss across the top, out of frame but lighting the beams.
		var truss_mat := _mat(Color(0.1, 0.11, 0.2), 0.4, 0.7)
		for z in [-0.4, 2.4]:
			var beam := BoxMesh.new()
			beam.size = Vector3(8.4, 0.12, 0.12)
			var bmi := _mesh_instance(beam, truss_mat, beams)
			bmi.position = Vector3(0, 5.3, z)

		_key_light = OmniLight3D.new()
		_key_light.name = "KeyLight"
		_key_light.position = Vector3(0, 4.4, 3.4)
		_key_light.light_color = Color(1.0, 0.96, 0.88)
		_key_light.light_energy = 1.35
		_key_light.omni_range = 12.0
		add_child(_key_light)
		var rim := OmniLight3D.new()
		rim.position = Vector3(0, 3.4, -3.2)
		rim.light_color = Color(0.5, 0.75, 1.0)
		rim.light_energy = 1.0
		rim.omni_range = 11.0
		add_child(rim)
		var fill := OmniLight3D.new()
		fill.position = Vector3(3.2, 1.8, 4.4)
		fill.light_color = Color(0.72, 0.62, 1.0)
		fill.light_energy = 0.7
		fill.omni_range = 9.0
		add_child(fill)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-52, 24, 0)
		sun.light_color = Color(0.75, 0.82, 1.0)
		sun.light_energy = 0.18
		add_child(sun)


	func _build_audience() -> void:
		var crowd := Node3D.new()
		crowd.name = "Audience"
		add_child(crowd)
		var cap := CapsuleMesh.new()
		cap.radius = 0.19
		cap.height = 0.92
		var body_mm := MultiMesh.new()
		body_mm.transform_format = MultiMesh.TRANSFORM_3D
		body_mm.mesh = cap
		var spots: Array[Vector3] = []
		var count := 0
		for row in 3:
			var z := 5.5 + 0.8 * row
			var y := 0.26 + 0.26 * row
			var n := 10 - row
			for i in n:
				var x := -4.8 + 9.6 * float(i) / float(n - 1) + _cosmetic.randf_range(-0.25, 0.25)
				spots.append(Vector3(x, y, z + _cosmetic.randf_range(-0.2, 0.2)))
				count += 1
		body_mm.instance_count = count
		for i in count:
			body_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))
		var body_mi := MultiMeshInstance3D.new()
		body_mi.multimesh = body_mm
		# Silhouettes: darker than the hall, so the stage stays the brightest thing.
		body_mi.material_override = _mat(Color(0.02, 0.025, 0.065), 0.95)
		crowd.add_child(body_mi)

		# Glowsticks: little unshaded colour bars held up in the dark.
		var stick := BoxMesh.new()
		stick.size = Vector3(0.032, 0.22, 0.032)
		var stick_mm := MultiMesh.new()
		stick_mm.transform_format = MultiMesh.TRANSFORM_3D
		stick_mm.mesh = stick
		stick_mm.use_colors = true
		var stick_colors := [Color(0.4, 0.9, 1.0), Color(1.0, 0.5, 0.85), Color(1.0, 0.85, 0.4), Color(0.6, 1.0, 0.6)]
		stick_mm.instance_count = 26
		for i in 26:
			var base := spots[_cosmetic.randi_range(0, spots.size() - 1)]
			var t := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, _cosmetic.randf_range(-0.5, 0.5)), base + Vector3(_cosmetic.randf_range(-0.26, 0.26), 0.36, 0.1))
			stick_mm.set_instance_transform(i, t)
			stick_mm.set_instance_color(i, stick_colors[_cosmetic.randi_range(0, stick_colors.size() - 1)])
		var stick_mi := MultiMeshInstance3D.new()
		stick_mi.multimesh = stick_mm
		var stick_mat := StandardMaterial3D.new()
		stick_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		stick_mat.vertex_color_use_as_albedo = true
		stick_mi.material_override = stick_mat
		crowd.add_child(stick_mi)


	## Static bodies for everything a thrown gem can land on, plus a net far
	## below the house floor so a wild throw can never fall out of the world.
	func _build_colliders() -> void:
		var physics := Node3D.new()
		physics.name = "Physics"
		add_child(physics)

		var platform_body := StaticBody3D.new()
		platform_body.name = "PlatformBody"
		physics.add_child(platform_body)
		var platform_shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = STAGE_RADIUS
		cyl.height = STAGE_TOP
		platform_shape.shape = cyl
		platform_body.add_child(platform_shape)
		platform_body.position = Vector3(0, STAGE_TOP * 0.5, 0)
		platform_body.physics_material_override = _gem_physics_material(0.5)
		platform_body.collision_layer = 1
		platform_body.collision_mask = 0

		# The closed throw box: four glass walls and a lid over the platform.
		var box := StaticBody3D.new()
		box.name = "ThrowBox"
		physics.add_child(box)
		box.position = BOX_CENTER
		box.physics_material_override = _gem_physics_material(0.35)
		box.collision_layer = 1
		box.collision_mask = 0
		var t := 0.2
		var walls := {
			"WallLeft": [Vector3(-BOX_HALF.x - t * 0.5, 0, 0), Vector3(t, BOX_HALF.y * 2.0, BOX_HALF.z * 2.0)],
			"WallRight": [Vector3(BOX_HALF.x + t * 0.5, 0, 0), Vector3(t, BOX_HALF.y * 2.0, BOX_HALF.z * 2.0)],
			"WallBack": [Vector3(0, 0, -BOX_HALF.z - t * 0.5), Vector3(BOX_HALF.x * 2.0, BOX_HALF.y * 2.0, t)],
			"WallFront": [Vector3(0, 0, BOX_HALF.z + t * 0.5), Vector3(BOX_HALF.x * 2.0, BOX_HALF.y * 2.0, t)],
			"Lid": [Vector3(0, BOX_HALF.y + t * 0.5, 0), Vector3(BOX_HALF.x * 2.0, t, BOX_HALF.z * 2.0)],
		}
		for wall_name in walls:
			var cs := CollisionShape3D.new()
			cs.name = wall_name
			var bs := BoxShape3D.new()
			bs.size = walls[wall_name][1]
			cs.shape = bs
			cs.position = walls[wall_name][0]
			box.add_child(cs)
		# Its floor outline glows faintly so the audience sees the arena.
		var outline_mat := _mat(Color(0.4, 0.85, 1.0), 0.4, 0.0, Color(0.4, 0.85, 1.0), 1.2)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var post := CylinderMesh.new()
				post.top_radius = 0.018
				post.bottom_radius = 0.018
				post.height = BOX_HALF.y * 2.0
				var pm := _mesh_instance(post, outline_mat, box)
				pm.name = "Post"
				pm.position = Vector3(BOX_HALF.x * sx, 0, BOX_HALF.z * sz)

		var net := StaticBody3D.new()
		net.name = "SafetyNet"
		physics.add_child(net)
		var net_shape := CollisionShape3D.new()
		var net_box := BoxShape3D.new()
		net_box.size = Vector3(60.0, 0.5, 40.0)
		net_shape.shape = net_box
		net.add_child(net_shape)
		net.position = Vector3(0, -6.0, 4.0)
		net.collision_layer = 1
		net.collision_mask = 0


	func _gem_physics_material(bounce: float) -> PhysicsMaterial:
		var pm := PhysicsMaterial.new()
		pm.bounce = bounce
		pm.friction = 0.8
		return pm


	func _build_marks() -> void:
		var marks := Node3D.new()
		marks.name = "Marks"
		add_child(marks)
		var disc := CylinderMesh.new()
		disc.top_radius = 0.42
		disc.bottom_radius = 0.42
		disc.height = 0.015
		var mi := _mesh_instance(disc, _mat(Color(1.0, 0.55, 0.85), 0.3, 0.4, Color(1.0, 0.55, 0.85), 0.9), marks)
		mi.name = "AuroraMark"
		mi.position = AURORA_MARK + Vector3(0, 0.012, 0)


	func _build_pips() -> void:
		var pips := Node3D.new()
		pips.name = "StarPips"
		add_child(pips)
		for i in 3:
			var pip := FlatTopGemScript.new()
			pip.name = "Pip%d" % i
			pip.build_words = false
			pip.gem_color = Color(0.16, 0.18, 0.26, 0.8)
			pip.girdle_radius = 0.17
			pip.table_radius = 0.085
			pip.crown_height = 0.07
			pip.pavilion_height = 0.19
			pip.position = PIP_BASE + PIP_STEP * float(i)
			pip.rotation_degrees = Vector3(0, -18, 0)
			pips.add_child(pip)
			_pips.append(pip.body)


	func _apply_camera() -> void:
		_camera = get_node_or_null("Camera3D") as Camera3D
		if _camera == null:
			_camera = Camera3D.new()
			_camera.name = "Camera3D"
			add_child(_camera)
		_camera.position = CAM_POS
		_camera.rotation_degrees = Vector3(CAM_PITCH_DEG, 0.0, 0.0)
		_camera.fov = CAM_FOV
		_camera.current = true
		_camera.far = 60.0




func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		# Gems build their own mesh at runtime; only the gem node is authored.
		if not (child is FlatTopGem):
			_own(child, root)


func _init() -> void:
	var b := Builder.new()
	b.name = "ShowStage"
	b.build()
	b.set_script(load("res://scenes/show_stage/show_stage.gd"))
	_own(b, b)
	var packed := PackedScene.new()
	var err := packed.pack(b)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("BAKE: ", "OK" if err == OK else "FAIL %d" % err)
	b.free()
	quit(0 if err == OK else 1)
