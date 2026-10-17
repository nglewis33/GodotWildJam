class_name SuspensionBridge
extends Node3D
## A procedural rope bridge made of primitives: wooden planks on a gently
## sagging deck, a tower at each corner, a swooping main cable on each side, a
## handrail and hanger ropes. Call build(a, b) with the two ground points
## it should connect. Planks, posts and hangers are MultiMeshes, so it is cheap.

@export_group("Deck")
@export var deck_width := 2.8
@export var plank_length := 0.85 ## Along the bridge.
@export var plank_gap := 0.07
@export var plank_thickness := 0.12
## How far the middle of the deck hangs below a straight line, as a fraction of the length.
@export_range(0.0, 0.15, 0.001) var sag_fraction := 0.03
## The deck ends this high above the ground, so you have to climb steps to get on.
@export var end_lift := 1.0
@export var step_count := 2
@export var step_depth := 1.0 ## Length of each step along the bridge.
## Random per-plank nudges so it looks hand-built.
@export var plank_jitter := 1.0

@export_group("Towers and cables")
@export var tower_height := 5.0 ## Above the deck ends.
@export var tower_size := 0.4
@export var rail_height := 1.1 ## Handrail height above the deck.
@export var rope_radius := 0.045
@export var cable_radius := 0.07
@export var hanger_spacing := 2.4

@export_group("Look")
@export var wood_color := Color(0.2, 0.135, 0.08)
@export var rope_color := Color(0.4, 0.33, 0.22)
@export var seed_value := 0

var _rng := RandomNumberGenerator.new()


## How far the steps stick out past each end of the deck.
func get_approach_length() -> float:
	return step_count * step_depth


## Builds the bridge between world points a and b (their y is the ground height).
func build(a: Vector3, b: Vector3) -> void:
	for ch in get_children():
		ch.queue_free()
	_rng.seed = seed_value if seed_value != 0 else randi()

	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := flat.length()
	if length < 1.0:
		return
	var mid := (a + b) * 0.5
	var yaw := atan2(flat.x, flat.z)
	top_level = true
	global_transform = Transform3D(Basis(Vector3.UP, yaw), mid) # local +Z runs from a to b

	var half := length * 0.5
	var ga := a.y - mid.y # ground height at each end
	var gb := b.y - mid.y
	var ya := ga + end_lift
	var yb := gb + end_lift
	var sag := length * sag_fraction
	var half_w := deck_width * 0.5

	# Deck height at t (0..1 from a to b) and its slope along the bridge.
	var deck_y := func(t: float) -> float:
		return lerpf(ya, yb, t) - sag * 4.0 * t * (1.0 - t)
	var slope := func(t: float) -> float:
		return ((yb - ya) - sag * 4.0 * (1.0 - 2.0 * t)) / length

	var wood := _wood_material()
	var rope := _rope_material()

	# --- Planks, towers, hangers (boxes) ---------------------------------------
	var boxes: Array[Transform3D] = [] # wood
	var hangers: Array[Transform3D] = [] # rope
	var count := maxi(1, roundi(length / (plank_length + plank_gap)))
	var pitch := length / count
	for k in count:
		var t := (k + 0.5) / count
		var z := -half + (k + 0.5) * pitch
		var y: float = deck_y.call(t)
		var pitch_angle := -atan(slope.call(t))
		var jy := _rng.randf_range(-0.012, 0.012) * plank_jitter
		var jyaw := _rng.randf_range(-0.025, 0.025) * plank_jitter
		var bs := Basis(Vector3.RIGHT, pitch_angle) * Basis(Vector3.UP, jyaw) \
			* Basis.from_scale(Vector3(deck_width, plank_thickness, maxf(pitch - plank_gap, 0.1)))
		boxes.append(Transform3D(bs, Vector3(0.0, y + jy, z)))

	# Towers: four posts plus a cross beam on top of each end.
	for end in 2:
		var sgn := -1.0 if end == 0 else 1.0
		var t_end := 0.0 if end == 0 else 1.0
		var z_end := sgn * half
		var y_end: float = deck_y.call(t_end)
		var ground_y: float = (ga if end == 0 else gb) - 0.4
		var top_y := y_end + tower_height
		for side in [-1.0, 1.0]:
			var x := float(side) * (half_w + tower_size * 0.5)
			var h := top_y - ground_y
			boxes.append(Transform3D(Basis.from_scale(Vector3(tower_size, h, tower_size)), Vector3(x, ground_y + h * 0.5, z_end)))
		var span := deck_width + tower_size * 3.0
		boxes.append(Transform3D(Basis.from_scale(Vector3(span, tower_size * 0.7, tower_size * 0.7)), Vector3(0.0, top_y - tower_size * 0.35, z_end)))

	# Steps up to the raised deck at both ends.
	var step_boxes: Array[AABB] = []
	var riser := end_lift / float(step_count + 1)
	for end in 2:
		var sgn := -1.0 if end == 0 else 1.0
		var g := ga if end == 0 else gb
		for j in range(1, step_count + 1):
			var top := g + end_lift - riser * j
			var bottom := g - 1.2
			var h := top - bottom
			var zc := sgn * (half + (j - 0.5) * step_depth)
			var size := Vector3(deck_width + 0.3, h, step_depth)
			var center := Vector3(0.0, bottom + h * 0.5, zc)
			boxes.append(Transform3D(Basis.from_scale(size), center))
			step_boxes.append(AABB(center - size * 0.5, size))

	# Cables, handrails and hangers, one set per side.
	var ropes: Array[ArrayMesh] = []
	var samples := maxi(8, ceili(length / 1.0))
	for side in [-1.0, 1.0]:
		var x := float(side) * (half_w + tower_size * 0.5)
		var cable := PackedVector3Array()
		var handrail := PackedVector3Array()
		for i in samples + 1:
			var t := float(i) / samples
			var z := lerpf(-half, half, t)
			var y: float = deck_y.call(t)
			var u := 2.0 * t - 1.0
			var cable_above := rail_height + (tower_height - rail_height) * u * u
			cable.append(Vector3(x, y + cable_above, z))
			handrail.append(Vector3(x, y + rail_height, z))
		ropes.append(_tube(cable, cable_radius))
		ropes.append(_tube(handrail, rope_radius))
		# Hangers from the deck edge up to the main cable.
		var n_h := maxi(1, roundi(length / hanger_spacing))
		for h in n_h + 1:
			var t := float(h) / n_h
			var z := lerpf(-half, half, t)
			var y0: float = deck_y.call(t) + plank_thickness * 0.5
			var u := 2.0 * t - 1.0
			var y1 := y0 - plank_thickness * 0.5 + rail_height + (tower_height - rail_height) * u * u
			var hh := y1 - y0
			if hh > 0.1:
				hangers.append(Transform3D(Basis.from_scale(Vector3(rope_radius * 1.4, hh, rope_radius * 1.4)), Vector3(x, y0 + hh * 0.5, z)))

	_add_multimesh("Wood", boxes, wood)
	_add_multimesh("Hangers", hangers, rope)
	for i in ropes.size():
		var mi := MeshInstance3D.new()
		mi.name = "Rope%d" % i
		mi.mesh = ropes[i]
		mi.material_override = rope
		add_child(mi)

	# --- Collision: a smooth walkable ribbon plus low side barriers -------------
	var ribbon := PackedVector3Array()
	var barrier := PackedVector3Array()
	var cs := maxi(4, ceili(length / 0.6))
	var top_off := plank_thickness * 0.5
	var inner := half_w + 0.02
	for i in cs:
		var t0 := float(i) / cs
		var t1 := float(i + 1) / cs
		var z0 := lerpf(-half, half, t0)
		var z1 := lerpf(-half, half, t1)
		var y0: float = deck_y.call(t0) + top_off
		var y1: float = deck_y.call(t1) + top_off
		_quad(ribbon, Vector3(-inner, y0, z0), Vector3(inner, y0, z0), Vector3(inner, y1, z1), Vector3(-inner, y1, z1))
		for sd in [-1.0, 1.0]:
			var x := float(sd) * inner
			_quad(barrier,
				Vector3(x, y0, z0), Vector3(x, y0 + rail_height + 0.3, z0),
				Vector3(x, y1 + rail_height + 0.3, z1), Vector3(x, y1, z1))
	var faces := ribbon + barrier
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "BridgeBody"
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	for sb in step_boxes:
		var sc := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = sb.size
		sc.shape = box
		sc.position = sb.get_center()
		body.add_child(sc)
	add_child(body)


func _add_multimesh(node_name: String, xforms: Array[Transform3D], mat: Material) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new() # 1 x 1 x 1, scaled per instance
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


## Adds a quad (two triangles, both orientations don't matter: collision is two-sided).
func _quad(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	out.append_array([a, b, c, a, c, d])


func _tube(points: PackedVector3Array, radius: float, sides := 5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	for i in n:
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, n - 1)]
		var tangent := (next - prev).normalized()
		var n1 := tangent.cross(Vector3.UP)
		if n1.length() < 0.001:
			n1 = tangent.cross(Vector3.RIGHT)
		n1 = n1.normalized()
		var n2 := tangent.cross(n1).normalized()
		for s in sides:
			var ang := TAU * float(s) / sides
			var dir := n1 * cos(ang) + n2 * sin(ang)
			st.set_normal(dir)
			st.add_vertex(points[i] + dir * radius)
	for i in n - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a := i * sides + s
			var b := i * sides + s2
			var c := (i + 1) * sides + s
			var d := (i + 1) * sides + s2
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	return st.commit()


func _wood_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = wood_color
	m.roughness = 0.95
	return m


func _rope_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = rope_color
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
