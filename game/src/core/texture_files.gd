class_name TextureFiles
extends RefCounted
## Loads shipped art. Art is produced as PNG and shipped as WebP, so a path that
## names a .png is tried as .webp first. Returns null when neither exists.


static func load_texture(path: String) -> Texture2D:
	for candidate in [path.get_basename() + ".webp", path]:
		if ResourceLoader.exists(candidate):
			return load(candidate) as Texture2D
	return null
