class_name MusicZone
extends Area2D
## Asks for a music track when the knight walks in. Place one per region.

@export var track: StringName = &""
@export var size := Vector2(600, 360)


func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.bit(CollisionLayers.PLAYER)
	monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	add_child(shape)
	body_entered.connect(func(body: Node2D) -> void:
		if body is Player and track != &"":
			GameEvents.music_requested.emit(track))
