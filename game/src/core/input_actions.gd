extends Node
## Single source of truth for input actions: their names and default bindings.
## Everything else refers to actions through these constants. Touch buttons
## emit the same actions, so gameplay code never knows which device pressed.

const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const MOVE_UP: StringName = &"move_up"
const MOVE_DOWN: StringName = &"move_down"
const JUMP: StringName = &"jump"
const ATTACK: StringName = &"attack"
const INTERACT: StringName = &"interact"

## Default keyboard bindings, as physical keys. Up doubles as "interact" so that
## NPCs and portals work the MapleStory way; E and Enter are there for comfort.
const DEFAULT_BINDINGS: Dictionary = {
	MOVE_LEFT: [KEY_LEFT, KEY_A],
	MOVE_RIGHT: [KEY_RIGHT, KEY_D],
	MOVE_UP: [KEY_UP, KEY_W],
	MOVE_DOWN: [KEY_DOWN, KEY_S],
	JUMP: [KEY_SPACE, KEY_ALT],
	ATTACK: [KEY_X, KEY_CTRL],
	INTERACT: [KEY_UP, KEY_W, KEY_E, KEY_ENTER],
}


func _enter_tree() -> void:
	for action: StringName in DEFAULT_BINDINGS:
		_bind(action, DEFAULT_BINDINGS[action])


func _bind(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key as Key
		InputMap.action_add_event(action, event)
