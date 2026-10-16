extends PlayerState
## Airborne: jumping or falling. Can steer, grab a climbable, attack, or use
## the coyote window to jump just after leaving a ledge.


func enter(_from: StringName) -> void:
	_show_motion()


func physics_update(delta: float) -> StringName:
	var intent := player.intent
	if intent.jump_pressed and player.can_coyote_jump() and player.can_jump():
		player.start_jump()
	player.apply_gravity(delta)
	player.apply_air_control(intent.move_x)
	player.move_and_slide()
	if player.is_on_floor():
		return RUN if intent.move_x != 0.0 else IDLE
	_show_motion()
	if intent.up_held and player.climb_detector.find_grab(player.global_position) != null:
		return CLIMB
	if intent.attack_pressed and player.can_attack():
		return ATTACK
	return &""


## Rising shows the jump pose, falling the fall pose; the visual picks the frames.
func _show_motion() -> void:
	player.visual.set_pose(
		PlayerVisual.Pose.JUMP if player.velocity.y < 0.0 else PlayerVisual.Pose.FALL
	)
	player.visual.set_air_motion(player.velocity.y)
