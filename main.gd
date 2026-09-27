extends Node
## Klima Gem entry. The 3D television studio stands behind a glass title
## card; starting the show hides the card and opens the Dialogue Manager
## balloon on the show dialogue.

const STORY: DialogueResource = preload("res://dialogue/klima_gem_show.dialogue")
const DisplayScale = preload("res://scenes/display_scale.gd")
## The panic page leaves a return ticket when it replaces this scene; the
## balloon consumes it in start() and resumes at the line that was showing.
const PanicScript = preload("res://scenes/panic_screen.gd")

@onready var title_layer: CanvasLayer = $TitleLayer


func _ready() -> void:
	# The title card opens at the window the player saved, so a restart does not
	# look like the resolution setting was forgotten.
	DisplayScale.apply_saved_window(get_tree())
	var dm: Node = Engine.get_singleton("DialogueManager")
	if dm != null and not dm.dialogue_ended.is_connected(_on_dialogue_ended):
		dm.dialogue_ended.connect(_on_dialogue_ended)
	if PanicScript.has_ticket():
		# Coming back from the panic page: skip the title card and let the
		# balloon resume the saved line (the cue below is ignored for tickets).
		_titleless_start()
		return
	_play_title_theme()


## Start the dialogue without touching the title layer.
func _titleless_start() -> void:
	Engine.get_singleton("DialogueManager").show_dialogue_balloon(STORY, "")


func _unhandled_input(event: InputEvent) -> void:
	if title_layer == null or not title_layer.visible:
		return
	if event.is_action_pressed(&"dialogue_advance") or event.is_action_pressed(&"ui_accept"):
		_start("show_start")
		get_viewport().set_input_as_handled()


func _start(cue: String) -> void:
	title_layer.hide()
	Engine.get_singleton("DialogueManager").show_dialogue_balloon(STORY, cue)


func _on_begin_pressed() -> void:
	_start("show_start")


func _on_dialogue_ended(_resource: Resource) -> void:
	if is_instance_valid(title_layer):
		title_layer.show()
	_play_title_theme()


func _play_title_theme() -> void:
	var audio := get_node_or_null("/root/AudioDirector")
	# The menu theme obeys the saved sliders every time the title returns:
	# the balloon may have changed them and then been torn down.
	if audio != null and audio.has_method("apply_saved_volumes"):
		audio.apply_saved_volumes()
	if audio != null and audio.has_method("play_scene"):
		audio.play_scene("festival")
