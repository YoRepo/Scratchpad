class_name Hurtbox
extends Area2D
## The receiving side of combat. Forwards hits to the owner's Health node and
## announces them so the owner can flinch, flash, or play a sound.

signal hit(info: HitInfo)

## The Health node that takes the damage, relative to this hurtbox.
@export var health_path: NodePath = ^"../Health"

var health: Health


func _ready() -> void:
	health = get_node_or_null(health_path) as Health
	collision_layer = CollisionLayers.bit(CollisionLayers.HURTBOX)
	collision_mask = 0
	monitoring = false
	monitorable = true


func receive_hit(info: HitInfo) -> void:
	if health != null:
		health.damage(info.damage)
	hit.emit(info)
