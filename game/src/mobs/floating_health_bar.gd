class_name FloatingHealthBar
extends Node2D
## A small health bar that pops up over a creature when it is hurt and fades
## out a moment later, the way MapleStory shows mob health. Children (such as
## a name label) show and hide with it.

const WIDTH := 40.0
const HEIGHT := 5.0
const LINGER := 2.5
const FADE := 0.4

var _ratio := 1.0
var _time_left := 0.0


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		visible = false
		return
	modulate.a = clampf(_time_left / FADE, 0.0, 1.0)


func flash(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_time_left = LINGER
	modulate.a = 1.0
	visible = true
	queue_redraw()


func hide_now() -> void:
	_time_left = 0.0
	visible = false


func _draw() -> void:
	var rect := Rect2(-WIDTH * 0.5, -HEIGHT * 0.5, WIDTH, HEIGHT)
	draw_rect(rect.grow(1.0), Color(0.08, 0.05, 0.03, 0.85))
	draw_rect(rect, Color(0.25, 0.1, 0.08))
	if _ratio > 0.0:
		var fill := Rect2(rect.position, Vector2(rect.size.x * _ratio, rect.size.y))
		draw_rect(fill, Color(0.85, 0.2, 0.15))
