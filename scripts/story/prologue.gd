class_name Prologue
extends Node
## Story part 1: the dark loop, the stranger at the camp, the flashlight, the
## first sign, the fog lifting, and the offer to work together.
## Scene wiring is done with the exports; the text is below.

signal part_finished

@export var camp: CampSite
@export var player: Node3D
@export var camera: FollowCamera
@export var atmosphere: NightAtmosphere
@export var scatter: ForestScatter
@export var sign_spawner: SignSpawner
@export var sign_feature: SignFeature
## Hidden until the fog lifts.
@export var minimap: CanvasLayer
## Key reminders along the bottom; "F" is revealed when the flashlight is handed over.
@export var controls_hint: ControlsHint

@export_group("Fog")
## Pitch blackness at the start (higher = shorter sight).
@export var dark_density := 0.6
## Light fog around the camp once you loop back (enough to see the stranger).
@export var camp_density := 0.12
@export var dark_color := Color(0, 0, 0)

@export_group("Start")
## Off: you begin at the camp with the stranger in front of you and press E to talk.
## On: you begin in pitch blackness and loop back to camp first.
@export var start_with_dark_walk := false
@export var talk_distance := 4.0

@export_group("Fog Lift")
## The fog briefly thickens to this as the forest appears, then thins out over lift_time.
@export var lift_peak_density := 0.3
@export var lift_time := 6.0

@export_group("Loop")
## Leave this radius around the fire in the dark and you wake up at camp again.
@export var loop_radius := 14.0
@export var fade_time := 1.2
## Also loop back after this many seconds in the dark, wherever you are.
@export var loop_seconds := 30.0

@export_group("Sign")
## Where the first sign stands: distance from the fire toward the path, and sideways.
@export var sign_distance := 5.5
@export var sign_side := 2.5

@export_group("Cutscene Camera")
## How far along the path (from its start) the camera stands to look along it.
@export var path_view_distance := 8.0
## How far further along the path it looks, and how high the camera is above the ground.
@export var path_look_ahead := 25.0
@export var path_view_height := 1.2
@export var path_look_height := 0.6
## How far in front of the sign the camera stands to look at it.
@export var sign_view_distance := 2.4
## Camera height above the ground, and the height it aims at (lower = looks further down).
@export var sign_view_height := 1.1
@export var sign_look_height := 1.1

@export_group("Stranger Camera")
@export var npc_view_distance := 3.0
@export var npc_view_height := 1.5
@export var npc_look_height := 1.4

@export_group("Tent Camera")
@export var tent_view_distance := 5.0
@export var tent_view_height := 1.8
@export var tent_look_height := 1.0

@export_group("Dialogue")
@export_multiline var line_greeting := "Thank the heavens! Someone else is here to share in my misery. I have been lost in these woods for quite an age..."
@export_multiline var line_path := "You see that path? Whenever I try to follow the path, something nefarious always stops me from continuing, and I must return to this here camp"
@export_multiline var line_sign := "You see that sign? Those signs are littered across the forest. If you shine a flashlight on it, a truth of the forest will appear. Funny thing, the truth... Before you read the sign, its words are a lie. You don't believe me, do you? Here, take this flashlight, walk up to that there sign, and shine it on it"
@export_multiline var line_after := "The sign wants you to walk the path. But, you see, the path is too dangerous. Things are out to get me. So, I tried going through the woods, and found more signs. These signs held strange powers that altered the forest and path. Eventually, the signs shifted their message and started threatening me. They told me to get back on the path, or else. If I ignored them for too long, I found myself back at the main camp. What a pain! But, now that you're here. We can try something new. I'll stay on the path, and you'll look around the forest for these signs with strange powers. I don't know if this will work, but maybe we can both survive these woods. So what do you say, partner? Should we work together on this?"
@export_multiline var line_tent := "Glad you're willing to help. You didn't have much of a choice, but I still appreciate it. In that there tent is a map. Whenever you find something important, you can mark it on the map, so that we dont get lost. Go ahead and grab it, as soon as you do, ill start walking."
@export var answers: Array[String] = ["Yes", "Yes"]

var _dialogue: DialogueBox
var _fade: ColorRect
var _hint: Label
var _sign: Node3D
var _flashlight: Node
var _looped := false
var _in_dark := false
var _dark_time := 0.0
var _waiting_for_talk := false
var _leashed := true ## Can't wander off until the first sign has been read.
var _respawning := false
var _waiting_for_sign := false


func _ready() -> void:
	Cutscene.reset()
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps running during the sign cutscene's pause
	_dialogue = DialogueBox.new()
	add_child(_dialogue)
	_build_overlay()
	if camp == null or player == null or camera == null:
		push_warning("Prologue: needs camp, player and camera.")
		return
	_flashlight = player.get_node_or_null("Flashlight")
	_begin()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.offset_top = 60
	_hint.offset_left = -200
	_hint.offset_right = 200
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.modulate.a = 0.0
	layer.add_child(_hint)


# --- Part 1 ---------------------------------------------------------------------

func _begin() -> void:
	if camp.npc == null:
		await camp.built
	if _flashlight:
		_flashlight.call("set_locked", true)
	_place_first_sign() # can't be read until the flashlight is handed over
	if camp.tent:
		camp.tent.interactable = false # opened only after the stranger asks
	# Nothing but the camp is visible, and nothing is solid but the ground.
	_set_world_hidden(true)
	if not start_with_dark_walk:
		_set_minimap_shown(false)
		atmosphere.set_fog(camp_density, dark_color)
		atmosphere.set_mist_visible(false)
		_looped = true
		_place_player_by_log()
		camera.snap_to_target()
		await _fade_to(0.0, 2.0)
		_waiting_for_talk = true
		camp.npc.interact_distance = talk_distance
		camp.npc.interactable_enabled = true
		return
	_set_camp_shown(false)
	atmosphere.set_fog(dark_density, dark_color)
	atmosphere.set_mist_visible(false)
	_set_minimap_shown(false)
	_in_dark = true
	print("Prologue: dark phase started, fire at ", camp.fire_position)
	await _fade_to(0.0, 2.0)


func _process(delta: float) -> void:
	if player == null or camp == null or camp.npc == null:
		return
	if _waiting_for_talk:
		var near := Interaction.best(get_tree()) == camp.npc
		_hint.text = "Press E to interact with %s" % camp.npc.display_name
		_hint.modulate.a = 1.0 if near else 0.0
	if _leashed and not _in_dark and _looped and not _respawning and not get_tree().paused \
			and bool(player.get("input_enabled")):
		var away := Vector2(player.global_position.x, player.global_position.z) - camp.fire_position
		if away.length() > loop_radius:
			_respawn_at_camp()
		return
	if not _in_dark or _looped:
		return
	_dark_time += delta
	var d := Vector2(player.global_position.x, player.global_position.z) - camp.fire_position
	if d.length() > loop_radius or _dark_time > loop_seconds:
		print("Prologue: looping back to camp")
		_looped = true
		_loop_back()


## Walked too far before the story allows it: back to camp, facing the stranger.
func _respawn_at_camp() -> void:
	_respawning = true
	_set_player_input(false)
	await _fade_to(1.0, fade_time)
	_place_player_by_log()
	camera.snap_to_target()
	await _fade_to(0.0, fade_time)
	_set_player_input(true)
	_respawning = false


func _unhandled_input(event: InputEvent) -> void:
	if not _waiting_for_talk or get_tree().paused or Cutscene.busy():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		if Interaction.is_best(camp.npc):
			_waiting_for_talk = false
			camp.npc.interactable_enabled = false
			_hint.modulate.a = 0.0
			get_viewport().set_input_as_handled()
			_stranger_scene()


func _loop_back() -> void:
	_set_player_input(false)
	await _fade_to(1.0, fade_time)
	_place_player_by_log()
	_set_camp_shown(true)
	camera.snap_to_target()
	atmosphere.set_fog(camp_density, dark_color)
	_in_dark = false
	await _fade_to(0.0, fade_time)
	await _stranger_scene()


func _place_player_by_log() -> void:
	var log_pos := camp.log_node.global_position
	var fire := Vector3(camp.fire_position.x, log_pos.y, camp.fire_position.y)
	var away := log_pos - fire
	away.y = 0.0
	away = away.normalized()
	var p := log_pos + away * 3.0
	p.y = camp.ground_height(Vector2(p.x, p.z), log_pos.y) + 0.3
	player.global_position = p
	player.rotation.y = atan2(-away.x, -away.z) # face the log
	player.set("velocity", Vector3.ZERO)
	player.set("_spawn_position", p)


func _stranger_scene() -> void:
	var npc := camp.npc
	Cutscene.begin()
	_set_player_input(false)
	npc.auto_talk = false
	npc.set_talking(true)
	await _dialogue.show_text(line_greeting)
	var pv := _path_view()
	await camera.fly_to(pv[0], pv[1], 2.2)
	await _dialogue.show_text(line_path)
	var sv := _sign_view()
	await camera.fly_to(sv[0], sv[1], 2.2)
	await _dialogue.show_text(line_sign)
	npc.set_talking(false)
	await camera.release(2.0)
	# He hands over the flashlight.
	if _flashlight:
		_flashlight.call("set_locked", false)
	if controls_hint:
		controls_hint.set_hint_visible("F", true)
	_show_hint("Press F to use the flashlight")
	_set_player_input(true)
	_waiting_for_sign = true
	Cutscene.finish()


## Camera spot and look-at point for staring down the path.
func _path_view() -> Array:
	var a := _route_point(path_view_distance)
	var b := _route_point(path_view_distance + path_look_ahead)
	return [Vector3(a.x, camp.ground_height(a, 0.0) + path_view_height, a.y),
			Vector3(b.x, camp.ground_height(b, 0.0) + path_look_height, b.y)]


## A point on the real (curving) main path, this far along from its start.
func _route_point(dist: float) -> Vector2:
	var route: PackedVector2Array = camp.path_generator.main_route
	if route.size() < 2:
		return camp.fire_position + camp.out_direction * dist
	var left := dist
	for i in route.size() - 1:
		var seg := route[i].distance_to(route[i + 1])
		if left <= seg and seg > 0.0:
			return route[i].lerp(route[i + 1], left / seg)
		left -= seg
	return route[route.size() - 1]


func _on_tent_looted(_items: Array) -> void:
	# The map: the minimap appears and its key reminder is added.
	_set_minimap_shown(true)
	if controls_hint:
		controls_hint.set_hint_visible("M", true)
	part_finished.emit()


## Camera spot (in front of the tent's entrance, which faces the fire) and look-at point.
func _tent_view() -> Array:
	var t := camp.tent.global_position
	var to_fire := Vector3(camp.fire_position.x - t.x, 0.0, camp.fire_position.y - t.z).normalized()
	var pos := t + to_fire * tent_view_distance
	pos.y = t.y + tent_view_height
	return [pos, t + Vector3.UP * tent_look_height]


func _set_minimap_shown(on: bool) -> void:
	if minimap == null:
		return
	_set_node_shown(minimap, on)
	minimap.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_DISABLED # it must keep running while the game is paused for the big map


## Camera spot and look-at point for facing the stranger (from the player's side).
func _npc_view() -> Array:
	var np := camp.npc.global_position
	var to_player := player.global_position - np
	to_player.y = 0.0
	to_player = to_player.normalized()
	var side := Vector3.UP.cross(to_player)
	var pos := np + to_player * npc_view_distance + side * 0.6
	pos.y = np.y + npc_view_height
	return [pos, np + Vector3.UP * npc_look_height]


## Camera spot (in front of the sign) and look-at point for reading it.
func _sign_view() -> Array:
	var sp := _sign.global_position
	var ground := camp.ground_height(Vector2(sp.x, sp.z), sp.y)
	var front := Vector3(-camp.out_direction.x, 0.0, -camp.out_direction.y)
	var look := Vector3(sp.x, ground + sign_look_height, sp.z)
	return [Vector3(sp.x, ground + sign_view_height, sp.z) + front * sign_view_distance, look]


func _place_first_sign() -> void:
	var out := camp.out_direction
	var right := Vector2(-out.y, out.x)
	var p := camp.fire_position + out * sign_distance + right * sign_side
	var pos := Vector3(p.x, camp.ground_height(p, 0.0), p.y)
	var away := Vector3(out.x, 0.0, out.y) # the sign faces back toward the fire
	sign_spawner.auto_spawn = false
	_sign = sign_spawner.spawn_at(pos, away, sign_feature)
	_set_node_shown(_sign, true)


# --- Called by StartSignFeature (inside the sign cutscene, game paused) ----------

func on_first_sign_message(cam: Camera3D) -> void:
	# The player is invisible now. Look down the path while the fog lifts.
	var from := cam.global_transform
	var pv := _path_view()
	var to := Transform3D(Basis.IDENTITY, pv[0]).looking_at(pv[1], Vector3.UP)
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(t: float): cam.global_transform = from.interpolate_with(to, t), 0.0, 1.0, 2.2)
	var d0 := atmosphere.get_fog_density()
	var d1 := atmosphere.fog_density
	var c0 := dark_color
	var c1 := atmosphere.fog_color
	# The forest appears hidden inside a thicker fog, then the fog slowly thins.
	var fw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fw.tween_method(func(t: float): atmosphere.set_fog(lerpf(d0, lift_peak_density, t), c0), 0.0, 1.0, 0.8)
	fw.tween_callback(func():
		_set_world_hidden(false)
		atmosphere.set_mist_visible(true)
	)
	fw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fw.tween_method(func(t: float): atmosphere.set_fog(lerpf(lift_peak_density, d1, t), c0.lerp(c1, t)), 0.0, 1.0, lift_time)
	await tw.finished
	await fw.finished
	await get_tree().create_timer(0.4).timeout


func on_first_sign_done() -> void:
	_leashed = false
	if _waiting_for_sign:
		_waiting_for_sign = false
		_after_sign()


func _after_sign() -> void:
	Cutscene.begin()
	_set_player_input(false)
	var npc := camp.npc
	npc.stand_up()
	npc.face(player.global_position)
	var nv := _npc_view()
	await camera.fly_to(nv[0], nv[1], 2.0)
	await get_tree().create_timer(0.5).timeout
	var choice := await _dialogue.ask(line_after, answers)
	print("Prologue: answered option ", choice)
	var tv := _tent_view()
	await camera.fly_to(tv[0], tv[1], 2.0)
	await get_tree().create_timer(0.4).timeout
	await _dialogue.show_text(line_tent)
	await camera.release(1.6)
	_set_player_input(true)
	Cutscene.finish()
	if camp.tent:
		camp.tent.interactable = true
		camp.tent.looted.connect(_on_tent_looted, CONNECT_ONE_SHOT)


# --- Helpers --------------------------------------------------------------------

func _set_player_input(on: bool) -> void:
	player.set("input_enabled", on)


func _set_world_hidden(hidden: bool) -> void:
	if scatter:
		scatter.set_enabled(not hidden)


func _set_camp_shown(shown: bool) -> void:
	for n in camp.spawned:
		_set_node_shown(n, shown)


## Shows/hides a node and switches its colliders off/on (remembering their layers).
func _set_node_shown(node: Node, shown: bool) -> void:
	if node == null:
		return
	if node is Node3D or node is CanvasLayer:
		node.set("visible", shown)
	var bodies: Array = node.find_children("*", "CollisionObject3D", true, false)
	if node is CollisionObject3D:
		bodies.append(node)
	for b in bodies:
		var body := b as CollisionObject3D
		if shown:
			if body.has_meta("saved_layer"):
				body.collision_layer = body.get_meta("saved_layer")
				body.remove_meta("saved_layer")
		elif not body.has_meta("saved_layer"):
			body.set_meta("saved_layer", body.collision_layer)
			body.collision_layer = 0


func _fade_to(alpha: float, time: float) -> void:
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_fade, "color:a", alpha, time)
	await tw.finished


func _show_hint(text: String) -> void:
	_hint.text = text
	var tw := create_tween()
	tw.tween_property(_hint, "modulate:a", 1.0, 0.5)
	tw.tween_interval(4.0)
	tw.tween_property(_hint, "modulate:a", 0.0, 1.0)
