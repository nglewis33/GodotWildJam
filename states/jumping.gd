extends State
## Crouch (Jump_Start), launch, airborne loop (Jump), then hand over to Landing.

@export var jump_velocity := 8.0
## Seconds from pressing jump to leaving the ground, so the crouch animation
## can play first. 0 = launch immediately.
@export var launch_delay := 0.0

var _time := 0.0
var _launched := false


func enter() -> void:
	_time = 0.0
	_launched = false
	character.start_jump_cooldown()
	character.play(character.anim_jump_start)
	if launch_delay <= 0.0:
		_launch()


func update(delta: float) -> String:
	character.apply_move(delta)
	_time += delta
	if not _launched and _time >= launch_delay:
		_launch()

	# Once the start animation is done, switch to the airborne loop.
	var anim: AnimationPlayer = character.anim
	if _launched and anim and anim.current_animation == character.anim_jump_start \
			and (not anim.is_playing() or anim.current_animation_position >= anim.current_animation_length - 0.02):
		character.play(character.anim_jump)

	# Only count a landing once we're no longer moving upward.
	if _launched and character.velocity.y <= 0.0 and character.is_on_floor():
		return "Landing"
	return ""


func _launch() -> void:
	_launched = true
	character.velocity.y = jump_velocity
