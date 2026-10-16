class_name Health
extends Node
## Hit points for anything that can be damaged. Emits changes; does not decide
## what dying looks like, the owner does.

signal changed(current: int, maximum: int)
signal died

@export var max_hp := 30

var hp := 0


func _ready() -> void:
	hp = max_hp


func damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()


func restore() -> void:
	hp = max_hp
	changed.emit(hp, max_hp)
