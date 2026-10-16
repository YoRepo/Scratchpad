class_name HUD
extends CanvasLayer
## Heads-up display: version, status line, interaction prompt, orientation
## hint. The DialogueBox child manages itself.

const TOAST_SECONDS := 2.2
const HINT_SECONDS := 12.0
const UI_FOLDER := "res://assets/ui"
const ITEM_FOLDER := "res://assets/items"

var _player: Player
var _level_name := ""
var _prompt_text := ""
var _toast_left := 0.0
var _hint_left := HINT_SECONDS

@onready var _title: Label = $Title
@onready var _hint: Label = $Hint
@onready var _status: Label = $Status
@onready var _prompt: Label = $Prompt
@onready var _rotate: Label = $Rotate
@onready var _hp_bar: Control = $Vitals/HpBar
@onready var _hp_back: ColorRect = $Vitals/HpBar/Back
@onready var _hp_fill: ColorRect = $Vitals/HpBar/Fill
@onready var _hp_frame: TextureRect = $Vitals/HpBar/Frame
@onready var _hp_label: Label = $Vitals/HpBar/Value
@onready var _coin_icon: TextureRect = $Vitals/CoinIcon
@onready var _coins_label: Label = $Vitals/Coins
@onready var _quest_title: Label = $QuestTracker/Title
@onready var _quest_lines: RichTextLabel = $QuestTracker/Lines
@onready var _quest_tracker: VBoxContainer = $QuestTracker
@onready var _toast: Label = $Toast
@onready var _bag_button: Button = $BagButton
@onready var _inventory_panel: PanelContainer = $InventoryPanel
@onready var _inventory_list: RichTextLabel = $InventoryPanel/Margin/Rows/Items
@onready var _dialogue_box: PanelContainer = $DialogueBox


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
	_apply_painted_style()
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
	if _hint.visible and _hint_left > 0.0:
		_hint_left -= delta
		_hint.visible = _hint_left > 0.0


## Parchment frames, the health bar frame and the coin icon, when the art exists.
func _apply_painted_style() -> void:
	var frame := TextureFiles.load_texture(UI_FOLDER + "/dialogue_frame_small.png")
	if frame != null:
		_dialogue_box.add_theme_stylebox_override("panel", _nine_slice(frame, 30, 26))
	var panel := TextureFiles.load_texture(UI_FOLDER + "/panel_small.png")
	if panel != null:
		_inventory_panel.add_theme_stylebox_override("panel", _nine_slice(panel, 28, 24))
		_bag_button.add_theme_stylebox_override("normal", _nine_slice(panel, 12, 10))
		_bag_button.add_theme_stylebox_override("hover", _nine_slice(panel, 12, 10))
		_bag_button.add_theme_stylebox_override("pressed", _nine_slice(panel, 12, 10))
		_bag_button.add_theme_color_override("font_color", Color(0.3, 0.18, 0.08))
		_bag_button.add_theme_color_override("font_pressed_color", Color(0.5, 0.2, 0.1))
		_bag_button.add_theme_color_override("font_hover_color", Color(0.3, 0.18, 0.08))
	var hp_frame := TextureFiles.load_texture(UI_FOLDER + "/hp_frame_small.png")
	if hp_frame != null:
		_hp_frame.texture = hp_frame
		_hp_frame.visible = true
		_hp_back.visible = false
		_hp_fill.offset_left = 9.0
		_hp_fill.offset_right = -9.0
		_hp_fill.offset_top = 6.0
		_hp_fill.offset_bottom = -6.0
	var coin := TextureFiles.load_texture(UI_FOLDER + "/coin_hud.png")
	if coin != null:
		_coin_icon.texture = coin
		_coin_icon.visible = true


static func _nine_slice(texture: Texture2D, side: int, top: int) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = side
	style.texture_margin_right = side
	style.texture_margin_top = top
	style.texture_margin_bottom = top
	style.content_margin_left = side * 0.7
	style.content_margin_right = side * 0.7
	style.content_margin_top = top * 0.5
	style.content_margin_bottom = top * 0.5
	return style


static func item_icon_bbcode(item_id: StringName, size: int) -> String:
	var item := ItemCatalog.get_item(item_id)
	var path := item.icon_path if item != null else ""
	for candidate in [path.get_basename() + ".webp", path]:
		if candidate != "" and ResourceLoader.exists(candidate):
			return "[img=%d]%s[/img] " % [size, candidate]
	return ""


func toggle_inventory() -> void:
	_inventory_panel.visible = not _inventory_panel.visible
	_refresh_inventory()
	GameEvents.panel_toggled.emit(_inventory_panel.visible)


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
	var lines := PackedStringArray()
	for item_id in quest.required_items:
		var item := ItemCatalog.get_item(item_id)
		var label := item.display_name if item != null else String(item_id)
		var needed := int(quest.required_items[item_id])
		var have := mini(Inventory.count_of(item_id), needed)
		var icon := item_icon_bbcode(item_id, 16)
		lines.append("%s%s %d/%d" % [icon, label, have, needed])
	_quest_lines.text = "[right]" + "\n".join(lines) + "[/right]"


func _refresh_inventory() -> void:
	if not _inventory_panel.visible:
		return
	var rows := PackedStringArray()
	var counts := Inventory.items()
	for id in counts:
		var item := ItemCatalog.get_item(id)
		var label := item.display_name if item != null else String(id)
		rows.append("%s%s  x%d" % [item_icon_bbcode(id, 22), label, counts[id]])
	rows.append("%s%d coins" % [item_icon_bbcode(&"coin", 22), Inventory.coins])
	if rows.size() > 1:
		_inventory_list.text = "\n".join(rows)
	else:
		_inventory_list.text = "Nothing yet, apart from pocket lint."


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
