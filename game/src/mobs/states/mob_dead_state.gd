extends MobState
## Dying, dropping loot, lying still, then respawning at home after a while.

var _time := 0.0
var _dropped := false


func enter(_from: StringName) -> void:
	_time = 0.0
	_dropped = false
	mob.velocity.x = 0.0
	mob.set_hostile(false)
	mob.visual_play(&"die" if mob.visual_has(&"die") else &"idle", true)


func physics_update(delta: float) -> StringName:
	_time += delta
	mob.apply_gravity(delta)
	mob.move_and_slide()
	if not _dropped and _time >= 0.25:
		_dropped = true
		mob.drop_loot()
	if _time >= 1.4:
		mob.set_visible_body(false)
	if _time >= mob.config.respawn_seconds:
		mob.respawn()
		return IDLE
	return &""
