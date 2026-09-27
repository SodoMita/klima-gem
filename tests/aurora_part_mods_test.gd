extends Node
## The body-part gem has to be visible on the body.
##
## Every part x mod pair must (a) change the portrait, (b) change it inside the
## region the gem named, (c) differ from the same mod on another part and from
## another mod on the same part. That is the whole promise of the two gems: the
## audience can read the pairing off Aurora without the chip.

const PARTS := ["HANDS", "EYES", "LEGS", "VOICE", "HAIR", "BACK", "HEART", "SKIN"]
const MODS := ["GIANT", "TINY", "STICKY", "BOUNCY", "GLASS", "MAGNET", "HEAVY", "GLOWING", "MEGA"]
const BASE := "res://assets/characters/aurora_serious.webp"

var failures := 0


func check(ok: bool, detail: String) -> void:
	if ok:
		print("  ok: ", detail)
	else:
		failures += 1
		printerr("  FAIL: ", detail)


const PROBE := Vector2i(110, 184)


func _image(tex: Texture2D) -> Image:
	var img := tex.get_image()
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## A thumbnail is enough to prove a shift is visible, and keeps 72 pairings
## inside a headless test budget.
func _probe(tex: Texture2D) -> Image:
	var img := _image(tex)
	img.resize(PROBE.x, PROBE.y, Image.INTERPOLATE_BILINEAR)
	return img


## Mean absolute difference between two same-sized images, restricted to a
## normalised rect.
func _diff(a: Image, b: Image, area: Rect2 = Rect2(0, 0, 1, 1)) -> float:
	var w := a.get_width()
	var h := a.get_height()
	var x0 := int(area.position.x * w)
	var y0 := int(area.position.y * h)
	var x1 := mini(w, int((area.position.x + area.size.x) * w))
	var y1 := mini(h, int((area.position.y + area.size.y) * h))
	var pa := a.get_data()
	var pb := b.get_data()
	var total := 0.0
	var count := 0
	for y in range(y0, y1):
		var row := y * w * 4
		for x in range(x0, x1):
			var i := row + x * 4
			var aa := float(pa[i + 3]) / 255.0
			var ab := float(pb[i + 3]) / 255.0
			total += (absf(float(pa[i]) * aa - float(pb[i]) * ab) \
				+ absf(float(pa[i + 1]) * aa - float(pb[i + 1]) * ab) \
				+ absf(float(pa[i + 2]) * aa - float(pb[i + 2]) * ab)) / 255.0 \
				+ absf(aa - ab)
			count += 1
	return total / maxf(1.0, float(count))


func _region_rect(part: String) -> Rect2:
	var shapes: Array = AuroraBody.REGIONS[part]["shapes"]
	var lo := Vector2(1, 1)
	var hi := Vector2(0, 0)
	for shape in shapes:
		var d: Dictionary = shape
		lo.x = minf(lo.x, float(d["cx"]) - float(d["rx"]))
		lo.y = minf(lo.y, float(d["cy"]) - float(d["ry"]))
		hi.x = maxf(hi.x, float(d["cx"]) + float(d["rx"]))
		hi.y = maxf(hi.y, float(d["cy"]) + float(d["ry"]))
	# The transformed layer may grow outside its own region (GIANT, MEGA).
	var pad := Vector2(0.28, 0.28)
	lo = (lo - pad).clampf(0.0, 1.0)
	hi = (hi + pad).clampf(0.0, 1.0)
	return Rect2(lo, hi - lo)


func _ready() -> void:
	var base: Texture2D = load(BASE)
	check(base != null, "Aurora's original serious portrait loads")
	if base == null:
		get_tree().quit(1)
		return
	var original := _probe(base)
	check(AuroraBody.PARTS.size() == PARTS.size(), "the composer knows all eight body parts")

	var hashes: Dictionary = {}
	for part in PARTS:
		check(AuroraBody.has_region(part), "%s has a cut region on the sprite" % part)
		var per_part: Array[float] = []
		for mod in MODS:
			var tex := AuroraBody.compose("aurora_serious", base, {part: mod})
			if tex == null:
				check(false, "%s %s composes a portrait" % [part, mod])
				continue
			check(tex.get_size() == base.get_size(), "%s %s keeps the portrait's frame" % [part, mod])
			var img := _probe(tex)
			var whole := _diff(original, img)
			check(whole > 0.0004, "%s %s actually changes the sprite" % [part, mod])
			var inside := _diff(original, img, _region_rect(part))
			check(inside >= whole * 0.95, "%s %s changes Aurora where the gem pointed" % [part, mod])
			var key := hash(img.get_data())
			check(not hashes.has(key), "%s %s is its own picture, not a repeat of %s" % [part, mod, hashes.get(key, "-")])
			hashes[key] = "%s %s" % [part, mod]
			per_part.append(whole)
		check(per_part.size() == MODS.size(), "%s reacts to every modification" % part)

	# Same mod, different parts: the silhouettes must not match.
	var giant_hands := _probe(AuroraBody.compose("aurora_serious", base, {"HANDS": "GIANT"}))
	var giant_legs := _probe(AuroraBody.compose("aurora_serious", base, {"LEGS": "GIANT"}))
	check(_diff(giant_hands, giant_legs) > 0.002, "GIANT HANDS and GIANT LEGS are different bodies")
	var tiny_hands := _probe(AuroraBody.compose("aurora_serious", base, {"HANDS": "TINY"}))
	check(_diff(giant_hands, tiny_hands) > 0.002, "GIANT HANDS and TINY HANDS are different bodies")

	# Parts stack: two gem rounds leave two marks on her.
	var stacked := AuroraBody.compose("aurora_serious", base, {"HANDS": "GIANT", "EYES": "GLOWING"})
	var stacked_img := _probe(stacked)
	check(_diff(stacked_img, giant_hands) > 0.0002, "a second shift adds to the first, it does not replace it")
	check(int(stacked.get_meta("aurora_part_layers", 0)) == 2, "both shifts are recorded on the portrait")

	# Cheap enough to redraw on every rollback: identical calls are cached.
	var again := AuroraBody.compose("aurora_serious", base, {"HANDS": "GIANT"})
	var once := AuroraBody.compose("aurora_serious", base, {"HANDS": "GIANT"})
	check(again == once, "the same pairing is composed once and cached")
	AuroraBody.clear_cache()

	# An unknown word must never blank the portrait.
	check(AuroraBody.compose("aurora_serious", base, {"TAIL": "GIANT"}) == base,
		"a word with no body part falls back to the untouched sprite")
	check(AuroraBody.compose("aurora_serious", base, {}) == base, "no shift means the original art")

	print("AURORA PART MODS: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
