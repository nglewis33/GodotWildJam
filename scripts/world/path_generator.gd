class_name PathGenerator
extends Node3D
## Procedurally "paints" a dirt path onto the ground: a big start circle in the
## middle of a quadrant, a main path to an end point in the opposite quadrant, and dead-end forks.
## The path is drawn into a mask texture and projected onto the ground with a
## Decal, so it follows hills and forks look natural. Scatter can query
## distance_to_path() to keep trees, rocks and grass off the path.
## Don't rotate or scale this node.

@export var ground_grid: GroundGrid

@export_group("Path")
enum Quadrant { RANDOM, NW, NE, SW, SE }
## The start circle sits in the middle of this quadrant; the end is in the opposite one.
@export var start_quadrant := Quadrant.RANDOM
## 0 = end just inside the near corner (map center) of the opposite quadrant,
## 100 = at the far corner of the map. Both keep a start-circle-sized buffer.
@export_range(0.0, 100.0, 0.1) var end_distance := 50.0
## Random offset (+/- per axis, world units) added to the end point.
@export var end_noise := 2.0
@export var path_width := 3.0
## 0 = nearly straight, 1 = winding.
@export_range(0.0, 1.0, 0.01) var curviness := 0.5

@export_group("Checkpoints")
## The main path visits this many checkpoints (in order) between start and end.
## They are placed in any quadrant except the start's (several can share one). 0 = go straight to the end.
@export var checkpoint_count := 3
## Minimum distance between the start, every checkpoint and the end.
@export var checkpoint_spacing := 200.0
## Different parts of the path (that aren't neighbors) stay at least this far apart,
## so you can't see another stretch of path from the one you're on.
@export var leg_clearance := 60.0
## The earlier parts of the path stay at least this far from the end point.
@export var end_clearance := 130.0
## Biggest allowed bend at a checkpoint (0 = straight on, 180 = doubling back).
@export_range(0.0, 180.0, 1.0) var max_turn_degrees := 100.0
## Keep checkpoints this far inside the map edge.
@export var checkpoint_margin := 40.0
## Curvy layouts tested before settling for the best one found.
@export var layout_attempts := 20

@export_group("Forks")
@export var fork_count := 4
## Average length of a fork before it dead-ends.
@export var fork_length := 25.0
## Spread of fork lengths as a fraction of the average (standard deviation).
@export_range(0.0, 1.0, 0.01) var fork_length_variation := 0.3
@export_range(0.2, 1.0, 0.01) var fork_width_scale := 0.75
## Allow forks to branch off other forks, not just the main path.
@export var branch_from_forks := true

@export_group("Circles")
@export var start_radius := 6.0
@export var end_radius := 4.0

@export_group("Look")
@export var path_color := Color(0.30, 0.20, 0.11, 1.0)
@export var edge_softness := 1.0
## Wobble of the path edge, in world units.
@export var edge_roughness := 0.5
## Mask texture size (longest side). Higher = sharper edges, slower to generate.
@export var texture_size := 1024
## Vertical size of the projection box (must cover the ground's hills).
@export var decal_height := 16.0

@export_group("Generation")
## 0 = a new random path every run.
@export var seed_value := 0
@export var generate_on_ready := true

const PAINT_LAYER := 1 << 19 ## Visual layer 20: ground meshes only, so trees/player stay clean.
const HASH_CELL := 10.0
const QUERY_RANGE := 8.0 ## distance_to_path() is exact within this distance.
const STEP := 2.0
const MAX_LAYOUT_TRIES := 600 ## Random checkpoint sets screened per generate().

signal generated

var start_position := Vector2.ZERO
var checkpoints: Array[Vector2] = []
var end_position := Vector2.ZERO
var _segments: Array = [] # [Vector2 a, Vector2 b, float radius]
var _hash := {}
var _rng := RandomNumberGenerator.new()
var _bounds := Rect2()
var _decal: Decal
var _noise := FastNoiseLite.new()


func _ready() -> void:
	if generate_on_ready:
		generate()


func clear() -> void:
	_segments.clear()
	_hash.clear()
	if is_instance_valid(_decal):
		_decal.queue_free()
	_decal = null


## Distance from a world XZ point to the edge of the path (negative inside).
## Only exact within QUERY_RANGE; farther away returns a large number.
func distance_to_path(p: Vector2) -> float:
	var best := 1e9
	for s in _hash.get(_cell(p), []):
		best = minf(best, _dist_seg(p, s[0], s[1]) - s[2])
	return best


## Path pieces as [Vector2 a, Vector2 b, float radius]. a == b means a circle.
func get_segments() -> Array:
	return _segments


func get_end_position() -> Vector3:
	var y := ground_grid.global_position.y
	return Vector3(end_position.x, y, end_position.y)


func generate() -> void:
	clear()
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_noise.seed = _rng.randi()
	_noise.frequency = 0.35

	if ground_grid == null:
		push_warning("PathGenerator: assign a ground_grid.")
		return
	var c := ground_grid.get_map_center()
	var center := Vector2(c.x, c.z)
	var size := ground_grid.get_map_size()
	var ground_y := ground_grid.global_position.y
	if size.x <= 0.0 or size.y <= 0.0:
		push_warning("PathGenerator: map size is zero (is the ground generated?).")
		return
	_bounds = Rect2(center - size * 0.5, size)
	var inner := _bounds.grow(-(path_width + maxf(start_radius, end_radius)))

	# Start in the middle of a quadrant; end in the opposite one.
	var sq := _pick_quadrant()
	var s := Vector2(1.0 if sq.x == 1 else -1.0, 1.0 if sq.y == 1 else -1.0)
	start_position = _clamp_to(inner, center + s * size * 0.25)
	end_position = _pick_end(center, size, -s, inner)

	var main_pts := _plan_route(center, size, inner)
	var polylines: Array = [{"pts": main_pts, "width": path_width}]
	var origins: Array[Vector2] = []
	for i in fork_count:
		var f := _make_fork(polylines, origins, inner)
		if not f.is_empty():
			polylines.append(f)

	for pl in polylines:
		var pts: PackedVector2Array = pl.pts
		for i in pts.size() - 1:
			_segments.append([pts[i], pts[i + 1], pl.width * 0.5])
	_segments.append([start_position, start_position, start_radius])
	_segments.append([end_position, end_position, end_radius])
	_build_hash()

	_make_decal(center, size, ground_y)
	_mark_ground()
	print("PathGenerator: start %s, end %s, %d checkpoints, %d forks." % [start_position, end_position, checkpoints.size(), polylines.size() - 1])
	generated.emit()


# --- Layout -----------------------------------------------------------------

func _pick_quadrant() -> Vector2i:
	match start_quadrant:
		Quadrant.NW: return Vector2i(0, 0)
		Quadrant.NE: return Vector2i(1, 0)
		Quadrant.SW: return Vector2i(0, 1)
		Quadrant.SE: return Vector2i(1, 1)
	return Vector2i(_rng.randi() % 2, _rng.randi() % 2)


## dir = (+/-1, +/-1) pointing from the map center into the end quadrant.
func _pick_end(center: Vector2, size: Vector2, dir: Vector2, inner: Rect2) -> Vector2:
	var buffer := Vector2(start_radius, start_radius)
	var near := center + dir * buffer
	var far := center + dir * (size * 0.5 - buffer)
	var p := near.lerp(far, clampf(end_distance / 100.0, 0.0, 1.0))
	p += Vector2(_rng.randf_range(-end_noise, end_noise), _rng.randf_range(-end_noise, end_noise))
	return _clamp_to(inner, p)


## Builds the main path: start -> checkpoints -> end. Random checkpoint layouts
## are first screened with cheap straight-line checks; the survivors are turned
## into curvy paths and kept only if those stay clear of each other too.
func _plan_route(center: Vector2, size: Vector2, inner: Rect2) -> PackedVector2Array:
	checkpoints.clear()
	if checkpoint_count <= 0:
		return _leg_points(start_position, end_position, inner)
	var start_q := _quadrant_of(start_position, center)
	var area := inner.grow(-checkpoint_margin)
	var best_pts := PackedVector2Array()
	var best_cps: Array[Vector2] = []
	var best_v := INF
	var curved_tries := 0
	var fallback: Array[Vector2] = []
	for k in MAX_LAYOUT_TRIES:
		var cps := _random_checkpoints(area, center, start_q)
		if cps.size() < checkpoint_count:
			continue
		fallback = cps.duplicate()
		for s in 8: # a few visiting orders per set of checkpoints
			_shuffle(cps)
			var wp: Array[Vector2] = [start_position]
			wp.append_array(cps)
			wp.append(end_position)
			if not _straight_ok(wp):
				continue
			var built := _build_route(wp, inner)
			var v := _route_violation(built[0], built[1], wp)
			curved_tries += 1
			if v < best_v:
				best_v = v
				best_pts = built[0]
				best_cps = cps.duplicate()
			if v == 0.0 or curved_tries >= layout_attempts:
				break
		if best_v == 0.0 or curved_tries >= layout_attempts:
			break
	if best_pts.is_empty(): # nothing passed the screening; use any layout
		push_warning("PathGenerator: no checkpoint layout met the spacing/clearance settings (map too small for them?). Using a best-effort layout.")
		var wp: Array[Vector2] = [start_position]
		wp.append_array(fallback)
		wp.append(end_position)
		best_pts = _build_route(wp, inner)[0]
		best_cps = fallback
	elif best_v > 0.0:
		push_warning("PathGenerator: the path comes closer to itself than leg_clearance in places. Using the best layout found.")
	checkpoints = best_cps
	return best_pts


## Returns [PackedVector2Array points, Array[int] waypoint indices into points].
func _build_route(wp: Array[Vector2], inner: Rect2) -> Array:
	var pts := PackedVector2Array()
	var widx: Array[int] = []
	for i in wp.size() - 1:
		var leg := _leg_points(wp[i], wp[i + 1], inner)
		widx.append(pts.size())
		if i > 0:
			leg = leg.slice(1)
		pts.append_array(leg)
	widx.append(pts.size() - 1)
	return [pts, widx]


func _shuffle(a: Array[Vector2]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp


func _quadrant_of(p: Vector2, center: Vector2) -> Vector2i:
	return Vector2i(1 if p.x >= center.x else 0, 1 if p.y >= center.y else 0)


## Checkpoints can be anywhere outside the start quadrant (several may share one).
func _random_checkpoints(area: Rect2, center: Vector2, start_q: Vector2i) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in checkpoint_count:
		for t in 20:
			var p := Vector2(_rng.randf_range(area.position.x, area.end.x),
					_rng.randf_range(area.position.y, area.end.y))
			if _quadrant_of(p, center) == start_q:
				continue
			if _checkpoint_ok(p, out):
				out.append(p)
				break
	return out


func _seg_dist(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(
			a.distance_to(Geometry2D.get_closest_point_to_segment(a, c, d)),
			b.distance_to(Geometry2D.get_closest_point_to_segment(b, c, d))),
			minf(c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)),
			d.distance_to(Geometry2D.get_closest_point_to_segment(d, a, b))))


## Cheap screening on the straight lines between waypoints, with some extra room
## for the path to wander.
func _straight_ok(wp: Array[Vector2]) -> bool:
	var extra := 60.0 * curviness
	for i in range(1, wp.size() - 1):
		var a := wp[i] - wp[i - 1]
		var b := wp[i + 1] - wp[i]
		if absf(rad_to_deg(a.angle_to(b))) > max_turn_degrees:
			return false
	var legs := wp.size() - 1
	for i in legs:
		if i < legs - 1:
			var near := Geometry2D.get_closest_point_to_segment(end_position, wp[i], wp[i + 1])
			if near.distance_to(end_position) < end_clearance + extra:
				return false
		for j in range(i + 2, legs):
			if _seg_dist(wp[i], wp[i + 1], wp[j], wp[j + 1]) < leg_clearance + extra:
				return false
	return true


func _checkpoint_ok(p: Vector2, placed: Array[Vector2]) -> bool:
	if p.distance_to(start_position) < checkpoint_spacing or p.distance_to(end_position) < checkpoint_spacing:
		return false
	for o in placed:
		if p.distance_to(o) < checkpoint_spacing:
			return false
	return true


## 0 when the route is fine; otherwise bigger = worse.
func _route_violation(pts: PackedVector2Array, widx: Array[int], wp: Array[Vector2]) -> float:
	var v := 0.0
	# Bends at checkpoints.
	for i in range(1, wp.size() - 1):
		var a := wp[i] - wp[i - 1]
		var b := wp[i + 1] - wp[i]
		if a.length() > 0.001 and b.length() > 0.001:
			var turn := rad_to_deg(a.angle_to(b))
			turn = absf(turn)
			if turn > max_turn_degrees:
				v += (turn - max_turn_degrees) * 2.0
	# Distance walked along the route at each point, and which leg it belongs to.
	var n := pts.size()
	var cum := PackedFloat32Array()
	cum.resize(n)
	var leg_of := PackedInt32Array()
	leg_of.resize(n)
	var legs := wp.size() - 1
	var k := 0
	for i in n:
		if i > 0:
			cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
		while k < legs - 1 and i >= widx[k + 1]:
			k += 1
		leg_of[i] = k
	var step := 3
	for i in range(0, n, step):
		# Earlier legs must stay away from the end.
		if leg_of[i] < legs - 1:
			var de := pts[i].distance_to(end_position)
			if de < end_clearance:
				v += end_clearance - de
		for j in range(i + step, n, step):
			var dl := leg_of[j] - leg_of[i]
			if dl == 0:
				continue
			var d := pts[i].distance_to(pts[j])
			if d >= leg_clearance:
				continue
			if dl >= 2:
				v += leg_clearance - d
			else:
				# Neighboring legs may converge near their shared checkpoint only.
				var w := widx[leg_of[j]]
				if (cum[w] - cum[i]) + (cum[j] - cum[w]) > 3.0 * leg_clearance:
					v += leg_clearance - d
	return v


## One curvy stretch of path from a to b (both ends exact).
func _leg_points(a: Vector2, b: Vector2, inner: Rect2) -> PackedVector2Array:
	var total := a.distance_to(b)
	var dir := (b - a).normalized()
	var perp := dir.orthogonal()
	var steps := maxi(2, ceili(total / STEP))
	var amp := total * 0.15 * curviness
	var phase := _rng.randf() * 1000.0
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		var off := _noise_1d(t * total * 0.07 + phase) * 2.0 * amp * sin(PI * t)
		pts.append(_clamp_to(inner, a + dir * (total * t) + perp * off))
	pts[0] = a
	pts[steps] = b
	return pts


func _noise_1d(x: float) -> float:
	return _noise.get_noise_2d(x, 0.5) * 2.0


func _make_fork(polylines: Array, origins: Array[Vector2], inner: Rect2) -> Dictionary:
	var candidates := []
	for pi in polylines.size():
		if pi > 0 and not branch_from_forks:
			break
		var pts: PackedVector2Array = polylines[pi].pts
		for i in range(1, pts.size() - 1):
			candidates.append([pi, i])
	var spacing := maxf(path_width * 3.0, 8.0)
	for attempt in 40:
		if candidates.is_empty():
			return {}
		var c: Array = candidates[_rng.randi() % candidates.size()]
		var pts: PackedVector2Array = polylines[c[0]].pts
		var origin: Vector2 = pts[c[1]]
		if origin.distance_to(end_position) < end_clearance:
			continue
		if origin.distance_to(start_position) < start_radius * 0.8:
			continue
		var ok := true
		for o in origins:
			if origin.distance_to(o) < spacing:
				ok = false
				break
		if not ok:
			continue
		origins.append(origin)
		var tangent := (pts[c[1] + 1] - pts[c[1] - 1]).angle()
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var heading := tangent + side * deg_to_rad(_rng.randf_range(35.0, 80.0))
		var length := maxf(_rng.randfn(fork_length, fork_length * fork_length_variation), 6.0)
		var turn := 0.05 + 0.35 * curviness
		var out := PackedVector2Array([origin])
		var pos := origin
		var steps := maxi(2, ceili(length / STEP))
		for s in steps:
			heading += _rng.randf_range(-turn, turn)
			var nxt := pos + Vector2.from_angle(heading) * STEP
			if not inner.has_point(nxt) or nxt.distance_to(end_position) < end_clearance:
				break
			if c[0] == 0 and _near_other_leg(polylines[0].pts, c[1], nxt):
				break
			pos = nxt
			out.append(pos)
		if out.size() < 3:
			continue
		return {"pts": out, "width": path_width * fork_width_scale}
	return {}


## True if p is close to a stretch of the main path far (along the path) from index `from`.
func _near_other_leg(main: PackedVector2Array, from: int, p: Vector2) -> bool:
	var skip := ceili(leg_clearance * 1.5 / STEP)
	var lim := leg_clearance * 0.5
	for j in main.size():
		if absi(j - from) > skip and main[j].distance_squared_to(p) < lim * lim:
			return true
	return false


func _clamp_to(r: Rect2, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


# --- Spatial hash -------------------------------------------------------------

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / HASH_CELL), floori(p.y / HASH_CELL))


func _build_hash() -> void:
	for s in _segments:
		var pad: float = s[2] + QUERY_RANGE
		var lo := Vector2(minf(s[0].x, s[1].x), minf(s[0].y, s[1].y)) - Vector2(pad, pad)
		var hi := Vector2(maxf(s[0].x, s[1].x), maxf(s[0].y, s[1].y)) + Vector2(pad, pad)
		var c0 := _cell(lo)
		var c1 := _cell(hi)
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var k := Vector2i(x, y)
				if not _hash.has(k):
					_hash[k] = []
				_hash[k].append(s)


func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- Painting -----------------------------------------------------------------

func _make_decal(center: Vector2, size: Vector2, ground_y: float) -> void:
	var mpp := maxf(size.x, size.y) / float(maxi(texture_size, 64))
	var w := maxi(ceili(size.x / mpp), 1)
	var h := maxi(ceili(size.y / mpp), 1)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(path_color.r, path_color.g, path_color.b, 0.0))
	var origin := center - size * 0.5

	for s in _segments:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var r: float = s[2]
		var pad := r + edge_softness + edge_roughness + mpp
		var x0 := clampi(floori((minf(a.x, b.x) - pad - origin.x) / mpp), 0, w - 1)
		var x1 := clampi(ceili((maxf(a.x, b.x) + pad - origin.x) / mpp), 0, w - 1)
		var y0 := clampi(floori((minf(a.y, b.y) - pad - origin.y) / mpp), 0, h - 1)
		var y1 := clampi(ceili((maxf(a.y, b.y) + pad - origin.y) / mpp), 0, h - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var wp := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * mpp
				var d := _dist_seg(wp, a, b) - r + _noise.get_noise_2d(wp.x, wp.y) * edge_roughness
				var cov := 1.0 - smoothstep(-edge_softness * 0.5, edge_softness * 0.5, d)
				if cov <= 0.0:
					continue
				if cov > img.get_pixel(x, y).a:
					img.set_pixel(x, y, Color(path_color.r, path_color.g, path_color.b, cov))
	img.generate_mipmaps()

	_decal = Decal.new()
	_decal.texture_albedo = ImageTexture.create_from_image(img)
	_decal.size = Vector3(w * mpp, decal_height, h * mpp)
	_decal.cull_mask = PAINT_LAYER
	_decal.upper_fade = 0.01
	_decal.lower_fade = 0.01
	_decal.modulate = Color(1, 1, 1, path_color.a)
	add_child(_decal)
	_decal.global_position = Vector3(origin.x + w * mpp * 0.5, ground_y + decal_height * 0.25, origin.y + h * mpp * 0.5)


## Puts the ground meshes on the paint layer so only they receive the decal.
func _mark_ground() -> void:
	if ground_grid == null:
		return
	for n in ground_grid.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers |= PAINT_LAYER
