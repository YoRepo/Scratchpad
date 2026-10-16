extends MobState
## Ambling to a point near home, then resting.

var _target_x := 0.0


func enter(_from: StringName) -> void:
	_target_x = mob.home_x + mob.rng.randf_range(-mob.config.leash, mob.config.leash)
	mob.visual_play(&"move")


func physics_update(delta: float) -> StringName:
	mob.apply_gravity(delta)
	var direction := signf(_target_x - mob.global_position.x)
	mob.walk(direction, mob.config.move_speed)
	mob.move_and_slide()
	var aggro := aggro_transition()
	if aggro != &"":
		return aggro
	if absf(_target_x - mob.global_position.x) < 6.0 or mob.is_on_wall() or mob.at_ledge():
		return IDLE
	return &""
