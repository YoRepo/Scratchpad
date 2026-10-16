class_name Player
extends CharacterBody2D
## The knight's body: physics helpers and components. Behaviour is decided by
## the states under StateMachine; input is read only by PlayerInput.

const GROUP := &"player"
const INVULNERABLE_TIME := 1.0

@export var config: PlayerMovementConfig

var intent := PlayerIntent.new()
var facing := 1
## Counters read by the browser smoke test.
var jumps := 0
var attacks := 0

var _airborne_time := 0.0
var _invulnerable_left := 0.0

@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var state_machine: StateMachine = $StateMachine
@onready var input: PlayerInput = $PlayerInput
@onready var visual: PlayerVisual = $Visual
@onready var climb_detector: ClimbDetector = $ClimbDetector
@onready var interactor: Interactor = $Interactor
@onready var hitbox: Hitbox = $Hitbox
@onready var stand_shape: CollisionShape2D = $StandShape
@onready var crouch_shape: CollisionShape2D = $CrouchShape
@onready var ceiling_check: ShapeCast2D = $CeilingCheck
@onready var foothold_probe: RayCast2D = $FootholdProbe
@onready var drop_timer: Timer = $DropTimer


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = CollisionLayers.bit(CollisionLayers.PLAYER)
	collision_mask = CollisionLayers.bits(
		[CollisionLayers.WORLD_SOLID, CollisionLayers.WORLD_PLATFORM]
	)
	floor_constant_speed = true
	floor_snap_length = 6.0
	floor_max_angle = deg_to_rad(50.0)
	drop_timer.one_shot = true
	drop_timer.wait_time = config.drop_through_time
	drop_timer.timeout.connect(func() -> void: set_platform_collision(true))
	hurtbox.hit.connect(_on_hurtbox_hit)
	health.changed.connect(func(current: int, maximum: int) -> void:
		GameEvents.player_health_changed.emit(current, maximum))
	health.died.connect(func() -> void: state_machine.change(PlayerState.DIE))
	state_machine.start(self)
	DebugBridge.register(&"player", debug_state)


func _exit_tree() -> void:
	DebugBridge.unregister(&"player")


func _physics_process(delta: float) -> void:
	intent = input.read()
	state_machine.physics_update(delta)
	var grounded := is_on_floor()
	if grounded and _airborne_time > 0.15:
		GameEvents.player_landed.emit()
	_airborne_time = 0.0 if grounded else _airborne_time + delta
	if _invulnerable_left > 0.0:
		_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
		visual.set_blink(_invulnerable_left > 0.0)


# --- Movement helpers used by the states -------------------------------------


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + config.gravity * delta, config.max_fall_speed)


func apply_run(axis: float) -> void:
	velocity.x = axis * config.run_speed
	face_toward(axis)


## Steers while airborne; with no input the knight keeps its momentum.
func apply_air_control(axis: float) -> void:
	if axis == 0.0 or config.air_control <= 0.0:
		return
	velocity.x = axis * config.run_speed * config.air_control
	face_toward(axis)


func start_jump() -> void:
	velocity.y = config.jump_velocity
	jumps += 1
	GameEvents.player_jumped.emit()


## True for a short while after walking off a ledge, so a late jump still works.
func can_coyote_jump() -> bool:
	return velocity.y >= 0.0 and _airborne_time <= config.coyote_time


func jump_off_climbable(axis: float) -> void:
	velocity.x = axis * config.run_speed
	velocity.y = config.climb_jump_velocity
	face_toward(axis)
	jumps += 1
	GameEvents.player_jumped.emit()


## Drops through the one-way foothold underfoot. Returns false on solid ground.
func try_drop_through() -> bool:
	foothold_probe.force_raycast_update()
	if not foothold_probe.is_colliding():
		return false
	set_platform_collision(false)
	drop_timer.start()
	velocity.y = maxf(velocity.y, 60.0)
	return true


func set_platform_collision(enabled: bool) -> void:
	set_collision_mask_value(CollisionLayers.WORLD_PLATFORM, enabled)


func set_crouching(crouching: bool) -> void:
	stand_shape.set_deferred("disabled", crouching)
	crouch_shape.set_deferred("disabled", not crouching)


func can_stand() -> bool:
	ceiling_check.force_shapecast_update()
	return not ceiling_check.is_colliding()


func set_facing(direction: int) -> void:
	if direction == facing:
		return
	facing = direction
	visual.set_facing(direction)
	hitbox.set_facing(direction)


func face_toward(axis: float) -> void:
	if axis > 0.0:
		set_facing(1)
	elif axis < 0.0:
		set_facing(-1)


# --- Combat -------------------------------------------------------------------


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


## Starts the hurt reaction: knockback away from the source and a short grace period.
func take_hit(info: HitInfo) -> void:
	if is_invulnerable() or health.hp <= 0:
		return
	health.damage(info.damage)
	_invulnerable_left = INVULNERABLE_TIME
	var away := signf(global_position.x - info.source_position.x)
	if away == 0.0:
		away = -facing
	velocity = Vector2(away * info.knockback, -160.0)
	GameEvents.player_hurt.emit()
	if health.hp > 0:
		state_machine.change(PlayerState.HURT)


## Brings the knight back to life at a position, full health, idle.
func respawn_at(position_in_world: Vector2) -> void:
	global_position = position_in_world
	velocity = Vector2.ZERO
	health.restore()
	_invulnerable_left = INVULNERABLE_TIME
	set_facing(1)
	state_machine.change(PlayerState.IDLE)
	GameEvents.player_respawned.emit()


func _on_hurtbox_hit(info: HitInfo) -> void:
	take_hit(info)


func debug_state() -> Dictionary:
	var state := String(state_machine.state_name())
	return {
		"x": snappedf(global_position.x, 0.1),
		"y": snappedf(global_position.y, 0.1),
		"vx": snappedf(velocity.x, 0.1),
		"vy": snappedf(velocity.y, 0.1),
		"on_floor": is_on_floor(),
		"facing": facing,
		"state": state,
		"attacking": state == String(PlayerState.ATTACK),
		"jumps": jumps,
		"attacks": attacks,
		"interactable": interactor.focus_name(),
		"hp": health.hp,
		"max_hp": health.max_hp,
		"presses": input.presses,
		"interactions": interactor.interactions,
		"interaction_result": interactor.last_result,
	}
