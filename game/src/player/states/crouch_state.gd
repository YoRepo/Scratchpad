extends PlayerState
## Crouching (MapleStory "prone"): no walking. Jump drops through a one-way
## foothold; Down at the top of a climbable grabs it; releasing Down stands up
## if there is headroom.


func enter(_from: StringName) -> void:
	player.velocity.x = 0.0
	player.set_crouching(true)
	player.visual.set_pose(PlayerVisual.Pose.CROUCH)


func exit() -> void:
	player.set_crouching(false)


func physics_update(delta: float) -> StringName:
	player.apply_gravity(delta)
	player.velocity.x = 0.0
	player.move_and_slide()
	var intent := player.intent
	if not player.is_on_floor():
		return AIR
	if intent.jump_pressed and player.try_drop_through():
		return AIR
	if intent.down_held and player.climb_detector.find_grab_from_top(player.global_position) != null:
		return CLIMB
	if not intent.down_held and player.can_stand():
		return IDLE
	return &""
