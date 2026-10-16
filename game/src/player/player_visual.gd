class_name PlayerVisual
extends Node2D
## What the knight looks like. Uses the painted animation sheets under
## res://assets/characters/knight when they exist, otherwise the coloured
## rectangle placeholder. The only place that maps player poses to animations.

enum Pose { STAND, RUN, CROUCH, CLIMB, CLIMB_PAUSED, ATTACK, JUMP, FALL, HURT, DIE, TALK }

const CHARACTER_FOLDER := "res://assets/characters/knight"
const CROUCH_DROP := 10.0
const ANIMATION_FOR_POSE := {
	Pose.STAND: &"idle", Pose.TALK: &"idle", Pose.RUN: &"walk", Pose.CROUCH: &"crouch",
	Pose.CLIMB: &"climb", Pose.CLIMB_PAUSED: &"climb", Pose.ATTACK: &"attack",
	Pose.JUMP: &"jump", Pose.FALL: &"jump", Pose.HURT: &"hurt", Pose.DIE: &"die",
}

var _pose: Pose = Pose.STAND

@onready var _body: Node2D = $Body
@onready var _legs: ColorRect = $Body/Legs
@onready var _slash: ColorRect = $Body/Slash
@onready var _character: CharacterVisual = $Character


func _ready() -> void:
	if _character.setup(CHARACTER_FOLDER):
		_body.visible = false
		_character.play(&"idle")


func set_facing(direction: int) -> void:
	scale.x = direction


func set_pose(pose: Pose) -> void:
	_pose = pose
	_body.position.y = CROUCH_DROP if pose == Pose.CROUCH else 0.0
	_legs.visible = pose != Pose.CROUCH
	_slash.visible = pose == Pose.ATTACK
	if not _character.available:
		return
	var animation: StringName = ANIMATION_FOR_POSE.get(pose, &"idle")
	if not _character.has(animation):
		animation = &"idle"
	_character.play(animation, pose == Pose.ATTACK or pose == Pose.HURT or pose == Pose.JUMP)
	_character.set_paused(pose == Pose.CLIMB_PAUSED)


func set_hurt_tint(active: bool) -> void:
	_character.set_tint(Color(1.0, 0.55, 0.55) if active else Color.WHITE)


## Flickers the whole figure while the knight cannot be hit.
func set_blink(active: bool) -> void:
	var phase := fmod(Time.get_ticks_msec() / 1000.0, 0.16) < 0.08
	modulate.a = 0.45 if active and phase else 1.0
