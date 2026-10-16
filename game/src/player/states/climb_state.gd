extends PlayerState
## On a ladder or rope. The knight is pinned to the climbable's centre line,
## gravity is off, and one-way footholds are ignored so the body can pass
## through the foothold a ladder leads to.

const STEP_DISTANCE := 26.0

var _climbable: Climbable
var _travelled := 0.0


func enter(_from: StringName) -> void:
	_travelled = 0.0
	var feet := player.global_position
	_climbable = player.climb_detector.find_grab(feet)
	if _climbable == null:
		_climbable = player.climb_detector.find_grab_from_top(feet)
	player.velocity = Vector2.ZERO
	player.set_platform_collision(false)
	player.visual.set_pose(PlayerVisual.Pose.CLIMB)
	if _climbable != null:
		player.global_position = Vector2(
			_climbable.global_position.x,
			clampf(feet.y, _climbable.top_y(), _climbable.bottom_y())
		)


func exit() -> void:
	player.set_platform_collision(true)
	_climbable = null


func physics_update(delta: float) -> StringName:
	if not is_instance_valid(_climbable):
		return AIR
	var intent := player.intent
	if intent.jump_pressed and intent.move_x != 0.0:
		player.jump_off_climbable(intent.move_x)
		return AIR
	var top := _climbable.top_y()
	var bottom := _climbable.bottom_y()
	var y := player.global_position.y + intent.move_y * player.config.climb_speed * delta
	if y <= top:
		if _climbable.exit_top:
			player.global_position.y = top
			return IDLE
		y = top
	if y >= bottom:
		if intent.move_y > 0.0:
			player.global_position.y = bottom
			return AIR
		y = bottom
	_travelled += absf(y - player.global_position.y)
	if _travelled >= STEP_DISTANCE:
		_travelled = 0.0
		GameEvents.player_ladder_step.emit()
	player.global_position.y = y
	player.visual.set_pose(
		PlayerVisual.Pose.CLIMB if intent.move_y != 0.0 else PlayerVisual.Pose.CLIMB_PAUSED
	)
	return &""
