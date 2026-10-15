extends State


func enter() -> void:
	character.play(character.anim_interact)


func update(delta: float) -> String:
	character.stop_move(delta)
	if not character.is_on_floor():
		return "Falling"
	if character.is_key(KEY_E):
		return ""
	if character.is_moving():
		return "Walking"
	return "Idle"
