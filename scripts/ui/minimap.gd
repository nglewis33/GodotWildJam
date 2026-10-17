class_name Minimap
extends CanvasLayer
## Minimalist quadrant minimap. The map is split into NW/NE/SW/SE quadrants;
## the small map shows the quadrant the player is in (north is up).
## M opens a large centered map (game pauses) where WASD / arrows switch
## quadrant; M or Esc closes it. N toggles reveal_all while testing.

@export var ground_grid: GroundGrid
@export var path_generator: PathGenerator
## If set, the ravine is drawn as a line.
@export var ravine: Ravine

@export_group("Discovery")
## true: the whole path is visible. false: only path near where you've walked.
@export var reveal_all := false
## Path within this distance of the player (world units) becomes discovered.
@export var discover_radius := 12.0

@export_group("Look")
@export var mini_size := Vector2(128, 128)
@export var margin := Vector2(24, 24)
## Fraction of the screen's shorter side used by the expanded map.
@export_range(0.3, 0.95, 0.01) var expanded_fraction := 0.8
@export var background := Color(0, 0, 0, 0.6)
@export var grid_color := Color(1, 1, 1, 0.12)
@export var path_color := Color(1, 1, 1, 0.95)
@export var line_width := 1.5 ## Doubles-ish in the expanded map (x1.7).
@export var ravine_color := Color(1.0, 0.85, 0.1, 0.95)
@export var player_color := Color(1.0, 0.85, 0.2)
@export var npc_color := Color(0.4, 0.8, 1.0)

const QUAD_NAMES := ["NW", "NE", "SW", "SE"]

var _view: Control
var _backdrop: ColorRect
var _hint: Label
var _expanded := false
var _view_q := Vector2i.ZERO
var _pieces: Array = [] # [Vector2 a, Vector2 b, float r, bool discovered]
var _timer := 0.0
var _ravine_seen := false
var _origin := Vector2.ZERO
var _k := Vector2.ONE


func _ready() -> void:
	layer = 39
	process_mode = Node.PROCESS_MODE_ALWAYS

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.55)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.visible = false
	add_child(_backdrop)

	_view = Control.new()
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_on_draw)
	add_child(_view)

	_hint = Label.new()
	_hint.text = "WASD: look around    M / Esc: close    N: toggle reveal-all (testing)"
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.modulate = Color(1, 1, 1, 0.8)
	_hint.visible = false
	add_child(_hint)

	if path_generator:
		path_generator.generated.connect(_rebuild)
		_rebuild()
	else:
		push_warning("Minimap: no path_generator assigned.")
	if ground_grid == null:
		push_warning("Minimap: no ground_grid assigned.")


func _rebuild() -> void:
	_pieces.clear()
	for s in path_generator.get_segments():
		_pieces.append([s[0], s[1], s[2], false])
	_update_discovery()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = event.physical_keycode
	if key == KEY_N:
		reveal_all = not reveal_all
		return
	if key == KEY_M:
		if _expanded:
			_set_expanded(false)
		elif not get_tree().paused: # don't open over the pause menu / dialogue
			_set_expanded(true)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not _expanded:
		return
	var handled := true
	match key:
		KEY_ESCAPE: _set_expanded(false)
		KEY_W, KEY_UP: _view_q.y = 0
		KEY_S, KEY_DOWN: _view_q.y = 1
		KEY_A, KEY_LEFT: _view_q.x = 0
		KEY_D, KEY_RIGHT: _view_q.x = 1
		_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _set_expanded(on: bool) -> void:
	_expanded = on
	if on:
		_view_q = _player_quadrant()
	get_tree().paused = on
	_backdrop.visible = on
	_hint.visible = on


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		_update_discovery()

	var vp := get_viewport().get_visible_rect().size
	if _expanded:
		var s := minf(vp.x, vp.y) * expanded_fraction
		_view.size = Vector2(s, s)
		_view.position = (vp - _view.size) * 0.5
		var hs := _hint.get_minimum_size()
		_hint.position = Vector2((vp.x - hs.x) * 0.5, _view.position.y + s + 10.0)
	else:
		_view.size = mini_size
		_view.position = margin
	_view.queue_redraw()


func _update_discovery() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	for piece in _pieces:
		if piece[3]:
			continue
		if _dist_seg(p, piece[0], piece[1]) - piece[2] < discover_radius:
			piece[3] = true
	# The ravine shows up once you get near it.
	if ravine and not _ravine_seen and ravine.blocks(p, discover_radius * 3.0):
		_ravine_seen = true


func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


# --- Quadrants ------------------------------------------------------------------

func _player_quadrant() -> Vector2i:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or ground_grid == null:
		return Vector2i.ZERO
	var c := ground_grid.get_map_center()
	return Vector2i(1 if player.global_position.x >= c.x else 0,
			1 if player.global_position.z >= c.z else 0)


func _w2m(p: Vector2) -> Vector2:
	return (p - _origin) * _k


# --- Drawing --------------------------------------------------------------------

func _on_draw() -> void:
	if ground_grid == null:
		return
	var sz := _view.size
	var q := _view_q if _expanded else _player_quadrant()
	var map_size := ground_grid.get_map_size()
	var c3 := ground_grid.get_map_center()
	var quad := map_size * 0.5
	_origin = Vector2(c3.x, c3.z) - quad + Vector2(q.x * quad.x, q.y * quad.y)
	_k = Vector2(sz.x / quad.x, sz.y / quad.y)
	var big := 1.7 if _expanded else 1.0

	_view.draw_rect(Rect2(Vector2.ZERO, sz), background)

	# Grid: one cell per ground tile.
	var tiles := Vector2(ground_grid.grid_size) * 0.5
	for i in range(1, int(ceil(tiles.x))):
		var x := sz.x * i / tiles.x
		_view.draw_line(Vector2(x, 0), Vector2(x, sz.y), grid_color, 1.0)
	for i in range(1, int(ceil(tiles.y))):
		var y := sz.y * i / tiles.y
		_view.draw_line(Vector2(0, y), Vector2(sz.x, y), grid_color, 1.0)

	# Ravine (yellow line).
	if ravine and (reveal_all or _ravine_seen):
		var line := ravine.get_center_line()
		if line.size() == 2:
			_view.draw_line(_w2m(line[0]), _w2m(line[1]), ravine_color, line_width * 2.0 * big, true)

	# Path.
	for piece in _pieces:
		if not (reveal_all or piece[3]):
			continue
		var a := _w2m(piece[0])
		if piece[0] == piece[1]:
			_view.draw_circle(a, maxf(piece[2] * _k.x, 2.0), path_color)
		else:
			_view.draw_line(a, _w2m(piece[1]), path_color, line_width * big, true)

	# NPCs.
	for n in get_tree().get_nodes_in_group("npc"):
		if n is Node3D:
			_view.draw_circle(_w2m(Vector2(n.global_position.x, n.global_position.z)),
					2.5 * big, npc_color)

	# Player (arrow pointing the way they face; model faces +Z).
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var pp := _w2m(Vector2(player.global_position.x, player.global_position.z))
		var f := Vector2(player.global_transform.basis.z.x, player.global_transform.basis.z.z)
		f = f.normalized() if f.length() > 0.01 else Vector2.UP
		var s := 4.0 * big
		_view.draw_colored_polygon(PackedVector2Array([
				pp + f * s * 1.3,
				pp - f * s * 0.8 + f.orthogonal() * s * 0.8,
				pp - f * s * 0.8 - f.orthogonal() * s * 0.8]), player_color)

	# Frame, quadrant name and "map continues" arrows.
	_view.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.35), false, 1.0)
	if _expanded:
		_view.draw_string(ThemeDB.fallback_font, Vector2(10, 22), QUAD_NAMES[q.y * 2 + q.x],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.8))
	var t := 4.0 * big
	var m := 3.0
	var mid := sz * 0.5
	var w := Color.WHITE
	if q.y == 1: # more map to the north
		_view.draw_colored_polygon(PackedVector2Array([Vector2(mid.x, m), Vector2(mid.x - t, m + t), Vector2(mid.x + t, m + t)]), w)
	if q.y == 0: # south
		_view.draw_colored_polygon(PackedVector2Array([Vector2(mid.x, sz.y - m), Vector2(mid.x - t, sz.y - m - t), Vector2(mid.x + t, sz.y - m - t)]), w)
	if q.x == 1: # west
		_view.draw_colored_polygon(PackedVector2Array([Vector2(m, mid.y), Vector2(m + t, mid.y - t), Vector2(m + t, mid.y + t)]), w)
	if q.x == 0: # east
		_view.draw_colored_polygon(PackedVector2Array([Vector2(sz.x - m, mid.y), Vector2(sz.x - m - t, mid.y - t), Vector2(sz.x - m - t, mid.y + t)]), w)
