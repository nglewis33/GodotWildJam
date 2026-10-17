class_name DialogueBox
extends CanvasLayer
## Bottom-centered typewriter text box. Shows three lines at a time; when a page
## is finished a white arrow with "E" appears, and E scrolls the text up so the
## last line becomes the first, then types the next two. Runs while paused.

signal closed
signal _advance
signal _page_typed

enum Mode { IDLE, TYPING, WAIT, SCROLLING, CHOOSING }

@export var chars_per_second := 40.0
## Hold Space to type faster.
@export var fast_multiplier := 2.0
@export var font_size := 22
@export var visible_lines := 3
@export var scroll_time := 0.3

var _panel: PanelContainer
var _clip: Control
var _label: RichTextLabel
var _arrow_row: HBoxContainer
var _arrow: Control
var _mode := Mode.IDLE
var _progress := 0.0
var _total := 0
var _target := 0
var _line_count := 0
var _line_starts := PackedInt32Array()
var _choices: Array = []
var _choice_index := 0
var _t := 0.0


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.15
	_panel.anchor_right = 0.85
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -40
	_panel.offset_bottom = -40
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.custom_minimum_size = Vector2(0, font_size * 1.5 * visible_lines)
	box.add_child(_clip)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label.add_theme_color_override("default_color", Color.WHITE)
	_label.add_theme_font_size_override("normal_font_size", font_size)
	_clip.add_child(_label)
	# Bottom row: white down-pointing triangle with "E" next to it.
	_arrow_row = HBoxContainer.new()
	_arrow_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_arrow_row.add_theme_constant_override("separation", 8)
	_arrow = Control.new()
	_arrow.custom_minimum_size = Vector2(16, 18)
	_arrow.draw.connect(func():
		_arrow.draw_colored_polygon(PackedVector2Array([
			Vector2(1, 4), Vector2(15, 4), Vector2(8, 15)]), Color.WHITE))
	_arrow_row.add_child(_arrow)
	var e := Label.new()
	e.text = "E"
	e.add_theme_font_size_override("font_size", 18)
	e.add_theme_color_override("font_color", Color.WHITE)
	_arrow_row.add_child(e)
	_arrow_row.modulate.a = 0.0
	box.add_child(_arrow_row)
	add_child(_panel)
	visible = false


## Shows the text, page by page, and returns when the player closes the box.
func show_text(text: String) -> void:
	await _present(text)
	_close()


## Shows the prompt, then a list of options (W/S or Up/Down, E or Enter to pick).
## Returns the index of the chosen option.
func ask(prompt: String, options: Array) -> int:
	await _present(prompt)
	_choices = options
	_choice_index = 0
	_mode = Mode.CHOOSING
	_arrow_row.modulate.a = 0.0
	_label.position.y = 0.0
	_label.text = _choice_text()
	_label.visible_characters = -1
	await _advance
	_close()
	return _choice_index


func _choice_text() -> String:
	var lines := ""
	for i in _choices.size():
		lines += ("> " if i == _choice_index else "   ") + str(_choices[i]) + "\n"
	return lines.strip_edges(false, true)


func _present(text: String) -> void:
	_label.text = text
	_label.visible_characters = 0
	_label.position.y = 0.0
	_arrow_row.modulate.a = 0.0
	_progress = 0.0
	_total = text.length()
	_mode = Mode.IDLE
	visible = true
	# Let the layout settle so line breaks can be measured.
	await get_tree().process_frame
	await get_tree().process_frame
	_measure()
	var page_last := visible_lines - 1
	while true:
		var last_line := mini(page_last, _line_count - 1)
		_target = _line_end(last_line)
		if _progress < _target:
			_mode = Mode.TYPING
			await _page_typed
		_mode = Mode.WAIT
		if last_line >= _line_count - 1:
			await _advance
			break
		await _advance
		_mode = Mode.SCROLLING
		_arrow_row.modulate.a = 0.0
		await _scroll_to_line(last_line)
		page_last = last_line + (visible_lines - 1)
	_arrow_row.modulate.a = 0.0


func _close() -> void:
	_mode = Mode.IDLE
	visible = false
	closed.emit()


func _measure() -> void:
	_line_count = maxi(_label.get_line_count(), 1)
	_line_starts = PackedInt32Array()
	_line_starts.resize(_line_count)
	var seen := -1
	for c in _total:
		var l := clampi(_label.get_character_line(c), 0, _line_count - 1)
		while seen < l:
			seen += 1
			_line_starts[seen] = c
	while seen < _line_count - 1:
		seen += 1
		_line_starts[seen] = _total
	var lh := font_size * 1.5
	if _line_count > 1:
		lh = _label.get_line_offset(1) - _label.get_line_offset(0)
	_clip.custom_minimum_size.y = lh * visible_lines + 4.0


func _line_end(line: int) -> int:
	return _line_starts[line + 1] if line + 1 < _line_count else _total


func _scroll_to_line(line: int) -> void:
	var y := _label.get_line_offset(line)
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_label, "position:y", -y, scroll_time)
	await tw.finished


func _process(delta: float) -> void:
	_t += delta
	if _mode == Mode.WAIT:
		_arrow_row.modulate.a = 0.65 + 0.35 * sin(_t * 5.0)
	if _mode != Mode.TYPING:
		return
	var speed := chars_per_second
	if Input.is_key_pressed(KEY_SPACE):
		speed *= fast_multiplier
	_progress = minf(_progress + speed * delta, _target)
	_label.visible_characters = int(_progress)
	if _progress >= _target:
		_label.visible_characters = _target
		_mode = Mode.WAIT
		_page_typed.emit()


func _input(event: InputEvent) -> void:
	if _mode == Mode.IDLE or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k == KEY_ESCAPE:
		get_viewport().set_input_as_handled() # keeps Esc from toggling the pause menu
		return
	var is_e: bool = event.physical_keycode == KEY_E
	if _mode == Mode.WAIT and is_e:
		get_viewport().set_input_as_handled()
		_advance.emit()
	elif _mode == Mode.CHOOSING:
		if k == KEY_UP or k == KEY_W:
			_choice_index = (_choice_index - 1 + _choices.size()) % _choices.size()
			_label.text = _choice_text()
			get_viewport().set_input_as_handled()
		elif k == KEY_DOWN or k == KEY_S:
			_choice_index = (_choice_index + 1) % _choices.size()
			_label.text = _choice_text()
			get_viewport().set_input_as_handled()
		elif is_e or k == KEY_ENTER or k == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_advance.emit()
