class_name Mob
extends CharacterBody2D
## A creature of the margins. The body, its senses and helpers live here;
## behaviour is decided by the states under StateMachine, numbers by MobConfig.

const GROUP := &"mobs"

@export var config: MobConfig

var home_x := 0.0
var facing := -1
var rng := RandomNumberGenerator.new()

var _spawn_position := Vector2.ZERO
var _attack_timer := 0.0
var _target: Node2D

@onready var state_machine: StateMachine = $StateMachine
@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var contact: Hitbox = $ContactDamage
@onready var visual: Node2D = $Visual
@onready var character: CharacterVisual = $Visual/Character
@onready var placeholder: Node2D = $Visual/Placeholder
@onready var health_bar: FloatingHealthBar = $HealthBar
@onready var name_label: Label = $HealthBar/NameLabel
@onready var body_shape: CollisionShape2D = $BodyShape
@onready var ledge_probe: RayCast2D = $LedgeProbe


func _ready() -> void:
	add_to_group(GROUP)
	rng.seed = hash(name) + int(global_position.x)
	collision_layer = CollisionLayers.bit(CollisionLayers.MOB)
	collision_mask = CollisionLayers.bits(
		[CollisionLayers.WORLD_SOLID, CollisionLayers.WORLD_PLATFORM]
	)
	floor_snap_length = 6.0
	home_x = global_position.x
	_spawn_position = global_position
	_configure()
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	hurtbox.hit.connect(_on_hit)
	_on_health_changed(health.hp, health.max_hp)
	state_machine.start(self)


func _physics_process(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	state_machine.physics_update(delta)


# --- Senses --------------------------------------------------------------------


func target() -> Node2D:
	if not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(&"player") as Node2D
	return _target


func target_distance() -> float:
	var who := target()
	return INF if who == null else absf(who.global_position.x - global_position.x)


func direction_to_target() -> float:
	var who := target()
	return facing if who == null else signf(who.global_position.x - global_position.x)


func at_ledge() -> bool:
	ledge_probe.position.x = facing * (config.world_width * 0.5 + 4.0)
	ledge_probe.force_raycast_update()
	return is_on_floor() and not ledge_probe.is_colliding()


func attack_ready() -> bool:
	return _attack_timer <= 0.0


func mark_attack() -> void:
	_attack_timer = config.attack_cooldown


# --- Movement helpers ------------------------------------------------------------


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + 1100.0 * delta, 700.0)


func walk(direction: float, speed: float) -> void:
	velocity.x = direction * speed
	face(direction)


func face(direction: float) -> void:
	if direction == 0.0:
		return
	facing = 1 if direction > 0.0 else -1
	visual.scale.x = facing
	contact.set_facing(facing)


# --- Combat --------------------------------------------------------------------------


func set_hostile(hostile: bool) -> void:
	contact.set_active(hostile)
	hurtbox.set_deferred("monitorable", hostile)


func set_hurt_tint(active: bool) -> void:
	var tint := Color(1.0, 0.5, 0.5) if active else Color.WHITE
	character.set_tint(tint)
	placeholder.modulate = tint


func set_visible_body(shown: bool) -> void:
	visual.visible = shown
	if not shown:
		health_bar.hide_now()


func drop_loot() -> void:
	DropSpawner.spawn(get_parent(), global_position, config.drop_table, rng)
	GameEvents.mob_killed.emit(self)


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector2.ZERO
	health.restore()
	health_bar.hide_now()
	set_visible_body(true)
	set_hostile(true)


func _on_hit(info: HitInfo) -> void:
	if health.hp <= 0:
		return
	var away := signf(global_position.x - info.source_position.x)
	velocity.x = away * info.knockback
	velocity.y = -80.0
	GameEvents.mob_hurt.emit(self)
	if health.hp > 0:
		state_machine.change(MobState.HURT)


func _on_died() -> void:
	state_machine.change(MobState.DEAD)


func _on_health_changed(current: int, maximum: int) -> void:
	if current < maximum:
		health_bar.flash(float(current) / float(maximum))


# --- Visual --------------------------------------------------------------------------


func visual_has(animation: StringName) -> bool:
	return character.has(animation)


func visual_play(animation: StringName, restart := false) -> void:
	character.play(animation, restart)


func _configure() -> void:
	health_bar.position.y = -config.world_height - 12.0
	name_label.text = config.display_name
	health.max_hp = config.max_hp
	health.hp = config.max_hp
	_size_shape(body_shape, Vector2(config.world_width * 0.7, config.world_height))
	_size_shape(hurtbox.get_node("Shape"), Vector2(config.world_width * 0.9, config.world_height))
	var contact_size := Vector2(config.world_width * 0.8, config.world_height * 0.9)
	_size_shape(contact.get_node("Shape"), contact_size)
	contact.knockback = config.knockback
	contact.target_layer = CollisionLayers.PLAYER_HURTBOX
	contact.begin_swing(config.contact_damage)
	contact.repeat_hits = true
	var loaded := config.animation_folder != "" and character.setup(config.animation_folder)
	placeholder.visible = not loaded
	if not loaded:
		var rect := placeholder.get_node("Body") as ColorRect
		rect.offset_left = -config.world_width * 0.5
		rect.offset_right = config.world_width * 0.5
		rect.offset_top = -config.world_height
		rect.offset_bottom = 0.0
	set_hostile(true)


func _size_shape(node: CollisionShape2D, size: Vector2) -> void:
	var rect := RectangleShape2D.new()
	rect.size = size
	node.shape = rect
	node.position.y = -size.y * 0.5
