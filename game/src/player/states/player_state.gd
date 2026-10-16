class_name PlayerState
extends State
## Base for the knight's states: typed access to the player and the
## transitions every grounded state shares.

const IDLE := &"Idle"
const RUN := &"Run"
const AIR := &"Air"
const CROUCH := &"Crouch"
const CLIMB := &"Climb"
const ATTACK := &"Attack"
const TALK := &"Talk"
const HURT := &"Hurt"
const DIE := &"Die"

var player: Player


func setup(actor: Node, state_machine: StateMachine) -> void:
	super(actor, state_machine)
	player = actor as Player


## Transitions available whenever the knight stands on a foothold.
## Priority: interact, jump (or drop through), grab a climbable, crouch, attack.
func grounded_transition() -> StringName:
	var intent := player.intent
	if not player.is_on_floor():
		return AIR
	var interaction := _interaction_transition(intent)
	if interaction != &"":
		return interaction
	if intent.jump_pressed:
		return _jump_transition(intent)
	if intent.up_held and player.climb_detector.find_grab(player.global_position) != null:
		return CLIMB
	if intent.down_held:
		return _down_transition()
	return ATTACK if intent.attack_pressed and player.can_attack() else &""


func _interaction_transition(intent: PlayerIntent) -> StringName:
	if not (intent.interact_pressed and player.interactor.has_focus()):
		return &""
	match player.interactor.interact(player):
		Interactable.Result.DIALOGUE:
			return TALK
		Interactable.Result.LEVEL_CHANGE:
			return IDLE
	return &""


## Down+Jump drops through a one-way foothold; otherwise it is a normal jump,
## which only the armed stance allows (in town the knight keeps his feet down).
func _jump_transition(intent: PlayerIntent) -> StringName:
	if intent.down_held and player.try_drop_through():
		return AIR
	if not player.can_jump():
		return &""
	player.start_jump()
	return AIR


## Down at the top of a climbable grabs it; anywhere else it crouches.
func _down_transition() -> StringName:
	if player.climb_detector.find_grab_from_top(player.global_position) != null:
		return CLIMB
	return CROUCH
