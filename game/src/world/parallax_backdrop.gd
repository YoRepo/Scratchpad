class_name ParallaxBackdrop
extends Node2D
## Painted parallax layers behind the level, built from assets/backdrops when
## the files exist: sky (barely moves), far hills, mid trees. Each layer is
## scaled to the level height and repeated sideways.

const FOLDER := "res://assets/backdrops"
## name, scroll factor, vertical anchor: 1 = image bottom sits on the ground line.
const LAYERS := [["sky", 0.05, 0.0], ["hills_far", 0.25, 1.0], ["trees_mid", 0.5, 1.0]]

## World y of the ground line the bottom-anchored layers rest on.
@export var ground_y := 330.0
@export var level_height := 360.0


func _ready() -> void:
	for spec: Array in LAYERS:
		var path := "%s/%s.png" % [FOLDER, spec[0]]
		if not ResourceLoader.exists(path):
			continue
		var texture := load(path) as Texture2D
		if texture == null:
			continue
		var layer := Parallax2D.new()
		layer.name = String(spec[0])
		layer.scroll_scale = Vector2(float(spec[1]), 1.0)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		var factor := level_height / float(texture.get_height())
		sprite.scale = Vector2.ONE * factor
		var width := texture.get_width() * factor
		layer.repeat_size = Vector2(width, 0)
		layer.repeat_times = 3
		var bottom_anchored: bool = float(spec[2]) > 0.5
		sprite.position.y = ground_y - texture.get_height() * factor if bottom_anchored else 0.0
		layer.add_child(sprite)
		add_child(layer)
