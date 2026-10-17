extends Node
## Spawns one sign per feature in front of the player at the start.

@export var sign_scene: PackedScene
@export var features: Array[SignFeature] = []
@export var distance := 3.5 ## In front of the player (the camp fire is about 6 away).
@export var side_offset := 1.5 ## Shifts the whole row to the right so it stays off the fire line.
@export var spacing := 3.0 ## Sideways gap between signs.
@export var sign_height := 1.8 ## Model is rescaled to this height.
@export var auto_spawn := true ## False: the story code calls spawn_at() itself.
@export var ray_height := 5.0
@export var ray_depth := 15.0


func _ready() -> void:
	if not auto_spawn:
		return
	# CampSite moves the player after two physics frames; wait for that.
	for i in 3:
		await get_tree().physics_frame
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		player = get_parent().get_node_or_null("Player") as Node3D
		if player:
			player.add_to_group("player")
	if player == null or sign_scene == null:
		push_warning("SignSpawner: missing player or sign_scene")
		return
	var fwd := player.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := Vector3.UP.cross(fwd).normalized()
	var list: Array = features if not features.is_empty() else [null]
	for i in list.size():
		var offset := (i - (list.size() - 1) * 0.5) * spacing + side_offset
		_spawn(player, player.global_position + fwd * distance + right * offset, fwd, list[i])


## Places one sign at a point; its face looks along -fwd (toward whoever walks along fwd).
func spawn_at(pos: Vector3, fwd: Vector3, feature: SignFeature) -> Node3D:
	return _spawn(get_parent() as Node3D, pos, fwd, feature)


func _spawn(player: Node3D, pos: Vector3, fwd: Vector3, feature: SignFeature) -> Node3D:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * ray_height, pos + Vector3.DOWN * ray_depth)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		pos = hit.position
	var s := sign_scene.instantiate() as Node3D
	get_parent().add_child(s)
	s.global_position = pos
	s.rotation.y = atan2(-fwd.x, -fwd.z) # +Z faces the player
	var box := _local_aabb(s)
	if box.size.y > 0.0001:
		var k := sign_height / box.size.y
		s.scale = Vector3.ONE * k
		s.global_position = pos - Vector3.UP * (box.position.y * k) # bottom sits on ground
	var ctrl := s.find_child("SignPost", true, false) as SignPost
	if ctrl == null:
		ctrl = SignPost.new()
		ctrl.name = "SignPost"
		s.add_child(ctrl)
	if feature:
		ctrl.feature = feature
	print("SignSpawner: sign at ", s.global_position, " ground hit: ", hit != null)
	return s


func _local_aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var b: AABB = (inv * vi.global_transform) * vi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
