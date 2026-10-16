extends PlayerState
## Standing still on a foothold.


func enter(_from: StringName) -> void:
	player.velocity.x = 0.0
	player.visual.set_pose(PlayerVisual.Pose.STAND)


func physics_update(delta: float) -> StringName:
	player.apply_gravity(delta)
	player.velocity.x = 0.0
	player.move_and_slide()
	var next := grounded_transition()
	if next != &"":
		return next
	if player.intent.move_x != 0.0:
		return RUN
	return &""
