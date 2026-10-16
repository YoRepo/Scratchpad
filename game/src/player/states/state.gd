class_name State
extends Node
## Base class for StateMachine states. Subclasses override the hooks they need.

var machine: StateMachine


func setup(_actor: Node, state_machine: StateMachine) -> void:
	machine = state_machine


func enter(_from: StringName) -> void:
	pass


func exit() -> void:
	pass


## Returns the name of the state to switch to, or an empty name to stay.
func physics_update(_delta: float) -> StringName:
	return &""
