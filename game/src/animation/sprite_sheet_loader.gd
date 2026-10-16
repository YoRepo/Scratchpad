class_name SpriteSheetLoader
extends RefCounted
## Builds SpriteFrames from a character folder produced by the art pipeline
## (tools/art/cycle.py): <folder>/character.json lists the animations, and each
## <folder>/anim/<name>.json + <name>.png holds one sheet. See tools/art/CONVENTIONS.md.

## Everything the runtime needs to draw a character: its frames, where each
## animation's origin (feet centre) sits inside a frame, and the world scale.
class CharacterSet:
	var frames := SpriteFrames.new()
	var origins: Dictionary = {}
	var scale := 1.0
	var names: Array[StringName] = []


static func load_character(folder: String) -> CharacterSet:
	var meta := _read_json(folder.path_join("character.json"))
	if meta.is_empty():
		return null
	var character_set := CharacterSet.new()
	var world_height: float = meta.get("world_height", 84.0)
	var source_height: float = meta.get("source_height", 560.0)
	var frame_scale: float = meta.get("frame_scale", 0.4)
	character_set.scale = world_height / (source_height * frame_scale)
	for name in meta.get("animations", []):
		if _add_animation(character_set, folder.path_join("anim"), String(name)):
			character_set.names.append(StringName(name))
	if character_set.frames.has_animation(&"default"):
		character_set.frames.remove_animation(&"default")
	return character_set


static func _add_animation(character_set: CharacterSet, folder: String, name: String) -> bool:
	var meta := _read_json(folder.path_join(name + ".json"))
	var texture := _load_sheet(folder, name)
	if meta.is_empty() or texture == null:
		push_warning("SpriteSheetLoader: missing animation '%s' in %s" % [name, folder])
		return false
	var animation := StringName(name)
	var frames := character_set.frames
	frames.add_animation(animation)
	frames.set_animation_speed(animation, float(meta.get("fps", 12.0)))
	frames.set_animation_loop(animation, bool(meta.get("loop", false)))
	var columns := int(meta.get("columns", 12))
	var width := int(meta.get("width", 0))
	var height := int(meta.get("height", 0))
	for index in int(meta.get("frames", 0)):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2((index % columns) * width, (index / columns) * height, width, height)
		frames.add_frame(animation, atlas)
	var origin: Array = meta.get("origin", [width / 2.0, height])
	character_set.origins[animation] = Vector2(float(origin[0]), float(origin[1]))
	return true


## Sheets ship as WebP (tools/art/finalize_sheets.py); PNG is the pipeline's working format.
static func _load_sheet(folder: String, name: String) -> Texture2D:
	for extension in ["webp", "png"]:
		var path := folder.path_join("%s.%s" % [name, extension])
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
