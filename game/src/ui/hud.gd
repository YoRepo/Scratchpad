class_name HUD
extends CanvasLayer
## Heads-up display: version, status line, interaction prompt, orientation
## hint. The DialogueBox child manages itself.

const TOAST_SECONDS := 2.2

var _player: Player
var _level_name := ""
var _prompt_text := ""
var _toast_left := 0.0

@onready var _title: Label = $Title
@onready var _hint: Label = $Hint
@onready var _status: Label = $Status
@onready var _prompt: Label = $Prompt
@onready var _rotate: Label = $Rotate
@onready var _hp_fill: ColorRect = $Vitals/HpBar/Fill
@onready var _hp_label: Label = $Vitals/HpBar/Value
@onready var _coins_label: Label = $Vitals/Coins
@onready var _quest_title: Label = $QuestTracker/Title
@onready var _quest_lines: Label = $QuestTracker/Lines
@onready var _quest_tracker: VBoxContainer = $QuestTracker
@onready var _toast: Label = $Toast
@onready var _bag_button: Button = $BagButton
@onready var _inventory_panel: PanelContainer = $InventoryPanel
@onready var _inventory_list: Label = $InventoryPanel/Margin/Rows/Items


func _ready() -> void:
	var version: String = ProjectSettings.get_setting("application/config/version", "dev")
	_title.text = "Scratchpad Side-Scroller  v%s" % version
	_hint.visible = not DeviceInfo.has_touch
	_prompt.visible = false
	GameEvents.interactable_focused.connect(_on_interactable_focused)
	GameEvents.interactable_unfocused.connect(_on_interactable_unfocused)
	GameEvents.level_changed.connect(_on_level_changed)
	GameEvents.player_health_changed.connect(_on_player_health_changed)
	GameEvents.pickup_collected.connect(_on_pickup_collected)
	Inventory.coins_changed.connect(_on_coins_changed)
	Inventory.item_changed.connect(func(_id: StringName, _count: int) -> void: _refresh_inventory())
	QuestLog.quest_accepted.connect(_on_quest_accepted)
	QuestLog.quest_progressed.connect(func(_quest: QuestData) -> void: _refresh_quest())
	QuestLog.quest_completed.connect(_on_quest_completed)
	DialogueRunner.started.connect(_on_dialogue_started)
	DialogueRunner.ended.connect(_on_dialogue_ended)
	_bag_button.pressed.connect(toggle_inventory)
	_inventory_panel.visible = false
	_toast.visible = false
	_quest_tracker.visible = false
	_on_coins_changed(Inventory.coins)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func _process(delta: float) -> void:
	if is_instance_valid(_player):
		_status.text = "%s | %s" % [_level_name, String(_player.state_machine.state_name())]
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.visible = _toast_left > 0.0


func toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible
	_refresh_inventory()


func show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = TOAST_SECONDS
	_toast.visible = true


func setup(player: Player) -> void:
	_player = player
	_on_player_health_changed(player.health.hp, player.health.max_hp)


func _on_player_health_changed(current: int, maximum: int) -> void:
	_hp_fill.anchor_right = float(current) / float(maxi(maximum, 1))
	_hp_label.text = "%d / %d" % [current, maximum]


func _on_coins_changed(total: int) -> void:
	_coins_label.text = "%d coins" % total


func _on_pickup_collected(pickup: Pickup) -> void:
	if pickup.item_id == &"":
		return
	var item := ItemCatalog.get_item(pickup.item_id)
	var label := item.display_name if item != null else String(pickup.item_id)
	show_toast("+%d %s" % [pickup.amount, label])


func _on_quest_accepted(quest: QuestData) -> void:
	show_toast("Quest accepted: %s" % quest.title)
	_refresh_quest()


func _on_quest_completed(quest: QuestData) -> void:
	show_toast("Quest complete: %s" % quest.title)
	_refresh_quest()


func _refresh_quest() -> void:
	var active := QuestLog.active_quests()
	_quest_tracker.visible = not active.is_empty()
	if active.is_empty():
		return
	var quest: QuestData = active[0]
	_quest_title.text = quest.title
	_quest_lines.text = "\n".join(quest.progress_lines())


func _refresh_inventory() -> void:
	if not _inventory_panel.visible:
		return
	var rows := PackedStringArray()
	var counts := Inventory.items()
	for id in counts:
		var item := ItemCatalog.get_item(id)
		rows.append("%s x%d" % [item.display_name if item != null else String(id), counts[id]])
	_inventory_list.text = "\n".join(rows) if not rows.is_empty() else "Nothing yet."


func _on_interactable_focused(interactable: Interactable) -> void:
	var key := "Tap the button" if DeviceInfo.has_touch else "Up or E"
	_prompt_text = "%s: %s %s" % [key, interactable.prompt, interactable.display_name]
	_refresh_prompt()


func _on_interactable_unfocused(_interactable: Interactable) -> void:
	_prompt_text = ""
	_refresh_prompt()


func _on_dialogue_started(_data: DialogueData) -> void:
	_refresh_prompt()


func _on_dialogue_ended() -> void:
	_refresh_prompt()


func _refresh_prompt() -> void:
	_prompt.text = _prompt_text
	_prompt.visible = _prompt_text != "" and not DialogueRunner.is_active()


func _on_level_changed(level: Level) -> void:
	_level_name = level.display_name
	_prompt_text = ""
	_refresh_prompt()


func _on_resize() -> void:
	var vp := get_viewport().get_visible_rect().size
	_rotate.visible = vp.y > vp.x
