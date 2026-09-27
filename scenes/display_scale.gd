extends RefCounted
## Shared window layout for the game and the panic page.
## The layout stays at its authored 1280x720 geometry (the UI chrome, the
## system row and the title card are all laid out in these units). A larger
## window draws that layout with more pixels instead of stretching a
## low-resolution picture.


const DESIGN := Vector2i(1280, 720)


## How much a window enlarges the design canvas. Below the design size, leave
## it at 1 so a narrow window reflows instead of shrinking the chrome.
static func keep_ratio(window_size: Vector2) -> float:
	if window_size.x < 1.0 or window_size.y < 1.0:
		return 1.0
	var fit := minf(window_size.x / float(DESIGN.x), window_size.y / float(DESIGN.y))
	return fit if fit > 1.0 else 1.0


static func read_settings() -> Dictionary:
	# The show keeps its settings namespaced away from the demo balloon
	# this UI was adapted from.
	if not FileAccess.file_exists("user://klima_gem/settings.json"):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://klima_gem/settings.json"))
	return parsed if parsed is Dictionary else {}


## The work area the window has to live in: the screen minus panels/taskbars.
static func work_area() -> Vector2i:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x < 2 or usable.size.y < 2:
		return DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	return usable.size


## The largest window that still fits [param work] (default: the current work
## area) without changing the requested aspect. A size that already fits comes
## back untouched, so callers can tell "as asked" from "fitted to the screen".
static func fit_to_screen(w: int, h: int, work := Vector2i.ZERO) -> Vector2i:
	if w < 1 or h < 1:
		return Vector2i.ZERO
	if work == Vector2i.ZERO:
		work = work_area()
	if work.x < 2 or work.y < 2:
		return Vector2i(w, h)
	var fit := minf(work.x / float(w), work.y / float(h))
	if fit >= 1.0:
		return Vector2i(w, h)
	return Vector2i(maxi(int(w * fit), 1), maxi(int(h * fit), 1))


## True while the window manager owns the window size: a maximized or
## fullscreen window ignores (and fights) a size request.
static func wm_owns_size(tree: SceneTree) -> bool:
	if tree == null:
		return false
	var mode: int = tree.root.mode
	return mode == Window.MODE_MAXIMIZED or mode == Window.MODE_FULLSCREEN


## The window the player last chose. Falls back to the design size.
static func saved_window() -> Vector2i:
	var data := read_settings()
	return Vector2i(int(data.get("res_w", DESIGN.x)), int(data.get("res_h", DESIGN.y)))


## Pin the layout to the design size and give the extra pixels to the window.
## Headless has no window; mutating the layout there breaks orientation tests.
##
## [param force] is for a resolution the player just picked: that one has to
## take effect, so a maximized or fullscreen window is returned to a plain
## window first. Restored settings pass false and leave such a window alone.
##
## Returns the size the window was asked for, or [constant Vector2i.ZERO] when
## the window manager kept its own size.
static func apply_window(tree: SceneTree, w: int, h: int, force := false) -> Vector2i:
	if w < 1 or h < 1 or tree == null:
		return Vector2i.ZERO
	if DisplayServer.get_name() == "headless":
		return Vector2i.ZERO
	var root := tree.root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = DESIGN
	var wanted := fit_to_screen(w, h)
	if wm_owns_size(tree):
		if not force:
			return Vector2i.ZERO
		# Leave the maximized/fullscreen state, otherwise the size request is
		# dropped by the window manager and the setting does nothing.
		root.mode = Window.MODE_WINDOWED
	DisplayServer.window_set_size(wanted)
	return wanted


## Boot: the title card has to open at the size the player saved, not at the
## project default, or every launch looks like the setting was forgotten.
static func apply_saved_window(tree: SceneTree) -> void:
	if tree == null or DisplayServer.get_name() == "headless":
		return
	var size := saved_window()
	apply_window(tree, size.x, size.y)
	# A saved fullscreen window comes back as one; the balloon applies the same
	# flag again when the story starts, which is harmless.
	if bool(read_settings().get("fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
