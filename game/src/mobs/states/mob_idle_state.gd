extends MobState
## Standing still for a moment before wandering again.

var _wait := 0.0


func enter(_from: StringName) -> void:
	_wait = mob.rng.randf_range(0.8, 2.2)
	mob.visual_play(&"idle")
	mob.velocity.x = 0.0


func physics_update(delta: float) -> StringName:
	mob.apply_gravity(delta)
	mob.velocity.x = 0.0
	mob.move_and_slide()
	var aggro := aggro_transition()
	if aggro != &"":
		return aggro
	_wait -= delta
	return WANDER if _wait <= 0.0 else &""
