extends CanvasLayer
## Barebones pause menu. Esc pauses and resumes.
## Each volume slider's MIDDLE is the volume you set on that audio bus in the
## Audio panel. Left of the middle is quieter (down to silent), right of the
## middle is louder (up to max_boost_db). Choices are saved between runs.

@export var music_bus: StringName = &"Music"
@export var sfx_bus: StringName = &"SFX"
## How much louder than your default the far-right end of a slider is.
@export var max_boost_db := 10.0
@export var settings_path := "user://settings.cfg"

var _root: Control
var _main_center: Control
var _dev_center: Control
var _dev_status: Label
var _resume_button: Button
var _default_db := {}  # bus name -> volume (dB) set in the editor
var _sliders := {}  # bus name -> HSlider


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	for bus in [music_bus, sfx_bus]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			_default_db[bus] = AudioServer.get_bus_volume_db(idx)
	_build_ui()
	_load_settings()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		if _dev_center.visible: # Esc inside Dev Controls goes back one level
			_show_dev(false)
			get_viewport().set_input_as_handled()
			return
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	_root.visible = on
	if on:
		_show_dev(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_resume_button.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_save_settings()


# --- Volume ----------------------------------------------------------------

## Slider 0..1 -> dB relative to the default. 0.5 = no change.
func _slider_to_db(v: float) -> float:
	if v <= 0.5:
		return linear_to_db(maxf(v, 0.001) * 2.0)
	return (v - 0.5) * 2.0 * max_boost_db


func _apply(bus: StringName, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, _default_db.get(bus, 0.0) + _slider_to_db(v))


# --- Saving ----------------------------------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for bus in _sliders:
		_sliders[bus].value = cfg.get_value("audio", String(bus), 0.5)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for bus in _sliders:
		cfg.set_value("audio", String(bus), _sliders[bus].value)
	cfg.save(settings_path)


# --- UI (built in code to keep this barebones) -----------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var main := _make_panel("Paused")
	_main_center = main[0]
	var box: VBoxContainer = main[1]

	_add_slider(box, "Music", music_bus)
	_add_slider(box, "Sound Effects", sfx_bus)

	_resume_button = Button.new()
	_resume_button.text = "Resume"
	_resume_button.pressed.connect(_set_paused.bind(false))
	box.add_child(_resume_button)

	var dev := Button.new()
	dev.text = "Dev Controls"
	dev.pressed.connect(_show_dev.bind(true))
	box.add_child(dev)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func():
		_save_settings()
		get_tree().quit())
	box.add_child(quit)

	var devp := _make_panel("Dev Controls")
	_dev_center = devp[0]
	var dbox: VBoxContainer = devp[1]
	_dev_center.visible = false

	var to_ravine := Button.new()
	to_ravine.text = "Teleport to Ravine"
	to_ravine.pressed.connect(_teleport_to_ravine)
	dbox.add_child(to_ravine)

	var to_cam := Button.new()
	to_cam.text = "Teleport to Free Camera"
	to_cam.pressed.connect(_teleport_to_camera)
	dbox.add_child(to_cam)

	_dev_status = Label.new()
	_dev_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dev_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dev_status.modulate = Color(1, 1, 1, 0.75)
	dbox.add_child(_dev_status)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_show_dev.bind(false))
	dbox.add_child(back)


## A centered panel with a title; returns [the container to show/hide, the VBox to fill].
func _make_panel(title_text: String) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	return [center, box]


# --- Dev controls -----------------------------------------------------------

func _show_dev(on: bool) -> void:
	_main_center.visible = not on
	_dev_center.visible = on
	if on:
		_dev_status.text = ""
		(_dev_center.find_children("*", "Button", true, false)[0] as Button).grab_focus()
	else:
		_resume_button.grab_focus()


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _teleport(player: Node3D, pos: Vector3, yaw := NAN) -> void:
	player.global_position = pos
	if not is_nan(yaw):
		player.rotation.y = yaw
	if "velocity" in player:
		player.set("velocity", Vector3.ZERO)
	_set_paused(false)


func _teleport_to_ravine() -> void:
	var player := _player()
	var ravine := get_tree().get_first_node_in_group("ravine") as Ravine
	if player == null:
		_dev_status.text = "No player found."
		return
	if ravine == null:
		_dev_status.text = "There is no ravine in this scene."
		return
	var spot := ravine.get_teleport_spot()
	if spot.is_empty():
		_dev_status.text = "The ravine isn't ready (or couldn't be placed)."
		return
	_teleport(player, spot["position"], spot["yaw"])


func _teleport_to_camera() -> void:
	var player := _player()
	var cam := get_viewport().get_camera_3d()
	if player == null or cam == null:
		_dev_status.text = "No player or camera found."
		return
	if not ("free_mode" in cam) or not cam.get("free_mode"):
		_dev_status.text = "Turn on the free camera first (Q), fly somewhere, then pause."
		return
	var x := cam.global_position.x
	var z := cam.global_position.z
	var y := _floor_height(player, x, z)
	if is_nan(y):
		_dev_status.text = "There's no floor under the camera."
		return
	# Back to the normal camera so you can play from the new spot.
	if cam.has_method("set_free_mode"):
		cam.call("set_free_mode", false)
	_teleport(player, Vector3(x, y + 0.3, z))


## Height of the floor at (x, z): the bare ground first, then the ravine rim and
## bridge (the ground-only physics layer is 20, see GroundGrid). NAN if none.
func _floor_height(player: Node3D, x: float, z: float) -> float:
	var space := player.get_world_3d().direct_space_state
	var top := 1000.0
	for mask in [1 << 19, 1]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -top, z), mask)
		if player is CollisionObject3D:
			q.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return (hit.position as Vector3).y
	return NAN


func _add_slider(parent: Control, label_text: String, bus: StringName) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.5
	slider.custom_minimum_size = Vector2(0, 24)
	slider.value_changed.connect(func(v: float): _apply(bus, v))
	parent.add_child(slider)
	_sliders[bus] = slider
