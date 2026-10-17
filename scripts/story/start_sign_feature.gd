class_name StartSignFeature
extends SignFeature
## The first sign (beside the camp). After its message the Prologue pans the
## camera to the path and lifts the fog before the view returns to the player.


func after_message(world: Node, camera: Camera3D, _player: Node3D) -> void:
	var prologue := world.get_node_or_null("Prologue") as Prologue
	if prologue:
		await prologue.on_first_sign_message(camera)


func apply(world: Node) -> void:
	var prologue := world.get_node_or_null("Prologue") as Prologue
	if prologue:
		prologue.on_first_sign_done()
