class_name AuroraBody
extends RefCounted
## Aurora's portrait, cut into body parts so a shift lands on the part the
## gem named.
##
## The show pairs a BODY PART gem with a MODIFICATION gem. Eight parts times
## nine mods is seventy-two full-body plates per expression — nobody is
## painting that. So the portrait is split instead: the part named by the gem
## is lifted out of Aurora's own sprite as a layer, transformed (scaled,
## squashed, tinted, made translucent, made to glow), and composited back over
## the body with the hole it left erased. Nine layers, not seventy-two plates,
## and every combination reads differently on stage.
##
## Layer art can be overridden per pair: drop a keyed RGBA plate at
## [code]assets/characters/parts/plates/<part>_<mod>.webp[/code] (see
## [code]tools/gen_part_plates.py[/code], which feeds the cut-out crop of the
## real sprite to an image model) and the composer uses the painted plate
## instead of the procedural transform. Those plates are placeholders: an
## artist replaces the file, nothing else changes.

const PARTS: PackedStringArray = [
	"HANDS", "EYES", "LEGS", "VOICE", "HAIR", "BACK", "HEART", "SKIN",
]

const PLATE_DIR := "res://assets/characters/parts/plates/"

## Shapes are normalised to the sprite: cx, cy, rx, ry describe a soft ellipse
## and px, py the pivot the transform scales around (feet for SKIN, hips for
## LEGS, the shape centre otherwise). "behind" layers are drawn under the body.
const REGIONS := {
	"HANDS": {
		"shapes": [
			{"cx": 0.325, "cy": 0.476, "rx": 0.072, "ry": 0.072},
			{"cx": 0.684, "cy": 0.470, "rx": 0.072, "ry": 0.072},
		],
		"behind": false,
	},
	"EYES": {
		"shapes": [
			{"cx": 0.417, "cy": 0.128, "rx": 0.050, "ry": 0.030},
			{"cx": 0.556, "cy": 0.128, "rx": 0.050, "ry": 0.030},
		],
		"behind": false,
	},
	"LEGS": {
		"shapes": [
			{"cx": 0.500, "cy": 0.800, "rx": 0.190, "ry": 0.215, "px": 0.500, "py": 0.590},
		],
		"behind": false,
	},
	"VOICE": {
		"shapes": [
			{"cx": 0.487, "cy": 0.183, "rx": 0.058, "ry": 0.048},
		],
		"behind": false,
	},
	"HAIR": {
		"shapes": [
			{"cx": 0.255, "cy": 0.330, "rx": 0.185, "ry": 0.300, "px": 0.370, "py": 0.120},
			{"cx": 0.752, "cy": 0.330, "rx": 0.185, "ry": 0.300, "px": 0.640, "py": 0.120},
			{"cx": 0.500, "cy": 0.085, "rx": 0.165, "ry": 0.085, "px": 0.500, "py": 0.150},
		],
		"behind": false,
	},
	"BACK": {
		"shapes": [
			{"cx": 0.500, "cy": 0.350, "rx": 0.245, "ry": 0.235},
		],
		"behind": true,
	},
	"HEART": {
		"shapes": [
			{"cx": 0.500, "cy": 0.300, "rx": 0.092, "ry": 0.080},
		],
		"behind": false,
	},
	"SKIN": {
		"shapes": [
			{"cx": 0.500, "cy": 0.500, "rx": 0.520, "ry": 0.520, "px": 0.500, "py": 0.975},
		],
		"behind": false,
	},
}

## What a modification does to whatever layer it is welded to. Scale, squash,
## drift, tint, translucency and glow are per layer, so GIANT HANDS and GIANT
## LEGS are different silhouettes, not the same wash.
const EFFECTS := {
	"GIANT": {"sx": 1.55, "sy": 1.55, "tint": Color(1.0, 0.83, 0.36), "mix": 0.20, "glow": 0.25},
	"TINY": {"sx": 0.52, "sy": 0.52, "tint": Color(0.60, 0.88, 1.0), "mix": 0.18},
	"STICKY": {"sx": 1.08, "sy": 1.02, "tint": Color(0.46, 0.94, 0.66), "mix": 0.38, "drip": 0.09},
	"BOUNCY": {"sx": 1.28, "sy": 0.82, "tint": Color(1.0, 0.66, 0.42), "mix": 0.30},
	"GLASS": {"sx": 1.0, "sy": 1.0, "tint": Color(0.70, 0.93, 1.0), "mix": 0.30, "alpha": 0.42, "glow": 0.18},
	"MAGNET": {"sx": 1.04, "sy": 1.04, "tint": Color(0.52, 0.38, 0.72), "mix": 0.45, "dark": 0.20},
	"HEAVY": {"sx": 1.18, "sy": 0.92, "dy": 0.022, "tint": Color(0.42, 0.45, 0.55), "mix": 0.42, "dark": 0.28},
	"GLOWING": {"sx": 1.06, "sy": 1.06, "tint": Color(0.40, 0.98, 0.94), "mix": 0.35, "glow": 0.85},
	"MEGA": {"sx": 1.95, "sy": 1.95, "tint": Color(1.0, 0.65, 0.55), "mix": 0.28, "glow": 0.55},
}

static var _cache: Dictionary = {}

## Signature for the cache: the expression plus every part/mod pair applied.
static func signature(base_key: String, mods: Dictionary) -> String:
	var keys: Array = mods.keys()
	keys.sort()
	var bits := PackedStringArray()
	for k in keys:
		bits.append("%s=%s" % [str(k).to_upper(), str(mods[k]).to_upper()])
	return base_key + "|" + "|".join(bits)


static func clear_cache() -> void:
	_cache.clear()


static func has_region(part: String) -> bool:
	return REGIONS.has(part.to_upper())


static func plate_path(part: String, mod: String) -> String:
	return PLATE_DIR + "%s_%s.webp" % [part.to_lower(), mod.to_lower()]


## Keep only the pairs this composer can actually draw.
static func usable_mods(mods: Dictionary) -> Dictionary:
	var applied: Dictionary = {}
	for key in mods.keys():
		var part := str(key).to_upper()
		var mod := str(mods[key]).to_upper()
		if REGIONS.has(part) and EFFECTS.has(mod):
			applied[part] = mod
	return applied


## Build the portrait: Aurora's own sprite with one layer per applied pair.
## Returns [param base] unchanged when there is nothing to do, so a show with
## no shifts still draws the untouched, artist-made texture.
static func compose(base_key: String, base: Texture2D, mods: Dictionary) -> Texture2D:
	if base == null:
		return base
	var applied := usable_mods(mods)
	if applied.is_empty():
		return base
	var sig := signature(base_key, applied)
	if _cache.has(sig):
		return _cache[sig]
	var source: Image = base.get_image()
	if source == null:
		return base
	source = source.duplicate()
	if source.is_compressed():
		source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var w := source.get_width()
	var h := source.get_height()
	var src_data := source.get_data()
	var body_data := source.get_data()
	var behind := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var front := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var parts: Array = applied.keys()
	parts.sort()
	for part in parts:
		var mod: String = applied[part]
		var region: Dictionary = REGIONS[part]
		var canvas: Image = behind if bool(region.get("behind", false)) else front
		for shape in region["shapes"]:
			_stamp_shape(src_data, body_data, w, h, canvas, shape as Dictionary, str(part), mod)
	var body := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, body_data)
	var out := behind
	out.blend_rect(body, Rect2i(0, 0, w, h), Vector2i.ZERO)
	out.blend_rect(front, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var tex := ImageTexture.create_from_image(out)
	tex.set_meta("aurora_base_key", base_key)
	tex.set_meta("aurora_body_mods", applied.duplicate())
	tex.set_meta("aurora_part_layers", applied.size())
	_cache[sig] = tex
	return tex


## Lift one shape out of the sprite, transform it, erase the hole it left and
## paste the result on the layer canvas.
static func _stamp_shape(src_data: PackedByteArray, body_data: PackedByteArray, w: int, h: int, canvas: Image, shape: Dictionary, part: String, mod: String) -> void:
	var effect: Dictionary = EFFECTS[mod]
	var cx := float(shape.get("cx", 0.5)) * w
	var cy := float(shape.get("cy", 0.5)) * h
	var rx := maxf(2.0, float(shape.get("rx", 0.1)) * w)
	var ry := maxf(2.0, float(shape.get("ry", 0.1)) * h)
	var px := float(shape.get("px", shape.get("cx", 0.5))) * w
	var py := float(shape.get("py", shape.get("cy", 0.5))) * h
	var x0 := int(maxf(0.0, floorf(cx - rx)))
	var y0 := int(maxf(0.0, floorf(cy - ry)))
	var x1 := int(minf(float(w), ceilf(cx + rx) + 1.0))
	var y1 := int(minf(float(h), ceilf(cy + ry) + 1.0))
	if x1 <= x0 or y1 <= y0:
		return
	var lw := x1 - x0
	var lh := y1 - y0
	var tint: Color = effect.get("tint", Color.WHITE)
	var mix := float(effect.get("mix", 0.0))
	var dark := float(effect.get("dark", 0.0))
	var layer_alpha := float(effect.get("alpha", 1.0))
	var cut: bool = float(effect.get("sx", 1.0)) != 1.0 or float(effect.get("sy", 1.0)) != 1.0 \
		or layer_alpha < 0.999 or float(effect.get("dy", 0.0)) != 0.0
	# Bytes, not Colors: the composer runs on rollback and quick-load, so the
	# cut is done on raw RGBA8 rows instead of a million get_pixel() calls.
	var layer_data := PackedByteArray()
	layer_data.resize(lw * lh * 4)
	var tr := tint.r * 255.0
	var tg := tint.g * 255.0
	var tb := tint.b * 255.0
	for y in range(y0, y1):
		var ny := (float(y) + 0.5 - cy) / ry
		var ny2 := ny * ny
		var row := y * w * 4
		var lrow := (y - y0) * lw * 4
		for x in range(x0, x1):
			var nx := (float(x) + 0.5 - cx) / rx
			var d := sqrt(nx * nx + ny2)
			if d >= 1.0:
				continue
			var mask := clampf((1.0 - d) / 0.22, 0.0, 1.0)
			var i := row + x * 4
			var a := src_data[i + 3]
			if a == 0:
				continue
			var r := float(src_data[i])
			var g := float(src_data[i + 1])
			var b := float(src_data[i + 2])
			r = lerpf(lerpf(r, tr, mix), 12.0, dark)
			g = lerpf(lerpf(g, tg, mix), 15.0, dark)
			b = lerpf(lerpf(b, tb, mix), 23.0, dark)
			var o := lrow + (x - x0) * 4
			layer_data[o] = int(r)
			layer_data[o + 1] = int(g)
			layer_data[o + 2] = int(b)
			layer_data[o + 3] = int(float(a) * mask * layer_alpha)
			if cut:
				body_data[i + 3] = int(float(body_data[i + 3]) * (1.0 - mask))
	var layer := Image.create_from_data(lw, lh, false, Image.FORMAT_RGBA8, layer_data)
	var plate := _load_plate(part, mod)
	if plate != null:
		plate.resize(lw, lh, Image.INTERPOLATE_BILINEAR)
		layer = plate
	var sx := float(effect.get("sx", 1.0))
	var sy := float(effect.get("sy", 1.0))
	var tw := int(maxf(1.0, roundf(lw * sx)))
	var th := int(maxf(1.0, roundf(lh * sy)))
	if tw != lw or th != lh:
		layer.resize(tw, th, Image.INTERPOLATE_BILINEAR)
	# Keep the pivot nailed down: the part grows away from the joint, never
	# off the shoulder.
	var ox := px - (px - float(x0)) * sx
	var oy := py - (py - float(y0)) * sy + float(effect.get("dy", 0.0)) * h
	var at := Vector2i(int(roundf(ox)), int(roundf(oy)))
	var glow := float(effect.get("glow", 0.0))
	if glow > 0.0:
		_blend_glow(canvas, layer, at, tint, glow)
	if float(effect.get("drip", 0.0)) > 0.0:
		_blend_drip(canvas, layer, at, tint, float(effect["drip"]) * h)
	canvas.blend_rect(layer, Rect2i(0, 0, tw, th), at)


## A soft, oversized copy behind the layer: cheap bloom that survives the
## portrait being a plain quad texture.
static func _blend_glow(canvas: Image, layer: Image, at: Vector2i, tint: Color, power: float) -> void:
	var gw := int(layer.get_width() * 1.22) + 2
	var gh := int(layer.get_height() * 1.22) + 2
	# Down then up: a bilinear round trip is the blur, and the tint is painted
	# on the tiny image, so a MEGA halo costs a few thousand pixels of work.
	var sw := maxi(4, gw / 8)
	var sh := maxi(4, gh / 8)
	var halo := layer.duplicate() as Image
	halo.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	var data := halo.get_data()
	var strength := clampf(power, 0.0, 1.0) * 0.55
	var tr := int(tint.r * 255.0)
	var tg := int(tint.g * 255.0)
	var tb := int(tint.b * 255.0)
	for p in range(0, data.size(), 4):
		data[p] = tr
		data[p + 1] = tg
		data[p + 2] = tb
		data[p + 3] = int(float(data[p + 3]) * strength)
	halo = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, data)
	halo.resize(gw, gh, Image.INTERPOLATE_BILINEAR)
	var off := Vector2i(at.x - int((gw - layer.get_width()) * 0.5), at.y - int((gh - layer.get_height()) * 0.5))
	canvas.blend_rect(halo, Rect2i(0, 0, gw, gh), off)


## STICKY leaves the part trailing strands.
static func _blend_drip(canvas: Image, layer: Image, at: Vector2i, tint: Color, length: float) -> void:
	var lw := layer.get_width()
	var lh := layer.get_height()
	var drop := int(maxf(3.0, length))
	var layer_data := layer.get_data()
	var strand_data := PackedByteArray()
	strand_data.resize(lw * drop * 4)
	var tr := int(tint.r * 255.0)
	var tg := int(tint.g * 255.0)
	var tb := int(tint.b * 255.0)
	for x in lw:
		if (x % 9) > 2:
			continue
		var bottom := -1
		for y in range(lh - 1, -1, -1):
			if layer_data[(y * lw + x) * 4 + 3] > 64:
				bottom = y
				break
		if bottom < 0:
			continue
		var run := int(drop * (0.4 + 0.6 * float((x * 37) % 11) / 11.0))
		for y in run:
			var fade := 1.0 - float(y) / float(drop)
			var o := (y * lw + x) * 4
			strand_data[o] = tr
			strand_data[o + 1] = tg
			strand_data[o + 2] = tb
			strand_data[o + 3] = int(140.0 * fade)
	var strands := Image.create_from_data(lw, drop, false, Image.FORMAT_RGBA8, strand_data)
	canvas.blend_rect(strands, Rect2i(0, 0, lw, drop), Vector2i(at.x, at.y + lh - 2))


static func _load_plate(part: String, mod: String) -> Image:
	var path := plate_path(part, mod)
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img
