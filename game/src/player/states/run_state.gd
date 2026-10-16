extends PlayerState
## Running along a foothold, slopes included.


func enter(_from: StringName) -> void:
	player.visual.set_pose(PlayerVisual.Pose.RUN)


func physics_update(delta: float) -> StringName:
	player.apply_gravity(delta)
	player.apply_run(player.intent.move_x)
	player.move_and_slide()
	var next := grounded_transition()
	if next != &"":
		return next
	if player.intent.move_x == 0.0:
		return IDLE
	return &""
