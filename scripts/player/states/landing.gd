extends State
## Plays Jump_Land after touching down, then returns to Walking or Idle.

## Safety limit in case the animation is missing or never finishes.
@export var max_land_time := 0.8

var _time := 0.0


func enter() -> void:
	_time = 0.0
	character.play(character.anim_jump_land)
	character.play_landing_sound()


func update(delta: float) -> String:
	character.stop_move(delta)
	_time += delta

	var anim: AnimationPlayer = character.anim
	var done := _time >= max_land_time
	if anim and anim.current_animation == character.anim_jump_land:
		done = done or not anim.is_playing() \
				or anim.current_animation_position >= anim.current_animation_length - 0.02
	else:
		done = true  # animation couldn't play (missing); don't get stuck

	if not character.is_on_floor():
		return "Falling"
	if done:
		return "Walking" if character.is_moving() else "Idle"
	return ""
