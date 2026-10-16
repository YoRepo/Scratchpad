class_name ParallaxBackdrop
extends Node2D
## Painted parallax layers behind the level, built from assets/backdrops when
## the files exist: sky (barely moves), far hills, mid trees. Each layer is
## scaled to the level height and repeated sideways.

const FOLDER := "res://assets/backdrops"
## name, scroll factor, ground line as a fraction of the image height (-1 = the layer
## is a full-view sky: scaled to the level height and pinned to the top), target height
## in world px (0 = level height).
const LAYERS := [
	["sky", 0.05, -1.0, 0.0],
	["hills_far", 0.25, 1.0, 300.0],
	["trees_mid", 0.5, 0.766, 200.0],
]

## World y of the ground line the bottom-anchored layers rest on.
@export var ground_y := 330.0
@export var level_height := 360.0


func _ready() -> void:
	for spec: Array in LAYERS:
		var texture := TextureFiles.load_texture("%s/%s.png" % [FOLDER, spec[0]])
		if texture == null:
			continue
		var layer := Parallax2D.new()
		layer.name = String(spec[0])
		layer.scroll_scale = Vector2(float(spec[1]), 1.0)
		var ground_fraction := float(spec[2])
		var target_height := float(spec[3]) if float(spec[3]) > 0.0 else level_height
		var factor := target_height / float(texture.get_height())
		var width := texture.get_width() * factor
		var top := 0.0
		if ground_fraction >= 0.0:
			top = ground_y - texture.get_height() * factor * ground_fraction
		# A plain copy and a mirrored one side by side: the pair always tiles seamlessly.
		for index in 2:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.centered = false
			sprite.scale = Vector2.ONE * factor
			sprite.flip_h = index == 1
			sprite.position = Vector2(index * width, top)
			layer.add_child(sprite)
		layer.repeat_size = Vector2(width * 2.0, 0)
		layer.repeat_times = 3
		add_child(layer)
