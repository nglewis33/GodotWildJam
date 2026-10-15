extends Node3D
## Procedurally scatters scenes over a rectangular area, on top of whatever
## ground has collision. Hard objects (trees) get a collider; soft objects
## (grass, flowers) have all collision removed. Nothing overlaps.
## The area is centered on this node, or on the GroundGrid if one is assigned
## (don't rotate or scale the node).
## All sizes are in world units, so they must match your assets' scale.

@export var hard_objects: Array[ScatterEntry] = []
@export var soft_objects: Array[ScatterEntry] = []

@export_group("Area")
## If set, the scatter area is sized and centered to cover the whole map.
@export var ground_grid: GroundGrid
## Used when no ground_grid is assigned.
@export var area_size := Vector2(1000, 1000)
## Nothing is placed within this radius of this node (put it at the player spawn).
@export var clearing_radius := 50.0
## If set, nothing is placed on or near the generated dirt path.
@export var path_generator: PathGenerator
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

var _rng := RandomNumberGenerator.new()
var _grid := {}  # Vector2i -> Array of [Vector2 center, float radius]
var _cell := 1.0
var _spawned: Array[Node] = []
var _area := Vector2.ZERO
var _area_center := Vector2.ZERO
var _info := {}  # ScatterEntry -> {"radius": float, "height": float}


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

	_area = area_size
	_area_center = Vector2(global_position.x, global_position.z)
	if ground_grid:
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
	for d in plan:
		var e: ScatterEntry = d.entry
		var inst := e.scene.instantiate() as Node3D
		if inst == null:
			push_warning("Scatter scene '%s' root is not a Node3D." % e.scene.resource_path)
			continue
		add_child(inst)
		inst.global_transform = d.xform
		_spawned.append(inst)
		if hard:
			_add_collider(inst, e)
		else:
			_strip_collision(inst)


func _add_collider(inst: Node3D, e: ScatterEntry) -> void:
	var info: Dictionary = _info[e]
	var shape: Shape3D = info.shape
	if shape == null:
		return
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = info.offset
	var body := StaticBody3D.new()
	body.add_child(col)
	inst.add_child(body)


func _strip_collision(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			child.queue_free()
		else:
			_strip_collision(child)
