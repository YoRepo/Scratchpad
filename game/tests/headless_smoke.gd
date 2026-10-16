extends Node
## Headless integration check: boots the game, drives the knight with simulated
## actions, and exits non-zero if anything is off. Fast enough to run before
## every push. Runs as its own scene so the autoloads are present:
##
##   godot --headless --path game tests/headless_smoke.tscn

const GAME_SCENE := preload("res://src/game/game.tscn")

var _failures := 0


func _ready() -> void:
	var game: Game = GAME_SCENE.instantiate()
	game.first_level = "res://content/levels/meadow/meadow.tscn"
	add_child(game)
	_run()


func _run() -> void:
	await _frames(5)
	var game: Game = $Game
	var player: Player = $Game/World/Player
	var level_name := game.level.display_name
	_check("boots into the meadow", level_name == "Marginalia Meadow", level_name)
	var idle_on_floor := player.is_on_floor() and _state(player) == &"Idle"
	_check("starts idle on the floor", idle_on_floor, _state(player))

	var npc: NPC = game.level.get_node("NPCs/Anselm")
	_check("npc has dialogue data", npc.dialogue != null and not npc.dialogue.lines.is_empty())
	player.global_position = npc.global_position + Vector2(-12, 0)
	await _frames(4)
	var focus := player.interactor.focus_name()
	_check("npc gets focused", focus == "Brother Anselm", focus)
	await _press(InputActions.INTERACT)
	_check("interact starts dialogue", DialogueRunner.is_active())
	_check("player is talking", _state(player) == &"Talk", _state(player))
	for i in 6:
		if not DialogueRunner.is_active():
			break
		if DialogueRunner.is_awaiting_choice():
			DialogueRunner.choose(1)  # decline the quest for now; it is tested later
		else:
			DialogueRunner.advance()
		await _frames(1)
	await _frames(2)
	_check("dialogue ends, back to idle", _state(player) == &"Idle", _state(player))
	_check("declining leaves the quest available", not QuestLog.is_active(npc.quest))

	var jumps := player.jumps
	await _press(InputActions.JUMP)
	_check("jump registers", player.jumps == jumps + 1 and not player.is_on_floor())
	await _frames(60)
	_check("lands again", player.is_on_floor())

	var ladder: Climbable = game.level.get_node("Climbables/LadderA")
	player.global_position = Vector2(ladder.global_position.x, ladder.bottom_y())
	await _frames(3)
	Input.action_press(InputActions.MOVE_UP)
	await _frames(3)
	_check("up grabs the ladder", _state(player) == &"Climb", _state(player))
	await _frames(70)
	Input.action_release(InputActions.MOVE_UP)
	await _frames(5)
	_check("climbs off the top onto the platform",
		player.is_on_floor() and absf(player.global_position.y - ladder.top_y()) < 2.0,
		"y=%s top=%s state=%s" % [player.global_position.y, ladder.top_y(), _state(player)])

	Input.action_press(InputActions.MOVE_DOWN)
	await _frames(3)
	_check("down at the top grabs the ladder", _state(player) == &"Climb", _state(player))
	await _frames(70)
	Input.action_release(InputActions.MOVE_DOWN)
	await _frames(5)
	_check("steps off the bottom onto the ground",
		player.is_on_floor() and absf(player.global_position.y - ladder.bottom_y()) < 2.0,
		"y=%s" % player.global_position.y)

	Input.action_press(InputActions.MOVE_DOWN)
	await _frames(3)
	_check("down crouches", _state(player) == &"Crouch", _state(player))
	Input.action_release(InputActions.MOVE_DOWN)
	await _frames(3)
	_check("release stands", _state(player) == &"Idle", _state(player))

	var snail: TrainingDummy = game.level.get_node("Dummies/Snail")
	player.global_position = snail.global_position + Vector2(-22, 0)
	player.set_facing(1)
	await _frames(3)
	var hp := snail.health.hp
	await _press(InputActions.ATTACK)
	await _frames(20)
	_check("sword hits the snail", snail.health.hp == hp - 10, "hp %d -> %d" % [hp, snail.health.hp])

	# Quest: offer with a choice, progress from the inventory, turn in for the reward.
	var quest: QuestData = npc.quest
	player.global_position = npc.global_position + Vector2(-12, 0)
	await _frames(4)
	await _press(InputActions.INTERACT)
	for i in 6:
		if DialogueRunner.is_awaiting_choice():
			break
		DialogueRunner.advance()
		await _frames(1)
	_check("quest offer ends with a choice", DialogueRunner.is_awaiting_choice())
	DialogueRunner.choose(0)
	await _frames(3)
	_check("accepting the offer activates the quest", QuestLog.is_active(quest))
	Inventory.add_item(&"snail_shell", 3)
	Inventory.add_item(&"hares_foot", 2)
	Inventory.add_item(&"hedgehog_quill", 5)
	_check("quest is ready to turn in once the items are held", QuestLog.can_turn_in(quest))
	var coins_at_turn_in := Inventory.coins
	await _press(InputActions.INTERACT)
	for i in 6:
		if not DialogueRunner.is_active():
			break
		DialogueRunner.advance()
		await _frames(1)
	await _frames(3)
	_check("turning in pays the reward and finishes the quest",
		QuestLog.status_of(quest) == QuestLog.Status.COMPLETED
		and Inventory.coins == coins_at_turn_in + quest.reward_coins
		and Inventory.count_of(&"illuminated_bookmark") == 1
		and Inventory.count_of(&"snail_shell") == 0,
		"status=%s coins=%d" % [QuestLog.status_of(quest), Inventory.coins])

	# Combat: the snail hurts the knight on contact, the sword kills it, loot drops and is picked up.
	var snail_mob: Mob = game.level.get_node("Mobs/Snail")
	var hp_before := player.health.hp
	player.global_position = snail_mob.global_position
	await _frames(12)
	_check("creature contact damages the knight", player.health.hp < hp_before,
		"hp %d -> %d" % [hp_before, player.health.hp])
	_check("knight is knocked into the hurt state or past it", player.health.hp > 0)
	await _frames(70)
	var coins_before := Inventory.coins
	for i in 6:
		if snail_mob.health.hp <= 0:
			break
		player.global_position = snail_mob.global_position + Vector2(-34, 0)
		player.velocity = Vector2.ZERO
		player.set_facing(1)
		await _frames(2)
		await _press(InputActions.ATTACK)
		await _frames(24)
	_check("sword kills the snail", snail_mob.health.hp <= 0, "hp=%d" % snail_mob.health.hp)
	await _frames(90)
	var pickups := get_tree().get_nodes_in_group(Pickup.GROUP)
	for node in pickups:
		if not is_instance_valid(node):
			continue
		player.global_position = (node as Pickup).global_position
		await _frames(3)
	await _frames(3)
	_check("coins were picked up into the inventory", Inventory.coins > coins_before,
		"coins %d -> %d" % [coins_before, Inventory.coins])

	# Death and respawn (after the invulnerability from the snail has worn off).
	player.global_position = game.level.spawn_position(&"start") + Vector2(300, 0)
	await _frames(75)
	var lethal := HitInfo.new()
	lethal.damage = 999
	lethal.source_position = player.global_position + Vector2(20, 0)
	player.take_hit(lethal)
	await _frames(3)
	_check("lethal hit puts the knight in the Die state", _state(player) == &"Die", _state(player))
	await _frames(170)
	_check("knight respawns at the start with full health",
		player.health.hp == player.health.max_hp and _state(player) == &"Idle"
		and player.global_position.distance_to(game.level.spawn_position(&"start")) < 4.0,
		"hp=%d state=%s" % [player.health.hp, _state(player)])

	var portal: Portal = game.level.get_node("Portals/ToCloister")
	player.global_position = portal.global_position
	await _frames(4)
	await _press(InputActions.INTERACT)
	await _frames(4)
	_check("portal changes level", game.level.display_name == "Cloister", game.level.display_name)

	# The town itself: loads, populated, the knight stands at the start.
	game.change_level("res://content/levels/town/town.tscn", &"start")
	await _frames(10)
	var marks := game.level.landmarks()
	_check("town loads with its townsfolk and creatures",
		game.level.display_name == "Saint Ysolde's Ford" and marks["npcs"].size() == 5
		and marks["mobs"].size() == 9, "npcs=%d mobs=%d" % [marks["npcs"].size(), marks["mobs"].size()])
	_check("knight stands in the town square", player.is_on_floor() and _state(player) == &"Idle",
		_state(player))
	_check("town sheathes the sword", player.stance == Player.Stance.UNARMED)
	var town_jumps := player.jumps
	await _press(InputActions.JUMP)
	await _frames(3)
	_check("no jumping in town", player.jumps == town_jumps and player.is_on_floor(), _where(player))

	# The ford: the bridge deck carries the knight over the stream, Down+Jump drops him
	# into it, and a jump from the stream bed reaches the bank again. Creatures stand down.
	for mob in get_tree().get_nodes_in_group(Mob.GROUP):
		(mob as Mob).set_hostile(false)
	player.global_position = Vector2(2900, 278)
	await _frames(5)
	_check("the outskirts arm the knight", player.stance == Player.Stance.ARMED)
	Input.action_press(InputActions.MOVE_RIGHT)
	for i in 200:
		if player.global_position.x >= 3150.0:
			break
		await get_tree().physics_frame
	Input.action_release(InputActions.MOVE_RIGHT)
	await _frames(5)
	_check("bridge deck carries the knight over the ford",
		player.is_on_floor() and player.global_position.y < 272.0
		and absf(player.global_position.x - 3160.0) < 40.0, _where(player))
	Input.action_press(InputActions.MOVE_DOWN)
	await _frames(3)
	await _press(InputActions.JUMP)
	Input.action_release(InputActions.MOVE_DOWN)
	await _frames(60)
	_check("down+jump drops off the deck into the stream",
		player.is_on_floor() and absf(player.global_position.y - 330.0) < 2.0, _where(player))
	Input.action_press(InputActions.MOVE_RIGHT)
	await _frames(20)
	await _press(InputActions.JUMP)
	await _frames(60)
	Input.action_release(InputActions.MOVE_RIGHT)
	await _frames(5)
	_check("a jump from the stream bed reaches the east bank",
		player.is_on_floor() and player.global_position.y < 300.0
		and player.global_position.x > 3215.0, _where(player))

	var verdict := "ALL CHECKS PASSED" if _failures == 0 else "%d CHECK(S) FAILED" % _failures
	print("[headless] %s" % verdict)
	get_tree().quit(1 if _failures > 0 else 0)


func _press(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _state(player: Player) -> StringName:
	return player.state_machine.state_name()


func _where(player: Player) -> String:
	var at := player.global_position
	return "x=%.0f y=%.0f state=%s" % [at.x, at.y, _state(player)]


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, "  " + detail if detail != "" else ""])
	if not ok:
		_failures += 1
