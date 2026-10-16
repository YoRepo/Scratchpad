class_name ClimbDetector
extends Area2D
## Finds ladders and ropes the knight can grab. Overlap says "a climbable is
## beside me"; geometry decides whether the grab is allowed.

## How close (px) the feet must be to the climbable's centre line.
@export var grab_range := 12.0
## Vertical tolerance (px) for "standing on the foothold at the top".
@export var top_tolerance := 3.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.bit(CollisionLayers.CLIMBABLE)
	monitorable = false


## The overlapping climbable whose centre line is within reach of the feet, or null.
func find_grab(feet: Vector2) -> Climbable:
	var best: Climbable = null
	var best_distance := grab_range
	for area in get_overlapping_areas():
		var climbable := area as Climbable
		if climbable == null:
			continue
		var distance := absf(climbable.global_position.x - feet.x)
		if distance <= best_distance:
			best = climbable
			best_distance = distance
	return best


## A climbable whose top end is right under the feet, i.e. the knight stands
## on the foothold it leads to and can climb down onto it. Null if none.
func find_grab_from_top(feet: Vector2) -> Climbable:
	for node in get_tree().get_nodes_in_group(Climbable.GROUP):
		var climbable := node as Climbable
		if climbable == null or not climbable.exit_top:
			continue
		if absf(climbable.global_position.x - feet.x) > grab_range:
			continue
		if absf(climbable.top_y() - feet.y) <= top_tolerance:
			return climbable
	return null
