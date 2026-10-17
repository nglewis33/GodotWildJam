class_name SittingNpc
extends Node3D
## An NPC that sits and idles, and now and then "talks". Uses the same
## character model (and animation library) as the player.

@export var idle_animation := "Sitting_Idle"
@export var talk_animation := "Sitting_Talking"
@export var blend := 0.3
## Shown in the prompt: "Press E to interact with <name>".
@export var display_name := "Stranger"
## When standing up he steps this far forward (away from the log).
@export var stand_forward := 0.45
@export var auto_talk := true
@export var idle_time_min := 4.0
@export var idle_time_max := 10.0
@export var talk_time_min := 3.0
@export var talk_time_max := 8.0

var _ap: AnimationPlayer
var _talking := false
var _timer := 0.0


func _ready() -> void:
	add_to_group("npc")
	_ap = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _ap == null:
		push_warning("SittingNpc: no AnimationPlayer found under the Model.")
		return
	for clip in [idle_animation, talk_animation]:
		if _ap.has_animation(clip):
			_ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		else:
			push_warning("SittingNpc: animation '%s' not found." % clip)
	set_talking(false)


## Gets up from the log: stops the sitting animations and stands idle.
func stand_up(stand_animation := "Idle") -> void:
	auto_talk = false
	if stand_forward > 0.0:
		var to := global_position + global_transform.basis.z * stand_forward
		create_tween().tween_property(self, "global_position", to, 0.5)
	if _ap and _ap.has_animation(stand_animation):
		_ap.get_animation(stand_animation).loop_mode = Animation.LOOP_LINEAR
		_ap.play(stand_animation, blend)


## Turns to face a point (yaw only).
func face(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		rotation.y = atan2(d.x, d.z)


## Switches between the idle and talking animations (also usable from dialogue).
func set_talking(value: bool) -> void:
	_talking = value
	if _ap == null:
		return
	var clip := talk_animation if value else idle_animation
	if _ap.has_animation(clip):
		_ap.play(clip, blend)
	_timer = randf_range(talk_time_min, talk_time_max) if value else randf_range(idle_time_min, idle_time_max)


func _process(delta: float) -> void:
	if not auto_talk or _ap == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		set_talking(not _talking)
