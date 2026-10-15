extends Node3D
## Put floor scenes under this node: every MeshInstance3D below it gets trimesh collision at startup.


func _ready() -> void:
	_add_collision(self)


func _add_collision(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh:
			child.create_trimesh_collision()
		_add_collision(child)
