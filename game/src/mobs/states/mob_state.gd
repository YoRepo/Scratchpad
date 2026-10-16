class_name MobState
extends State
## Base for creature states: typed access to the mob and shared helpers.

const IDLE := &"Idle"
const WANDER := &"Wander"
const CHASE := &"Chase"
const ATTACK := &"Attack"
const HURT := &"Hurt"
const DEAD := &"Dead"

var mob: Mob


func setup(actor: Node, state_machine: StateMachine) -> void:
	super(actor, state_machine)
	mob = actor as Mob


## Transition shared by every live state when the knight comes close.
func aggro_transition() -> StringName:
	if mob.target_distance() <= mob.config.aggro_range:
		return CHASE
	return &""
