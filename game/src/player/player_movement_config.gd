class_name PlayerMovementConfig
extends Resource
## Tunable numbers for how the knight moves: the one place to change the feel.
## Edit the values in content/config/player_movement.tres.

@export_group("Ground")
@export var run_speed := 150.0

@export_group("Air")
@export var gravity := 1100.0
@export var max_fall_speed := 650.0
@export var jump_velocity := -430.0
## 0 = no steering while airborne, 1 = full control.
@export_range(0.0, 1.0) var air_control := 1.0
## Seconds after walking off a ledge during which a jump still counts.
@export var coyote_time := 0.08

@export_group("Climbing")
@export var climb_speed := 110.0
@export var climb_jump_velocity := -300.0

@export_group("Platforms")
## How long one-way footholds are ignored after dropping through one.
@export var drop_through_time := 0.25

@export_group("Attack")
@export var attack_duration := 0.3
@export var attack_active_start := 0.05
@export var attack_active_end := 0.2
@export var attack_damage := 10
