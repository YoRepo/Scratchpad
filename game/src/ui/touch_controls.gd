class_name TouchControls
extends CanvasLayer
## Thumb-friendly touch controls for phones held in landscape: a floating
## virtual joystick for the left thumb and round JUMP / ATTACK / INTERACT
## buttons for the right thumb. Everything emits the same input actions as the
## keyboard, so gameplay never knows which device pressed. The layout follows
## the visible viewport, which widens on phones (stretch aspect "expand").
##
## Painted art is loaded from res://assets/ui/ when present (joystick_base.png,
## joystick_knob.png, button_jump.png, button_attack.png, button_interact.png)
## and scaled to the sizes below; otherwise soft translucent circles are built
## in code. Swapping the PNGs needs no code change.

const ART_FOLDER := "res://assets/ui"

# Stick geometry, in logical pixels.
const STICK_RADIUS := 48.0
const STICK_BASE_DIAMETER := 136.0
const STICK_KNOB_DIAMETER := 44.0
## A touch that begins in this left fraction of the screen, below the HUD
## strip, spawns the stick at the touch point.
const STICK_ZONE_WIDTH := 0.45
const STICK_ZONE_TOP := 40.0
const STICK_REST_MARGIN := 20.0
const STICK_REST_ALPHA := 0.35
const STICK_ACTIVE_ALPHA := 0.95
const STICK_FADE_SECONDS := 0.25

# Stick response, as fractions of STICK_RADIUS.
const DEAD_ZONE := 0.18
## Horizontal strength reaches 1.0 at this |x|, so a normal push runs at
## full speed and a light nudge walks slowly for lining up with ladders.
const FULL_RUN := 0.7
const VERTICAL_PRESS := 0.55
const VERTICAL_RELEASE := 0.4
## While the stick is this vertical (and this little sideways) horizontal
## output is suppressed, so climbing never drifts off the ladder.
const VERTICAL_LOCK_Y := 0.8
const VERTICAL_LOCK_X := 0.35

# Buttons.
const BUTTON_SIZE := 68.0
const MARGIN := 14.0
const GAP := 10.0
const ATTACK_RAISE := 22.0
const PRESSED_TINT := Color(1.35, 1.35, 1.35)
## name, action, art file, label, label font size.
const BUTTONS := [
	["Jump", InputActions.JUMP, "button_jump.png", "JUMP", 14],
	["Attack", InputActions.ATTACK, "button_attack.png", "ATK", 16],
	["Interact", InputActions.INTERACT, "button_interact.png", "TALK", 14],
]

var _buttons: Dictionary = {}
var _interact_label: Label
var _stick: Node2D
var _knob: Sprite2D
var _stick_anchor := Vector2.ZERO
## Touch index driving the stick, or -1 while it rests.
var _stick_touch := -1
var _stick_tween: Tween
## -1 up, 1 down, 0 neither; kept between events for the hysteresis.
var _vertical := 0
## Actions the stick currently holds, with the strength last sent.
var _held: Dictionary = {}


func _ready() -> void:
	visible = DeviceInfo.has_touch
	set_process_input(visible)
	set_process_unhandled_input(visible)
	_build_stick()
	for spec: Array in BUTTONS:
		var button := _make_button(spec)
		add_child(button)
		_buttons[spec[0]] = button
	_interact_label = _buttons["Interact"].get_node("Label")
	_buttons["Interact"].visible = false
	GameEvents.interactable_focused.connect(_on_interactable_focused)
	GameEvents.interactable_unfocused.connect(_on_interactable_unfocused)
	get_viewport().size_changed.connect(_layout)
	_layout()
	DebugBridge.register(&"touch_controls", debug_state)


func _exit_tree() -> void:
	for action: StringName in _held:
		Input.action_release(action)
	_held.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_stick()


## Once the stick owns a touch index, every later event of that index is its
## own, wherever the finger wanders.
func _input(event: InputEvent) -> void:
	if _stick_touch < 0:
		return
	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _stick_touch:
		_move_stick(drag.position)
		get_viewport().set_input_as_handled()
		return
	var touch := event as InputEventScreenTouch
	if touch != null and touch.index == _stick_touch and not touch.pressed:
		_release_stick()
		get_viewport().set_input_as_handled()


## A fresh touch arrives here only when no button or UI control claimed it.
func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed or _stick_touch >= 0:
		return
	if not _stick_zone().has_point(touch.position):
		return
	_grab_stick(touch.index, touch.position)
	get_viewport().set_input_as_handled()


## Screen-space geometry for the browser smoke test: the centre of every
## button, and the resting stick anchor plus its radius, in screen pixels.
func debug_state() -> Dictionary:
	var to_screen := get_viewport().get_screen_transform()
	var centers := {}
	for name: String in _buttons:
		var root: Node2D = _buttons[name]
		var to_canvas := root.get_global_transform_with_canvas()
		var center: Vector2 = to_screen * to_canvas * (Vector2.ONE * BUTTON_SIZE * 0.5)
		centers[name.to_lower()] = {"x": snappedf(center.x, 0.1), "y": snappedf(center.y, 0.1)}
	var layer_to_screen := to_screen * get_final_transform()
	var anchor := layer_to_screen * _stick_anchor
	var radius := layer_to_screen.basis_xform(Vector2(STICK_RADIUS, 0.0)).length()
	var vp := get_viewport().get_visible_rect().size
	var stick := {
		"x": snappedf(anchor.x, 0.1), "y": snappedf(anchor.y, 0.1), "radius": snappedf(radius, 0.1),
	}
	return {"buttons": centers, "stick": stick, "viewport": {"w": vp.x, "h": vp.y}}


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var bottom := vp.y - MARGIN - BUTTON_SIZE
	var right := vp.x - MARGIN - BUTTON_SIZE
	_buttons["Jump"].position = Vector2(right, bottom)
	_buttons["Attack"].position = Vector2(right - BUTTON_SIZE - GAP, bottom - ATTACK_RAISE)
	_buttons["Interact"].position = Vector2(right, bottom - BUTTON_SIZE - GAP)
	var half := STICK_BASE_DIAMETER * 0.5
	_stick_anchor = Vector2(STICK_REST_MARGIN + half, vp.y - STICK_REST_MARGIN - half)
	if _stick_touch < 0:
		_stick.position = _stick_anchor


func _stick_zone() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	return Rect2(0.0, STICK_ZONE_TOP, vp.x * STICK_ZONE_WIDTH, vp.y - STICK_ZONE_TOP)


# --- Stick ---------------------------------------------------------------------


func _grab_stick(index: int, at: Vector2) -> void:
	_stick_touch = index
	_vertical = 0
	_fade_stick(STICK_ACTIVE_ALPHA, 0.0)
	_stick.position = at
	_knob.position = Vector2.ZERO


func _move_stick(at: Vector2) -> void:
	var vector := (at - _stick.position) / STICK_RADIUS
	if vector.length() > 1.0:
		vector = vector.normalized()
	_knob.position = vector * STICK_RADIUS
	_emit_stick(vector)


func _release_stick() -> void:
	if _stick_touch < 0:
		return
	_stick_touch = -1
	_vertical = 0
	for action: StringName in _held.keys():
		_set_action(action, 0.0)
	_knob.position = Vector2.ZERO
	_fade_stick(STICK_REST_ALPHA, STICK_FADE_SECONDS)


## Turns the knob offset (in radii) into action presses.
func _emit_stick(vector: Vector2) -> void:
	var v := vector if vector.length() >= DEAD_ZONE else Vector2.ZERO
	_vertical = _vertical_direction(v.y)
	var locked := absf(v.y) > VERTICAL_LOCK_Y and absf(v.x) < VERTICAL_LOCK_X
	var sideways := clampf((absf(v.x) - DEAD_ZONE) / (FULL_RUN - DEAD_ZONE), 0.0, 1.0)
	if locked:
		sideways = 0.0
	_set_action(InputActions.MOVE_LEFT, sideways if v.x < 0.0 else 0.0)
	_set_action(InputActions.MOVE_RIGHT, sideways if v.x > 0.0 else 0.0)
	_set_action(InputActions.MOVE_UP, 1.0 if _vertical < 0 else 0.0)
	_set_action(InputActions.MOVE_DOWN, 1.0 if _vertical > 0 else 0.0)


## Up or down with hysteresis: a held direction stays until the knob comes
## back past VERTICAL_RELEASE, so walking never flickers into crouching.
func _vertical_direction(y: float) -> int:
	if _vertical != 0 and y * float(_vertical) >= VERTICAL_RELEASE:
		return _vertical
	if y <= -VERTICAL_PRESS:
		return -1
	if y >= VERTICAL_PRESS:
		return 1
	return 0


## Presses or releases an action through Input, and mirrors press and release
## edges as InputEventAction so UI (the dialogue box) sees them like a
## TouchScreenButton's.
func _set_action(action: StringName, strength: float) -> void:
	var current: float = _held.get(action, 0.0)
	if is_equal_approx(strength, current):
		return
	if strength > 0.0:
		Input.action_press(action, strength)
		_held[action] = strength
		if current == 0.0:
			_push_action_event(action, true, strength)
		return
	Input.action_release(action)
	_held.erase(action)
	_push_action_event(action, false, 0.0)


func _push_action_event(action: StringName, pressed: bool, strength: float) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = strength
	get_viewport().push_input(event, true)


func _fade_stick(alpha: float, seconds: float) -> void:
	if _stick_tween != null and _stick_tween.is_valid():
		_stick_tween.kill()
	if seconds <= 0.0:
		_stick.modulate.a = alpha
		return
	_stick_tween = create_tween().set_parallel(true)
	_stick_tween.tween_property(_stick, "modulate:a", alpha, seconds)
	_stick_tween.tween_property(_stick, "position", _stick_anchor, seconds)


func _build_stick() -> void:
	_stick = Node2D.new()
	_stick.name = "Stick"
	_stick.modulate.a = STICK_REST_ALPHA
	var base := _make_sprite("Base", "joystick_base.png", STICK_BASE_DIAMETER, _make_ring_texture())
	_stick.add_child(base)
	_knob = _make_sprite("Knob", "joystick_knob.png", STICK_KNOB_DIAMETER, _make_knob_texture())
	_stick.add_child(_knob)
	add_child(_stick)


func _make_sprite(name: String, art_file: String, diameter: float, fallback: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = name
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var art := _load_art(art_file)
	sprite.texture = art if art != null else fallback
	sprite.scale = Vector2.ONE * diameter / sprite.texture.get_size()
	return sprite


# --- Buttons -------------------------------------------------------------------


func _on_interactable_focused(interactable: Interactable) -> void:
	_interact_label.text = interactable.prompt.get_slice(" ", 0).to_upper()
	_buttons["Interact"].visible = true


func _on_interactable_unfocused(_interactable: Interactable) -> void:
	_buttons["Interact"].visible = false


## A positioned root holding the (texture-scaled) TouchScreenButton and an
## unscaled label, so the label stays crisp whatever size the art comes in.
func _make_button(spec: Array) -> Node2D:
	var root := Node2D.new()
	root.name = spec[0]
	var button := TouchScreenButton.new()
	button.name = "Button"
	button.action = spec[1]
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var art := _load_art(spec[2])
	button.texture_normal = art if art != null else _make_button_texture(0.22)
	button.texture_pressed = art if art != null else _make_button_texture(0.5)
	button.passby_press = false
	button.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	var texture_size := button.texture_normal.get_size()
	button.scale = Vector2.ONE * BUTTON_SIZE / texture_size
	var circle := CircleShape2D.new()
	circle.radius = texture_size.x * 0.56
	button.shape = circle
	button.shape_visible = false
	button.pressed.connect(func() -> void: root.modulate = PRESSED_TINT)
	button.released.connect(func() -> void: root.modulate = Color.WHITE)
	root.add_child(button)
	var label := Label.new()
	label.name = "Label"
	label.text = spec[3]
	label.size = Vector2.ONE * BUTTON_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", spec[4])
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("outline_size", 3)
	# Painted jump and attack buttons carry their own glyph; the interact
	# label is dynamic (the interactable's verb) so it always shows.
	label.visible = art == null or spec[0] == "Interact"
	root.add_child(label)
	return root


# --- Textures ------------------------------------------------------------------


func _load_art(file: String) -> Texture2D:
	var path := "%s/%s" % [ART_FOLDER, file]
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	return load(path) as Texture2D


## Placeholder button: a translucent disc with a thin bright rim.
static func _make_button_texture(fill_alpha: float) -> GradientTexture2D:
	return _make_radial_texture(
		int(BUTTON_SIZE),
		PackedFloat32Array([0.0, 0.84, 0.9, 0.97, 1.0]),
		PackedColorArray([
			Color(1, 1, 1, fill_alpha), Color(1, 1, 1, fill_alpha),
			Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0),
		])
	)


## Placeholder stick base: a faint disc with a soft rim.
static func _make_ring_texture() -> GradientTexture2D:
	return _make_radial_texture(
		int(STICK_BASE_DIAMETER),
		PackedFloat32Array([0.0, 0.86, 0.92, 0.97, 1.0]),
		PackedColorArray([
			Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.14),
			Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0),
		])
	)


## Placeholder knob: a solid soft-edged disc.
static func _make_knob_texture() -> GradientTexture2D:
	return _make_radial_texture(
		int(STICK_KNOB_DIAMETER),
		PackedFloat32Array([0.0, 0.8, 0.92, 1.0]),
		PackedColorArray([
			Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0),
		])
	)


static func _make_radial_texture(
	size: int, offsets: PackedFloat32Array, colors: PackedColorArray
) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = size
	texture.height = size
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture
