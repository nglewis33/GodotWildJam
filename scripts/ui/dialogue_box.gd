class_name DialogueBox
extends CanvasLayer
## Bottom-centered typewriter text box. Runs while the tree is paused.

signal closed

@export var chars_per_second := 40.0
@export var fast_multiplier := 2.0
@export var font_size := 22

var _label: RichTextLabel
var _panel: PanelContainer
var _progress := 0.0
var _total := 0
var _active := false
var _choices: Array = []
var _choice_index := 0
var _choosing := false
var _picked := -1


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.15
	_panel.anchor_right = 0.85
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -190
	_panel.offset_bottom = -40
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.scroll_active = false
	_label.add_theme_color_override("default_color", Color.WHITE)
	_label.add_theme_font_size_override("normal_font_size", font_size)
	_panel.add_child(_label)
	add_child(_panel)
	visible = false


## Shows the prompt, then a list of options (W/S or Up/Down, Enter to pick).
## Returns the index of the chosen option.
func ask(prompt: String, options: Array) -> int:
	_choices = options
	_choice_index = 0
	_choosing = true
	_picked = -1
	_label.text = prompt
	_total = prompt.length()
	_progress = 0.0
	_label.visible_characters = 0
	_active = true
	visible = true
	await closed
	return _picked


func _choice_text() -> String:
	var lines := _label.text.split("\n\n")[0] + "\n\n"
	for i in _choices.size():
		lines += ("> " if i == _choice_index else "   ") + str(_choices[i]) + "\n"
	return lines


## Shows the text and returns when the player closes the box.
func show_text(text: String) -> void:
	_label.text = text
	_total = text.length()
	_progress = 0.0
	_label.visible_characters = 0
	_active = true
	visible = true
	await closed


func _process(delta: float) -> void:
	if not _active or _progress >= _total:
		return
	var speed := chars_per_second
	if Input.is_key_pressed(KEY_SPACE):
		speed *= fast_multiplier
	_progress = minf(_progress + speed * delta, _total)
	_label.visible_characters = int(_progress)
	if _choosing and _progress >= _total:
		_label.text = _choice_text()
		_label.visible_characters = -1


func _input(event: InputEvent) -> void:
	if not _active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if _choosing and _progress >= _total:
		if k == KEY_UP or k == KEY_W:
			_choice_index = (_choice_index - 1 + _choices.size()) % _choices.size()
			_label.text = _choice_text()
			get_viewport().set_input_as_handled()
			return
		if k == KEY_DOWN or k == KEY_S:
			_choice_index = (_choice_index + 1) % _choices.size()
			_label.text = _choice_text()
			get_viewport().set_input_as_handled()
			return
	var is_enter := k == KEY_ENTER or k == KEY_KP_ENTER
	var is_esc := k == KEY_ESCAPE
	if not (is_enter or is_esc):
		return
	get_viewport().set_input_as_handled() # keeps Esc from toggling the pause menu
	if _progress < _total:
		if is_enter:
			_progress = _total
			if _choosing:
				_label.text = _choice_text()
			_label.visible_characters = -1
		return
	if _choosing:
		if not is_enter:
			return
		_picked = _choice_index
		_choosing = false
	_active = false
	visible = false
	closed.emit()
