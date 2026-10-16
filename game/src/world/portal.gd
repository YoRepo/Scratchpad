class_name Portal
extends Interactable
## A doorway to another level. Interacting asks the Game to change level;
## the portal itself never touches the scene tree.

const GROUP := &"portals"

@export_file("*.tscn") var target_level := ""
@export var target_spawn: StringName = &"start"

@onready var _label: Label = $Label


func _ready() -> void:
	super()
	add_to_group(GROUP)
	prompt = "Enter"
	_label.text = display_name


func interact(_player: Player) -> Result:
	if target_level.is_empty():
		return Result.NONE
	GameEvents.level_change_requested.emit(target_level, target_spawn)
	return Result.LEVEL_CHANGE


func _draw() -> void:
	var stone := Color(0.55, 0.52, 0.5)
	var glow := Color(0.35, 0.55, 0.95, 0.75)
	draw_rect(Rect2(-16, -52, 32, 52), stone)
	draw_rect(Rect2(-11, -46, 22, 46), glow)
