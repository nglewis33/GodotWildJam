class_name CampProp
extends Node3D
## Wraps an imported model (a child named "Model"): rescales it to a target size,
## sits it on the ground at the origin, and gives it a collider.

enum ColliderType { BOX, CYLINDER, CONVEX_HULL }

## Longest horizontal side of the model after rescaling (world units).
@export var target_size := 2.0
@export var add_collision := true
@export var collider: ColliderType = ColliderType.CONVEX_HULL
## Nodes whose names contain any of these are ignored when measuring and
## building the collider (e.g. flame sprites).
@export var ignore_names := PackedStringArray()

var model: Node3D
## Bounds of the fitted model in this node's space (base sits at y = 0).
var fitted_box := AABB()


func _ready() -> void:
	model = get_node_or_null("Model") as Node3D
	if model == null:
		push_warning("CampProp '%s' needs a child node called Model." % name)
		return
	_fit()
	if add_collision:
		_build_collider()


func _ignored(node: Node) -> bool:
	for n in ignore_names:
		if n != "" and String(node.name).contains(n):
			return true
	return false


func _fit() -> void:
	var r := _measure(model, Transform3D.IDENTITY, AABB(), false)
	var box: AABB = r[0]
	if not r[1]:
		return
	var s := target_size / maxf(maxf(box.size.x, box.size.z), 0.0001)
	var c := box.get_center()
	model.scale = Vector3.ONE * s
	model.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	fitted_box = AABB(Vector3(-box.size.x * s * 0.5, 0.0, -box.size.z * s * 0.5), box.size * s)


## Returns [merged AABB, found_any_mesh], in `model`'s local space.
func _measure(node: Node, xf: Transform3D, box: AABB, found: bool) -> Array:
	if node is MeshInstance3D and node.mesh:
		var b: AABB = xf * node.mesh.get_aabb()
		box = box.merge(b) if found else b
		found = true
	for child in node.get_children():
		if _ignored(child):
			continue
		var cxf := xf
		if child is Node3D:
			cxf = xf * child.transform
		var r := _measure(child, cxf, box, found)
		box = r[0]
		found = r[1]
	return [box, found]


func _build_collider() -> void:
	var shape: Shape3D
	var offset := Vector3.ZERO
	match collider:
		ColliderType.BOX:
			var b := BoxShape3D.new()
			b.size = fitted_box.size
			shape = b
			offset = fitted_box.get_center()
		ColliderType.CYLINDER:
			var cy := CylinderShape3D.new()
			cy.radius = maxf(fitted_box.size.x, fitted_box.size.z) * 0.5
			cy.height = fitted_box.size.y
			shape = cy
			offset = fitted_box.get_center()
		ColliderType.CONVEX_HULL:
			var pts := PackedVector3Array()
			_collect_points(model, model.transform, pts)
			if pts.is_empty():
				return
			var hull := ConvexPolygonShape3D.new()
			hull.points = pts
			shape = hull
	var body := StaticBody3D.new()
	body.name = "Collision"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	body.add_child(cs)
	add_child(body)


func _collect_points(node: Node, xf: Transform3D, pts: PackedVector3Array) -> void:
	if node is MeshInstance3D and node.mesh:
		var hull: ConvexPolygonShape3D = node.mesh.create_convex_shape(true, true)
		if hull:
			for p in hull.points:
				pts.append(xf * p)
	for child in node.get_children():
		if _ignored(child):
			continue
		var cxf := xf
		if child is Node3D:
			cxf = xf * child.transform
		_collect_points(child, cxf, pts)
