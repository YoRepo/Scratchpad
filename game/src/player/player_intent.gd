class_name PlayerIntent
extends RefCounted
## What the player wants to do this physics frame, independent of the device
## that produced it. Produced by PlayerInput; consumed by the player states.

var move_x := 0.0          # -1 left .. 1 right
var move_y := 0.0          # -1 up .. 1 down
var up_held := false
var down_held := false
var jump_pressed := false
var attack_pressed := false
var interact_pressed := false
