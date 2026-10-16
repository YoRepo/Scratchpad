extends PlayerState
## In conversation. Input is ignored until the DialogueRunner finishes.


func enter(_from: StringName) -> void:
	player.velocity.x = 0.0
	player.visual.set_pose(PlayerVisual.Pose.STAND)


func physics_update(delta: float) -> StringName:
	player.apply_gravity(delta)
	player.velocity.x = 0.0
	player.move_and_slide()
	if not DialogueRunner.is_active():
		return IDLE
	return &""
