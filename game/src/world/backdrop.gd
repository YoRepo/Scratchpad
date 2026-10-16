class_name Backdrop
extends CanvasLayer
## A full-screen vertical gradient behind the level.

@export var top_color := Color(0.33, 0.62, 0.93)
@export var bottom_color := Color(0.9, 0.95, 1.0)

@onready var _sky: TextureRect = $Sky


func _ready() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([top_color, bottom_color])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 256
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	_sky.texture = texture
