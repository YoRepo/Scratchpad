class_name Interactable
extends Area2D
## Something the knight can act on when standing close: NPCs, portals, signs.
## Subclasses implement interact() and report what happened so the player's
## state machine can react without knowing the subclass.

enum Result { NONE, DIALOGUE, LEVEL_CHANGE }

## Verb shown in the prompt and on the touch button ("Talk", "Enter").
@export var prompt := "Interact"
@export var display_name := ""


func _ready() -> void:
	collision_layer = CollisionLayers.bit(CollisionLayers.INTERACTABLE)
	collision_mask = 0
	monitoring = false
	monitorable = true


func interact(_player: Player) -> Result:
	return Result.NONE
