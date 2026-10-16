class_name GameCamera
extends Camera2D
## Follows a target inside the level bounds. Framing and smoothing live here.

@export var vertical_offset := -40.0

var _target: Node2D


func follow(target: Node2D) -> void:
	_target = target


func set_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)


## Jumps to the target without smoothing, e.g. after a level change.
func snap_to_target() -> void:
	if not is_instance_valid(_target):
		return
	global_position = _target.global_position + Vector2(0, vertical_offset)
	reset_smoothing()


func _physics_process(_delta: float) -> void:
	if is_instance_valid(_target):
		global_position = _target.global_position + Vector2(0, vertical_offset)
