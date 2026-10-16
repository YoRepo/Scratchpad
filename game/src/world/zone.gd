class_name Zone
extends Area2D
## A region of the map and the rules that change as the knight walks in: the
## music to play and the stance he takes (sheathed in town, armed outside).
## Place one per region; a zone that leaves a field blank changes nothing.

@export var track: StringName = &""
## -1 keeps the current stance; otherwise Player.Stance (0 unarmed, 1 armed).
@export_enum("Keep:-1", "Unarmed:0", "Armed:1") var stance := -1
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
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	if track != &"":
		GameEvents.music_requested.emit(track)
	if stance >= 0:
		player.set_stance(stance as Player.Stance)
