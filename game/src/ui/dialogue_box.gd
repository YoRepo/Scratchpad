class_name DialogueBox
extends PanelContainer
## Shows the running conversation. Advances on interact/jump/attack or a tap
## on the box. Knows nothing about who is talking.

var _continue_hint := ""

@onready var _speaker: Label = $Margin/Rows/Speaker
@onready var _text: Label = $Margin/Rows/Text
@onready var _hint: Label = $Margin/Rows/Hint


func _ready() -> void:
	visible = false
	DialogueRunner.started.connect(_on_started)
	DialogueRunner.line_changed.connect(_on_line_changed)
	DialogueRunner.ended.connect(_on_ended)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (
		event.is_action_pressed(InputActions.INTERACT)
		or event.is_action_pressed(InputActions.JUMP)
		or event.is_action_pressed(InputActions.ATTACK)
	):
		DialogueRunner.advance()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not _is_tap(event):
		return
	DialogueRunner.advance()
	accept_event()


func _is_tap(event: InputEvent) -> bool:
	var touch := event as InputEventScreenTouch
	if touch != null:
		return touch.pressed
	var click := event as InputEventMouseButton
	return click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT


func _on_started(_data: DialogueData) -> void:
	visible = true
	_continue_hint = "tap to continue" if DeviceInfo.has_touch else "Up or E to continue"


func _on_line_changed(speaker: String, text: String, index: int, total: int) -> void:
	_speaker.text = speaker
	_text.text = text
	_hint.text = "%d / %d   %s" % [index + 1, total, _continue_hint]


func _on_ended() -> void:
	visible = false
