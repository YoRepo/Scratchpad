extends Node
## Global signal bus for notifications that cross system boundaries.
## Emitters do not know their listeners. Keep it small: when two nodes can
## reasonably talk directly, they should.

signal interactable_focused(interactable: Interactable)
signal interactable_unfocused(interactable: Interactable)
signal level_change_requested(level_path: String, spawn_name: StringName)
signal level_changed(level: Level)
