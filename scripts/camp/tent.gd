class_name Tent
extends CampProp
## A tent you can search with E. It holds items (its "inventory"); searching
## hands them all to the player's Inventory and fires `looted`. Scatter these
## around the forest with different `items`.

signal looted(items: Array)

## Item ids inside (shown capitalized, e.g. "map" -> "Map").
@export var items: Array[String] = ["map"]
@export var interact_distance := 3.5
## Shown in the prompt: "Press E to interact with <name>".
@export var display_name := "Tent"
## Story code can switch this off until the tent is allowed to be searched.
var interactable := true

var _prompt: Label
var _toast: Label


func _ready() -> void:
	super._ready()
	add_to_group("tent")
	add_to_group("interactable")
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_prompt = _make_label(layer, 60, "Press E to interact")
	_toast = _make_label(layer, 100, "")
	_prompt.modulate.a = 0.0
	_toast.modulate.a = 0.0


func _make_label(layer: CanvasLayer, top: float, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.offset_top = top
	l.offset_left = -250
	l.offset_right = 250
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 22)
	layer.add_child(l)
	return l


func has_items() -> bool:
	return not items.is_empty()


func _player_near() -> Node3D:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return null
	var d := p.global_position - global_position
	d.y = 0.0
	return p if d.length() <= interact_distance else null


## For Interaction: enabled and in range (the facing test happens there).
func interact_ready() -> bool:
	return interactable and has_items() and _player_near() != null


func interact_position() -> Vector3:
	return global_position


func _can_interact() -> bool:
	return Interaction.is_best(self)


func _process(_delta: float) -> void:
	if _prompt:
		var show := _can_interact()
		if show:
			_prompt.text = "Press E to interact with %s" % display_name
		_prompt.modulate.a = 1.0 if show else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_E and _can_interact():
		get_viewport().set_input_as_handled()
		search()


## Hands everything inside to the player.
func search() -> void:
	var player := _player_near()
	if player == null or not has_items():
		return
	var taken := items.duplicate()
	items.clear()
	var inv := Inventory.of(player)
	var names := []
	for id in taken:
		inv.add(id)
		names.append(String(id).capitalize())
	_show_toast("Took: " + ", ".join(names))
	get_tree().call_group("minimap", "add_marker", global_position, "tent")
	looted.emit(taken)


func _show_toast(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.3)
	tw.tween_interval(2.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)
