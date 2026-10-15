class_name GhostFeature
extends SignFeature
## Test feature: makes the player partly transparent.

@export_range(0.0, 1.0) var opacity := 0.5


func apply(world: Node) -> void:
	var player := world.get_tree().get_first_node_in_group("player")
	if player == null:
		return
	for m in player.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).transparency = 1.0 - opacity
