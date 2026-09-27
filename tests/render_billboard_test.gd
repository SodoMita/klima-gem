extends Node
## Rendered proof for the Y-billboard shader (Sprite3DQuad). Needs a real
## rasterizer, e.g. sway headless + pixman + llvmpipe (see
## tests/render_billboard_test.sh). Two cameras look at a Sprite3DQuad and a
## plain quad with identical placement: the billboard must show a wide,
## upright silhouette from both, while the plain quad only ever shows its
## true face from the front. Prints "BILLBOARD RENDER TEST: PASS".

const SQ := preload("res://scenes/motion/sprite_3d_quad.gd")

var cam: Camera3D
var out_dir := "/tmp/billboard_render"

func _make_texture(base: Color) -> ImageTexture:
	var img := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	img.fill(base)
	img.fill_rect(Rect2i(0, 0, 64, 12), Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("out="):
			out_dir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := get_viewport()
	vp.size = Vector2i(800, 450)
	var world := Node3D.new()
	add_child(world)
	cam = Camera3D.new()
	world.add_child(cam)
	var quad: MeshInstance3D = SQ.new()
	world.add_child(quad)
	quad.texture = _make_texture(Color(1, 0, 1, 1))
	quad.world_height = 2.0
	var plain := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 2.0)
	qm.center_offset = Vector3(0, 1.0, 0)
	plain.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0, 1, 1, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plain.material_override = mat
	plain.position = Vector3(0, 0, -2.5)
	world.add_child(plain)

	var ok := true
	# Side view: camera on +X; a fixed-orientation quad is edge-on here.
	cam.position = Vector3(6.0, 1.4, 0.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	var side := await _shot("side")
	ok = ok and side.bb_width >= 60 and side.bb_width > side.plain_width * 1.5 and side.top_spread <= 2
	# Elevated view: a full-camera billboard would tilt; the Y-locked one
	# keeps vertical edges (small top-edge spread).
	cam.position = Vector3(5.0, 6.0, 2.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	var high := await _shot("elevated")
	ok = ok and high.bb_width >= 50 and high.top_spread <= 8

	if ok:
		print("BILLBOARD RENDER TEST: PASS")
		get_tree().quit(0)
	else:
		print("BILLBOARD RENDER TEST: FAIL")
		get_tree().quit(1)

class Shot:
	var bb_width := 0
	var plain_width := 0
	var top_spread := 0

func _shot(name: String) -> Shot:
	for i in range(4):
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_webp("%s/billboard_%s.webp" % [out_dir, name], false)
	var cols := {}
	var tops := {}
	var plain_cols := {}
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.r > 0.6 and c.b > 0.6 and c.g < 0.3:
				cols[x] = true
				if not tops.has(x) or y < tops[x]:
					tops[x] = y
			elif c.g > 0.6 and c.b > 0.6 and c.r < 0.3:
				plain_cols[x] = true
	var s := Shot.new()
	s.bb_width = cols.size()
	s.plain_width = plain_cols.size()
	if not tops.is_empty():
		var v: Array = tops.values()
		v.sort()
		s.top_spread = v[v.size() - 1] - v[0]
	print("RENDER %-8s billboard %d px, plain %d px, top spread %d px" % [name, s.bb_width, s.plain_width, s.top_spread])
	return s
