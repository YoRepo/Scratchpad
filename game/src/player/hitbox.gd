class_name Hitbox
extends Area2D
## The attacking side of combat. Active only during a swing's live window and
## hits each Hurtbox at most once per swing.

## Physics layer of the hurtboxes this hitbox can touch.
@export var target_layer := CollisionLayers.HURTBOX
@export var knockback := 220.0
## When true the hitbox keeps hitting a target every repeat_interval while it overlaps
## (creature contact damage); when false each target is hit once per swing.
@export var repeat_hits := false
@export var repeat_interval := 1.0

var _damage := 0
var _hit_this_swing: Array[Hurtbox] = []
var _base_x := 0.0
var _overlapping: Array[Hurtbox] = []
var _repeat_clock := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.bit(target_layer)
	monitorable = false
	monitoring = false
	_base_x = position.x
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _physics_process(delta: float) -> void:
	if not repeat_hits or not monitoring:
		return
	_repeat_clock = maxf(_repeat_clock - delta, 0.0)
	if _repeat_clock > 0.0 or _overlapping.is_empty():
		return
	_repeat_clock = repeat_interval
	for hurtbox in _overlapping:
		if is_instance_valid(hurtbox) and hurtbox.monitorable:
			_strike(hurtbox)


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
	if hurtbox == null:
		return
	if repeat_hits:
		_overlapping.append(hurtbox)
		if _repeat_clock <= 0.0:
			_repeat_clock = repeat_interval
			_strike(hurtbox)
		return
	if hurtbox in _hit_this_swing:
		return
	_hit_this_swing.append(hurtbox)
	_strike(hurtbox)


func _on_area_exited(area: Area2D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox != null:
		_overlapping.erase(hurtbox)


func _strike(hurtbox: Hurtbox) -> void:
	var info := HitInfo.new()
	info.damage = _damage
	info.source_position = global_position
	info.knockback = knockback
	hurtbox.receive_hit(info)
