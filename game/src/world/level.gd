class_name Level
extends Node2D
## A map: footholds, climbables, NPCs, portals and spawn points. Pure content;
## the Game node decides when a level loads and where the knight appears.

@export var display_name := "Unnamed"
## World-space rectangle the camera may show.
@export var bounds := Rect2(0, 0, 640, 360)


func spawn_position(spawn_name: StringName) -> Vector2:
	var marker := get_node_or_null("Spawns/%s" % spawn_name) as Marker2D
	if marker == null:
		push_warning("Level '%s' has no spawn named '%s'" % [display_name, spawn_name])
		return bounds.get_center()
	return marker.global_position


## Positions of notable things, for the browser smoke test to navigate by.
func landmarks() -> Dictionary:
	var out := {"npcs": {}, "climbables": {}, "portals": {}, "dummies": {}, "solids": {}, "spawns": {}}
	for node: Node2D in _own(NPC.GROUP):
		out["npcs"][String(node.name)] = {"x": node.global_position.x, "y": node.global_position.y}
	for node: Climbable in _own(Climbable.GROUP):
		out["climbables"][String(node.name)] = {
			"x": node.global_position.x, "top": node.top_y(), "bottom": node.bottom_y()
		}
	for node: Portal in _own(Portal.GROUP):
		out["portals"][String(node.name)] = {
			"x": node.global_position.x, "target": String(node.target_spawn)
		}
	for node: TrainingDummy in _own(TrainingDummy.GROUP):
		out["dummies"][String(node.name)] = {"x": node.global_position.x, "hp": node.health.hp}
	for child in get_node("Footholds").get_children():
		var foothold := child as Foothold
		if foothold != null and not foothold.one_way:
			var box := _polygon_bounds(foothold)
			out["solids"][String(child.name)] = {
				"x": box.position.x, "y": box.position.y, "w": box.size.x, "h": box.size.y
			}
	for marker in get_node("Spawns").get_children():
		var spawn := marker as Marker2D
		if spawn != null:
			out["spawns"][String(spawn.name)] = {"x": spawn.global_position.x, "y": spawn.global_position.y}
	return out


func _own(group: StringName) -> Array:
	return get_tree().get_nodes_in_group(group).filter(is_ancestor_of)


func _polygon_bounds(foothold: Foothold) -> Rect2:
	var box := Rect2(foothold.global_position + foothold.points[0], Vector2.ZERO)
	for point in foothold.points:
		box = box.expand(foothold.global_position + point)
	return box
