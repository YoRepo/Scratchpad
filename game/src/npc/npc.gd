class_name NPC
extends Interactable
## A character who talks when interacted with. What they say lives in the
## DialogueData resource assigned in the level, not in code.

const GROUP := &"npcs"

@export var dialogue: DialogueData

@onready var _visual: Node2D = $Visual
@onready var _name_label: Label = $NameLabel


func _ready() -> void:
	super()
	add_to_group(GROUP)
	prompt = "Talk to"
	_name_label.text = display_name


func interact(player: Player) -> Result:
	if dialogue == null:
		return Result.NONE
	face(player.global_position)
	return Result.DIALOGUE if DialogueRunner.start(dialogue, self) else Result.NONE


func face(target: Vector2) -> void:
	_visual.scale.x = -1.0 if target.x < global_position.x else 1.0
