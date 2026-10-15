extends Camera3D
## Third-person follow camera. The mouse (up/down) tilts it around the player;
## left/right turning is done by the player itself.
## Press Q to toggle a free-fly debug camera (the player ignores input while
## it's active). Free mode: mouse = look, WASD = move, R/F = up/down,
## Shift = fast.

@export var target: Node3D
## Offset in the target's local space (model faces +Z, so behind is -Z).
@export var offset := Vector3(0, 2, -2)
@export var look_height := 1.0
@export var smoothing := 8.0
## Radians per pixel of vertical mouse movement.
@export var pitch_sensitivity := 0.003
@export var min_follow_pitch := -0.4
@export var max_follow_pitch := 0.6

@export_group("Free Camera")
@export var start_free := false
@export var free_speed := 20.0
@export var free_fast_multiplier := 4.0
@export var mouse_sensitivity := 0.003

var free_mode := false
var _yaw := 0.0
var _pitch := 0.0
var _follow_pitch := 0.0


func _ready() -> void:
	if start_free:
		_set_free(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			_set_free(not free_mode)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if free_mode:
			_yaw -= event.relative.x * mouse_sensitivity
			_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -PI / 2.0 + 0.01, PI / 2.0 - 0.01)
			global_rotation = Vector3(_pitch, _yaw, 0.0)
		else:
			_follow_pitch = clampf(
				_follow_pitch + event.relative.y * pitch_sensitivity,
				min_follow_pitch, max_follow_pitch)


func _process(delta: float) -> void:
	if free_mode:
		_process_free(delta)
	else:
		_process_follow(delta)


func _process_follow(delta: float) -> void:
	if target == null:
		return
	var tilted := Basis(Vector3.RIGHT, _follow_pitch) * offset
	var desired := target.global_transform * tilted
	global_position = global_position.lerp(desired, 1.0 - exp(-smoothing * delta))
	look_at(target.global_position + Vector3.UP * look_height)


func _process_free(delta: float) -> void:
	var dir := Vector3.ZERO
	var b := global_transform.basis
	if Input.is_physical_key_pressed(KEY_W): dir -= b.z
	if Input.is_physical_key_pressed(KEY_S): dir += b.z
	if Input.is_physical_key_pressed(KEY_D): dir += b.x
	if Input.is_physical_key_pressed(KEY_A): dir -= b.x
	if Input.is_physical_key_pressed(KEY_R): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_F): dir += Vector3.DOWN
	if dir == Vector3.ZERO:
		return
	var speed := free_speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= free_fast_multiplier
	global_position += dir.normalized() * speed * delta


func _set_free(on: bool) -> void:
	free_mode = on
	if on:
		_yaw = global_rotation.y
		_pitch = global_rotation.x
	# Stop the player reacting to keys/mouse while the free camera is active.
	if target and "input_enabled" in target:
		target.set("input_enabled", not on)
