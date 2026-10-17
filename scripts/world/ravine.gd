class_name Ravine
extends Node3D
## A straight, bottomless ravine that crosses the main path.
##
## It picks a spot position_percent % of the way along the main path (plus
## noise), removes a band of ground tiles perpendicular to the path there, lines
## the edges with dark cliff walls that fade to black, and spans the gap with a
## suspension bridge (a SuspensionBridge child node, created if missing).
## The band never reaches the edge of the map, so you can also walk around it.
## Put this node after the PathGenerator in the scene tree.

signal carved ## Tiles are removed (Scatter and others can now avoid the hole).
signal built ## Walls and bridge exist.

@export var enabled := true
@export var ground_grid: GroundGrid
@export var path_generator: PathGenerator

@export_group("Placement")
## How far along the main path the ravine sits: 0 = start, 100 = end.
@export_range(0.0, 100.0, 0.5) var position_percent := 50.0
## Random +/- shift of that spot, in percent of the path.
@export_range(0.0, 50.0, 0.5) var position_noise := 10.0
## Length of the ravine along its own direction, in world units (rounded to whole tiles).
@export var length := 140.0
## Width of the gap the bridge crosses, in world units (rounded to whole tiles, at least one).
@export var width := 30.0
## Tiles kept solid between the ravine and the map edge, so it never cuts the map in two.
@export var edge_margin_tiles := 2
## 0 = different every run.
@export var seed_value := 0

@export_group("Walls")
## How far the cliffs drop. Keep it deeper than the player's fall_limit.
@export var depth := 120.0
## Spacing of wall samples along the edge.
@export var wall_step := 1.5
## The wall turns fully black this far below the edge.
@export var fade_depth := 40.0
@export var rock_color_light := Color(0.2, 0.17, 0.14)
@export var rock_color_dark := Color(0.08, 0.07, 0.06)

@export_group("Bridge")
@export var build_bridge := true
## The deck starts this far beyond the cliff edge, on solid ground.
@export var anchor_inset := 2.0

## World-space footprint of the hole (X, Z). Empty until carved.
var hole := Rect2()

const GROUND_MASK := 1 << 19 # GroundGrid.GROUND_ONLY_LAYER (20)

var _rng := RandomNumberGenerator.new()
var _bridge_a := Vector2.ZERO
var _bridge_b := Vector2.ZERO
var _long_along_z := true


func _ready() -> void:
	if not enabled:
		return
	if ground_grid == null or path_generator == null:
		push_warning("Ravine: assign ground_grid and path_generator.")
		return
	if path_generator.main_route.size() < 2:
		await path_generator.generated
	if not _carve():
		push_warning("Ravine: could not find a spot for the ravine.")
		return
	carved.emit()
	# Wait for the remaining ground's collision to register before measuring it.
	for i in 3:
		await get_tree().physics_frame
	_build_walls()
	if build_bridge:
		_build_bridge()
	built.emit()


## The ravine's centre line (two world X/Z points, end to end), or empty before it exists.
func get_center_line() -> PackedVector2Array:
	if hole.size == Vector2.ZERO:
		return PackedVector2Array()
	var c := hole.get_center()
	if _long_along_z:
		return PackedVector2Array([Vector2(c.x, hole.position.y), Vector2(c.x, hole.end.y)])
	return PackedVector2Array([Vector2(hole.position.x, c.y), Vector2(hole.end.x, c.y)])


## True if a world (X, Z) point is inside the hole or within margin of it.
func blocks(p: Vector2, margin := 0.0) -> bool:
	return hole.size != Vector2.ZERO and hole.grow(margin).has_point(p)


# --- Finding a spot and removing the tiles -------------------------------------

func _carve() -> bool:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	var route := path_generator.main_route
	var f0 := position_percent + _rng.randf_range(-position_noise, position_noise)
	var offsets := [0.0, 5.0, -5.0, 10.0, -10.0, 15.0, -15.0, 20.0, -20.0, 30.0, -30.0]
	for off in offsets:
		var f := clampf(f0 + float(off), 8.0, 92.0)
		if _try_place(route, f / 100.0):
			print("Ravine: hole %s at %.0f%% of the path, bridge %s -> %s." % [hole, f, _bridge_a, _bridge_b])
			return true
	return false


func _try_place(route: PackedVector2Array, frac: float) -> bool:
	var at := _route_at(route, frac)
	var pos: Vector2 = at[0]
	var dir: Vector2 = at[1]
	# The ravine runs across the path: if the path heads along X, the ravine runs along Z.
	_long_along_z = absf(dir.x) >= absf(dir.y)

	var spacing := ground_grid.get_spacing()
	var grid := ground_grid.grid_size
	var c := ground_grid.cell_at(pos)
	var n_across := maxi(1, roundi(width / (spacing.x if _long_along_z else spacing.y)))
	var n_long := maxi(3, roundi(length / (spacing.y if _long_along_z else spacing.x)))

	var c_across := c.x if _long_along_z else c.y
	var c_long := c.y if _long_along_z else c.x
	var g_across := grid.x if _long_along_z else grid.y
	var g_long := grid.y if _long_along_z else grid.x
	var a_lo := c_across - (n_across - 1) >> 1
	var a_hi := a_lo + n_across - 1
	var l_lo := c_long - n_long >> 1
	var l_hi := l_lo + n_long - 1
	var m := edge_margin_tiles
	a_lo = maxi(a_lo, m)
	a_hi = mini(a_hi, g_across - 1 - m)
	l_lo = maxi(l_lo, m)
	l_hi = mini(l_hi, g_long - 1 - m)

	while a_hi >= a_lo and l_hi - l_lo + 1 >= 3:
		var c0 := Vector2i(a_lo, l_lo) if _long_along_z else Vector2i(l_lo, a_lo)
		var c1 := Vector2i(a_hi, l_hi) if _long_along_z else Vector2i(l_hi, a_hi)
		var rect := _cells_to_rect(c0, c1)
		if _rect_ok(route, rect):
			ground_grid.remove_cells(c0, c1)
			hole = rect
			_set_bridge_line(pos)
			return true
		l_lo += 1
		l_hi -= 1
	return false


func _cells_to_rect(c0: Vector2i, c1: Vector2i) -> Rect2:
	var spacing := ground_grid.get_spacing()
	var lo := ground_grid.cell_center(c0) - spacing * 0.5
	var hi := ground_grid.cell_center(c1) + spacing * 0.5
	var trim := ground_grid.get_trim() # neighbors' meshes poke this far into the hole
	return Rect2(lo + trim, hi - lo - trim * 2.0)


## The route must cross the hole exactly once, and the camp and finish must stay clear.
func _rect_ok(route: PackedVector2Array, rect: Rect2) -> bool:
	if rect.grow(path_generator.start_radius + 6.0).has_point(path_generator.start_position):
		return false
	if rect.grow(path_generator.end_radius + 6.0).has_point(path_generator.end_position):
		return false
	var crossings := 0
	var inside := false
	for i in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / 1.5))
		for k in steps:
			var now := rect.has_point(a.lerp(b, float(k) / steps))
			if now and not inside:
				crossings += 1
			inside = now
	return crossings == 1


func _route_at(route: PackedVector2Array, frac: float) -> Array:
	var total := 0.0
	for i in route.size() - 1:
		total += route[i].distance_to(route[i + 1])
	var target := total * clampf(frac, 0.0, 1.0)
	var walked := 0.0
	for i in route.size() - 1:
		var l := route[i].distance_to(route[i + 1])
		if walked + l >= target and l > 0.0001:
			var pos := route[i].lerp(route[i + 1], (target - walked) / l)
			var dir := (route[mini(i + 2, route.size() - 1)] - route[maxi(i - 1, 0)])
			if dir.length() < 0.001:
				dir = route[i + 1] - route[i]
			return [pos, dir.normalized()]
		walked += l
	return [route[route.size() - 1], (route[route.size() - 1] - route[route.size() - 2]).normalized()]


func _set_bridge_line(path_pos: Vector2) -> void:
	if _long_along_z:
		var z := clampf(path_pos.y, hole.position.y + 3.0, hole.end.y - 3.0)
		_bridge_a = Vector2(hole.position.x - anchor_inset, z)
		_bridge_b = Vector2(hole.end.x + anchor_inset, z)
	else:
		var x := clampf(path_pos.x, hole.position.x + 3.0, hole.end.x - 3.0)
		_bridge_a = Vector2(x, hole.position.y - anchor_inset)
		_bridge_b = Vector2(x, hole.end.y + anchor_inset)


# --- Walls --------------------------------------------------------------------

func _ground_y(p: Vector2, fallback: float) -> float:
	var space := get_world_3d().direct_space_state
	var ref := ground_grid.global_position.y
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, ref + 150.0, p.y), Vector3(p.x, ref - 150.0, p.y), GROUND_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return fallback
	return (hit.position as Vector3).y


func _build_walls() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var x0 := hole.position.x
	var x1 := hole.end.x
	var z0 := hole.position.y
	var z1 := hole.end.y
	# [start, end, outward direction], all in world X/Z.
	var sides := [
		[Vector2(x0, z0), Vector2(x1, z0), Vector2(0, -1)],
		[Vector2(x0, z1), Vector2(x1, z1), Vector2(0, 1)],
		[Vector2(x0, z0), Vector2(x0, z1), Vector2(-1, 0)],
		[Vector2(x1, z0), Vector2(x1, z1), Vector2(1, 0)],
	]
	var fallback := ground_grid.global_position.y
	for side in sides:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var out: Vector2 = side[2]
		var inward := Vector3(-out.x, 0.0, -out.y)
		var n := maxi(1, ceili(a.distance_to(b) / wall_step))
		var first := verts.size()
		var y := fallback
		for k in n + 1:
			var q := a.lerp(b, float(k) / n)
			y = _ground_y(q + out * 0.4, y)
			var u := q.distance_to(a) / 6.0
			verts.append(Vector3(q.x, y + 0.02, q.y))
			uvs.append(Vector2(u, 0.0))
			verts.append(Vector3(q.x, y - depth, q.y))
			uvs.append(Vector2(u, depth))
			normals.append(inward)
			normals.append(inward)
		for k in n:
			var t0 := first + k * 2
			var t1 := t0 + 2
			# Two triangles per quad, wound so the front face looks into the hole.
			_tri(verts, indices, t0, t1, t0 + 1, inward)
			_tri(verts, indices, t1, t1 + 1, t0 + 1, inward)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Walls"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _wall_material()
	mi.top_level = true
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY

	var shape := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	if shape:
		shape.backface_collision = true
		var body := StaticBody3D.new()
		body.name = "WallBody"
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		body.top_level = true
		add_child(body)
		body.global_transform = Transform3D.IDENTITY


## Adds one triangle, flipping the winding if needed so its front faces `facing`.
func _tri(verts: PackedVector3Array, indices: PackedInt32Array, a: int, b: int, c: int, facing: Vector3) -> void:
	var front := (verts[c] - verts[a]).cross(verts[b] - verts[a]) # Godot: clockwise = front
	if front.dot(facing) >= 0.0:
		indices.append_array([a, b, c])
	else:
		indices.append_array([a, c, b])


func _wall_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 rock_light : source_color;
uniform vec3 rock_dark : source_color;
uniform float fade_depth = 40.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	float n = vnoise(UV * vec2(1.6, 0.5)) * 0.6 + vnoise(UV * vec2(5.0, 1.8)) * 0.4;
	float strata = 0.5 + 0.5 * sin(UV.y * 0.9 + n * 5.0);
	vec3 rock = mix(rock_dark, rock_light, clamp(n * 0.7 + strata * 0.5, 0.0, 1.0));
	float fade = 1.0 - smoothstep(0.0, fade_depth, UV.y);
	ALBEDO = rock * fade;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("rock_light", rock_color_light)
	mat.set_shader_parameter("rock_dark", rock_color_dark)
	mat.set_shader_parameter("fade_depth", fade_depth)
	return mat


# --- Bridge -------------------------------------------------------------------

func _build_bridge() -> void:
	var bridge: SuspensionBridge = null
	for ch in get_children():
		if ch is SuspensionBridge:
			bridge = ch
			break
	if bridge == null:
		bridge = SuspensionBridge.new()
		bridge.name = "Bridge"
		add_child(bridge)
	var fallback := ground_grid.global_position.y
	var ya := _ground_y(_bridge_a, fallback)
	var yb := _ground_y(_bridge_b, fallback)
	bridge.build(Vector3(_bridge_a.x, ya, _bridge_a.y), Vector3(_bridge_b.x, yb, _bridge_b.y))
