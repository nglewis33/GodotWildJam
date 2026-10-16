extends CharacterBody3D
## State machine owner. Each child of the "States" node is a State script.
## Also handles WASD movement (relative to facing) and mouse turning.

@export var anim_idle := "Idle"
@export var anim_walk := "Walk"
@export var anim_sprint := "Sprint"
@export var anim_jump_start := "Jump_Start"
@export var anim_jump := "Jump"
@export var anim_jump_land := "Jump_Land"
@export var anim_fall := "Jump"
@export var anim_interact := "Interact"
@export var initial_state := "Idle"
@export var gravity := 20.0
## If we fall this far below the spawn point, teleport back to it.
@export var fall_limit := 100.0

@export_group("Movement")
@export var move_speed := 1.5
## Can the character steer and move forward while jumping or falling?
## If off, it keeps whatever momentum it had when it left the ground.
@export var air_movement := true
## Forward speed while in the air (used when air_movement is on).
@export var air_move_speed := 1.5
## How quickly we reach full speed / come to a stop (units per second squared).
@export var acceleration := 6.0
@export var deceleration := 8.0
## Seconds to cross-fade between animations.
@export var anim_blend := 0.2
## Seconds after jumping before the character can jump again.
@export var jump_cooldown := 1.0

@export_group("Sprint")
## Hold this key (with W) to run.
@export var sprint_key: Key = KEY_SHIFT
@export var sprint_speed := 3.0
## Forward speed in the air while sprinting (so jumping keeps your run speed).
@export var air_sprint_speed := 3.0
@export var max_stamina := 200.0
## Stamina used per second while running.
@export var stamina_drain := 20.0
## Stamina gained per second when not running.
@export var stamina_regen := 30.0
## Gain per second after running out; no running again until the bar is full.
@export var stamina_exhausted_regen := 20.0
## Each jump costs this much; you can't jump with less than this left.
@export var jump_stamina_cost := 30.0

@export_group("Audio")
## Landing plays a footstep at this volume multiplier.
@export var landing_volume_scale := 1.2

@export_group("Turning")
## Radians per pixel of mouse movement.
@export var mouse_sensitivity := 0.003
## Fastest the character can turn, in degrees per second (0 = no limit).
## Mouse movement beyond this is queued up and played out at this speed.
@export var max_turn_speed := 120.0
## Most turning (degrees) that can be queued up, so the character doesn't
## keep spinning long after you stop moving the mouse.
@export var max_queued_turn := 45.0

## Set to false (e.g. by the free camera) to ignore keyboard and mouse.
var input_enabled := true
var current_state: State
var states := {}
var _spawn_position: Vector3
var _pending_turn := 0.0  # radians still to turn
var _jump_cooldown_left := 0.0
var stamina := 200.0
var exhausted := false
var _sprinting := false
@onready var anim: AnimationPlayer = find_child("AnimationPlayer", true, false)


func _ready() -> void:
	add_to_group("player")
	stamina = max_stamina
	add_child(JumpRing.new())
	add_child(StaminaBar.new())
	var health := Health.new()
	health.name = "Health"
	add_child(health)
	add_child(HealthBar.new())
	_spawn_position = global_position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for child in $States.get_children():
		if child is State:
			child.character = self
			states[child.name] = child
	_change_state(initial_state)


func _unhandled_input(event: InputEvent) -> void:
	# Esc is handled by the pause menu, which also frees/recaptures the mouse.
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and input_enabled \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var limit := deg_to_rad(max_queued_turn)
		_pending_turn = clampf(_pending_turn - event.relative.x * mouse_sensitivity, -limit, limit)


func _physics_process(delta: float) -> void:
	_apply_turn(delta)
	_jump_cooldown_left = maxf(_jump_cooldown_left - delta, 0.0)
	_update_stamina(delta)

	if not is_on_floor():
		velocity.y -= gravity * delta

	var next := current_state.update(delta)
	if next != "":
		_change_state(next)

	move_and_slide()

	if global_position.y < _spawn_position.y - fall_limit:
		global_position = _spawn_position
		velocity = Vector3.ZERO


## Turn toward the queued mouse turning, no faster than max_turn_speed.
func _apply_turn(delta: float) -> void:
	if max_turn_speed <= 0.0:
		rotate_y(_pending_turn)
		_pending_turn = 0.0
		return
	var max_step := deg_to_rad(max_turn_speed) * delta
	var step := clampf(_pending_turn, -max_step, max_step)
	rotate_y(step)
	_pending_turn -= step


func _change_state(state_name: String) -> void:
	if not states.has(state_name):
		push_warning("No state named '%s'." % state_name)
		return
	if current_state:
		current_state.exit()
	current_state = states[state_name]
	current_state.enter()


func play(anim_name: String) -> void:
	if anim == null:
		push_warning("No AnimationPlayer found under character.")
	elif anim.has_animation(anim_name):
		anim.speed_scale = 1.0
		anim.play(anim_name, anim_blend)
	else:
		push_warning("AnimationPlayer has no animation named '%s'." % anim_name)


## Keyboard check that respects input_enabled.
func is_key(key: Key) -> bool:
	return input_enabled and Input.is_physical_key_pressed(key)


## True when Space is held, the jump cooldown is over and there's enough stamina.
func wants_jump() -> bool:
	return is_key(KEY_SPACE) and _jump_cooldown_left <= 0.0 and stamina >= jump_stamina_cost


## 0..1 fill of the jump cooldown (1 = ready).
func jump_cooldown_progress() -> float:
	if jump_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - _jump_cooldown_left / jump_cooldown, 0.0, 1.0)


func start_jump_cooldown() -> void:
	_jump_cooldown_left = jump_cooldown
	stamina = maxf(stamina - jump_stamina_cost, 0.0)
	if stamina <= 0.0:
		exhausted = true # fully drained: refill the whole bar before running again


func _update_stamina(delta: float) -> void:
	_sprinting = is_key(sprint_key) and is_moving() and not exhausted and stamina > 0.0
	# Stamina is frozen for the whole jump (after its cost); it moves again on landing.
	if current_state and current_state.name == "Jumping":
		return
	if _sprinting:
		stamina = maxf(stamina - stamina_drain * delta, 0.0)
		if stamina <= 0.0:
			exhausted = true
			_sprinting = false
	else:
		var rate := stamina_exhausted_regen if exhausted else stamina_regen
		stamina = minf(stamina + rate * delta, max_stamina)
		if exhausted and stamina >= max_stamina:
			exhausted = false


## True while running (Shift + W with stamina left).
func is_sprinting() -> bool:
	return _sprinting


## 0..1 stamina.
func stamina_fraction() -> float:
	return clampf(stamina / maxf(max_stamina, 0.001), 0.0, 1.0)


## Footstep sound, a bit louder, for touching down.
func play_landing_sound() -> void:
	var fs := get_node_or_null("Footsteps")
	if fs and fs.has_method("play_step"):
		fs.play_step(landing_volume_scale)


## Only W moves the character; the mouse turns it.
func is_moving() -> bool:
	return is_key(KEY_W)


## Current horizontal speed.
func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Match the walk animation's pace to how fast we're actually moving, so the
## feet don't slide while speeding up or slowing down.
func sync_anim_speed() -> void:
	if anim:
		var ref := sprint_speed if anim.current_animation == anim_sprint else move_speed
		anim.speed_scale = clampf(horizontal_speed() / maxf(ref, 0.01), 0.3, 1.0)


## Speed up toward full speed while W is held, otherwise slow down.
func apply_move(delta: float) -> void:
	var in_air := not is_on_floor()
	if in_air and not air_movement:
		return  # no air control: keep the momentum we left the ground with
	var speed := move_speed
	if in_air:
		speed = air_sprint_speed if _sprinting else air_move_speed
	elif _sprinting:
		speed = sprint_speed
	var target := Vector2.ZERO
	var rate := deceleration
	if is_moving():
		# The model faces +Z, so forward is +Z.
		var fwd := global_transform.basis.z
		target = Vector2(fwd.x, fwd.z).normalized() * speed
		rate = acceleration
	var h := Vector2(velocity.x, velocity.z).move_toward(target, rate * delta)
	velocity.x = h.x
	velocity.z = h.y


## Slow to a stop, ignoring input.
func stop_move(delta: float) -> void:
	var h := Vector2(velocity.x, velocity.z).move_toward(Vector2.ZERO, deceleration * delta)
	velocity.x = h.x
	velocity.z = h.y
