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
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func _set_paused(on: bool) -> void:
	get_tree().paused = on
	_root.visible = on
	if on:
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
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_add_slider(box, "Music", music_bus)
	_add_slider(box, "Sound Effects", sfx_bus)

	_resume_button = Button.new()
	_resume_button.text = "Resume"
	_resume_button.pressed.connect(_set_paused.bind(false))
	box.add_child(_resume_button)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func():
		_save_settings()
		get_tree().quit())
	box.add_child(quit)


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
