extends MobState
## Knocked back by a hit; brief and uncontrollable.

var _time := 0.0


func enter(_from: StringName) -> void:
	_time = 0.0
	mob.visual_play(&"hurt" if mob.visual_has(&"hurt") else &"idle", true)
	mob.set_hurt_tint(true)


func exit() -> void:
	mob.set_hurt_tint(false)


func physics_update(delta: float) -> StringName:
	_time += delta
	mob.apply_gravity(delta)
	mob.velocity.x = move_toward(mob.velocity.x, 0.0, 600.0 * delta)
	mob.move_and_slide()
	if _time >= mob.config.hurt_duration:
		return CHASE if mob.target_distance() <= mob.config.aggro_range else IDLE
	return &""
