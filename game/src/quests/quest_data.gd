class_name QuestData
extends Resource
## One quest: who gives it, what it needs, what it pays, and what is said at
## each stage. Instances live in content/quests/*.tres.

@export var id: StringName = &""
@export var title := ""
@export_multiline var description := ""
@export var giver_name := ""
## Item id -> count needed to turn the quest in.
@export var required_items: Dictionary = {}
@export var reward_coins := 0
@export var reward_item_id: StringName = &""
@export var reward_item_amount := 1
## Conversation stages. `offer` should end with choices [Accept, Decline].
@export var offer: DialogueData
@export var in_progress: DialogueData
@export var turn_in: DialogueData
@export var done: DialogueData


func progress_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for item_id in required_items:
		var item := ItemCatalog.get_item(item_id)
		var label := item.display_name if item != null else String(item_id)
		var have := mini(Inventory.count_of(item_id), int(required_items[item_id]))
		lines.append("%s %d/%d" % [label, have, int(required_items[item_id])])
	return lines
