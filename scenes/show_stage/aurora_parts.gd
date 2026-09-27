class_name AuroraPartsRig
extends Node3D
## Aurora as nine separately transformable body-part layers, one per word on
## the BODY PART gem: BACK, LEGS, SKIN, HAIR, MILK, HANDS, EYES, VOICE, HEART.
##
## Placeholders drawn from scratch by tools/draw_body_parts.py onto one shared
## 768x1376 canvas, so the nine Sprite3DQuad layers here stack pixel-perfectly
## (human directive: no mask slices of the painted sprite, lossless WebP only).
## An artist repaints any assets/characters/parts/*.webp at the same canvas
## size and the rig picks it up unchanged.
##
## A modification transforms ONLY the layer the gem named: GIANT HANDS grows
## the hands, GLASS MILK turns the bust translucent, and shifts staying on the
## body across trials simply keep their layer styled. Repeats compound like
## the edge math: x2 doubles the transform, x3+ also warms to gold.
##
## The rig speaks the small protocol the show already uses on the portrait
## quad: world_height, modulate, position. Everything else is opt-in.

const PARTS_DIR := "res://assets/characters/parts/"
const LAYER_STEP := 0.0032
const SPRITE_QUAD := preload("res://scenes/motion/sprite_3d_quad.gd")

## Per-shift look of the named layer. scale is (x, y) around the part pivot
## from parts.json, tint multiplies the layer, yoff is a fraction of height.
const MOD_STYLE := {
	"GIANT": {"scale": Vector2(1.45, 1.45)},
	"MEGA": {"scale": Vector2(1.62, 1.62), "tint": Color(1.22, 1.0, 0.94)},
	"TINY": {"scale": Vector2(0.62, 0.62)},
	"STICKY": {"scale": Vector2(1.10, 0.92), "tint": Color(0.88, 1.18, 0.95)},
	"BOUNCY": {"scale": Vector2(1.14, 0.86)},
	"GLASS": {"tint": Color(0.88, 1.06, 1.35, 0.45)},
	"MAGNET": {"tint": Color(1.16, 0.90, 1.36), "yoff": 0.016},
	"HEAVY": {"scale": Vector2(1.06, 0.84), "tint": Color(0.72, 0.70, 0.86), "yoff": -0.028},
	"GLOWING": {"tint": Color(1.38, 1.62, 1.52)},
}

## Mastered shifts warm toward stage gold.
const STACK_GOLD := Color(1.30, 1.18, 0.72)

@export var world_height: float = 1.68:
	set(value):
		world_height = maxf(value, 0.001)
		_relayout()

@export var modulate: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		modulate = value
		_push_modulate()

var _meta: Dictionary = {}
var _quads: Dictionary = {}
var _part_tint: Dictionary = {}
var _aspect := 0.558
var _expression := "neutral"
var _mods: Dictionary = {}
var _stacks: Dictionary = {}


static func parts_available() -> bool:
	return ResourceLoader.exists(PARTS_DIR + "skin.webp") and FileAccess.file_exists(PARTS_DIR + "parts.json")


func _ready() -> void:
	if _quads.is_empty():
		setup()


## Build one layer per part, back-to-front by the z written in parts.json.
func setup() -> void:
	if not _meta.is_empty():
		return
	var raw: String = FileAccess.get_file_as_string(PARTS_DIR + "parts.json")
	if raw.is_empty():
		push_warning("AuroraPartsRig: parts.json missing, run tools/draw_body_parts.py")
		return
	var data: Variant = JSON.parse_string(raw)
	if not (data is Dictionary):
		push_warning("AuroraPartsRig: parts.json unreadable")
		return
	var canvas_size: Array = (data as Dictionary).get("canvas", [768, 1376])
	_aspect = float(canvas_size[0]) / maxf(float(canvas_size[1]), 1.0)
	_meta = (data as Dictionary).get("parts", {})
	var order: Array = _meta.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return int(_meta[a].get("z", 0)) < int(_meta[b].get("z", 0)))
	for i in order.size():
		var part: String = order[i]
		var quad: Sprite3DQuad = SPRITE_QUAD.new()
		quad.name = "Part_%s" % part
		quad.bottom_anchored = true
		add_child(quad)
		quad.texture = _part_texture(part)
		quad.world_height = world_height
		_quads[part] = quad
		_part_tint[part] = Color(1, 1, 1, 1)
	_apply_expression()
	_apply_mods()


func expression() -> String:
	return _expression


## Swap the face layers (EYES and VOICE carry every stage expression; the
## other seven parts do not have faces, so nothing else changes texture).
func set_expression(emotion: String) -> void:
	var expr := emotion.trim_prefix("aurora_")
	_expression = expr
	if not _quads.is_empty():
		_apply_expression()


func part_quad(part: String) -> Sprite3DQuad:
	return _quads.get(part.to_upper()) as Sprite3DQuad


## The whole shift account: {PART: MOD} plus {MOD: times_applied}. Layers are
## restyled from scratch every call, so rollback re-dressing is idempotent.
func set_part_mods(mods: Dictionary, stacks: Dictionary = {}) -> void:
	_mods = {}
	for part in mods:
		_mods[str(part).to_upper()] = str(mods[part]).to_upper()
	_stacks = {}
	for mod in stacks:
		_stacks[str(mod).to_upper()] = int(stacks[mod])
	if not _quads.is_empty():
		_apply_mods()


func reset_mods() -> void:
	set_part_mods({})


func reset_all() -> void:
	reset_mods()
	modulate = Color(1, 1, 1, 1)


func _part_texture(part: String) -> Texture2D:
	var file := str(_meta.get(part, {}).get("file", "%s.webp" % part.to_lower()))
	return load(PARTS_DIR + file) as Texture2D


func _apply_expression() -> void:
	for part in _quads:
		var variants: Dictionary = _meta.get(part, {}).get("variants", {})
		var file := str(variants.get(_expression, _meta[part].get("file", "")))
		if file == "":
			continue
		var quad: Sprite3DQuad = _quads[part]
		var tex := load(PARTS_DIR + file) as Texture2D
		if tex != null:
			quad.texture = tex


func _relayout() -> void:
	for part in _quads:
		(_quads[part] as Sprite3DQuad).world_height = world_height
	_apply_mods()


func _push_modulate() -> void:
	for part in _quads:
		(_quads[part] as Sprite3DQuad).modulate = (_part_tint.get(part, Color(1, 1, 1, 1)) as Color) * modulate


## Restyle every layer from the current shift account.
func _apply_mods() -> void:
	if _quads.is_empty():
		return
	var w := world_height * _aspect
	for part in _quads:
		var quad: Sprite3DQuad = _quads[part]
		var meta: Dictionary = _meta.get(part, {})
		var z := int(meta.get("z", 0))
		var pivot: Array = meta.get("pivot", [0.5, 0.5])
		var scale := Vector2.ONE
		var yoff := 0.0
		var tint := Color(1, 1, 1, 1)
		var mod := str(_mods.get(part, ""))
		if mod != "" and MOD_STYLE.has(mod):
			var style: Dictionary = MOD_STYLE[mod]
			scale = style.get("scale", Vector2.ONE)
			yoff = float(style.get("yoff", 0.0))
			tint = style.get("tint", Color(1, 1, 1, 1))
			var n := int(_stacks.get(mod, 1))
			if n >= 2:
				var extra := 1.0 + 0.6 * (n - 1)
				scale = Vector2.ONE + (scale - Vector2.ONE) * extra
				yoff *= extra
			if n >= 3:
				# From the third copy on the body has adapted: stronger and gold.
				tint = tint.lerp(STACK_GOLD, 0.45)
		quad.scale = Vector3(scale.x, scale.y, 1.0)
		var px := (float(pivot[0]) - 0.5) * w
		var py := float(pivot[1]) * world_height
		quad.position = Vector3(px * (1.0 - scale.x), py * (1.0 - scale.y) + yoff * world_height, LAYER_STEP * z)
		_part_tint[part] = tint
	_push_modulate()
