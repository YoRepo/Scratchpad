extends Node
## Autoload (QuestLog): which quests are available, active or finished, and
## the rules for accepting and turning them in. NPCs ask it what to say.

signal quest_accepted(quest: QuestData)
signal quest_progressed(quest: QuestData)
signal quest_completed(quest: QuestData)

enum Status { AVAILABLE, ACTIVE, COMPLETED }

var _status: Dictionary = {}
var _quests: Dictionary = {}


func _ready() -> void:
	Inventory.item_changed.connect(_on_item_changed)
	DebugBridge.register(&"quests", debug_state)


func status_of(quest: QuestData) -> Status:
	return _status.get(quest.id, Status.AVAILABLE)


func is_active(quest: QuestData) -> bool:
	return status_of(quest) == Status.ACTIVE


func accept(quest: QuestData) -> void:
	if status_of(quest) != Status.AVAILABLE:
		return
	_status[quest.id] = Status.ACTIVE
	_quests[quest.id] = quest
	quest_accepted.emit(quest)


func can_turn_in(quest: QuestData) -> bool:
	if not is_active(quest):
		return false
	for item_id in quest.required_items:
		if Inventory.count_of(item_id) < int(quest.required_items[item_id]):
			return false
	return true


## Takes the ingredients, pays the reward, marks the quest done. False if not ready.
func turn_in(quest: QuestData) -> bool:
	if not can_turn_in(quest):
		return false
	for item_id in quest.required_items:
		Inventory.remove_item(item_id, int(quest.required_items[item_id]))
	if quest.reward_coins > 0:
		Inventory.add_coins(quest.reward_coins)
	if quest.reward_item_id != &"":
		Inventory.add_item(quest.reward_item_id, quest.reward_item_amount)
	_status[quest.id] = Status.COMPLETED
	quest_completed.emit(quest)
	return true


func active_quests() -> Array[QuestData]:
	var result: Array[QuestData] = []
	for id in _status:
		if _status[id] == Status.ACTIVE:
			result.append(_quests[id])
	return result


func debug_state() -> Dictionary:
	var quests := {}
	for id in _status:
		quests[String(id)] = Status.keys()[_status[id]].to_lower()
	return {"quests": quests}


func _on_item_changed(id: StringName, _count: int) -> void:
	for quest in active_quests():
		if quest.required_items.has(id):
			quest_progressed.emit(quest)
