extends Node3D
## Procedurally scatters scenes over a rectangular area, on top of whatever
## ground has collision. Hard objects (trees) get a collider; soft objects
## (grass, flowers) have none. Nothing overlaps.
## For speed, everything is drawn with MultiMeshes (one per mesh, per map chunk),
## hidden beyond view_distance, and tree colliders only exist near the player.
## The area is centered on this node, or on the GroundGrid if one is assigned
## (don't rotate or scale the node).
## All sizes are in world units, so they must match your assets' scale.

@export var hard_objects: Array[ScatterEntry] = []
@export var soft_objects: Array[ScatterEntry] = []

@export_group("Area")
## The scatter area is sized and centered to cover the whole map.
@export var ground_grid: GroundGrid
## Nothing is placed within this radius of the path's start (or of this node if no path_generator).
@export var clearing_radius := 50.0
## If set, nothing is placed on or near the generated dirt path.
@export var path_generator: PathGenerator
## If set, nothing is placed in or next to the ravine.
@export var ravine: Ravine
@export var ravine_clearance := 3.0
## Extra gap kept between the path edge and objects.
@export var path_clearance := 0.5

@export_group("Density")
## Hard objects: fraction of the area covered by object footprints (0 to 1).
## Random packing jams around 0.5, so values near 1 just mean "as full as possible".
@export_range(0.0, 1.0, 0.01) var hard_coverage := 0.1
## Soft objects: how many to place per square unit of area (so 0.2 on a
## 22 x 22 area is about 100 objects). Fine-grained, unlike coverage, which
## is far too coarse for tiny grass and flowers.
@export_range(0.0, 10.0, 0.01, "or_greater") var soft_density := 0.2
## Safety cap per category (Jolt allows ~10k physics bodies in total).
@export var max_objects := 3000

@export_group("Placement")
## 0 = a new random layout every run.
@export var seed_value := 0
@export var random_yaw := true
@export_range(0.0, 89.0) var max_slope_degrees := 35.0
## Physics layers that count as ground.
@export_flags_3d_physics var ground_mask := 1
## Rays start this far above the node and end ray_depth below it.
@export var ray_height := 100.0
@export var ray_depth := 500.0
## Tries per object before giving up on it (more = denser packing).
@export var max_attempts := 20
@export var generate_on_ready := true

@export_group("Performance")
## Objects farther than this from the camera aren't drawn (roughly; it works per chunk).
@export var view_distance := 150.0
## Objects are grouped into square chunks of this size, each drawn as one batch.
@export var chunk_size := 80.0
## Tree colliders only exist within this distance of the player.
@export var collider_distance := 40.0

var _rng := RandomNumberGenerator.new()
var _grid := {}  # Vector2i -> Array of [Vector2 center, float radius]
var _cell := 1.0
var _spawned: Array[Node] = []
var _area := Vector2.ZERO
var _area_center := Vector2.ZERO
var _info := {}  # ScatterEntry -> {"radius": float, "height": float}
var _parts := {}  # ScatterEntry -> Array of {"mesh", "xf", "material", "shadow"}
var _hard_items: Array = []  # [{"pos": Vector2, "xform": Transform3D, "entry": ScatterEntry}]
var _hard_cells := {}  # Vector2i -> PackedInt32Array of indices into _hard_items
var _active := {}  # index into _hard_items -> collider holder Node3D
var _stream_timer := 0.0
const COLLIDER_CELL := 16.0


func _ready() -> void:
	if generate_on_ready:
		# Wait for the ground's collision to register with the physics server.
		await get_tree().physics_frame
		await get_tree().physics_frame
		generate()


func generate() -> void:
	clear()
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

	if ground_grid == null:
		push_warning("Scatter: assign a ground_grid.")
		return
	_area = ground_grid.get_map_size()
	var c := ground_grid.get_map_center()
	_area_center = Vector2(c.x, c.z)

	_info.clear()
	for e in hard_objects:
		_measure_entry(e, true)
	for e in soft_objects:
		_measure_entry(e, false)
	_cell = maxf(_max_footprint() * 2.0, 0.5)

	# Plan everything first (raycasts), then spawn, so generated colliders
	# never interfere with ground detection.
	var hard_target := _count_from_coverage(hard_objects, hard_coverage)
	var soft_target := int(round(soft_density * _area.x * _area.y))
	var hard_plan := _plan(hard_objects, hard_target, "hard")
	var soft_plan := _plan(soft_objects, soft_target, "soft")
	_spawn(hard_plan, true)
	_spawn(soft_plan, false)
	print("Scatter: placed %d hard and %d soft objects." % [hard_plan.size(), soft_plan.size()])


func clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			remove_child(n)
			n.free()
	_spawned.clear()
	for i in _active:
		if is_instance_valid(_active[i]):
			remove_child(_active[i])
			_active[i].free()
	_active.clear()
	_hard_items.clear()
	_hard_cells.clear()
	_parts.clear()
	_grid.clear()


# --- Measuring -------------------------------------------------------------

func _measure_entry(e: ScatterEntry, build_collider: bool) -> void:
	if e == null or e.scene == null or _info.has(e):
		return
	var root := e.scene.instantiate() as Node3D
	var box := AABB()
	var has_box := false
	if root:
		var result := _collect_aabb(root, Transform3D.IDENTITY, box, false)
		box = result[0]
		has_box = result[1]

	var footprint := e.radius
	if footprint <= 0.0:
		footprint = maxf(box.size.x, box.size.z) * 0.5 if has_box else 1.0
	footprint = maxf(footprint, 0.01)
	var height := box.size.y if has_box else 1.0

	# Build the collider shape once per entry; every instance shares it.
	var shape: Shape3D = null
	var offset := Vector3.ZERO
	if build_collider and e.add_collider and root and has_box:
		var center := box.get_center()
		match e.collider_shape:
			ScatterEntry.ColliderShape.TRUNK, ScatterEntry.ColliderShape.CYLINDER:
				var trunk := e.collider_shape == ScatterEntry.ColliderShape.TRUNK
				var cyl := CylinderShape3D.new()
				var default_r := footprint * 0.2 if trunk else footprint
				cyl.radius = e.collider_radius if e.collider_radius > 0.0 else default_r
				cyl.height = e.collider_height if e.collider_height > 0.0 else height
				shape = cyl
				offset = Vector3(0.0 if trunk else center.x, box.position.y + cyl.height * 0.5, 0.0 if trunk else center.z)
			ScatterEntry.ColliderShape.BOX:
				var bx := BoxShape3D.new()
				bx.size = box.size
				shape = bx
				offset = center
			ScatterEntry.ColliderShape.CONVEX_HULL:
				var pts := PackedVector3Array()
				_collect_points(root, Transform3D.IDENTITY, pts)
				if not pts.is_empty():
					var hull := ConvexPolygonShape3D.new()
					hull.points = pts
					shape = hull
	if root:
		root.free()
	_info[e] = {"radius": footprint, "height": height, "shape": shape, "offset": offset}


## Returns [merged AABB, found_any_mesh].
func _collect_aabb(node: Node, xf: Transform3D, box: AABB, found: bool) -> Array:
	if node is MeshInstance3D and node.mesh:
		var b: AABB = xf * node.mesh.get_aabb()
		box = box.merge(b) if found else b
		found = true
	for child in node.get_children():
		var child_xf := xf
		if child is Node3D:
			child_xf = xf * child.transform
		var r := _collect_aabb(child, child_xf, box, found)
		box = r[0]
		found = r[1]
	return [box, found]


## Appends the convex-hull points of every mesh under node to pts.
func _collect_points(node: Node, xf: Transform3D, pts: PackedVector3Array) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		var hull := mi.mesh.create_convex_shape(true, false)
		if hull:
			for p in hull.points:
				pts.append(xf * p)
	for child in node.get_children():
		var child_xf := xf
		var c3 := child as Node3D
		if c3:
			child_xf = xf * c3.transform
		_collect_points(child, child_xf, pts)


func _max_footprint() -> float:
	var m := 0.0
	for e in _info:
		m = maxf(m, _info[e].radius * maxf(e.min_scale, e.max_scale))
	return m


# --- Planning --------------------------------------------------------------

func _valid(entries: Array) -> Array:
	return entries.filter(func(e): return e != null and e.scene != null and e.weight > 0.0)


## Converts "fraction of the area covered" into an object count.
func _count_from_coverage(entries: Array, coverage: float) -> int:
	var valid := _valid(entries)
	if valid.is_empty() or coverage <= 0.0:
		return 0
	var total_weight := 0.0
	var avg_area := 0.0
	for e in valid:
		total_weight += e.weight
		var r: float = _info[e].radius * (e.min_scale + e.max_scale) * 0.5
		avg_area += e.weight * PI * r * r
	avg_area /= total_weight
	return int(coverage * _area.x * _area.y / avg_area)


func _plan(entries: Array, target: int, label: String) -> Array:
	var valid := _valid(entries)
	var out := []
	if valid.is_empty() or target <= 0:
		return out

	var total_weight := 0.0
	for e in valid:
		total_weight += e.weight

	if target > max_objects:
		push_warning("Scatter (%s): wanted %d objects, capped at max_objects = %d." % [label, target, max_objects])
		target = max_objects

	var clear_center := Vector2(global_position.x, global_position.z)
	if path_generator:
		clear_center = path_generator.start_position
	var half := _area * 0.5
	var space := get_world_3d().direct_space_state
	var max_slope := deg_to_rad(max_slope_degrees)

	for i in target:
		for attempt in max_attempts:
			var e: ScatterEntry = _pick(valid, total_weight)
			var s := _rng.randf_range(e.min_scale, e.max_scale)
			var r: float = _info[e].radius * s
			var p := _area_center + Vector2(
				_rng.randf_range(-half.x, half.x),
				_rng.randf_range(-half.y, half.y))
			if p.distance_to(clear_center) < clearing_radius + r or not _is_free(p, r):
				continue
			if path_generator and path_generator.distance_to_path(p) < r + path_clearance:
				continue
			if ravine and ravine.blocks(p, r + ravine_clearance):
				continue
			var hit := _ground(space, p)
			if hit.is_empty():
				continue
			var normal: Vector3 = hit.normal
			if normal.angle_to(Vector3.UP) > max_slope:
				continue
			_register(p, r)
			var yaw := _rng.randf() * TAU if random_yaw else 0.0
			var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
			out.append({"entry": e, "xform": Transform3D(b, hit.position)})
			break
	return out


func _pick(entries: Array, total: float) -> ScatterEntry:
	var roll := _rng.randf() * total
	for e in entries:
		roll -= e.weight
		if roll <= 0.0:
			return e
	return entries.back()


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _cell), floori(p.y / _cell))


func _is_free(p: Vector2, r: float) -> bool:
	var c := _cell_of(p)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for o in _grid.get(c + Vector2i(dx, dy), []):
				if p.distance_to(o[0]) < r + o[1]:
					return false
	return true


func _register(p: Vector2, r: float) -> void:
	var c := _cell_of(p)
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append([p, r])


func _ground(space: PhysicsDirectSpaceState3D, p: Vector2) -> Dictionary:
	var from := Vector3(p.x, global_position.y + ray_height, p.y)
	var to := Vector3(p.x, global_position.y - ray_depth, p.y)
	var query := PhysicsRayQueryParameters3D.create(from, to, ground_mask)
	var exclude: Array[RID] = []
	# Skip non-static hits (e.g. the player) and keep looking for ground.
	for i in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.collider is StaticBody3D:
			return hit
		exclude.append(hit.rid)
	return {}


# --- Spawning --------------------------------------------------------------

func _spawn(plan: Array, hard: bool) -> void:
	# Group the placements: entry -> chunk -> transforms.
	var groups := {}
	for d in plan:
		var e: ScatterEntry = d.entry
		var xf: Transform3D = d.xform
		var cell := Vector2i(floori(xf.origin.x / chunk_size), floori(xf.origin.z / chunk_size))
		if not groups.has(e):
			groups[e] = {}
		if not groups[e].has(cell):
			groups[e][cell] = []
		groups[e][cell].append(xf)
		if hard:
			_hard_items.append({"pos": Vector2(xf.origin.x, xf.origin.z), "xform": xf, "entry": e})

	var vis_end := view_distance + chunk_size * 0.8 # chunks are measured from their middle
	for e in groups:
		var parts := _get_parts(e)
		for cell in groups[e]:
			var xforms: Array = groups[e][cell]
			for part in parts:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = part.mesh
				mm.instance_count = xforms.size()
				for i in xforms.size():
					mm.set_instance_transform(i, xforms[i] * part.xf)
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.top_level = true # instance transforms are already in world space
				mmi.cast_shadow = part.shadow
				if part.material:
					mmi.material_override = part.material
				mmi.visibility_range_end = vis_end
				add_child(mmi)
				mmi.global_transform = Transform3D.IDENTITY
				_spawned.append(mmi)

	if hard:
		for i in _hard_items.size():
			var key := Vector2i(floori(_hard_items[i].pos.x / COLLIDER_CELL), floori(_hard_items[i].pos.y / COLLIDER_CELL))
			if not _hard_cells.has(key):
				_hard_cells[key] = PackedInt32Array()
			_hard_cells[key].append(i)
		_stream_timer = 0.0


## Every MeshInstance3D in the entry's scene, as {mesh, xf (relative to the
## scene root), material (override or null), shadow mode}.
func _get_parts(e: ScatterEntry) -> Array:
	if _parts.has(e):
		return _parts[e]
	var out := []
	var root := e.scene.instantiate() as Node3D
	if root:
		_collect_parts(root, Transform3D.IDENTITY, out)
		root.free()
	_parts[e] = out
	return out


func _collect_parts(node: Node, xf: Transform3D, out: Array) -> void:
	var mi := node as MeshInstance3D
	if mi and mi.mesh:
		var mesh: Mesh = mi.mesh
		# Per-surface overrides can't be set on a MultiMeshInstance3D, so bake them
		# into a copy of the mesh.
		for s in mesh.get_surface_count():
			var ov := mi.get_surface_override_material(s)
			if ov:
				if mesh == mi.mesh:
					mesh = mesh.duplicate() as Mesh
				mesh.surface_set_material(s, ov)
		out.append({"mesh": mesh, "xf": xf, "material": mi.material_override, "shadow": mi.cast_shadow})
	for child in node.get_children():
		var child_xf := xf
		var c3 := child as Node3D
		if c3:
			child_xf = xf * c3.transform
		_collect_parts(child, child_xf, out)


# --- Colliders near the player -------------------------------------------------

func _process(delta: float) -> void:
	if _hard_items.is_empty():
		return
	_stream_timer -= delta
	if _stream_timer > 0.0:
		return
	_stream_timer = 0.2
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	_stream_colliders(Vector2(player.global_position.x, player.global_position.z))


func _stream_colliders(center: Vector2) -> void:
	var r := collider_distance
	var c0 := Vector2i(floori((center.x - r) / COLLIDER_CELL), floori((center.y - r) / COLLIDER_CELL))
	var c1 := Vector2i(floori((center.x + r) / COLLIDER_CELL), floori((center.y + r) / COLLIDER_CELL))
	var wanted := {}
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			for i in _hard_cells.get(Vector2i(x, y), PackedInt32Array()):
				if _hard_items[i].pos.distance_to(center) <= r:
					wanted[i] = true
					if not _active.has(i):
						_active[i] = _make_collider(_hard_items[i])
	# Drop colliders that are well out of range (a little slack avoids flicker).
	var drop := []
	for i in _active:
		if not wanted.has(i) and _hard_items[i].pos.distance_to(center) > r + 8.0:
			drop.append(i)
	for i in drop:
		var n: Node = _active[i]
		_active.erase(i)
		if is_instance_valid(n):
			remove_child(n)
			n.free()


func _make_collider(item: Dictionary) -> Node3D:
	var info: Dictionary = _info[item.entry]
	var shape: Shape3D = info.shape
	if shape == null:
		return null
	# Same layout as before: a scaled holder, with the body and shape under it.
	var holder := Node3D.new()
	add_child(holder)
	holder.global_transform = item.xform
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = info.offset
	var body := StaticBody3D.new()
	body.add_child(col)
	holder.add_child(body)
	return holder
