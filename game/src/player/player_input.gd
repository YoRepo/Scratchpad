class_name PlayerInput
extends Node
## Translates input actions into a PlayerIntent. This is the only gameplay
## code that reads the Input singleton. Set enabled = false to freeze the knight.

var enabled := true
## How often each one-shot action was seen, for tests that poll too slowly to
## catch a single frame.
var presses := {"jump": 0, "attack": 0, "interact": 0}


func read() -> PlayerIntent:
	var intent := PlayerIntent.new()
	if not enabled:
		return intent
	intent.move_x = Input.get_axis(InputActions.MOVE_LEFT, InputActions.MOVE_RIGHT)
	intent.move_y = Input.get_axis(InputActions.MOVE_UP, InputActions.MOVE_DOWN)
	intent.up_held = Input.is_action_pressed(InputActions.MOVE_UP)
	intent.down_held = Input.is_action_pressed(InputActions.MOVE_DOWN)
	intent.jump_pressed = Input.is_action_just_pressed(InputActions.JUMP)
	intent.attack_pressed = Input.is_action_just_pressed(InputActions.ATTACK)
	intent.interact_pressed = Input.is_action_just_pressed(InputActions.INTERACT)
	presses["jump"] += int(intent.jump_pressed)
	presses["attack"] += int(intent.attack_pressed)
	presses["interact"] += int(intent.interact_pressed)
	return intent
