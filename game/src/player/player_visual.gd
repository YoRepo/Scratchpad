class_name PlayerVisual
extends Node2D
## Placeholder look for the knight, built from coloured rectangles. The only
## place that knows what the knight looks like; swap in sprites here later.

enum Pose { STAND, RUN, CROUCH, CLIMB, ATTACK }

const CROUCH_DROP := 10.0

@onready var _body: Node2D = $Body
@onready var _legs: ColorRect = $Body/Legs
@onready var _slash: ColorRect = $Body/Slash


func set_facing(direction: int) -> void:
	scale.x = direction


func set_pose(pose: Pose) -> void:
	_body.position.y = CROUCH_DROP if pose == Pose.CROUCH else 0.0
	_legs.visible = pose != Pose.CROUCH
	_slash.visible = pose == Pose.ATTACK
