extends Node
## Runs one conversation at a time and tells listeners what to show.
## The UI subscribes to the signals; gameplay asks is_active().

signal started(data: DialogueData)
signal line_changed(speaker: String, text: String, index: int, total: int)
## Emitted when the last line is shown and the data offers choices.
signal choices_offered(options: PackedStringArray)
signal ended

## Index of the option picked in the conversation that just ended (-1 if none).
var last_choice := -1

var _data: DialogueData
var _index := -1
var _last_start := "never"
var _awaiting_choice := false


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
	last_choice = -1
	_awaiting_choice = false
	started.emit(data)
	_emit_line()
	return true


func advance() -> void:
	if not is_active() or _awaiting_choice:
		return
	_index += 1
	if _index >= _data.lines.size():
		_finish()
	else:
		_emit_line()


## Picks one of the offered choices and ends the conversation.
func choose(index: int) -> void:
	if not is_active() or not _awaiting_choice:
		return
	last_choice = clampi(index, 0, _data.choices.size() - 1)
	_awaiting_choice = false
	_finish()


func is_awaiting_choice() -> bool:
	return _awaiting_choice


func debug_state() -> Dictionary:
	return {
		"dialogue_active": is_active(),
		"dialogue_index": _index,
		"dialogue_total": _data.lines.size() if is_active() else 0,
		"dialogue_last_start": _last_start,
		"dialogue_choices": _awaiting_choice,
		"dialogue_last_choice": last_choice,
	}


func _emit_line() -> void:
	line_changed.emit(_data.speaker, _data.lines[_index], _index, _data.lines.size())
	if _index == _data.lines.size() - 1 and not _data.choices.is_empty():
		_awaiting_choice = true
		choices_offered.emit(_data.choices)


func _finish() -> void:
	_data = null
	_index = -1
	ended.emit()
