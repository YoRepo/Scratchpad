class_name Foothold
extends StaticBody2D
## A piece of walkable ground described by a polygon: flat platforms, walls,
## hills and ramps alike. One-way footholds can be jumped through from below.
## Collision and the placeholder look are both built from the polygon.

@export var points := PackedVector2Array(
	[Vector2(0, 0), Vector2(160, 0), Vector2(160, 12), Vector2(0, 12)]
):
	set(value):
		points = value
		queue_redraw()
@export var one_way := true
@export var fill_color := Color(0.45, 0.3, 0.18)
@export var top_color := Color(0.38, 0.72, 0.32)
## Edges whose outward normal points up at least this much are drawn as a surface.
@export var surface_threshold := 0.3


func _ready() -> void:
	collision_layer = CollisionLayers.bit(
		CollisionLayers.WORLD_PLATFORM if one_way else CollisionLayers.WORLD_SOLID
	)
	collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.polygon = points
	shape.one_way_collision = one_way
	add_child(shape)


func _draw() -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, fill_color)
	var winding := _winding()
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var edge := b - a
		var outward := Vector2(edge.y, -edge.x).normalized() * winding
		if outward.y < -surface_threshold:
			draw_line(a, b, top_color, 4.0)


## +1 when the polygon runs clockwise on screen (y down), -1 otherwise.
func _winding() -> float:
	var area := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return 1.0 if area > 0.0 else -1.0
