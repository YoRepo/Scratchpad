class_name DialogueData
extends Resource
## What a character says, in order. Linear for now; branching and choices
## belong here when they arrive, not in the NPC or the UI.

@export var speaker := ""
@export_multiline var lines: PackedStringArray = []
