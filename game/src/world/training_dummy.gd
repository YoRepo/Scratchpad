class_name TrainingDummy
extends Node2D
## A marginalia snail that takes hits and comes back after a moment.
## Stands in for real mobs until combat gets its own module.

const GROUP := &"dummies"

@export var display_name := "Snail"
@export var respawn_delay := 2.0

@onready var health: Health = $Health
@onready var _visual: Node2D = $Visual
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _label: Label = $Label
@onready var _respawn_timer: Timer = $RespawnTimer


func _ready() -> void:
	add_to_group(GROUP)
	_respawn_timer.one_shot = true
	_respawn_timer.wait_time = respawn_delay
	_respawn_timer.timeout.connect(_respawn)
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_on_health_changed(health.hp, health.max_hp)


func _on_health_changed(current: int, maximum: int) -> void:
	_label.text = "%s %d/%d" % [display_name, current, maximum]


func _on_died() -> void:
	_visual.visible = false
	_hurtbox.set_deferred("monitorable", false)
	_respawn_timer.start()


func _respawn() -> void:
	health.restore()
	_visual.visible = true
	_hurtbox.set_deferred("monitorable", true)
