class_name RainFeature
extends SignFeature
## Starts light rain when the sign is read (only once).

@export var rain_scene: PackedScene


func apply(world: Node) -> void:
	if rain_scene == null or world.get_node_or_null("Rain") != null:
		return
	var r := rain_scene.instantiate()
	r.name = "Rain"
	world.add_child(r)
