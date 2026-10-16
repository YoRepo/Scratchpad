class_name Prop
extends Sprite2D
## A painted scenery piece placed at its ground contact point. Looks itself up
## in assets/props/props.json; draws a labelled box until the art exists.

const CATALOG := "res://assets/props/props.json"

static var _catalog: Dictionary = {}
static var _catalog_loaded := false

@export var prop_name: StringName = &""
## World height; 0 uses the catalog's height.
@export var height_override := 0.0
@export var mirrored := false

var _placeholder_size := Vector2(60, 60)


func _ready() -> void:
	_load_catalog()
	var entry: Dictionary = _catalog.get(String(prop_name), {})
	var height: float = height_override if height_override > 0.0 else float(entry.get("height", 60.0))
	var path: String = "res://assets/props/%s" % entry.get("file", "") if not entry.is_empty() else ""
	var loaded := load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
	if loaded == null:
		_placeholder_size = Vector2(height * 0.8, height)
		queue_redraw()
		return
	texture = loaded
	centered = false
	var factor := height / float(texture.get_height())
	scale = Vector2(factor * (-1.0 if mirrored else 1.0), factor)
	var inset := float(entry.get("ground_inset", 0.0))
	offset = Vector2(-texture.get_width() / 2.0, -(texture.get_height() - inset))


func _draw() -> void:
	if texture != null:
		return
	var size := _placeholder_size
	var rect := Rect2(-size.x / 2.0, -size.y, size.x, size.y)
	draw_rect(rect, Color(0.5, 0.42, 0.34, 0.9))
	draw_rect(rect, Color(0.25, 0.2, 0.15), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 4, -_placeholder_size.y / 2.0),
		String(prop_name), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, 10, Color(1, 1, 1, 0.9))


static func _load_catalog() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	if not FileAccess.file_exists(CATALOG):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if parsed is Dictionary:
		_catalog = parsed
