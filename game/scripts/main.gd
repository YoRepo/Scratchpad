extends Node2D
## Entry point: defines input actions, drives the HUD, and exposes a debug hook
## (window.__game) on web builds so automated browser tests can read game state.

@onready var player: Player = $Player
@onready var touch_controls: TouchControls = $TouchControls
@onready var title_label: Label = $HUD/Title
@onready var hint_label: Label = $HUD/Hint
@onready var rotate_label: Label = $HUD/Rotate

var _debug_accum := 0.0
var _touch := false


func _ready() -> void:
	_setup_input()
	var version: String = ProjectSettings.get_setting("application/config/version", "dev")
	title_label.text = "Scratchpad Side-Scroller  v%s" % version
	_touch = _detect_touch()
	touch_controls.visible = _touch
	hint_label.visible = not _touch
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	print("[boot] Scratchpad Side-Scroller v", version, " touch=", _touch)


func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_debug_accum += delta
	if _debug_accum < 0.25:
		return
	_debug_accum = 0.0
	var vp := get_viewport().get_visible_rect().size
	var state := {
		"booted": true,
		"version": ProjectSettings.get_setting("application/config/version", "dev"),
		"x": snappedf(player.global_position.x, 0.1),
		"y": snappedf(player.global_position.y, 0.1),
		"vx": snappedf(player.velocity.x, 0.1),
		"vy": snappedf(player.velocity.y, 0.1),
		"on_floor": player.is_on_floor(),
		"facing": player.facing,
		"attacking": player.is_attacking(),
		"jumps": player.jumps,
		"attacks": player.attacks,
		"touch": _touch,
		"viewport": {"w": vp.x, "h": vp.y},
		"buttons": touch_controls.debug_button_centers(),
	}
	JavaScriptBridge.eval("window.__game = %s;" % JSON.stringify(state), true)


## Browsers report "ontouchstart" even on touch-less headless setups, so on web
## trust the touch-point count instead; elsewhere ask the display server.
func _detect_touch() -> bool:
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 0", true))
	return DisplayServer.is_touchscreen_available()


func _on_resize() -> void:
	var vp := get_viewport().get_visible_rect().size
	rotate_label.visible = vp.y > vp.x


func _setup_input() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A])
	_add_action("move_right", [KEY_RIGHT, KEY_D])
	_add_action("move_down", [KEY_DOWN, KEY_S])
	_add_action("jump", [KEY_SPACE, KEY_ALT, KEY_W, KEY_UP])
	_add_action("attack", [KEY_X, KEY_J, KEY_CTRL])


func _add_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
