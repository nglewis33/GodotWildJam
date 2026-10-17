class_name ControlsHint
extends CanvasLayer
## Faint key reminders laid across the bottom of the screen.

@export_range(0.0, 1.0) var opacity := 0.4
@export var font_size := 16
@export var bottom_margin := 8.0
@export var hints: Array[String] = [
	"W - Move forward", "Mouse - Turn", "F - Flashlight", "E - Interact",
	"Space - Jump", "Shift - Sprint", "M - Map",
]


## Keys (the text before " - ") that start hidden; reveal with set_hint_visible().
@export var hidden_at_start: Array[String] = []

var _labels := {}


## Shows or hides one reminder by its key, e.g. "F" or "M".
func set_hint_visible(key: String, on: bool) -> void:
	if _labels.has(key):
		(_labels[key] as Label).visible = on


func _ready() -> void:
	layer = 10
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_top = -(font_size + 12 + bottom_margin)
	row.offset_bottom = -bottom_margin
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.modulate.a = opacity
	for h in hints:
		var l := Label.new()
		l.text = h
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		row.add_child(l)
		var key := h.split(" - ")[0]
		_labels[key] = l
		l.visible = not hidden_at_start.has(key)
	add_child(row)
