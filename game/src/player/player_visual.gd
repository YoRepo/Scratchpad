class_name PlayerVisual
extends Node2D
## What the knight looks like. Uses the painted animation sheets under
## res://assets/characters/knight when they exist, otherwise the coloured
## rectangle placeholder. The only place that maps player poses to animations.

enum Pose { STAND, RUN, CROUCH, CLIMB, CLIMB_PAUSED, ATTACK, JUMP, FALL, HURT, DIE, TALK }

const CHARACTER_FOLDER := "res://assets/characters/knight"
const CROUCH_DROP := 10.0
## Unarmed sheets. The armed stance prefers "armed_<name>" and falls back to these;
## climbing always uses the sheathed sheet (the knight puts the sword away to climb).
const ANIMATION_FOR_POSE := {
	Pose.STAND: &"idle", Pose.TALK: &"idle", Pose.RUN: &"walk", Pose.CROUCH: &"crouch",
	Pose.CLIMB: &"climb", Pose.CLIMB_PAUSED: &"climb", Pose.ATTACK: &"attack",
	Pose.JUMP: &"jump", Pose.FALL: &"jump", Pose.HURT: &"hurt", Pose.DIE: &"die",
}
const ARMED_ANIMATION_FOR_POSE := {
	Pose.STAND: &"armed_idle", Pose.TALK: &"armed_idle", Pose.RUN: &"armed_run",
	Pose.CROUCH: &"armed_crouch", Pose.ATTACK: &"armed_attack", Pose.JUMP: &"armed_jump",
	Pose.FALL: &"armed_jump", Pose.HURT: &"armed_hurt", Pose.DIE: &"armed_die",
}
## Vertical speed below which the apex frame shows, if the jump sheet has one.
const APEX_SPEED := 90.0
## How long the landing frame holds before the standing or running sheet takes over.
const LAND_TIME := 0.1

var _pose: Pose = Pose.STAND
var _stance := Player.Stance.ARMED
var _land_left := 0.0

@onready var _body: Node2D = $Body
@onready var _legs: ColorRect = $Body/Legs
@onready var _slash: ColorRect = $Body/Slash
@onready var _character: CharacterVisual = $Character


func _ready() -> void:
	if _character.setup(CHARACTER_FOLDER):
		_body.visible = false
		_character.play(&"idle")


func _process(delta: float) -> void:
	if _land_left <= 0.0:
		return
	_land_left -= delta
	if _land_left <= 0.0:
		_apply_pose()


func set_facing(direction: int) -> void:
	scale.x = direction


func set_stance(stance: Player.Stance) -> void:
	_stance = stance
	_land_left = 0.0
	_apply_pose()


func set_pose(pose: Pose) -> void:
	var was_airborne := _pose == Pose.JUMP or _pose == Pose.FALL
	_pose = pose
	_body.position.y = CROUCH_DROP if pose == Pose.CROUCH else 0.0
	_legs.visible = pose != Pose.CROUCH
	_slash.visible = pose == Pose.ATTACK
	if not _character.available:
		return
	var grounded := pose == Pose.STAND or pose == Pose.RUN
	if was_airborne and grounded and _character.has_phase(_jump_animation(), &"land"):
		# Touchdown: hold the landing frame briefly, then the ground sheet takes over.
		_character.show_phase(_jump_animation(), &"land")
		_land_left = LAND_TIME
		return
	_land_left = 0.0
	_apply_pose()


## The airborne frame follows the vertical speed when the jump sheet has phases:
## rising, hanging at the apex, falling. Without phases the jump sheet just plays.
func set_air_motion(vertical_speed: float) -> void:
	var animation := _jump_animation()
	if not _character.has_phase(animation, &"rise"):
		return
	var phase: StringName = &"rise" if vertical_speed < -APEX_SPEED else &"fall"
	if absf(vertical_speed) <= APEX_SPEED and _character.has_phase(animation, &"apex"):
		phase = &"apex"
	_character.show_phase(animation, phase)


func _apply_pose() -> void:
	var pose := _pose
	var animation := _animation_for(pose)
	_character.play(animation, pose == Pose.ATTACK or pose == Pose.HURT or pose == Pose.JUMP)
	_character.set_paused(pose == Pose.CLIMB_PAUSED)
	if pose != Pose.RUN:
		_character.set_speed_scale(1.0)


## The sheet for a pose in the current stance, falling back to the unarmed sheet
## and finally to idle.
func _animation_for(pose: Pose) -> StringName:
	if _stance == Player.Stance.ARMED and ARMED_ANIMATION_FOR_POSE.has(pose):
		var armed: StringName = ARMED_ANIMATION_FOR_POSE[pose]
		if _character.has(armed):
			return armed
	var animation: StringName = ANIMATION_FOR_POSE.get(pose, &"idle")
	return animation if _character.has(animation) else &"idle"


func _jump_animation() -> StringName:
	return _animation_for(Pose.JUMP)


## While running, the walk cycle plays at the pace the feet would need for this speed:
## rate 1.0 is the sheet's own fps, which matches the full run speed.
func set_move_rate(rate: float) -> void:
	if _pose == Pose.RUN:
		_character.set_speed_scale(clampf(rate, 0.35, 1.5))


func set_hurt_tint(active: bool) -> void:
	_character.set_tint(Color(1.0, 0.55, 0.55) if active else Color.WHITE)


## Flickers the whole figure while the knight cannot be hit.
func set_blink(active: bool) -> void:
	var phase := fmod(Time.get_ticks_msec() / 1000.0, 0.16) < 0.08
	modulate.a = 0.45 if active and phase else 1.0
