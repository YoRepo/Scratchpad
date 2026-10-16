class_name TouchControls
extends CanvasLayer
## On-screen buttons for touch devices, built from the BUTTONS table below.
## They emit the same input actions as the keyboard, so gameplay never knows.
## Layout follows the visible viewport, which widens on phones (aspect "expand").

const BUTTON_SIZE := 64.0
const MARGIN := 16.0
const GAP := 10.0
## name, action, label, label font size, whether sliding a finger onto it presses it.
const BUTTONS := [
	["Left", InputActions.MOVE_LEFT, "<", 28, true],
	["Right", InputActions.MOVE_RIGHT, ">", 28, true],
	["Up", InputActions.MOVE_UP, "^", 28, true],
	["Down", InputActions.MOVE_DOWN, "v", 24, true],
	["Jump", InputActions.JUMP, "JUMP", 13, false],
	["Attack", InputActions.ATTACK, "ATK", 15, false],
	["Interact", InputActions.INTERACT, "TALK", 13, false],
]

var _buttons: Dictionary = {}
var _interact_label: Label


func _ready() -> void:
	visible = DeviceInfo.has_touch
	var normal := _make_texture(0.22)
	var pressed := _make_texture(0.5)
	for spec: Array in BUTTONS:
		var button := _make_button(spec, normal, pressed)
		add_child(button)
		_buttons[spec[0]] = button
	_interact_label = _buttons["Interact"].get_node("Label")
	_buttons["Interact"].visible = false
	GameEvents.interactable_focused.connect(_on_interactable_focused)
	GameEvents.interactable_unfocused.connect(_on_interactable_unfocused)
	get_viewport().size_changed.connect(_layout)
	_layout()
	DebugBridge.register(&"touch_controls", debug_state)


## Screen-space centres of every button (canvas pixels), for the smoke test.
func debug_state() -> Dictionary:
	var centers := {}
	var to_screen := get_viewport().get_screen_transform()
	for name: String in _buttons:
		var button: TouchScreenButton = _buttons[name]
		var to_canvas := button.get_global_transform_with_canvas()
		var center: Vector2 = to_screen * to_canvas * (Vector2.ONE * BUTTON_SIZE * 0.5)
		centers[name.to_lower()] = {"x": snappedf(center.x, 0.1), "y": snappedf(center.y, 0.1)}
	var vp := get_viewport().get_visible_rect().size
	return {"buttons": centers, "viewport": {"w": vp.x, "h": vp.y}}


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var row := vp.y - MARGIN - BUTTON_SIZE
	var step := BUTTON_SIZE + GAP
	_buttons["Left"].position = Vector2(MARGIN, row)
	_buttons["Right"].position = Vector2(MARGIN + step, row)
	_buttons["Up"].position = Vector2(MARGIN + step / 2.0, row - step)
	_buttons["Down"].position = Vector2(MARGIN + step * 2.0, row)
	_buttons["Attack"].position = Vector2(vp.x - MARGIN - BUTTON_SIZE, row)
	_buttons["Jump"].position = Vector2(vp.x - MARGIN - BUTTON_SIZE - step, row - 20.0)
	_buttons["Interact"].position = Vector2(vp.x - MARGIN - BUTTON_SIZE, row - step)


func _on_interactable_focused(interactable: Interactable) -> void:
	_interact_label.text = interactable.prompt.get_slice(" ", 0).to_upper()
	_buttons["Interact"].visible = true


func _on_interactable_unfocused(_interactable: Interactable) -> void:
	_buttons["Interact"].visible = false


func _make_button(spec: Array, normal: Texture2D, pressed: Texture2D) -> TouchScreenButton:
	var button := TouchScreenButton.new()
	button.name = spec[0]
	button.action = spec[1]
	button.texture_normal = normal
	button.texture_pressed = pressed
	button.passby_press = spec[4]
	button.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	var circle := CircleShape2D.new()
	circle.radius = BUTTON_SIZE * 0.56
	button.shape = circle
	button.shape_visible = false
	var label := Label.new()
	label.name = "Label"
	label.text = spec[2]
	label.size = Vector2.ONE * BUTTON_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", spec[3])
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	button.add_child(label)
	return button


static func _make_texture(fill_alpha: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.84, 0.9, 0.97, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, fill_alpha), Color(1, 1, 1, fill_alpha),
		Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = int(BUTTON_SIZE)
	texture.height = int(BUTTON_SIZE)
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture
