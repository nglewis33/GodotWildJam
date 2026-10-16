class_name GroundGrid
extends Node3D
## Builds the map as a grid of ground tiles (columns x rows), each with
## trimesh collision. Tiles are placed edge to edge using the size measured
## from their meshes. Don't rotate or scale this node.

## Tile scenes to use. With several, each cell picks one at random.
## They should all be the same size.
@export var tile_scenes: Array[PackedScene] = []
## Number of tiles along X (columns) and Z (rows): your "n by m".
@export var grid_size := Vector2i(3, 3)
## Leave at (0, 0) to measure from the tile meshes.
@export var tile_size_override := Vector2.ZERO
## How much neighboring tiles overlap, as a fraction of the tile size. Hides
## gaps between tiles; raise it if you can still see or fall through seams.
@export_range(0.0, 0.5, 0.005) var tile_overlap := 0.03
## Center the grid on this node. If off, the first tile sits at the node
## and the grid extends toward +X and +Z.
@export var center_grid := true
## 0 = random tile choice each run.
@export var seed_value := 0
@export var generate_on_ready := true

var tile_size := Vector2.ZERO
var _spacing := Vector2.ZERO  # distance between neighboring tile origins
var _tile_center := Vector2.ZERO  # tile bounding-box center relative to its origin
var _origin_offset := Vector2.ZERO  # where tile (0, 0) sits relative to this node
var _tiles: Array[Node] = []
var _shape_cache := {}  # Mesh -> shared collision shape


func _ready() -> void:
	if generate_on_ready:
		generate()


func generate() -> void:
	clear()
	var scenes := tile_scenes.filter(func(s): return s != null)
	if scenes.is_empty() or grid_size.x <= 0 or grid_size.y <= 0:
		push_warning("GroundGrid: needs at least one tile scene and a grid size above 0.")
		return

	_measure(scenes[0])
	if tile_size.x <= 0.0 or tile_size.y <= 0.0:
		push_warning("GroundGrid: could not determine the tile size; set tile_size_override.")
		return

	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	_spacing = tile_size * (1.0 - tile_overlap)
	_origin_offset = Vector2.ZERO
	if center_grid:
		_origin_offset = -Vector2(grid_size.x - 1, grid_size.y - 1) * _spacing * 0.5

	for i in grid_size.x:
		for j in grid_size.y:
			var scene: PackedScene = scenes[rng.randi() % scenes.size()]
			var tile := scene.instantiate() as Node3D
			if tile == null:
				push_warning("GroundGrid: tile root must be a Node3D.")
				continue
			add_child(tile)
			tile.position = Vector3(
				_origin_offset.x + i * _spacing.x,
				0.0,
				_origin_offset.y + j * _spacing.y)
			_tiles.append(tile)
			_add_collision(tile)


func clear() -> void:
	_shape_cache.clear()
	for t in _tiles:
		if is_instance_valid(t):
			remove_child(t)
			t.free()
	_tiles.clear()


## Total map size in world units (X, Z).
func get_map_size() -> Vector2:
	return Vector2(grid_size - Vector2i.ONE) * _spacing + tile_size


## World-space center of the whole map (X, Z); y is this node's y.
func get_map_center() -> Vector3:
	var local := _origin_offset + _tile_center + Vector2(grid_size.x - 1, grid_size.y - 1) * _spacing * 0.5
	return global_position + Vector3(local.x, 0.0, local.y)


func _measure(scene: PackedScene) -> void:
	var root := scene.instantiate() as Node3D
	var box := AABB()
	var found := false
	if root:
		var r := _collect_aabb(root, Transform3D.IDENTITY, box, false)
		box = r[0]
		found = r[1]
		root.free()
	if found:
		tile_size = Vector2(box.size.x, box.size.z)
		_tile_center = Vector2(box.get_center().x, box.get_center().z)
	else:
		tile_size = Vector2.ZERO
		_tile_center = Vector2.ZERO
	if tile_size_override.x > 0.0 and tile_size_override.y > 0.0:
		tile_size = tile_size_override


## Returns [merged AABB, found_any_mesh].
func _collect_aabb(node: Node, xf: Transform3D, box: AABB, found: bool) -> Array:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		var b: AABB = xf * mi.mesh.get_aabb()
		box = box.merge(b) if found else b
		found = true
	for child in node.get_children():
		var child_xf := xf
		var c3 := child as Node3D
		if c3:
			child_xf = xf * c3.transform
		var r := _collect_aabb(child, child_xf, box, found)
		box = r[0]
		found = r[1]
	return [box, found]


## Every tile of the same kind shares one collision shape (building a separate
## one for each of the ~1300 tiles used a huge amount of time and memory).
func _add_collision(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		var shape: Shape3D = _shape_cache.get(mi.mesh)
		if shape == null:
			shape = mi.mesh.create_trimesh_shape()
			_shape_cache[mi.mesh] = shape
		if shape:
			var body := StaticBody3D.new()
			var col := CollisionShape3D.new()
			col.shape = shape
			body.add_child(col)
			mi.add_child(body)
	for child in node.get_children():
		_add_collision(child)
