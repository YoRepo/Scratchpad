extends Node
## Autoload (Inventory): what the knight carries. Coins plus item counts by id.
## Emits changes so the HUD and quests react without polling.

signal coins_changed(total: int)
signal item_changed(id: StringName, count: int)

var coins := 0

var _counts: Dictionary = {}


func _ready() -> void:
	DebugBridge.register(&"inventory", debug_state)


func add_coins(amount: int) -> void:
	coins = maxi(coins + amount, 0)
	coins_changed.emit(coins)


func add_item(id: StringName, amount := 1) -> void:
	var item := ItemCatalog.get_item(id)
	var limit := item.stack_limit if item != null else 99
	_counts[id] = mini(int(_counts.get(id, 0)) + amount, limit)
	item_changed.emit(id, _counts[id])


## Removes items if enough are held; returns false (and removes nothing) otherwise.
func remove_item(id: StringName, amount := 1) -> bool:
	if count_of(id) < amount:
		return false
	_counts[id] = int(_counts[id]) - amount
	if _counts[id] <= 0:
		_counts.erase(id)
	item_changed.emit(id, count_of(id))
	return true


func count_of(id: StringName) -> int:
	return int(_counts.get(id, 0))


func items() -> Dictionary:
	return _counts.duplicate()


func debug_state() -> Dictionary:
	var counts := {}
	for id in _counts:
		counts[String(id)] = _counts[id]
	return {"coins": coins, "items": counts}
