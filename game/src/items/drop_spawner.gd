class_name DropSpawner
extends RefCounted
## Turns a rolled DropTable into Pickup nodes scattered around a point.

const PICKUP_SCENE := preload("res://src/items/pickup.tscn")


static func spawn(
	parent: Node, origin: Vector2, table: DropTable, rng: RandomNumberGenerator
) -> void:
	if table == null:
		return
	for drop in table.roll(rng):
		var pickup := PICKUP_SCENE.instantiate() as Pickup
		pickup.global_position = origin + Vector2(0, -10)
		var toss := Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-260.0, -180.0))
		pickup.configure(drop, toss)
		parent.add_child(pickup)
