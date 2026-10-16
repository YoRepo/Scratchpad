class_name ItemData
extends Resource
## One kind of item: a drop, a quest ingredient, a reward. Instances live in
## content/items/*.tres and are looked up by id through ItemCatalog.

@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
## Icon under res://assets/items/, optional until the art exists.
@export var icon_path := ""
@export var stack_limit := 99
