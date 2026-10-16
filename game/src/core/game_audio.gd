extends Node
## Autoload (GameAudio): the one place that decides which sound plays for
## which event. Listens to the game's signals and forwards to SoundBank when
## that autoload exists, so the game runs silently without the audio pack.

const SFX := {
	"jump": &"jump", "land": &"land", "attack": &"sword_swing", "hurt": &"hurt_player",
	"mob_hurt": &"hit_enemy", "mob_shell": &"hit_shell", "mob_die": &"enemy_die",
	"coin": &"coin", "item": &"item_pickup", "quest_accept": &"quest_accept",
	"quest_complete": &"quest_complete", "blip": &"dialogue_blip", "ui_open": &"ui_open",
	"ui_close": &"ui_close", "respawn": &"respawn", "ladder": &"ladder_step",
}
const FOOTSTEPS: Array[StringName] = [&"footstep_1", &"footstep_2"]

var _bank: Node
var _step_index := 0


func _ready() -> void:
	_bank = get_tree().root.get_node_or_null("SoundBank")
	GameEvents.player_jumped.connect(func() -> void: _sfx("jump"))
	GameEvents.player_landed.connect(func() -> void: _sfx("land"))
	GameEvents.player_attacked.connect(func() -> void: _sfx("attack"))
	GameEvents.player_hurt.connect(func() -> void: _sfx("hurt"))
	GameEvents.player_footstep.connect(_on_footstep)
	GameEvents.player_ladder_step.connect(func() -> void: _sfx("ladder"))
	GameEvents.panel_toggled.connect(func(opened: bool) -> void:
		_sfx("ui_open" if opened else "ui_close"))
	GameEvents.player_respawned.connect(func() -> void: _sfx("respawn"))
	GameEvents.mob_hurt.connect(_on_mob_hurt)
	GameEvents.mob_killed.connect(func(_mob: Mob) -> void: _sfx("mob_die"))
	GameEvents.pickup_collected.connect(func(pickup: Pickup) -> void:
		_sfx("coin" if pickup.coins > 0 else "item"))
	GameEvents.music_requested.connect(play_music)
	GameEvents.level_changed.connect(func(level: Level) -> void:
		if level.music != &"":
			play_music(level.music))
	QuestLog.quest_accepted.connect(func(_quest: QuestData) -> void: _sfx("quest_accept"))
	QuestLog.quest_completed.connect(func(_quest: QuestData) -> void: _sfx("quest_complete"))
	DialogueRunner.line_changed.connect(
		func(_speaker: String, _text: String, _index: int, _total: int) -> void: _sfx("blip"))


func play_music(track: StringName) -> void:
	if _bank != null and _bank.has_method("play_music"):
		_bank.play_music(track)


func _on_footstep() -> void:
	_step_index = (_step_index + 1) % FOOTSTEPS.size()
	if _bank != null and _bank.has_method("play_sfx"):
		_bank.play_sfx(FOOTSTEPS[_step_index], -6.0)


func _on_mob_hurt(mob: Mob) -> void:
	_sfx("mob_shell" if mob.config.behaviour == MobConfig.Behaviour.CRAWL else "mob_hurt")


func _sfx(cue: String) -> void:
	if _bank != null and _bank.has_method("play_sfx"):
		_bank.play_sfx(SFX[cue])
