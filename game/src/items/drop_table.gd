class_name DropTable
extends Resource
## What a creature leaves behind. Coins always drop within the range; each item
## drops independently with its chance.

@export var coins_min := 1
@export var coins_max := 3
@export var item_id: StringName = &""
@export_range(0.0, 1.0) var item_chance := 0.6
@export var item_amount := 1


## Rolls the table into a list of {"coins": n} / {"item": id, "amount": n} drops.
func roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	var coins := rng.randi_range(coins_min, coins_max)
	for _i in coins:
		drops.append({"coins": 1})
	if item_id != &"" and rng.randf() < item_chance:
		drops.append({"item": item_id, "amount": item_amount})
	return drops
