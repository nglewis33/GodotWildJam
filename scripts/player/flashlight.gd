extends SpotLight3D
## Player flashlight: a cone pointing where the character faces.
## F toggles it. Tune the beam with this node's SpotLight3D properties
## (range, angle, energy, color, shadows).

@export var toggle_key: Key = KEY_F
@export var starts_on := true
## While locked the key does nothing and the light stays off (story: not found yet).
var locked := false


func set_locked(value: bool) -> void:
	locked = value
	if locked:
		visible = false


func _ready() -> void:
	visible = starts_on


func _unhandled_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == toggle_key:
		var player := get_parent()
		# Ignore the key while the free camera has taken over input.
		if player and player.get("input_enabled") == false:
			return
		visible = not visible
