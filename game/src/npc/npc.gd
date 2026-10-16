class_name NPC
extends Interactable
## A character who talks when interacted with. What they say lives in the
## DialogueData resource assigned in the level, not in code.

const GROUP := &"npcs"

@export var dialogue: DialogueData
## Optional quest this character gives and receives.
@export var quest: QuestData

@onready var _visual: Node2D = $Visual
@onready var _name_label: Label = $NameLabel


func _ready() -> void:
	super()
	add_to_group(GROUP)
	prompt = "Talk to"
	_name_label.text = display_name


func interact(player: Player) -> Result:
	face(player.global_position)
	var stage := _quest_stage()
	var data: DialogueData = stage.get("data", dialogue)
	if data == null or not DialogueRunner.start(data, self):
		return Result.NONE
	if stage.has("on_end"):
		DialogueRunner.ended.connect(stage["on_end"], CONNECT_ONE_SHOT)
	return Result.DIALOGUE


## Picks what to say from the quest's state: offer it, nag, take the goods, or thank.
func _quest_stage() -> Dictionary:
	if quest == null:
		return {}
	match QuestLog.status_of(quest):
		QuestLog.Status.COMPLETED:
			return {"data": quest.done if quest.done != null else dialogue}
		QuestLog.Status.ACTIVE:
			if QuestLog.can_turn_in(quest):
				return {"data": quest.turn_in, "on_end": func() -> void: QuestLog.turn_in(quest)}
			return {"data": quest.in_progress}
	return {
		"data": quest.offer,
		"on_end": func() -> void:
			if DialogueRunner.last_choice == 0 or quest.offer.choices.is_empty():
				QuestLog.accept(quest),
	}


func face(target: Vector2) -> void:
	_visual.scale.x = -1.0 if target.x < global_position.x else 1.0
