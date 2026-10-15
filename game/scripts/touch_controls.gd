class_name TouchControls
extends CanvasLayer
## On-screen buttons for touch devices. Hidden on desktop. The layout follows the
## visible viewport, which grows sideways on wide phones (stretch aspect "expand").

const BUTTON_SIZE := 72.0
const MARGIN := 18.0
const GAP := 12.0

@onready var left_button: TouchScreenButton = $Left
@onready var right_button: TouchScreenButton = $Right
@onready var jump_button: TouchScreenButton = $Jump
@onready var attack_button: TouchScreenButton = $Attack


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var row_y := vp.y - MARGIN - BUTTON_SIZE
	left_button.position = Vector2(MARGIN, row_y)
	right_button.position = Vector2(MARGIN + BUTTON_SIZE + GAP, row_y)
	attack_button.position = Vector2(vp.x - MARGIN - BUTTON_SIZE, row_y)
	jump_button.position = Vector2(vp.x - MARGIN - BUTTON_SIZE * 2.0 - GAP, row_y - 20.0)


## Screen-space centres of each button (canvas pixels), used by the browser smoke test to tap them.
func debug_button_centers() -> Dictionary:
	var centers := {}
	for button: TouchScreenButton in [left_button, right_button, jump_button, attack_button]:
		var to_screen := get_viewport().get_screen_transform() * button.get_global_transform_with_canvas()
		var center: Vector2 = to_screen * (Vector2.ONE * BUTTON_SIZE * 0.5)
		centers[String(button.name).to_lower()] = {"x": snappedf(center.x, 0.1), "y": snappedf(center.y, 0.1)}
	return centers
