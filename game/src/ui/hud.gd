class_name HUD
extends CanvasLayer
## Heads-up display: version, status line, interaction prompt, orientation
## hint. The DialogueBox child manages itself.

var _player: Player
var _level_name := ""
var _prompt_text := ""

@onready var _title: Label = $Title
@onready var _hint: Label = $Hint
@onready var _status: Label = $Status
@onready var _prompt: Label = $Prompt
@onready var _rotate: Label = $Rotate


func _ready() -> void:
	var version: String = ProjectSettings.get_setting("application/config/version", "dev")
	_title.text = "Scratchpad Side-Scroller  v%s" % version
	_hint.visible = not DeviceInfo.has_touch
	_prompt.visible = false
	GameEvents.interactable_focused.connect(_on_interactable_focused)
	GameEvents.interactable_unfocused.connect(_on_interactable_unfocused)
	GameEvents.level_changed.connect(_on_level_changed)
	DialogueRunner.started.connect(_on_dialogue_started)
	DialogueRunner.ended.connect(_on_dialogue_ended)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _process(_delta: float) -> void:
	if is_instance_valid(_player):
		_status.text = "%s | %s" % [_level_name, String(_player.state_machine.state_name())]


func setup(player: Player) -> void:
	_player = player


func _on_interactable_focused(interactable: Interactable) -> void:
	var key := "Tap the button" if DeviceInfo.has_touch else "Up or E"
	_prompt_text = "%s: %s %s" % [key, interactable.prompt, interactable.display_name]
	_refresh_prompt()


func _on_interactable_unfocused(_interactable: Interactable) -> void:
	_prompt_text = ""
	_refresh_prompt()


func _on_dialogue_started(_data: DialogueData) -> void:
	_refresh_prompt()


func _on_dialogue_ended() -> void:
	_refresh_prompt()


func _refresh_prompt() -> void:
	_prompt.text = _prompt_text
	_prompt.visible = _prompt_text != "" and not DialogueRunner.is_active()


func _on_level_changed(level: Level) -> void:
	_level_name = level.display_name
	_prompt_text = ""
	_refresh_prompt()


func _on_resize() -> void:
	var vp := get_viewport().get_visible_rect().size
	_rotate.visible = vp.y > vp.x
