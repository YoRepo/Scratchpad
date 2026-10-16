class_name GroundStrip
extends Node2D
## Paints a repeated ground texture along a flat foothold. The strip image has
## its walking surface at 70% of its height; mirrored tiles hide the seams.
## Draws nothing when the art is missing (the Foothold's own fill shows instead).

const FOLDER := "res://assets/backdrops"
const SURFACE_FRACTION := 0.7

@export var strip_name: StringName = &"ground_outskirts"
@export var width := 2000.0
## World thickness of the painted ground below the surface.
@export var thickness := 90.0


func _ready() -> void:
	var path := "%s/%s.png" % [FOLDER, strip_name]
	if not ResourceLoader.exists(path):
		return
	var texture := load(path) as Texture2D
	if texture == null:
		return
	var below := texture.get_height() * (1.0 - SURFACE_FRACTION)
	var factor := thickness / below
	var tile_width := texture.get_width() * factor
	var x := 0.0
	var index := 0
	while x < width:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2(factor, factor)
		sprite.flip_h = index % 2 == 1
		sprite.position = Vector2(x, -texture.get_height() * SURFACE_FRACTION * factor)
		add_child(sprite)
		x += tile_width
		index += 1
