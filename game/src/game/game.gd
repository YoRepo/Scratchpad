class_name Game
extends Node
## Root of the running game: owns the knight, the camera and the current
## level, and performs level transitions. Levels are content; this is the
## only place that loads or unloads them.

@export_file("*.tscn") var first_level := "res://content/levels/town/town.tscn"
@export var first_spawn: StringName = &"start"

var level: Level

@onready var _level_host: Node2D = $World/LevelHost
@onready var _player: Player = $World/Player
@onready var _camera: GameCamera = $World/GameCamera
@onready var _hud: HUD = $HUD


func _ready() -> void:
	GameEvents.level_change_requested.connect(_on_level_change_requested)
	GameEvents.player_died.connect(_on_player_died)
	_hud.setup(_player)
	_camera.follow(_player)
	change_level(_requested_level(), first_spawn)
	DebugBridge.register(&"game", debug_state)
	var version: String = ProjectSettings.get_setting("application/config/version", "dev")
	print("[boot] Scratchpad Side-Scroller v", version)


func change_level(path: String, spawn_name: StringName) -> void:
	if is_instance_valid(level):
		level.queue_free()
	var packed := load(path) as PackedScene
	assert(packed != null, "Game: cannot load level '%s'" % path)
	level = packed.instantiate() as Level
	_level_host.add_child(level)
	_player.global_position = level.spawn_position(spawn_name)
	_player.velocity = Vector2.ZERO
	_player.state_machine.change(PlayerState.IDLE)
	_camera.set_bounds(level.bounds)
	_camera.snap_to_target()
	GameEvents.level_changed.emit(level)


func debug_state() -> Dictionary:
	if not is_instance_valid(level):
		return {"level": "", "landmarks": {}}
	return {"level": level.display_name, "landmarks": level.landmarks()}


## On web, "?level=<name>" in the page URL picks content/levels/<name>/<name>.tscn
## (the browser test tours the meadow while players get the town).
func _requested_level() -> String:
	if not OS.has_feature("web"):
		return first_level
	var search = JavaScriptBridge.eval("new URLSearchParams(location.search).get('level') || ''", true)
	var name := String(search) if search != null else ""
	if name.is_empty() or not name.is_valid_identifier():
		return first_level
	var path := "res://content/levels/%s/%s.tscn" % [name, name]
	return path if ResourceLoader.exists(path) else first_level


func _on_player_died() -> void:
	if is_instance_valid(level):
		_player.respawn_at(level.spawn_position(level.respawn_spawn))
		_camera.snap_to_target()


func _on_level_change_requested(path: String, spawn_name: StringName) -> void:
	# Deferred: the request arrives from inside the physics step.
	change_level.call_deferred(path, spawn_name)
