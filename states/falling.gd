extends State
## In the air without having jumped (walked off a ledge, spawned above ground).

## Falls shorter than this just resume walking/idle with no landing animation,
## so small bumps and slopes don't trigger it.
@export var min_air_time_for_landing := 0.3

var _air_time := 0.0


func enter() -> void:
	_air_time = 0.0
	character.play(character.anim_fall)


func update(delta: float) -> String:
	_air_time += delta
	character.apply_move(delta)
	if character.is_on_floor():
		if _air_time >= min_air_time_for_landing:
			return "Landing"
		return "Walking" if character.is_moving() else "Idle"
	return ""
