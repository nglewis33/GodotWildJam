class_name SignPost
extends Node
## Child of the sign model. Watches the player; runs the read-sign cutscene.

@export var feature: SignFeature ## What this sign says and does.
@export_multiline var text := "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
@export var trigger_distance := 4.0
@export var wait_time := 2.0
@export_range(0, 90) var max_view_angle := 75.0 ## Degrees off the sign's front.
@export var reread_with_e := true ## After the first read, press E (nearby, in front, flashlight on) to read again.
@export_group("Cutscene")
@export var front_axis := Vector3(0, 0, 1) ## Local axis the sign's face points along.
@export var view_distance := 1.5
@export var view_height := 1.4
@export var camera_time := 1.2
@export var fade_time := 0.8

var _timer := 0.0
var _busy := false
var _read := false
var _dialogue: DialogueBox


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keep running so the cutscene survives the pause
	_dialogue = DialogueBox.new()
	add_child(_dialogue)


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
	if _busy or get_tree().paused or _read:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	if _can_read(player):
		_timer += delta
		if _timer >= wait_time:
			_timer = 0.0
			_run_cutscene(player)
	else:
		_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not (reread_with_e and _read) or _busy or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and _can_read(player):
			_run_cutscene(player)


func _flashlight_on(player: Node) -> bool:
	var f := player.get_node_or_null("Flashlight") as Node3D
	return f != null and f.is_visible_in_tree()


func _run_cutscene(player: Node3D) -> void:
	_busy = true
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_busy = false
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
	await _transition(cam, target, origin, player, 0.0, base_o)

	get_tree().paused = false
	_read = true
	_busy = false
	if feature:
		feature.apply(get_tree().current_scene)


func _transition(cam: Camera3D, from: Transform3D, to: Transform3D, player: Node3D, a0: float, a1: float) -> void:
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(t: float): cam.global_transform = from.interpolate_with(to, t), 0.0, 1.0, camera_time)
	tw.tween_method(func(v: float):
		if is_instance_valid(player):
			PlayerFade.set_opacity(player, v), a0, a1, fade_time)
	await tw.finished
