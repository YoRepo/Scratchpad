class_name Pickup
extends Area2D
## A coin or item lying in the world. Pops out of the creature that dropped it,
## settles on the floor, and goes into the Inventory when the knight touches it.

const GROUP := &"pickups"
const GRAVITY := 900.0
const LIFETIME := 45.0

var coins := 0
var item_id: StringName = &""
var amount := 1

var _velocity := Vector2.ZERO
var _grounded := false
var _age := 0.0

@onready var _visual: Node2D = $Visual
@onready var _label: Label = $Visual/Label
@onready var _floor_ray: RayCast2D = $FloorRay


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = CollisionLayers.bit(CollisionLayers.PLAYER)
	monitorable = false
	body_entered.connect(_on_body_entered)
	_floor_ray.collision_mask = CollisionLayers.bits(
		[CollisionLayers.WORLD_SOLID, CollisionLayers.WORLD_PLATFORM]
	)
	_apply_look()


## Sets what this pickup holds and gives it a little toss.
func configure(drop: Dictionary, toss: Vector2) -> void:
	coins = int(drop.get("coins", 0))
	item_id = StringName(drop.get("item", &""))
	amount = int(drop.get("amount", 1))
	_velocity = toss
	if is_inside_tree():
		_apply_look()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	if _grounded:
		_visual.position.y = -3.0 + sin(_age * 4.0) * 2.0
		return
	_velocity.y += GRAVITY * delta
	global_position += _velocity * delta
	_floor_ray.force_raycast_update()
	if _floor_ray.is_colliding() and _velocity.y > 0.0:
		global_position.y = _floor_ray.get_collision_point().y
		_velocity = Vector2.ZERO
		_grounded = true


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	if coins > 0:
		Inventory.add_coins(coins)
	if item_id != &"":
		Inventory.add_item(item_id, amount)
	GameEvents.pickup_collected.emit(self)
	queue_free()


func _apply_look() -> void:
	var is_coin := coins > 0
	_label.text = "¢" if is_coin else _item_short_name()
	_visual.modulate = Color(1.0, 0.85, 0.3) if is_coin else Color.WHITE


func _item_short_name() -> String:
	var item := ItemCatalog.get_item(item_id)
	return item.display_name.left(6) if item != null else String(item_id)
