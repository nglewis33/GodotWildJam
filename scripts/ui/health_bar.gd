class_name HealthBar
extends CanvasLayer
## Heart in the top-right corner. FilledHeart is revealed from the bottom up
## under OuterHeart. Fades to 50% when health hasn't changed for a while.

@export var filled_texture: Texture2D = preload("res://assets/ui/FilledHeart.png")
@export var outer_texture: Texture2D = preload("res://assets/ui/OuterHeart.png")
@export var heart_height := 110.0
@export var margin := Vector2(24, 24)
@export_range(0.0, 1.0) var active_opacity := 0.5 ## Opacity right after a health change.
@export_range(0.5, 1.0) var fill_scale := 0.95 ## Size of the red heart relative to the outline.
@export var idle_time := 5.0
@export_range(0.0, 1.0) var idle_opacity := 0.2
@export var fade_speed := 2.0 ## Opacity change per second.

var _health: Health
var _holder: Control
var _clipper: Control
var _filled: TextureRect
var _idle := 0.0
var _alpha := 0.5
var _size := Vector2.ZERO


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var aspect := float(filled_texture.get_width()) / float(filled_texture.get_height())
	var size := Vector2(heart_height * aspect, heart_height)
	_size = size
	_holder = Control.new()
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_holder.offset_left = -(size.x + margin.x)
	_holder.offset_right = -margin.x
	_holder.offset_top = margin.y
	_holder.offset_bottom = margin.y + size.y
	add_child(_holder)

	_clipper = Control.new()
	_clipper.clip_contents = true
	_clipper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_clipper)

	_filled = _make_rect(filled_texture, size * fill_scale)
	_clipper.add_child(_filled)
	_holder.add_child(_make_rect(outer_texture, size)) # on top

	_health = get_parent().get_node_or_null("Health") as Health
	if _health:
		_health.changed.connect(_on_changed)
		_update(_health.current, _health.max_health)
	else:
		push_warning("HealthBar: no Health node on parent")


func _make_rect(tex: Texture2D, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = Vector2.ZERO
	r.size = size
	return r


func _on_changed(current: float, maximum: float) -> void:
	_idle = 0.0
	_update(current, maximum)


func _update(current: float, maximum: float) -> void:
	var ratio := clampf(current / maximum, 0.0, 1.0)
	var h := _holder.size.y if _holder.size.y > 0.0 else heart_height
	var shown := h * ratio
	# Clip window = bottom `ratio` of the heart; the texture is offset back up so it stays aligned.
	_clipper.position = Vector2(0, h - shown)
	_clipper.size = Vector2(_holder.size.x, shown)
	# Red heart is shrunk and centered in the outline; shift it into the clipper's coordinates.
	_filled.position = Vector2(_size.x * (1.0 - fill_scale) * 0.5, h * (1.0 - fill_scale) * 0.5 - (h - shown))


func _process(delta: float) -> void:
	_idle += delta
	var target := active_opacity if _idle < idle_time else idle_opacity
	_alpha = move_toward(_alpha, target, fade_speed * delta)
	_holder.modulate.a = _alpha
