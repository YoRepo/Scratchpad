class_name Climbable
extends Area2D
## A ladder or rope. Positioned at its top end and hanging down by `length`.
## The knight climbs along the centre line; top_y/bottom_y bound the climb.

enum Kind { LADDER, ROPE }

const GROUP := &"climbables"
const WIDTH := 12.0

@export var kind: Kind = Kind.LADDER:
	set(value):
		kind = value
		queue_redraw()
@export var length := 100.0:
	set(value):
		length = value
		queue_redraw()
## Whether the knight can step off the top onto a foothold. False for a rope
## that hangs from nothing.
@export var exit_top := true


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = CollisionLayers.bit(CollisionLayers.CLIMBABLE)
	collision_mask = 0
	monitoring = false
	monitorable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(WIDTH, length)
	shape.shape = rect
	shape.position = Vector2(0, length / 2.0)
	add_child(shape)


func top_y() -> float:
	return global_position.y


func bottom_y() -> float:
	return global_position.y + length


func _draw() -> void:
	match kind:
		Kind.LADDER:
			var wood := Color(0.55, 0.38, 0.2)
			draw_rect(Rect2(-5, 0, 2, length), wood)
			draw_rect(Rect2(3, 0, 2, length), wood)
			var y := 5.0
			while y < length:
				draw_rect(Rect2(-5, y, 10, 2), wood.lightened(0.2))
				y += 10.0
		Kind.ROPE:
			var hemp := Color(0.72, 0.6, 0.36)
			draw_rect(Rect2(-1, 0, 2, length), hemp)
			var y := 7.0
			while y < length:
				draw_rect(Rect2(-2, y, 4, 3), hemp.darkened(0.25))
				y += 14.0
