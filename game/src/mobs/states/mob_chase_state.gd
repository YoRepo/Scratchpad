extends MobState
## Closing in on the knight. Hands over to Attack inside attack range.


func enter(_from: StringName) -> void:
	mob.visual_play(&"move")


func physics_update(delta: float) -> StringName:
	mob.apply_gravity(delta)
	var distance := mob.target_distance()
	var strayed := absf(mob.global_position.x - mob.home_x) > mob.config.leash * 2.0
	if distance > mob.config.aggro_range * 1.4 or strayed:
		return IDLE
	var direction := mob.direction_to_target()
	if distance <= mob.config.attack_range and mob.attack_ready():
		mob.velocity.x = 0.0
		mob.move_and_slide()
		return ATTACK
	if mob.at_ledge():
		mob.velocity.x = 0.0
	else:
		mob.walk(direction, mob.config.move_speed * 1.3)
	mob.move_and_slide()
	return &""
