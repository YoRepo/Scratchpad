class_name CollisionLayers
extends RefCounted
## Physics layer numbers, mirrored from the names in project.godot ([layer_names]).
## Scenes store the raw numbers; code goes through these constants.

const WORLD_SOLID := 1      # ground, walls, hills: solid from every side
const WORLD_PLATFORM := 2   # one-way footholds you can jump up through
const CLIMBABLE := 3        # ladder and rope areas
const INTERACTABLE := 4     # NPCs, portals
const PLAYER := 5
const HURTBOX := 6          # creatures and dummies that the knight's attacks can hit
const PLAYER_HURTBOX := 7   # the knight, hit by creature attacks
const MOB := 8              # creature bodies: collide with the world, not with the knight


static func bit(layer: int) -> int:
	return 1 << (layer - 1)


static func bits(layers: Array) -> int:
	var mask := 0
	for layer: int in layers:
		mask |= bit(layer)
	return mask
