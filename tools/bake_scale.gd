@tool
extends EditorScript
## One-time tool: bakes a uniform scale into every scene in assets/extracted/.
## Run it from the Script Editor: File > Run (Ctrl+Shift+X) with this script open.
##
## For each .tscn it multiplies every mesh vertex and every node position by
## SCALE_FACTOR (node scales/rotations are left alone), then saves the scene
## in place. A "<name>.tscn.bak" copy of the original is made first; files that
## already have a .bak are skipped, so running it twice can't double-scale.
## To undo: delete the .tscn and rename its .bak back to .tscn.
##
## Close any of these scenes in the editor before running.

const FOLDER := "res://assets/extracted/"
const SCALE_FACTOR := 0.01
## Files to leave alone (the full 119 MB Sketchfab scene).
const SKIP := ["Sketchfab_model.tscn"]


func _run() -> void:
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		push_error("Can't open " + FOLDER)
		return

	var done := 0
	var skipped := 0
	for file in dir.get_files():
		if not file.ends_with(".tscn") or file in SKIP:
			continue
		var path := FOLDER + file
		if FileAccess.file_exists(path + ".bak"):
			skipped += 1
			continue
		if _bake_scene(path):
			done += 1

	EditorInterface.get_resource_filesystem().scan()
	print("bake_scale: baked %d scenes, skipped %d (already have a .bak)." % [done, skipped])


func _bake_scene(path: String) -> bool:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Could not load " + path)
		return false
	var root := packed.instantiate()
	if root == null:
		return false

	var mesh_cache := {}  # original Mesh -> scaled ArrayMesh
	_bake_node(root, mesh_cache)

	var new_packed := PackedScene.new()
	if new_packed.pack(root) != OK:
		push_warning("Could not pack " + path)
		root.free()
		return false

	# Back up the original, then overwrite it.
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak")) != OK:
		push_warning("Could not back up %s; leaving it untouched." % path)
		root.free()
		return false
	var err := ResourceSaver.save(new_packed, path)
	root.free()
	if err != OK:
		push_warning("Could not save %s (error %d). Restore it from the .bak." % [path, err])
		return false
	return true


func _bake_node(node: Node, mesh_cache: Dictionary) -> void:
	if node is Node3D:
		var n := node as Node3D
		n.position *= SCALE_FACTOR
	if node is MeshInstance3D and node.mesh != null:
		var mi := node as MeshInstance3D
		if not mesh_cache.has(mi.mesh):
			mesh_cache[mi.mesh] = _scaled_mesh(mi.mesh)
		mi.mesh = mesh_cache[mi.mesh]
	for child in node.get_children():
		_bake_node(child, mesh_cache)


func _scaled_mesh(mesh: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts.size():
			verts[v] *= SCALE_FACTOR
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays)
		var idx := out.get_surface_count() - 1
		out.surface_set_material(idx, mesh.surface_get_material(i))
		out.surface_set_name(idx, mesh.surface_get_name(i) if mesh is ArrayMesh else "")
	return out
