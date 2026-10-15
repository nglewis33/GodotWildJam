class_name Health
extends Node
## Player health. Debug keys: T lowers, Y raises (hold to repeat).

signal changed(current: float, maximum: float)

@export var max_health := 200.0
@export var key_step := 5.0
var current := 200.0


func _ready() -> void:
	current = max_health


func set_health(value: float) -> void:
	var v := clampf(value, 0.0, max_health)
	if is_equal_approx(v, current):
		return
	current = v
	changed.emit(current, max_health)


func damage(amount: float) -> void:
	set_health(current - amount)


func heal(amount: float) -> void:
	set_health(current + amount)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_T:
			damage(key_step)
		elif event.keycode == KEY_Y:
			heal(key_step)
