class_name GroundStrip
extends Node2D
## Paints a repeated ground texture along the walking surface of its parent
## Foothold, flat ground and slopes alike. The strip image has its surface at
## SURFACE_FRACTION of its height; tiles alternate mirrored so seams stay hidden.
## Draws nothing when the art is missing (the Foothold's own fill shows instead).

const FOLDER := "res://assets/backdrops"
const SURFACE_FRACTION := 0.7

@export var strip_name: StringName = &"ground_outskirts"
## World thickness of the painted ground below the surface.
@export var thickness := 90.0

var _texture: Texture2D


func _ready() -> void:
	_texture = TextureFiles.load_texture("%s/%s.png" % [FOLDER, strip_name])
	var foothold := get_parent() as Foothold
	if _texture == null or foothold == null:
		return
	foothold.set_painted(true)
	queue_redraw()


func _draw() -> void:
	var foothold := get_parent() as Foothold
	if _texture == null or foothold == null:
		return
	var factor := thickness / (_texture.get_height() * (1.0 - SURFACE_FRACTION))
	var above := _texture.get_height() * SURFACE_FRACTION * factor
	var tile := _texture.get_width() * factor
	for polyline in foothold.surface_polylines():
		var distance := 0.0
		for i in polyline.size() - 1:
			distance = _draw_edge(polyline[i], polyline[i + 1], distance, tile, above)


## Paints one surface edge piece by piece, one piece per tile it crosses, and returns the
## distance along the surface at its end so the tiling continues across corners.
func _draw_edge(a: Vector2, b: Vector2, distance: float, tile: float, above: float) -> float:
	var length := a.distance_to(b)
	var covered := 0.0
	while covered < length - 0.01:
		var tile_index := int(floor((distance + covered + 0.001) / tile))
		var piece_end := minf(length, (tile_index + 1) * tile - distance)
		var u0 := clampf((distance + covered - tile_index * tile) / tile, 0.0, 1.0)
		var u1 := clampf((distance + piece_end - tile_index * tile) / tile, 0.0, 1.0)
		if tile_index % 2 == 1:
			u0 = 1.0 - u0
			u1 = 1.0 - u1
		var p0 := a.lerp(b, covered / length)
		var p1 := a.lerp(b, piece_end / length)
		var quad := PackedVector2Array([
			p0 + Vector2(0, -above),
			p1 + Vector2(0, -above),
			p1 + Vector2(0, thickness),
			p0 + Vector2(0, thickness),
		])
		var uvs := PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)])
		var colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
		draw_polygon(quad, colors, uvs, _texture)
		covered = piece_end
	return distance + length
