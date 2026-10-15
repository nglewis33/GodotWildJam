@tool
extends EditorScript

const OUT_DIR := "res://assets/extracted/"

func _run() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var container: Node = root
	while container.get_child_count() == 1 and not (container.get_child(0) is MeshInstance3D):
		container = container.get_child(0)
	print("Using container: ", container.name, " with ", container.get_child_count(), " children")
	var re := RegEx.create_from_string("[_@.]*\\d+$")
	var seen := {}
	for child in container.get_children():
		var key := re.sub(str(child.name), "")
		if seen.has(key):
			continue
		seen[key] = true
		var copy := child.duplicate()
		if copy is Node3D:
			copy.transform = Transform3D.IDENTITY
		_set_owner(copy, copy)
		var packed := PackedScene.new()
		packed.pack(copy)
		ResourceSaver.save(packed, OUT_DIR + key + ".tscn")
		copy.free()
	print("Saved ", seen.size(), " scenes")

func _set_owner(node: Node, new_owner: Node) -> void:
	for c in node.get_children():
		c.owner = new_owner
		_set_owner(c, new_owner)
