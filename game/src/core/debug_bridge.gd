extends Node
## Publishes game state to window.__game on web builds so browser tests can
## read it. Systems register a provider returning a Dictionary; the bridge
## merges them into one flat object and knows nothing about gameplay.

const INTERVAL := 0.05

var _providers: Dictionary = {}
var _accum := 0.0


func register(key: StringName, provider: Callable) -> void:
	_providers[key] = provider


func unregister(key: StringName) -> void:
	_providers.erase(key)


func snapshot() -> Dictionary:
	var state := {
		"booted": true,
		"version": ProjectSettings.get_setting("application/config/version", "dev"),
	}
	var stale: Array[StringName] = []
	for key: StringName in _providers:
		var provider: Callable = _providers[key]
		if provider.is_valid():
			state.merge(provider.call(), true)
		else:
			stale.append(key)
	for key in stale:
		_providers.erase(key)
	return state


func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_accum += delta
	if _accum < INTERVAL:
		return
	_accum = 0.0
	JavaScriptBridge.eval("window.__game = %s;" % JSON.stringify(snapshot()), true)
