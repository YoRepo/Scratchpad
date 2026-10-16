class_name CharacterVisual
extends Node2D
## Draws a character from its animation sheets. The node's origin is the feet
## centre; facing is a horizontal mirror. Owners call play() with animation
## names and listen to finished for one-shot clips.

signal finished(animation: StringName)

var available := false

var _sprite: AnimatedSprite2D
var _set: SpriteSheetLoader.CharacterSet
var _current: StringName = &""


## Loads the folder's sheets; returns false (and stays empty) if there are none.
func setup(folder: String) -> bool:
	_set = SpriteSheetLoader.load_character(folder)
	available = _set != null and not _set.names.is_empty()
	if not available:
		return false
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _set.frames
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * _set.scale
	_sprite.animation_finished.connect(func() -> void: finished.emit(_current))
	add_child(_sprite)
	return true


func has(animation: StringName) -> bool:
	return available and _set.frames.has_animation(animation)


## Plays an animation; a looping one already playing keeps its phase unless restart is true.
func play(animation: StringName, restart := false) -> void:
	if not has(animation):
		return
	if animation == _current and not restart and _sprite.is_playing():
		return
	_current = animation
	_sprite.offset = -_set.origins[animation]
	_sprite.play(animation)


func current() -> StringName:
	return _current


func set_paused(paused: bool) -> void:
	if not available:
		return
	if paused:
		_sprite.pause()
	elif not _sprite.is_playing():
		_sprite.play()


func set_facing(direction: int) -> void:
	scale.x = direction


func set_tint(color: Color) -> void:
	if available:
		_sprite.modulate = color
