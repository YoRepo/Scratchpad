class_name Hurtbox
extends Area2D
## The receiving side of combat. Forwards hits to the owner's Health node and
## announces them so the owner can flinch, flash, or play a sound.

signal hit(info: HitInfo)

## The Health node that takes the damage, relative to this hurtbox.
@export var health_path: NodePath = ^"../Health"
## Physics layer this hurtbox sits on (creatures: HURTBOX, the knight: PLAYER_HURTBOX).
@export var layer := CollisionLayers.HURTBOX

var health: Health


func _ready() -> void:
	health = get_node_or_null(health_path) as Health if not health_path.is_empty() else null
	collision_layer = CollisionLayers.bit(layer)
	collision_mask = 0
	monitoring = false
	monitorable = true


func receive_hit(info: HitInfo) -> void:
	if health != null:
		health.damage(info.damage)
	hit.emit(info)
