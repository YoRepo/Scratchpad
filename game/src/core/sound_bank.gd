extends Node
## Autoload (SoundBank): the one place that plays sound. Effects go through a
## small pool of players (polyphony SFX_POLYPHONY, oldest voice stolen when
## full); music loops on one of two players that cross-fade when the track
## changes. Streams load lazily by name from res://assets/audio: effects are
## sfx/<name>.wav, music is music/<name>.ogg (set to loop in code). A missing
## file warns once and is then silently ignored, so gameplay never depends on
## an asset existing. Everything plays on the Master bus. The catalogue and
## the generator live in tools/audio.

const SFX_PATH_FORMAT := "res://assets/audio/sfx/%s.wav"
const MUSIC_PATH_FORMAT := "res://assets/audio/music/%s.ogg"
const SFX_POLYPHONY := 8
## Largest pitch nudge, as a fraction, when a call asks for pitch variation.
const PITCH_JITTER := 0.04
const SILENCE_DB := -60.0
const BUS: StringName = &"Master"

## Trim applied to every music track so it sits under the effects.
var music_volume_db := -6.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _sfx_plays := 0
var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _current_music: StringName = &""
## Path -> AudioStream, or null for a file that was looked up and is missing.
var _streams: Dictionary = {}
var _fade: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_POLYPHONY:
		_sfx_players.append(_make_player("Sfx%d" % i))
	for i in 2:
		_music_players.append(_make_player("Music%d" % i))
	_register_debug.call_deferred()


## Plays the effect `name` (assets/audio/sfx/<name>.wav) once. `volume_db`
## offsets the file's own level; `randomize_pitch` nudges the pitch by up to
## PITCH_JITTER so repeated footsteps and hits do not sound stamped out.
func play_sfx(name: StringName, volume_db := 0.0, randomize_pitch := false) -> void:
	var stream := _stream(SFX_PATH_FORMAT % name)
	if stream == null:
		return
	var player := _free_sfx_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0
	if randomize_pitch:
		player.pitch_scale += _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	player.play()
	_sfx_plays += 1


## Cross-fades from whatever is playing to the loop `name`
## (assets/audio/music/<name>.ogg) over `fade_seconds`. Asking for the track
## that is already playing does nothing.
func play_music(name: StringName, fade_seconds := 1.0) -> void:
	if name == _current_music:
		return
	var stream := _stream(MUSIC_PATH_FORMAT % name)
	if stream == null:
		return
	_current_music = name
	var outgoing := _music_players[_music_active]
	_music_active = 1 - _music_active
	var incoming := _music_players[_music_active]
	incoming.stream = stream
	incoming.volume_db = SILENCE_DB
	incoming.play()
	_crossfade(outgoing, incoming, fade_seconds)


## Fades the music out over `fade_seconds` and stops it.
func stop_music(fade_seconds := 1.0) -> void:
	_current_music = &""
	_crossfade(_music_players[_music_active], null, fade_seconds)


func current_music() -> StringName:
	return _current_music


## Loads a stream the first time it is asked for and caches it; a miss is
## cached too, so the warning fires once per path.
func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path] as AudioStream
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		push_warning("SoundBank: no audio at %s" % path)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_streams[path] = stream
	return stream


## The first idle effect player after the last one used, or, when all are
## busy, the one that has been playing longest.
func _free_sfx_player() -> AudioStreamPlayer:
	for offset in SFX_POLYPHONY:
		var index := (_sfx_next + offset) % SFX_POLYPHONY
		if not _sfx_players[index].playing:
			_sfx_next = (index + 1) % SFX_POLYPHONY
			return _sfx_players[index]
	var stolen := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_POLYPHONY
	return stolen


## Fades `outgoing` to silence and stops it while `incoming` (if any) rises to
## music_volume_db. A fade already in progress is replaced.
func _crossfade(outgoing: AudioStreamPlayer, incoming: AudioStreamPlayer, seconds: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if seconds <= 0.0:
		outgoing.stop()
		if incoming != null:
			incoming.volume_db = music_volume_db
		return
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(outgoing, "volume_db", SILENCE_DB, seconds)
	if incoming != null:
		_fade.tween_property(incoming, "volume_db", music_volume_db, seconds)
	_fade.chain().tween_callback(outgoing.stop)


func _make_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = BUS
	add_child(player)
	return player


func _register_debug() -> void:
	DebugBridge.register(&"sound", _debug_state)


func _debug_state() -> Dictionary:
	var busy := 0
	for player in _sfx_players:
		if player.playing:
			busy += 1
	return {"music": String(_current_music), "sfx_plays": _sfx_plays, "sfx_busy": busy}
