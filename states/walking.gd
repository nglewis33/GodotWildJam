extends State
## Stays active while slowing down so the walk animation covers the whole stop.

const STOP_SPEED := 0.05


func enter() -> void:
	character.play(character.anim_walk)


func update(delta: float) -> String:
	character.apply_move(delta)
	character.sync_anim_speed()
	if not character.is_on_floor():
		return "Falling"
	if character.wants_jump():
		return "Jumping"
	if character.is_key(KEY_E):
		return "Interacting"
	if not character.is_moving() and character.horizontal_speed() < STOP_SPEED:
		return "Idle"
	return ""
