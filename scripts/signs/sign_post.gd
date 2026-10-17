class_name SignPost
extends Node
## Child of the sign model. Watches the player; runs the read-sign cutscene.

@export var feature: SignFeature ## What this sign says and does.
@export_multiline var text := "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
@export var trigger_distance := 4.0
## How long the flashlight must be held on the sign to read it.
@export var wait_time := 2.0
## How fast the ring empties when the light moves off (fraction per second).
@export var release_speed := 0.5
## Trees, rocks and the like between the light and the sign block it.
@export var require_line_of_sight := true
@export_range(0, 90) var max_view_angle := 75.0 ## Degrees off the sign's front.
@export var reread_with_e := true ## After the first read, press E (nearby, in front, flashlight on) to read again.
@export_group("Cutscene")
@export var front_axis := Vector3(0, 0, 1) ## Local axis the sign's face points along.
@export var view_distance := 1.5
@export var view_height := 1.4
@export var camera_time := 1.2
@export var fade_time := 0.8

signal finished ## After the sign was read and the game has unfrozen.

var _busy := false
var _read := false
var _dialogue: DialogueBox
var _prompt: InteractPrompt
var _ring: SignRing
var _charge := 0.0
var _box := AABB()


## For Interaction: re-reading with E, once it has been read.
func interact_ready() -> bool:
	if not (reread_with_e and _read) or _busy:
		return false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	return player != null and _near(player) and _in_front(player)


func interact_position() -> Vector3:
	return (get_parent() as Node3D).global_position


func _ready() -> void:
	add_to_group("interactable")
	process_mode = Node.PROCESS_MODE_ALWAYS # keep running so the cutscene survives the pause
	_dialogue = DialogueBox.new()
	add_child(_dialogue)
	_prompt = InteractPrompt.new()
	add_child(_prompt)
	_ring = SignRing.new()
	get_parent().add_child.call_deferred(_ring)


func _near(player: Node3D) -> bool:
	var d := player.global_position - (get_parent() as Node3D).global_position
	d.y = 0
	return d.length() <= trigger_distance


func _in_front(player: Node3D) -> bool:
	var sign_node := get_parent() as Node3D
	var front := sign_node.global_transform.basis * front_axis
	front.y = 0
	var to_player := player.global_position - sign_node.global_position
	to_player.y = 0
	if front.length() < 0.001 or to_player.length() < 0.001:
		return true
	return rad_to_deg(front.angle_to(to_player)) <= max_view_angle


func _can_read(player: Node3D) -> bool:
	return _near(player) and _in_front(player) and _flashlight_on(player)


func _process(delta: float) -> void:
	_prompt.show_prompt("Press E to re-read the sign", interact_ready() and Interaction.is_best(self))
	if _read:
		_ring.set_progress(0.0)
		return
	if _busy or get_tree().paused or Cutscene.busy():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# The light has to stay on the sign: the ring fills while it does and drains when it doesn't.
	var lit := _near(player) and _in_front(player) and _beam_touches(player)
	if lit:
		_charge = minf(_charge + delta / maxf(wait_time, 0.01), 1.0)
	else:
		_charge = maxf(_charge - delta * release_speed, 0.0)
	_ring.global_position = _ring_position()
	_ring.set_progress(_charge)
	if _charge >= 1.0:
		_charge = 0.0
		_ring.set_progress(0.0)
		_run_cutscene(player)


## World-space box around the sign's meshes (computed once).
func _world_box() -> AABB:
	if _box.size == Vector3.ZERO:
		var vis := get_parent().find_children("*", "VisualInstance3D", true, false)
		var first := true
		for v in vis:
			var vi := v as VisualInstance3D
			var b: AABB = vi.global_transform * vi.get_aabb()
			_box = b if first else _box.merge(b)
			first = false
		if first:
			_box = AABB((get_parent() as Node3D).global_position - Vector3(0.5, 0.0, 0.5), Vector3(1, 1.8, 1))
	return _box


func _ring_position() -> Vector3:
	var box := _world_box()
	var front := ((get_parent() as Node3D).global_transform.basis * front_axis).normalized()
	return box.get_center() + front * 0.5 + Vector3.UP * (box.size.y * 0.5 + 0.35)


## True when any part of the sign (its box centre or corners) is inside the flashlight's cone.
func _beam_touches(player: Node) -> bool:
	var f := player.get_node_or_null("Flashlight") as SpotLight3D
	if f == null or not f.is_visible_in_tree():
		return false
	var box := _world_box()
	var axis := -f.global_transform.basis.z
	var half := deg_to_rad(f.spot_angle)
	var pts: Array[Vector3] = [box.get_center()]
	for i in 8:
		pts.append(box.get_endpoint(i))
	for p in pts:
		var to := p - f.global_position
		var d := to.length()
		if d < 0.05 or d > f.spot_range:
			continue
		if axis.angle_to(to / d) <= half and _line_clear(f.global_position, p, player):
			return true
	return false


## No solid object between the light and the point (the sign's own collider doesn't count).
func _line_clear(from: Vector3, to: Vector3, player: Node) -> bool:
	if not require_line_of_sight:
		return true
	var space := (get_parent() as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	var c := hit.collider as Node
	return c != null and get_parent().is_ancestor_of(c)


func _unhandled_input(event: InputEvent) -> void:
	if not (reread_with_e and _read) or _busy or get_tree().paused or Cutscene.busy():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and _near(player) and _in_front(player) and Interaction.is_best(self):
			_run_cutscene(player)


func _flashlight_on(player: Node) -> bool:
	var f := player.get_node_or_null("Flashlight") as Node3D
	return f != null and f.is_visible_in_tree()


func _run_cutscene(player: Node3D) -> void:
	_busy = true
	Cutscene.begin()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_busy = false
		Cutscene.finish()
		return
	get_tree().paused = true
	var sign_node := get_parent() as Node3D
	var front := (sign_node.global_transform.basis * front_axis).normalized()
	var center := sign_node.global_position + Vector3.UP * 1.0
	var vis := sign_node.find_children("*", "VisualInstance3D", true, false)
	if not vis.is_empty():
		var box: AABB = (vis[0] as VisualInstance3D).global_transform * (vis[0] as VisualInstance3D).get_aabb()
		for v in vis:
			box = box.merge((v as VisualInstance3D).global_transform * (v as VisualInstance3D).get_aabb())
		center = box.get_center()
	var cam_pos := center + front * view_distance + Vector3.UP * (view_height - 1.4) # view_height 1.4 = level with sign center
	var target := Transform3D(Basis.IDENTITY, cam_pos).looking_at(center, Vector3.UP)
	var origin := cam.global_transform
	var base_o := PlayerFade.get_opacity(player)
	var shown := feature.text if feature else text

	await _transition(cam, origin, target, player, base_o, 0.0)
	await _dialogue.show_text(shown)
	if feature:
		await feature.after_message(get_tree().current_scene, cam, player)
	await _transition(cam, cam.global_transform, origin, player, PlayerFade.get_opacity(player), base_o)

	get_tree().paused = false
	if not _read: # first time: mark it on the map
		var sp := (get_parent() as Node3D).global_position
		get_tree().call_group("minimap", "add_marker", sp, "sign")
	_read = true
	_busy = false
	Cutscene.finish()
	if feature:
		feature.apply(get_tree().current_scene)
	finished.emit()


func _transition(cam: Camera3D, from: Transform3D, to: Transform3D, player: Node3D, a0: float, a1: float) -> void:
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(t: float): cam.global_transform = from.interpolate_with(to, t), 0.0, 1.0, camera_time)
	tw.tween_method(func(v: float):
		if is_instance_valid(player):
			PlayerFade.set_opacity(player, v), a0, a1, fade_time)
	await tw.finished
