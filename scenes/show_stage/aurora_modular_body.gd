class_name AuroraModularBody extends Node3D
## Nine-layer stage body for Aurora.
##
## Each layer is a direct-drawn transparent WebP. No full-body source plate,
## mask, crop, or generated combination is used. Body shifts change only the
## named layer, so combinations remain composable instead of requiring 81
## pre-rendered portraits (or many more once expressions are included).

const SpriteQuadScript := preload("res://scenes/motion/sprite_3d_quad.gd")
const ASSET_ROOT := "res://assets/characters/parts/aurora/"
const PART_ORDER: PackedStringArray = [
	"BACK", "LEGS", "SKIN", "MILK", "HEART", "HAIR", "EYES", "VOICE", "HANDS",
]
const EXPRESSIONS: PackedStringArray = ["serious", "surprised", "sad", "happy", "gorgeous"]
const STATIC_TEXTURES := {
	"BACK": ASSET_ROOT + "back.webp",
	"LEGS": ASSET_ROOT + "legs.webp",
	# Game words stay stable; art filenames state what they actually contain.
	"SKIN": ASSET_ROOT + "body.webp",
	"MILK": ASSET_ROOT + "breast.webp",
	"HEART": ASSET_ROOT + "heart.webp",
	"HAIR": ASSET_ROOT + "hair.webp",
	"HANDS": ASSET_ROOT + "hands.webp",
}

## Pivot positions in the shared 640x960 canvas. Scaling a sparse full-canvas
## texture around its center would make eyes/heart drift across the body;
## these pivots keep the visible named region pinned in place.
const PIVOTS := {
	"BACK": Vector2(0.50, 0.46),
	"LEGS": Vector2(0.50, 0.78),
	"SKIN": Vector2(0.50, 0.26),
	"MILK": Vector2(0.50, 0.53),
	"HEART": Vector2(0.50, 0.54),
	"HAIR": Vector2(0.50, 0.25),
	"EYES": Vector2(0.50, 0.27),
	"VOICE": Vector2(0.50, 0.35),
	"HANDS": Vector2(0.50, 0.59),
}

@export var world_height: float = 1.68:
	set(value):
		world_height = maxf(value, 0.1)
		for value_quad in _layers.values():
			var quad := value_quad as Sprite3DQuad
			if quad != null:
				quad.world_height = world_height
		_reapply_all_poses()

@export var expression: String = "serious"

var _layers: Dictionary = {}
var _mods: Dictionary = {}
var _base_scales: Dictionary = {}
var _base_offsets: Dictionary = {}
var _base_tints: Dictionary = {}
var _effect_time := 0.0


func _ready() -> void:
	_build_layers()
	set_expression(expression)
	apply_mods(_mods)


func _process(delta: float) -> void:
	_effect_time += delta
	for part_value in _mods:
		var part := str(part_value)
		var mod := str(_mods[part])
		var base_scale: Vector2 = _base_scales.get(part, Vector2.ONE)
		var base_offset: Vector2 = _base_offsets.get(part, Vector2.ZERO)
		var dynamic_scale := base_scale
		var dynamic_offset := base_offset
		match mod:
			"BOUNCY":
				var spring := sin(_effect_time * 7.0 + float(PART_ORDER.find(part)))
				dynamic_scale *= Vector2(1.0 - spring * 0.08, 1.0 + spring * 0.13)
				dynamic_offset.y -= absf(spring) * 0.016
			"MAGNET":
				dynamic_offset.x += sin(_effect_time * 4.5) * 0.014
			"STICKY":
				dynamic_scale.y *= 1.0 + 0.035 * sin(_effect_time * 2.4)
			"GLOWING":
				var pulse := 1.0 + 0.16 * (0.5 + 0.5 * sin(_effect_time * 5.0))
				_set_layer_tint(part, (_base_tints.get(part, Color.WHITE) as Color) * Color(pulse, pulse, pulse, 1.0))
		_apply_pose(part, dynamic_scale, dynamic_offset)


func _build_layers() -> void:
	if not _layers.is_empty():
		return
	for index in PART_ORDER.size():
		var part := PART_ORDER[index]
		var quad: Sprite3DQuad = SpriteQuadScript.new()
		quad.name = "Layer_%s" % part.capitalize()
		quad.world_height = world_height
		quad.bottom_anchored = true
		quad.alpha_scissor = 0.015
		quad.set_meta("aurora_part", part)
		add_child(quad)
		# Stable ordering without separating coplanar body parts in world space.
		var material := quad.material_override as Material
		if material != null:
			material.render_priority = index - 4
		_layers[part] = quad
	for part in STATIC_TEXTURES:
		_set_layer_texture(str(part), str(STATIC_TEXTURES[part]))


func set_expression(value: String) -> void:
	var next := value.to_lower()
	if next.begins_with("aurora_"):
		next = next.substr(7)
	if next not in EXPRESSIONS:
		next = "serious"
	expression = next
	if _layers.is_empty():
		return
	_set_layer_texture("EYES", ASSET_ROOT + "expressions/%s/eyes.webp" % expression)
	_set_layer_texture("VOICE", ASSET_ROOT + "expressions/%s/voice.webp" % expression)


func apply_mods(value: Dictionary) -> void:
	_mods = {}
	for part_value in value:
		var part := str(part_value).to_upper()
		var mod := str(value[part_value]).to_upper()
		if part in PART_ORDER and mod != "":
			_mods[part] = mod
	for part in PART_ORDER:
		_style_layer(part, str(_mods.get(part, "")))


func reset_mods() -> void:
	apply_mods({})


func mods() -> Dictionary:
	return _mods.duplicate(true)


func layer_count() -> int:
	return _layers.size()


func layer(part: String) -> Sprite3DQuad:
	return _layers.get(part.to_upper()) as Sprite3DQuad


func current_mod(part: String) -> String:
	return str(_mods.get(part.to_upper(), ""))


func _set_layer_texture(part: String, path: String) -> void:
	var quad := layer(part)
	if quad == null:
		return
	if not ResourceLoader.exists(path):
		push_warning("AuroraModularBody: missing %s layer at %s" % [part, path])
		return
	var next := load(path) as Texture2D
	if next != null:
		quad.texture = next


func _style_layer(part: String, mod: String) -> void:
	var scale_2d := Vector2.ONE
	var offset := Vector2.ZERO
	var tint := Color.WHITE
	match mod:
		"GIANT":
			scale_2d = Vector2(1.40, 1.38)
			tint = Color(1.18, 1.06, 0.78, 1.0)
		"TINY":
			scale_2d = Vector2(0.68, 0.68)
			tint = Color(0.82, 0.96, 1.14, 1.0)
		"STICKY":
			scale_2d = Vector2(1.07, 1.18)
			offset.y = 0.025
			tint = Color(0.70, 1.22, 0.78, 0.92)
		"BOUNCY":
			scale_2d = Vector2(1.10, 0.94)
			tint = Color(1.20, 0.91, 0.66, 1.0)
		"GLASS":
			scale_2d = Vector2(1.04, 1.04)
			tint = Color(0.76, 1.18, 1.42, 0.48)
		"MAGNET":
			scale_2d = Vector2(1.12, 1.04)
			tint = Color(1.16, 0.72, 1.36, 1.0)
		"HEAVY":
			scale_2d = Vector2(1.16, 0.80)
			offset.y = 0.045
			tint = Color(0.55, 0.58, 0.74, 1.0)
		"GLOWING":
			scale_2d = Vector2(1.08, 1.08)
			tint = Color(1.16, 1.48, 1.43, 1.0)
		"MEGA":
			scale_2d = Vector2(1.62, 1.58)
			tint = Color(1.36, 0.82, 0.96, 1.0)
	_base_scales[part] = scale_2d
	_base_offsets[part] = offset
	_base_tints[part] = tint
	_set_layer_tint(part, tint)
	_apply_pose(part, scale_2d, offset)


func _set_layer_tint(part: String, tint: Color) -> void:
	var quad := layer(part)
	if quad != null:
		quad.modulate = tint


func _apply_pose(part: String, scale_2d: Vector2, normalized_offset: Vector2) -> void:
	var quad := layer(part)
	if quad == null:
		return
	var normalized_pivot: Vector2 = PIVOTS.get(part, Vector2(0.5, 0.5))
	var aspect := 2.0 / 3.0 # shared 640x960 canvas
	var pivot := Vector3(
		(normalized_pivot.x - 0.5) * world_height * aspect,
		(1.0 - normalized_pivot.y) * world_height,
		0.0
	)
	var scale_3d := Vector3(scale_2d.x, scale_2d.y, 1.0)
	var offset := Vector3(
		normalized_offset.x * world_height * aspect,
		-normalized_offset.y * world_height,
		0.0
	)
	quad.scale = scale_3d
	quad.position = pivot - Vector3(pivot.x * scale_3d.x, pivot.y * scale_3d.y, 0.0) + offset


func _reapply_all_poses() -> void:
	if _layers.is_empty():
		return
	for part in PART_ORDER:
		_apply_pose(
			part,
			_base_scales.get(part, Vector2.ONE),
			_base_offsets.get(part, Vector2.ZERO)
		)
