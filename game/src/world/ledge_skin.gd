class_name LedgeSkin
extends Node2D
## Dresses a flat foothold with a painted ledge prop, tiled (mirrored alternately)
## along its width. Child of the Foothold, placed at its top-left corner.

@export var prop_name: StringName = &"platform_stone"
@export var width := 160.0
@export var height := 40.0
## How far the painted top sits above the collision surface, in world px.
@export var lip := 4.0


func _ready() -> void:
	var texture := TextureFiles.load_texture("res://assets/props/%s.png" % prop_name)
	if texture == null:
		return
	var factor := height / float(texture.get_height())
	var tile := texture.get_width() * factor
	var count := maxi(1, int(ceil(width / tile)))
	var step := width / count
	for index in count:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2(step / float(texture.get_width()), factor)
		sprite.flip_h = index % 2 == 1
		sprite.position = Vector2(index * step, -lip)
		add_child(sprite)
	var parent := get_parent() as Foothold
	if parent != null:
		parent.set_painted(true)
