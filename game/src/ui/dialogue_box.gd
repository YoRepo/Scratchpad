class_name DialogueBox
extends PanelContainer
## Shows the running conversation. Advances on interact/jump/attack or a tap
## on the box. Knows nothing about who is talking.

var _continue_hint := ""
var _selected := 0

@onready var _speaker: Label = $Margin/Rows/Speaker
@onready var _text: Label = $Margin/Rows/Text
@onready var _hint: Label = $Margin/Rows/Hint
@onready var _choices: HBoxContainer = $Margin/Rows/Choices


func _ready() -> void:
	visible = false
	DialogueRunner.started.connect(_on_started)
	DialogueRunner.line_changed.connect(_on_line_changed)
	DialogueRunner.choices_offered.connect(_on_choices_offered)
	DialogueRunner.ended.connect(_on_ended)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if DialogueRunner.is_awaiting_choice():
		if event.is_action_pressed(InputActions.MOVE_LEFT):
			_select(_selected - 1)
		elif event.is_action_pressed(InputActions.MOVE_RIGHT):
			_select(_selected + 1)
		elif event.is_action_pressed(InputActions.INTERACT) or event.is_action_pressed(InputActions.JUMP):
			DialogueRunner.choose(_selected)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if (
		event.is_action_pressed(InputActions.INTERACT)
		or event.is_action_pressed(InputActions.JUMP)
		or event.is_action_pressed(InputActions.ATTACK)
	):
		DialogueRunner.advance()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not _is_tap(event) or DialogueRunner.is_awaiting_choice():
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
	_clear_choices()
	_continue_hint = "tap to continue" if DeviceInfo.has_touch else "Up or E to continue"


func _on_line_changed(speaker: String, text: String, index: int, total: int) -> void:
	_speaker.text = speaker
	_text.text = text
	_hint.text = "%d / %d   %s" % [index + 1, total, _continue_hint]


func _on_choices_offered(options: PackedStringArray) -> void:
	_clear_choices()
	for index in options.size():
		var button := Button.new()
		button.text = options[index]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 30)
		button.pressed.connect(func() -> void: DialogueRunner.choose(index))
		_choices.add_child(button)
	_choices.visible = true
	_hint.text = "choose"
	_select(0)


func _on_ended() -> void:
	visible = false
	_clear_choices()


func _select(index: int) -> void:
	var count := _choices.get_child_count()
	if count == 0:
		return
	_selected = wrapi(index, 0, count)
	for child_index in count:
		var button := _choices.get_child(child_index) as Button
		button.modulate = Color(1, 0.9, 0.55) if child_index == _selected else Color(0.85, 0.8, 0.7, 0.9)


func _clear_choices() -> void:
	for child in _choices.get_children():
		child.queue_free()
	_choices.visible = false
	_selected = 0
