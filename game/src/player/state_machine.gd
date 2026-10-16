class_name StateMachine
extends Node
## Minimal finite state machine. Child nodes are the states; exactly one is
## active. A state returns the name of the next state from physics_update().

@export var initial_state: StringName = &""

var current: State

var _states: Dictionary = {}


func start(actor: Node) -> void:
	for child in get_children():
		var state := child as State
		if state == null:
			continue
		state.setup(actor, self)
		_states[child.name] = state
	assert(_states.has(initial_state), "StateMachine: no child state named '%s'" % initial_state)
	current = _states[initial_state]
	current.enter(&"")


func change(to: StringName) -> void:
	assert(_states.has(to), "StateMachine: unknown state '%s'" % to)
	if current != null and current.name == to:
		return
	var previous: StringName = current.name if current != null else &""
	if current != null:
		current.exit()
	current = _states[to]
	current.enter(previous)


func physics_update(delta: float) -> void:
	var next := current.physics_update(delta)
	if next != &"" and next != current.name:
		change(next)


func state_name() -> StringName:
	return current.name if current != null else &""
