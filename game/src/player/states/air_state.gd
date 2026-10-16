extends PlayerState
## Airborne: jumping or falling. Can steer, grab a climbable, attack, or use
## the coyote window to jump just after leaving a ledge.


func enter(_from: StringName) -> void:
	player.visual.set_pose(PlayerVisual.Pose.STAND)


func physics_update(delta: float) -> StringName:
	var intent := player.intent
	if intent.jump_pressed and player.can_coyote_jump():
		player.start_jump()
	player.apply_gravity(delta)
	player.apply_air_control(intent.move_x)
	player.move_and_slide()
	if player.is_on_floor():
		return RUN if intent.move_x != 0.0 else IDLE
	if intent.up_held and player.climb_detector.find_grab(player.global_position) != null:
		return CLIMB
	if intent.attack_pressed:
		return ATTACK
	return &""
