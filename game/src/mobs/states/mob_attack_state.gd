extends MobState
## One attack: a hop onto the knight, a charge past him, or just a lunge of
## contact damage for crawlers. Contact damage is dealt by the ContactDamage
## area the whole time the creature is alive; this state only moves the body.

var _time := 0.0
var _duration := 0.6


func enter(_from: StringName) -> void:
	_time = 0.0
	mob.mark_attack()
	var direction := mob.direction_to_target()
	mob.face(direction)
	mob.visual_play(&"attack" if mob.visual_has(&"attack") else &"move", true)
	match mob.config.behaviour:
		MobConfig.Behaviour.HOP:
			mob.velocity = Vector2(direction * mob.config.move_speed * 2.2, -mob.config.attack_speed)
			_duration = 0.9
		MobConfig.Behaviour.CHARGE:
			mob.velocity.x = direction * mob.config.attack_speed
			_duration = 0.7
		_:
			mob.velocity.x = direction * mob.config.move_speed * 1.6
			_duration = 0.5


func physics_update(delta: float) -> StringName:
	_time += delta
	mob.apply_gravity(delta)
	if mob.config.behaviour == MobConfig.Behaviour.CRAWL and _time > 0.25:
		mob.velocity.x = 0.0
	if mob.config.behaviour == MobConfig.Behaviour.CHARGE and (mob.is_on_wall() or mob.at_ledge()):
		mob.velocity.x = 0.0
	mob.move_and_slide()
	if _time >= _duration and (mob.is_on_floor() or mob.config.behaviour != MobConfig.Behaviour.HOP):
		return CHASE
	return &""
