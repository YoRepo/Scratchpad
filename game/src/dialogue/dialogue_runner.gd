extends Node
## Runs one conversation at a time and tells listeners what to show.
## The UI subscribes to the signals; gameplay asks is_active().

signal started(data: DialogueData)
signal line_changed(speaker: String, text: String, index: int, total: int)
signal ended

var _data: DialogueData
var _index := -1
var _last_start := "never"


func _ready() -> void:
	DebugBridge.register(&"dialogue", debug_state)


func is_active() -> bool:
	return _data != null


## Starts the conversation. Returns false if one is already running or the
## data has nothing to say.
func start(data: DialogueData, _speaker_node: Node = null) -> bool:
	if is_active():
		_last_start = "busy"
		return false
	if data == null:
		_last_start = "no data"
		return false
	if data.lines.is_empty():
		_last_start = "no lines"
		return false
	_last_start = "ok"
	_data = data
	_index = 0
	started.emit(data)
	_emit_line()
	return true


func advance() -> void:
	if not is_active():
		return
	_index += 1
	if _index >= _data.lines.size():
		_finish()
	else:
		_emit_line()


func debug_state() -> Dictionary:
	return {
		"dialogue_active": is_active(),
		"dialogue_index": _index,
		"dialogue_total": _data.lines.size() if is_active() else 0,
		"dialogue_last_start": _last_start,
	}


func _emit_line() -> void:
	line_changed.emit(_data.speaker, _data.lines[_index], _index, _data.lines.size())


func _finish() -> void:
	_data = null
	_index = -1
	ended.emit()
