extends PlayerState
## A sword swing. On the ground the knight stops to swing; in the air the swing
## keeps the knight's momentum. The hitbox is live for a window inside the swing.

var _time := 0.0
var _grounded := false


func enter(_from: StringName) -> void:
	_time = 0.0
	_grounded = player.is_on_floor()
	if _grounded:
		player.velocity.x = 0.0
	player.attacks += 1
	player.visual.set_pose(PlayerVisual.Pose.ATTACK)
	player.hitbox.begin_swing(player.config.attack_damage)


func exit() -> void:
	player.hitbox.set_active(false)


func physics_update(delta: float) -> StringName:
	var config := player.config
	_time += delta
	player.hitbox.set_active(_time >= config.attack_active_start and _time < config.attack_active_end)
	player.apply_gravity(delta)
	if _grounded:
		player.velocity.x = 0.0
	else:
		player.apply_air_control(player.intent.move_x)
	player.move_and_slide()
	if _time < config.attack_duration:
		return &""
	if not player.is_on_floor():
		return AIR
	return RUN if player.intent.move_x != 0.0 else IDLE
