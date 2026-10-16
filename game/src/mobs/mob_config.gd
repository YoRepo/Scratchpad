class_name MobConfig
extends Resource
## Everything that makes one creature kind what it is. Instances live in
## content/mobs/*.tres; the Mob scene reads them.

enum Behaviour { CRAWL, HOP, CHARGE }

@export var display_name := "Creature"
## Folder with character.json + anim sheets (empty = placeholder rectangle).
@export var animation_folder := ""
@export var world_height := 40.0
@export var world_width := 56.0
@export var max_hp := 30
@export var move_speed := 40.0
@export var behaviour: Behaviour = Behaviour.CRAWL
## HOP: launch velocity; CHARGE: dash speed.
@export var attack_speed := 180.0
@export var contact_damage := 10
@export var knockback := 200.0
## How far from home the creature wanders, and from how far it notices the knight.
@export var leash := 160.0
@export var aggro_range := 220.0
@export var attack_range := 90.0
@export var attack_cooldown := 1.6
@export var hurt_duration := 0.35
@export var respawn_seconds := 8.0
@export var drop_table: DropTable
