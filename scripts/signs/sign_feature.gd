class_name SignFeature
extends Resource
## Base class for what a sign says and does. Subclass and override apply().

@export_multiline var text := "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."


## Awaited after the message is dismissed, while the world is still frozen and
## the view is at the sign. Override for a scripted moment (camera pans, fog...).
func after_message(_world: Node, _camera: Camera3D, _player: Node3D) -> void:
	pass


## Called after the sign has been read and the game has unfrozen.
func apply(_world: Node) -> void:
	pass
