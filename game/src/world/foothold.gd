class_name Foothold
extends StaticBody2D
## A piece of walkable ground described by a polygon: flat platforms, walls,
## hills and ramps alike. One-way footholds can be jumped through from below.
## Collision is built from the polygon; so is the placeholder look, until a
## skin (GroundStrip, LedgeSkin) paints the foothold and marks it as painted.

@export var points := PackedVector2Array(
	[Vector2(0, 0), Vector2(160, 0), Vector2(160, 12), Vector2(0, 12)]
):
	set(value):
		points = value
		queue_redraw()
@export var one_way := true
@export var fill_color := Color(0.45, 0.3, 0.18)
@export var top_color := Color(0.38, 0.72, 0.32)
## Edges whose outward normal points up at least this much count as walking surface.
@export var surface_threshold := 0.3

var _painted := false


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
	if _painted or points.size() < 3:
		return
	draw_colored_polygon(points, fill_color)
	var winding := _winding()
	for i in points.size():
		if _is_surface_edge(i, winding):
			draw_line(points[i], points[(i + 1) % points.size()], top_color, 4.0)


## Skins call this so the placeholder fill stops drawing underneath their art.
func set_painted(painted: bool) -> void:
	_painted = painted
	queue_redraw()


## The walking surface as runs of consecutive surface edges, in local space.
func surface_polylines() -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	var count := points.size()
	if count < 3:
		return runs
	var winding := _winding()
	# Start just after a non-surface edge so a run never gets split at index 0.
	var start := 0
	for i in count:
		if not _is_surface_edge(i, winding):
			start = i + 1
			break
	var current := PackedVector2Array()
	for step in count:
		var i := (start + step) % count
		if _is_surface_edge(i, winding):
			if current.is_empty():
				current.append(points[i])
			current.append(points[(i + 1) % count])
		elif not current.is_empty():
			runs.append(current)
			current = PackedVector2Array()
	if not current.is_empty():
		runs.append(current)
	return runs


func _is_surface_edge(index: int, winding: float) -> bool:
	var a := points[index]
	var b := points[(index + 1) % points.size()]
	var edge := b - a
	var outward := Vector2(edge.y, -edge.x).normalized() * winding
	return outward.y < -surface_threshold


## +1 when the polygon runs clockwise on screen (y down), -1 otherwise.
func _winding() -> float:
	var area := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return 1.0 if area > 0.0 else -1.0
