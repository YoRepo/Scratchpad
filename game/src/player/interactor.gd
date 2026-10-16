class_name Interactor
extends Area2D
## Tracks interactables within reach and keeps the nearest one focused.
## Announces focus changes on GameEvents so the UI can show a prompt.

## How many interactions were attempted and what the last one returned, for tests.
var interactions := 0
var last_result := -1

var _focus: Interactable


func _ready() -> void:
	collision_layer = 0
	collision_mask = CollisionLayers.bit(CollisionLayers.INTERACTABLE)
	monitorable = false


func _physics_process(_delta: float) -> void:
	_refocus()


func has_focus() -> bool:
	return is_instance_valid(_focus)


func focus_name() -> String:
	return _focus.display_name if has_focus() else ""


func interact(player: Player) -> Interactable.Result:
	if not has_focus():
		return Interactable.Result.NONE
	interactions += 1
	last_result = _focus.interact(player)
	return last_result as Interactable.Result


func _refocus() -> void:
	var nearest: Interactable = null
	var best := INF
	for area in get_overlapping_areas():
		var interactable := area as Interactable
		if interactable == null:
			continue
		var distance := absf(interactable.global_position.x - global_position.x)
		if distance < best:
			best = distance
			nearest = interactable
	if nearest == _focus:
		return
	if is_instance_valid(_focus):
		GameEvents.interactable_unfocused.emit(_focus)
	_focus = nearest
	if _focus != null:
		GameEvents.interactable_focused.emit(_focus)
