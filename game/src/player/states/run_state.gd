extends PlayerState
## Running along a foothold, slopes included.

const STEP_INTERVAL := 0.32

var _step_clock := 0.0


func enter(_from: StringName) -> void:
	player.visual.set_pose(PlayerVisual.Pose.RUN)
	_step_clock = STEP_INTERVAL * 0.5


func physics_update(delta: float) -> StringName:
	player.apply_gravity(delta)
	player.apply_run(player.intent.move_x)
	player.move_and_slide()
	player.visual.set_move_rate(absf(player.velocity.x) / player.move_speed())
	_step_clock -= delta
	if _step_clock <= 0.0 and player.is_on_floor():
		_step_clock = STEP_INTERVAL
		GameEvents.player_footstep.emit()
	var next := grounded_transition()
	if next != &"":
		return next
	if player.intent.move_x == 0.0:
		return IDLE
	return &""
