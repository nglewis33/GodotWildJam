class_name Ravine
extends Node3D
## A bottomless ravine with a jagged rim that crosses the MAIN path (never a fork).
##
## It picks a spot position_percent % of the way along the main path (plus
## noise) and removes a band of ground tiles across the path there. Because
## whole tiles are removed, the straight cut is hidden by a jagged "lip" of
## generated ground and cliff walls with ledges that fade to black. A
## SuspensionBridge child spans the gap (it is created if missing).
## The band never reaches the edge of the map, so you can also walk around it.
## The PathGenerator's "ravine" export should point at this node; the ravine is
## carved right after the main path is planned and before the forks, so the forks
## simply avoid it and the main path only has to cross it once.

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

@export_group("Jagged edge")
## Most the rim can bite into the gap (world units). 0 = straight edges.
@export var jag_amplitude := 6.0
## Size of the big bumps along the edge.
@export var jag_scale := 14.0
## Small random chipping on top of the bumps.
@export var jag_roughness := 1.2
## Extra ledges and overhangs on the cliff face as it goes down.
@export var crag_amount := 3.0
@export var lip_color := Color(0.07, 0.075, 0.05)

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
## The deck starts this far back from the jagged rim, on solid ground.
@export var anchor_inset := 2.0

## World-space footprint of the removed tiles (X, Z). Empty until carved.
var hole := Rect2()

const GROUND_MASK := 1 << 19 # GroundGrid.GROUND_ONLY_LAYER (20)
const ROW_FRACTIONS := [0.0, 0.03, 0.12, 0.33, 1.0] # wall rows, as a fraction of depth

var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _long_along_z := true
var _path_pos := Vector2.ZERO
var _samples: Array = [] # rim samples, see _make_samples()


func _ready() -> void:
	if not enabled:
		return
	if ground_grid == null or path_generator == null:
		push_warning("Ravine: assign ground_grid and path_generator.")
		return
	if path_generator.main_route.size() < 2:
		await path_generator.generated
	if not carve():
		push_warning("Ravine: could not find a spot for the ravine.")
		return
	# Wait for the remaining ground's collision to register before measuring it.
	for i in 3:
		await get_tree().physics_frame
	_make_samples()
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

## Removes the ground tiles (once). Called by the PathGenerator right after the
## main path exists, or by this node's own _ready if nothing did it yet.
func carve() -> bool:
	if hole.size != Vector2.ZERO:
		return true
	if path_generator == null or ground_grid == null or path_generator.main_route.size() < 2:
		return false
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	var route := path_generator.main_route
	var base := clampf(position_percent + _rng.randf_range(-position_noise, position_noise), 8.0, 92.0)
	# Candidate spots, nearest to the wanted one first.
	var fracs: Array[float] = [base]
	var k := 1
	while base + k * 3.0 <= 92.0 or base - k * 3.0 >= 8.0:
		if base + k * 3.0 <= 92.0:
			fracs.append(base + k * 3.0)
		if base - k * 3.0 >= 8.0:
			fracs.append(base - k * 3.0)
		k += 1
	for f in fracs:
		if _try_place(route, f / 100.0):
			print("Ravine: hole %s at %.0f%% of the main path." % [hole, f])
			carved.emit()
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
	var a_lo := c_across - ((n_across - 1) >> 1)
	var a_hi := a_lo + n_across - 1
	var l_lo := c_long - (n_long >> 1)
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
			_path_pos = pos
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


## The main path must cross the hole exactly once; the camp and finish stay clear.
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


# --- Jagged rim ---------------------------------------------------------------

func _ground_y(p: Vector2, fallback: float) -> float:
	var space := get_world_3d().direct_space_state
	var ref := ground_grid.global_position.y
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, ref + 150.0, p.y), Vector3(p.x, ref - 150.0, p.y), GROUND_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return fallback
	return (hit.position as Vector3).y


## Walks around the rim of the hole and records, per sample: "p" (point on the
## straight edge), "n" (direction into the gap), "side" (0 top, 1 right,
## 2 bottom, 3 left), "s" (distance along the loop), "y" (ground height) and
## "offs" (how far each wall row is pushed into the gap).
func _make_samples() -> void:
	_samples.clear()
	_noise.seed = _rng.randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0 / maxf(jag_scale, 1.0)
	_noise.fractal_octaves = 3

	var corners := [
		Vector2(hole.position.x, hole.position.y), Vector2(hole.end.x, hole.position.y),
		Vector2(hole.end.x, hole.end.y), Vector2(hole.position.x, hole.end.y)]
	var inward := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	var max_in := minf(jag_amplitude, minf(hole.size.x, hole.size.y) * 0.3)
	var cap := minf(max_in + crag_amount, minf(hole.size.x, hole.size.y) * 0.4)
	var rows := ROW_FRACTIONS.size()
	var s := 0.0
	var y := ground_grid.global_position.y
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var seg := a.distance_to(b)
		var n := maxi(1, ceili(seg / wall_step))
		var n_side: Vector2 = inward[side]
		var n_prev: Vector2 = inward[(side + 3) % 4]
		for k in n:
			var p := a.lerp(b, float(k) / n)
			var nn := n_side
			if k == 0:
				nn = (n_side + n_prev).normalized() # corners push diagonally
			var d := max_in * (0.5 + 0.5 * _noise.get_noise_2d(s, 0.0))
			d = clampf(d + _rng.randf_range(-jag_roughness, jag_roughness) * 0.5, 0.0, max_in)
			y = _ground_y(p - nn * 0.4, y)
			var offs := PackedFloat32Array()
			for r in rows:
				var crag := 0.0
				if r > 0:
					crag = (0.5 + 0.5 * _noise.get_noise_2d(s * 1.7, float(r) * 37.0)) * crag_amount * float(r) / (rows - 1)
				offs.append(minf(d + crag, cap))
			_samples.append({"p": p, "n": nn, "side": side, "s": s, "y": y, "offs": offs})
			s += seg / n


func _build_walls() -> void:
	var count := _samples.size()
	if count < 3:
		return
	var rows := ROW_FRACTIONS.size()
	var total_s := 0.0
	var last: Dictionary = _samples[count - 1]
	total_s = float(last["s"]) + wall_step

	# --- Cliff wall: a ring of samples x rows -----------------------------------
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in count + 1:
		var smp: Dictionary = _samples[i % count]
		var p: Vector2 = smp["p"]
		var nn: Vector2 = smp["n"]
		var y: float = smp["y"]
		var offs: PackedFloat32Array = smp["offs"]
		var u := (float(smp["s"]) if i < count else total_s) / 6.0
		for r in rows:
			var drop: float = float(ROW_FRACTIONS[r]) * depth
			verts.append(Vector3(p.x + nn.x * offs[r], y + 0.02 - drop, p.y + nn.y * offs[r]))
			normals.append(Vector3(nn.x, 0.0, nn.y))
			uvs.append(Vector2(u, drop))
	for i in count:
		var smp: Dictionary = _samples[i]
		var nn: Vector2 = smp["n"]
		var facing := Vector3(nn.x, 0.0, nn.y)
		for r in rows - 1:
			var a := i * rows + r
			var b := (i + 1) * rows + r
			_tri(verts, indices, a, b, a + 1, facing)
			_tri(verts, indices, b, b + 1, a + 1, facing)

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# --- Lip: ground between the straight tile edge and the jagged rim -----------
	var lv := PackedVector3Array()
	var ln := PackedVector3Array()
	var luv := PackedVector2Array()
	var li := PackedInt32Array()
	for i in count:
		var smp: Dictionary = _samples[i]
		var p: Vector2 = smp["p"]
		var nn: Vector2 = smp["n"]
		var y: float = smp["y"]
		var offs: PackedFloat32Array = smp["offs"]
		var inner := p + nn * offs[0]
		lv.append(Vector3(p.x, y + 0.02, p.y))
		lv.append(Vector3(inner.x, y + 0.02, inner.y))
		ln.append(Vector3.UP)
		ln.append(Vector3.UP)
		luv.append(p)
		luv.append(inner)
	for i in count:
		var a := i * 2
		var b := ((i + 1) % count) * 2
		_tri(lv, li, a, b, a + 1, Vector3.UP)
		_tri(lv, li, b, b + 1, a + 1, Vector3.UP)
	var larrays := []
	larrays.resize(Mesh.ARRAY_MAX)
	larrays[Mesh.ARRAY_VERTEX] = lv
	larrays[Mesh.ARRAY_NORMAL] = ln
	larrays[Mesh.ARRAY_TEX_UV] = luv
	larrays[Mesh.ARRAY_INDEX] = li
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, larrays)
	mesh.surface_set_material(0, _wall_material())
	mesh.surface_set_material(1, _lip_material())

	var mi := MeshInstance3D.new()
	mi.name = "Walls"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


func _lip_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 lip_color : source_color;

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
	float n = vnoise(UV * 1.1) * 0.6 + vnoise(UV * 4.5) * 0.4;
	ALBEDO = lip_color * (0.6 + 0.9 * n);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("lip_color", lip_color)
	return mat


# --- Bridge -------------------------------------------------------------------

## The two deck end points (X, ground height, Z), found from the jagged rim at the path's crossing.
func _bridge_ends() -> Array[Vector3]:
	var coord := _path_pos.y if _long_along_z else _path_pos.x
	var lo := hole.position.y if _long_along_z else hole.position.x
	var hi := hole.end.y if _long_along_z else hole.end.x
	coord = clampf(coord, lo + 3.0, hi - 3.0)
	var sides: Array = [3, 1] if _long_along_z else [0, 2]
	var ends: Array[Vector3] = []
	for side in sides:
		var best: Dictionary = {}
		var best_d := INF
		for smp in _samples:
			if int(smp["side"]) != int(side):
				continue
			var sp: Vector2 = smp["p"]
			var dd := absf((sp.y if _long_along_z else sp.x) - coord)
			if dd < best_d:
				best_d = dd
				best = smp
		var p: Vector2 = best["p"]
		var nn: Vector2 = best["n"]
		var offs: PackedFloat32Array = best["offs"]
		var e := p + nn * (offs[0] - anchor_inset)
		if _long_along_z:
			e.y = coord
		else:
			e.x = coord
		ends.append(Vector3(e.x, float(best["y"]) + 0.02, e.y))
	return ends


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
	var ends := _bridge_ends()
	bridge.build(ends[0], ends[1])
