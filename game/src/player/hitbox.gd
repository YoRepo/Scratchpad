class_name Hitbox
extends Area2D
## The attacking side of combat. Active only during a swing's live window and
## hits each Hurtbox at most once per swing.

var _damage := 0
var _hit_this_swing: Array[Hurtbox] = []
var _base_x := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.bit(CollisionLayers.HURTBOX)
	monitorable = false
	monitoring = false
	_base_x = position.x
	area_entered.connect(_on_area_entered)


func begin_swing(damage: int) -> void:
	_damage = damage
	_hit_this_swing.clear()


func set_active(active: bool) -> void:
	if monitoring != active:
		set_deferred("monitoring", active)


## Mirrors the hitbox so it sits in front of the knight.
func set_facing(direction: int) -> void:
	position.x = _base_x * direction


func _on_area_entered(area: Area2D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox == null or hurtbox in _hit_this_swing:
		return
	_hit_this_swing.append(hurtbox)
	var info := HitInfo.new()
	info.damage = _damage
	info.source_position = global_position
	hurtbox.receive_hit(info)
