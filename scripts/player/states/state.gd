class_name State
extends Node
## Base class for character states. Override what you need.

var character: Node3D  # set by character.gd


func enter() -> void:
	pass


func exit() -> void:
	pass


## Return the name of the state to switch to (e.g. "Walking"), or "" to stay.
func update(_delta: float) -> String:
	return ""
