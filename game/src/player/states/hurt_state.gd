extends PlayerState
## Knocked back by a hit. Brief, uncontrollable, then back to the feet.

const DURATION := 0.35

var _time := 0.0


func enter(_from: StringName) -> void:
	_time = 0.0
	player.visual.set_pose(PlayerVisual.Pose.HURT)
	player.visual.set_hurt_tint(true)


func exit() -> void:
	player.visual.set_hurt_tint(false)


func physics_update(delta: float) -> StringName:
	_time += delta
	player.apply_gravity(delta)
	player.velocity.x = move_toward(player.velocity.x, 0.0, 500.0 * delta)
	player.move_and_slide()
	if _time < DURATION:
		return &""
	if not player.is_on_floor():
		return AIR
	return RUN if player.intent.move_x != 0.0 else IDLE
