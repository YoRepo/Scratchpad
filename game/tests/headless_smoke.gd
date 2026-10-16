extends Node
## Headless integration check: boots the game, drives the knight with simulated
## actions, and exits non-zero if anything is off. Fast enough to run before
## every push. Runs as its own scene so the autoloads are present:
##
##   godot --headless --path game tests/headless_smoke.tscn

const GAME_SCENE := preload("res://src/game/game.tscn")

var _failures := 0


func _ready() -> void:
	add_child(GAME_SCENE.instantiate())
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
	for i in 5:
		if DialogueRunner.is_active():
			DialogueRunner.advance()
	await _frames(2)
	_check("dialogue ends, back to idle", _state(player) == &"Idle", _state(player))

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

	var portal: Portal = game.level.get_node("Portals/ToCloister")
	player.global_position = portal.global_position
	await _frames(4)
	await _press(InputActions.INTERACT)
	await _frames(4)
	_check("portal changes level", game.level.display_name == "Cloister", game.level.display_name)

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


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, "  " + detail if detail != "" else ""])
	if not ok:
		_failures += 1
