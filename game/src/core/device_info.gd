extends Node
## Facts about the device the game is running on.

var has_touch: bool = false


func _ready() -> void:
	has_touch = _detect_touch()
	DebugBridge.register(&"device", func() -> Dictionary: return {"touch": has_touch})


## Browsers report "ontouchstart" even on touch-less headless setups, so on web
## trust the touch-point count instead; elsewhere ask the display server.
func _detect_touch() -> bool:
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 0", true))
	return DisplayServer.is_touchscreen_available()
