extends PlayerState
## Struck down. Plays the death, then asks the game for a respawn.

const DURATION := 2.4

var _time := 0.0
var _announced := false


func enter(_from: StringName) -> void:
	_time = 0.0
	_announced = false
	player.velocity.x = 0.0
	player.visual.set_pose(PlayerVisual.Pose.DIE)


func physics_update(delta: float) -> StringName:
	_time += delta
	player.apply_gravity(delta)
	player.velocity.x = move_toward(player.velocity.x, 0.0, 400.0 * delta)
	player.move_and_slide()
	if _time >= DURATION and not _announced:
		_announced = true
		GameEvents.player_died.emit()
	return &""
