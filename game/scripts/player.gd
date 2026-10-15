class_name Player
extends CharacterBody2D
## MapleStory-flavoured platforming: fixed-height jump, one-way platforms you can
## jump up through, and Down+Jump to drop through the platform you stand on.

const SPEED := 150.0
const JUMP_VELOCITY := -430.0
const GRAVITY := 1100.0
const MAX_FALL_SPEED := 650.0
const COYOTE_TIME := 0.08
const DROP_SPEED := 120.0
const PLATFORM_LAYER := 2

var facing := 1
var jumps := 0
var attacks := 0
var _coyote := 0.0

@onready var visual: Node2D = $Visual
@onready var slash: ColorRect = $Visual/Slash
@onready var attack_timer: Timer = $AttackTimer
@onready var drop_timer: Timer = $DropTimer


func _ready() -> void:
	attack_timer.timeout.connect(func() -> void: slash.visible = false)
	drop_timer.timeout.connect(func() -> void: set_collision_mask_value(PLATFORM_LAYER, true))


func is_attacking() -> bool:
	return not attack_timer.is_stopped()


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = direction * SPEED
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
		visual.scale.x = facing

	var jump_pressed := Input.is_action_just_pressed("jump")
	if jump_pressed and on_floor and Input.is_action_pressed("move_down"):
		# Drop through the one-way platform underfoot. Solid ground lives on another
		# collision layer, so it stays solid while platforms are ignored briefly.
		set_collision_mask_value(PLATFORM_LAYER, false)
		drop_timer.start()
		velocity.y = DROP_SPEED
		_coyote = 0.0
	elif jump_pressed and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		jumps += 1
		_coyote = 0.0

	if Input.is_action_just_pressed("attack") and attack_timer.is_stopped():
		attack_timer.start()
		attacks += 1
		slash.visible = true

	move_and_slide()
