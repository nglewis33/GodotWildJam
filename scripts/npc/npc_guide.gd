class_name NpcGuide
extends Node
## Makes the stranger walk the main path ahead of the player.
##  - Walks at the player's walking speed.
##  - Every `rest_check_interval` seconds of walking: `rest_chance` to rest on the path
##    (idle) for a random rest_min..rest_max seconds.
##  - At a fork he stops for `fork_think_time` seconds. Talk to him in that time to
##    tell him Left / Right / "take your time". If nobody tells him, he picks at random
##    when the time is up. A fork he takes is a dead end: at its end he turns around,
##    walks back and takes the other way at once.
##  - Pressing E on him while he moves or rests gets a short reply.

signal reached_end

enum Mode { APPROACH, WALK, REST, THINK, TALK, TURN_BACK, DONE }

@export var walk_animation := "Walk"
@export var idle_animation := "Idle"
## 0 = use the player's walking speed.
@export var speed := 0.0
@export var rest_check_interval := 25.0
@export_range(0.0, 1.0) var rest_chance := 0.45
@export var rest_min := 15.0
@export var rest_max := 30.0
@export var fork_think_time := 60.0
@export var talk_stop_time := 1.0
@export var turn_speed := 6.0
@export_multiline var line_moving := "I'll walk with haste, but may need to rest every so often"
@export_multiline var line_resting := "Just going to rest for a quick minute, ill begin moving again soon"
@export_multiline var line_fork := "There is a fork in the road, I'm taking my time to make a decision. Unless you already know which path is right.\nIf so, which way should I go?"
@export var fork_answers: Array[String] = ["Left", "Right", "I don't know, take your time"]

var npc: SittingNpc
var generator: PathGenerator
var player: Node3D

var _dialogue: DialogueBox
var _mode := Mode.APPROACH
var _lines: Array = [] # per polyline: {"pts", "cum", "len"}
var _forks_on: Array = [] # per polyline: Array of {"at_s", "index", "done"}
var _pl := 0
var _s := 0.0
var _dir := 1.0
var _stack: Array = [] # [polyline, junction distance] to return to
var _walk_clock := 0.0
var _timer := 0.0
var _think_left := 0.0
var _after_talk := Mode.WALK
var _pending_fork := -1 # fork index (0-based) he is thinking about
var _y := 0.0
var _approach_to := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func setup(npc_node: SittingNpc, path_gen: PathGenerator, player_node: Node3D) -> void:
	npc = npc_node
	generator = path_gen
	player = player_node


func _ready() -> void:
	_rng.randomize()
	_dialogue = DialogueBox.new()
	add_child(_dialogue)
	if npc == null or generator == null:
		push_warning("NpcGuide: needs an npc and a path generator.")
		set_process(false)
		return
	_build_lines()
	_y = npc.global_position.y
	# Start from the nearest point of the main route.
	var here := Vector2(npc.global_position.x, npc.global_position.z)
	_pl = 0
	_s = _nearest_s(0, here)
	_approach_to = _point_at(0, _s)
	_enter(Mode.APPROACH)
	npc.interactable_enabled = true
	npc.interacted.connect(_on_interacted)


# --- Path data ----------------------------------------------------------------------

func _build_lines() -> void:
	_lines.clear()
	_forks_on.clear()
	var all: Array = [generator.main_route]
	for f in generator.forks:
		all.append(f.pts)
	for pts in all:
		var cum := PackedFloat32Array()
		cum.resize(pts.size())
		for i in range(1, pts.size()):
			cum[i] = cum[i - 1] + pts[i].distance_to(pts[i - 1])
		_lines.append({"pts": pts, "cum": cum, "len": cum[pts.size() - 1]})
		_forks_on.append([])
	for i in generator.forks.size():
		var f: Dictionary = generator.forks[i]
		var parent: int = f.parent
		var cum: PackedFloat32Array = _lines[parent].cum
		_forks_on[parent].append({"at_s": cum[f.at], "fork": i, "done": false})


func _point_at(line: int, s: float) -> Vector2:
	var L: Dictionary = _lines[line]
	var pts: PackedVector2Array = L.pts
	var cum: PackedFloat32Array = L.cum
	s = clampf(s, 0.0, L.len)
	for i in range(1, pts.size()):
		if s <= cum[i]:
			var seg := cum[i] - cum[i - 1]
			return pts[i - 1].lerp(pts[i], (s - cum[i - 1]) / seg if seg > 0.0 else 0.0)
	return pts[pts.size() - 1]


func _nearest_s(line: int, p: Vector2) -> float:
	var L: Dictionary = _lines[line]
	var pts: PackedVector2Array = L.pts
	var best := 1e18
	var best_s := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			best_s = L.cum[i - 1] + ab.length() * t
	return best_s


# --- State machine ------------------------------------------------------------------

func _enter(m: Mode) -> void:
	_mode = m
	match m:
		Mode.WALK, Mode.APPROACH, Mode.TURN_BACK:
			npc.play_loop(walk_animation)
		_:
			npc.play_loop(idle_animation)


func _walk_speed() -> float:
	if speed > 0.0:
		return speed
	var v = player.get("move_speed") if player else null
	return float(v) if v != null else 1.5


func _process(delta: float) -> void:
	if npc == null:
		return
	if Cutscene.busy():
		return # the clocks stop while anyone is talking
	match _mode:
		Mode.APPROACH:
			_step_toward(_approach_to, delta)
			if _flat(npc.global_position).distance_to(_approach_to) < 0.2:
				_enter(Mode.WALK)
		Mode.WALK:
			_walk_clock += delta
			if _walk_clock >= rest_check_interval:
				_walk_clock = 0.0
				if _rng.randf() < rest_chance:
					_timer = _rng.randf_range(rest_min, rest_max)
					_enter(Mode.REST)
					return
			_advance(delta, 1.0)
		Mode.TURN_BACK:
			_advance(delta, -1.0)
		Mode.REST:
			_timer -= delta
			if _timer <= 0.0:
				_enter(Mode.WALK)
		Mode.THINK:
			_think_left -= delta
			if _think_left <= 0.0:
				_choose(_rng.randf() < 0.5)
		Mode.TALK:
			_timer -= delta
			if _timer <= 0.0:
				_enter(_after_talk)
	_stick_to_ground(delta)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _advance(delta: float, dir: float) -> void:
	var L: Dictionary = _lines[_pl]
	var step := _walk_speed() * delta
	if dir > 0.0:
		var target := _s + step
		# A fork he hasn't dealt with yet on the way out?
		for f in _forks_on[_pl]:
			if not f.done and f.at_s > _s - 0.001 and f.at_s <= target:
				_s = f.at_s
				_move_to(_point_at(_pl, _s), delta)
				_start_thinking(f)
				return
		_s = target
		if _s >= L.len:
			_s = L.len
			_move_to(_point_at(_pl, _s), delta)
			if _pl == 0:
				_mode = Mode.DONE
				npc.play_loop(idle_animation)
				reached_end.emit()
			else:
				_enter(Mode.TURN_BACK) # dead end: turn around
			return
	else:
		_s = maxf(_s - step, 0.0)
		if _s <= 0.0 and not _stack.is_empty():
			# Back at the junction: take the other way right now.
			_move_to(_point_at(_pl, 0.0), delta)
			var frame: Array = _stack.pop_back()
			_pl = frame[0]
			_s = frame[1]
			_enter(Mode.WALK)
			return
	_move_to(_point_at(_pl, _s), delta)


func _move_to(p: Vector2, delta: float) -> void:
	var cur := _flat(npc.global_position)
	var d := p - cur
	if d.length() > 0.001:
		var yaw := atan2(d.x, d.y)
		npc.rotation.y = lerp_angle(npc.rotation.y, yaw, clampf(turn_speed * delta, 0.0, 1.0))
	npc.global_position.x = p.x
	npc.global_position.z = p.y


func _step_toward(p: Vector2, delta: float) -> void:
	var cur := _flat(npc.global_position)
	var d := p - cur
	var step := _walk_speed() * delta
	_move_to(p if d.length() <= step else cur + d.normalized() * step, delta)


## Follows the terrain (the ground, or the bridge where the ground is missing).
func _stick_to_ground(delta: float) -> void:
	var space := npc.get_world_3d().direct_space_state
	var from := Vector3(npc.global_position.x, npc.global_position.y + 6.0, npc.global_position.z)
	var to := from + Vector3.DOWN * 40.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 << (GroundGrid.GROUND_ONLY_LAYER - 1))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		var q2 := PhysicsRayQueryParameters3D.create(from, to)
		if player is CollisionObject3D:
			q2.exclude = [(player as CollisionObject3D).get_rid()]
		hit = space.intersect_ray(q2)
	if not hit.is_empty():
		_y = lerpf(_y, hit.position.y, clampf(10.0 * delta, 0.0, 1.0))
	npc.global_position.y = _y


# --- Forks --------------------------------------------------------------------------

func _start_thinking(f: Dictionary) -> void:
	f.done = true
	_pending_fork = f.fork
	_think_left = fork_think_time
	_enter(Mode.THINK)


## take_fork: true = go down the fork, false = keep on along the current path.
func _choose(take_fork: bool) -> void:
	if take_fork:
		var idx := _pending_fork + 1 # polyline index of that fork
		_stack.append([_pl, _s])
		_pl = idx
		_s = 0.0
	_pending_fork = -1
	_enter(Mode.WALK)


## Is the fork on his left as he walks the current path?
func _fork_on_left() -> bool:
	var f: Dictionary = generator.forks[_pending_fork]
	var pts: PackedVector2Array = f.pts
	var out := (pts[mini(1, pts.size() - 1)] - pts[0]).normalized()
	var here := _point_at(_pl, _s)
	var ahead := _point_at(_pl, _s + 2.0)
	var d := (ahead - here).normalized()
	var left := Vector2(d.y, -d.x)
	return out.dot(left) > 0.0


# --- Talking to him -----------------------------------------------------------------

func _on_interacted() -> void:
	if _mode == Mode.DONE or _mode == Mode.TALK or Cutscene.busy():
		return
	match _mode:
		Mode.THINK:
			_talk_fork()
		Mode.REST:
			_talk_line(line_resting, Mode.REST)
		_:
			_talk_line(line_moving, _mode)


func _talk_line(text: String, resume: Mode) -> void:
	var saved := _timer # a rest in progress keeps its remaining time
	_after_talk = resume
	_enter(Mode.TALK)
	_timer = 1000000.0 # held until the dialogue closes
	await _dialogue.show_text(text)
	if resume == Mode.REST:
		_timer = saved
		_enter(Mode.REST)
	else:
		_timer = talk_stop_time # he stands still for a second, then carries on


func _talk_fork() -> void:
	_mode = Mode.TALK
	npc.play_loop(idle_animation)
	var answer := await _dialogue.ask(line_fork, fork_answers)
	if answer == 2 or answer < 0:
		_enter(Mode.THINK) # keeps whatever thinking time is left
		return
	var wants_left := answer == 0
	var fork_is_left := _fork_on_left()
	_choose(wants_left == fork_is_left)
