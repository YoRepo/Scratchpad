class_name Water
extends Node2D
## A shallow stretch of water painted over the ground: a translucent band with
## a slowly rippling surface line. Give it z_index 1 so it draws over whoever
## wades through it. Purely visual; the Foothold underneath stays walkable.

const RIPPLE_HEIGHT := 1.5
const RIPPLE_LENGTH := 26.0
const RIPPLE_SPEED := 1.4
const STEP := 6.0
const FADE_SLICES := 4

## Width of the water and how far it reaches below the surface line (local y = 0).
@export var size := Vector2(120.0, 14.0)
## How far above the surface line the top ripples reach (water over wading feet).
@export var rise := 5.0
@export var color := Color(0.22, 0.48, 0.62, 0.55)
@export var surface_color := Color(0.85, 0.95, 1.0, 0.7)

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var top := PackedVector2Array()
	var x := 0.0
	while x <= size.x:
		top.append(Vector2(x, -rise + _ripple(x)))
		x += STEP
	if top[top.size() - 1].x < size.x:
		top.append(Vector2(size.x, -rise + _ripple(size.x)))
	var body_bottom := size.y * 0.5
	var polygon := PackedVector2Array(top)
	polygon.append(Vector2(size.x, body_bottom))
	polygon.append(Vector2(0.0, body_bottom))
	draw_colored_polygon(polygon, color)
	# The lower half fades out so the water sinks into the painted ground.
	var slice := (size.y - body_bottom) / FADE_SLICES
	for index in FADE_SLICES:
		var faded := color
		faded.a = color.a * (1.0 - float(index + 1) / float(FADE_SLICES + 1))
		var y := body_bottom + index * slice
		draw_rect(Rect2(0.0, y, size.x, slice + 0.5), faded)
	draw_polyline(top, surface_color, 1.5, true)


func _ripple(x: float) -> float:
	return sin(x / RIPPLE_LENGTH * TAU + _time * RIPPLE_SPEED) * RIPPLE_HEIGHT
