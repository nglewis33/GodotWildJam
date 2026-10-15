class_name CampSite
extends Node
## Builds the starting camp on the path's start circle: campfire in the middle,
## tent on one side, log on the other, and the player at the circle's edge
## facing the fire.

@export var path_generator: PathGenerator
@export var campfire_scene: PackedScene
@export var tent_scene: PackedScene
@export var log_scene: PackedScene
@export var npc_scene: PackedScene

@export_group("Layout")
## Distance from the fire, in world units.
@export var tent_distance := 3.8
@export var log_distance := 3.2
## Player start, as a fraction of the start circle radius from the fire.
@export_range(0.2, 1.0) var player_edge_fraction := 0.75
@export var tent_on_right := true

@export_group("Orientation")
## Models "face" the fire along their +Z axis; rotate if the entrance or log
## direction is off.
@export var tent_yaw_offset_degrees := 270.0
@export var log_yaw_offset_degrees := 90.0

@export_group("NPC")
## Where the NPC sits, in the log's local space, measured from the middle of
## the log's top surface (x = along the log's width, y = up, z = along the log).
## Adjust y until the NPC's behind meets the log; scale the log with target_size
## on Log.tscn if the log itself needs to be taller or shorter.
@export var npc_seat_offset := Vector3(0.0, -0.45, 0.0)
@export var npc_yaw_offset_degrees := 0.0

@export var ray_height := 30.0
@export var ray_depth := 60.0


func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if path_generator == null:
		push_warning("CampSite: needs a PathGenerator.")
		return
	var c := path_generator.start_position
	var out_dir := (path_generator.end_position - c).normalized()
	if out_dir == Vector2.ZERO:
		out_dir = Vector2.RIGHT
	# Player's right-hand side (they face along out_dir).
	var right := Vector2(-out_dir.y, out_dir.x)
	var tent_side := right if tent_on_right else -right

	_place(campfire_scene, c, c + out_dir, 0.0)
	_place(tent_scene, c + tent_side * tent_distance, c, tent_yaw_offset_degrees)
	var log_pos := c - tent_side * log_distance
	var log_node := _place(log_scene, log_pos, c, log_yaw_offset_degrees)
	_seat_npc(log_node, c)

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var p := c - out_dir * path_generator.start_radius * player_edge_fraction
		var y := _ground_y(p, player.global_position.y)
		var d := c - p
		var pos := Vector3(p.x, y + 0.3, p.y)
		player.global_position = pos
		player.rotation.y = atan2(d.x, d.y)
		if "velocity" in player:
			player.velocity = Vector3.ZERO
		player.set("_spawn_position", pos) # respawn point after falling


func _place(scene: PackedScene, p: Vector2, look_at_xz: Vector2, yaw_offset_deg: float) -> Node3D:
	if scene == null:
		return null
	var n := scene.instantiate() as Node3D
	get_parent().add_child(n)
	var d := look_at_xz - p
	var yaw := atan2(d.x, d.y) + deg_to_rad(yaw_offset_deg) if d.length() > 0.01 else 0.0
	# Sit on the lowest ground under the footprint so tall grass tufts don't lift it.
	var r: float = (n.get("target_size") if n.get("target_size") != null else 1.0) * 0.4
	var y := _ground_y(p, n.global_position.y)
	for off in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		y = minf(y, _ground_y(p + off, y))
	n.global_position = Vector3(p.x, y - 0.02, p.y)
	n.rotation.y = yaw
	return n


func _seat_npc(log_node: Node3D, fire: Vector2) -> void:
	if npc_scene == null or log_node == null:
		return
	var top := 0.0
	if "fitted_box" in log_node:
		top = log_node.fitted_box.end.y
	var seat := log_node.to_global(Vector3(npc_seat_offset.x, top + npc_seat_offset.y, npc_seat_offset.z))
	var npc := npc_scene.instantiate() as Node3D
	get_parent().add_child(npc)
	npc.global_position = seat
	var d := fire - Vector2(seat.x, seat.z)
	npc.rotation.y = atan2(d.x, d.y) + deg_to_rad(npc_yaw_offset_degrees)


func _ground_y(p: Vector2, fallback: float) -> float:
	var ref := path_generator.global_position.y
	var from := Vector3(p.x, ref + ray_height, p.y)
	var to := Vector3(p.x, ref - ray_depth, p.y)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	return hit.position.y if hit else fallback
