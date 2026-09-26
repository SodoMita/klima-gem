extends SceneTree

const MODEL_PATHS := [
	"res://assets/models/nature/CommonTree_3.gltf",
	"res://assets/models/nature/Pine_5.gltf",
	"res://assets/models/nature/Bush_Common.gltf",
	"res://assets/models/nature/Bush_Common_Flowers.gltf",
	"res://assets/models/nature/Fern_1.gltf",
	"res://assets/models/nature/Flower_3_Group.gltf",
	"res://assets/models/nature/Grass_Common_Tall.gltf",
	"res://assets/models/nature/Mushroom_Common.gltf",
	"res://assets/models/nature/Rock_Medium_1.gltf",
	"res://assets/models/nature/RockPath_Round_Wide.gltf",
]

var failures := 0


func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	var preview := load("res://scenes/nature_showcase.tscn") as PackedScene
	if preview == null:
		_fail("nature_showcase.tscn did not load as a PackedScene")
	else:
		preview.instantiate().free()

	var textured_models := 0
	for model_path in MODEL_PATHS:
		var packed := load(model_path) as PackedScene
		if packed == null:
			_fail("model did not import as a PackedScene: %s" % model_path)
			continue

		var instance := packed.instantiate()
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(instance, meshes)
		var has_texture := false
		for mesh_instance in meshes:
			if mesh_instance.mesh == null:
				continue
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface)
				if material is BaseMaterial3D and material.albedo_texture != null:
					has_texture = true
					break
			if has_texture:
				break
		instance.free()
		if not has_texture:
			_fail("no decoded WebP albedo texture on model: %s" % model_path)
		else:
			textured_models += 1

	if failures == 0:
		print("Nature showcase OK: preview scene loads; %d glTF models have decoded WebP materials." % textured_models)
	quit(0 if failures == 0 else 1)


func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_meshes(child, result)


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
