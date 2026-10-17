class_name InteractPrompt
extends CanvasLayer
## One line of text at the top of the screen ("Press E to ...").

var _label: Label


func _init() -> void:
	layer = 20
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.offset_top = 60
	_label.offset_left = -300
	_label.offset_right = 300
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.modulate.a = 0.0
	add_child(_label)


func show_prompt(text: String, on: bool) -> void:
	if on:
		_label.text = text
	_label.modulate.a = 1.0 if on else 0.0
