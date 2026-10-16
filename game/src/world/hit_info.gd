class_name HitInfo
extends RefCounted
## Everything a Hurtbox needs to know about an incoming hit.

var damage := 0
var source_position := Vector2.ZERO
## Horizontal push given to the target, in world px/s (0 = none).
var knockback := 0.0
