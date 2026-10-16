extends Node
## Autoload (ItemCatalog): every ItemData in content/items, by id.

const FOLDER := "res://content/items"

var _items: Dictionary = {}


func _ready() -> void:
	for file in ResourceLoader.list_directory(FOLDER):
		if file.ends_with(".tres") or file.ends_with(".res"):
			var item := load(FOLDER.path_join(file)) as ItemData
			if item != null and item.id != &"":
				_items[item.id] = item


func get_item(id: StringName) -> ItemData:
	return _items.get(id)


func has_item(id: StringName) -> bool:
	return _items.has(id)


func ids() -> Array:
	return _items.keys()
