extends AudioStreamPlayer
## Footstep sounds synced to the walk animation's foot contacts.
##
## The long footstep recording holds 12 different steps back to back. Each
## time a foot lands in the walk animation, one of the 12 is picked at random
## (never the same one twice in a row), played from its own slice of the
## clip, with a slight random pitch and volume change around this node's own
## Volume Db and Pitch Scale (set those in the Inspector).

## Where each of the 12 steps ends in the clip, in seconds. Step 1 starts at 0.
@export var step_ends := PackedFloat32Array([
	0.58, 1.12, 1.69, 2.23, 2.87, 3.35, 4.08, 4.63, 5.26, 5.88, 6.47, 6.912])
## Seconds from the start of each slice to the actual footfall (the first
## loud moment). Skipping this lead-in keeps the thud on the beat.
@export var step_hit_offsets := PackedFloat32Array([
	0.025, 0.02, 0.07, 0.05, 0.095, 0.015, 0.0, 0.04, 0.08, 0.095, 0.025, 0.055])

## Set in code because the editor can reset a bus it doesn't know about yet.
@export var sfx_bus: StringName = &"SFX"

@export_group("Sync")
## Times in the walk animation (seconds) when a foot lands.
@export var contact_times := PackedFloat32Array([0.13, 0.69])
## Nudge all footsteps later (+) or earlier (-) in seconds if they feel off.
@export var sync_offset := 0.0

@export_group("Variation")
## Random pitch change, +/- this fraction (0.04 = up to 4% higher or lower).
@export_range(0.0, 0.3, 0.005) var pitch_variation := 0.04
@export_range(0.0, 6.0, 0.1) var volume_variation_db := 1.5

var _character: Node
var _last_anim := ""
var _last_pos := 0.0
var _last_step := -1
var _stop_timer := Timer.new()
var _base_pitch := 1.0
var _base_volume_db := 0.0


func _ready() -> void:
	_character = get_parent()
	bus = sfx_bus
	# Remember the Inspector values; each step varies around them.
	_base_pitch = pitch_scale
	_base_volume_db = volume_db
	_stop_timer.one_shot = true
	_stop_timer.timeout.connect(stop)
	add_child(_stop_timer)


func _process(_delta: float) -> void:
	var anim: AnimationPlayer = _character.get("anim")
	if anim == null or not anim.is_playing() \
			or anim.current_animation != _character.get("anim_walk"):
		_last_anim = ""
		return

	var pos := anim.current_animation_position
	var length := anim.current_animation_length
	if anim.current_animation != _last_anim:
		# Walk just started; don't count where we begin as a crossing.
		_last_anim = anim.current_animation
		_last_pos = pos
		return

	for contact in contact_times:
		var t := fposmod(contact + sync_offset, length)
		var crossed := false
		if pos >= _last_pos:
			crossed = _last_pos < t and t <= pos
		else:  # the loop wrapped around
			crossed = t > _last_pos or t <= pos
		if crossed:
			_play_step()
	_last_pos = pos


func _play_step() -> void:
	var n := step_ends.size()
	if stream == null or n == 0:
		return

	var idx := randi() % n
	if n > 1:
		while idx == _last_step:
			idx = randi() % n
	_last_step = idx

	var slice_start := 0.0 if idx == 0 else step_ends[idx - 1]
	var from := slice_start
	if idx < step_hit_offsets.size():
		from += maxf(step_hit_offsets[idx] - 0.01, 0.0)

	pitch_scale = _base_pitch * (1.0 + randf_range(-pitch_variation, pitch_variation))
	volume_db = _base_volume_db + randf_range(-volume_variation_db, volume_variation_db)
	play(from)
	# Cut off at the end of this step's slice so the next step's sound never leaks in.
	_stop_timer.start(maxf((step_ends[idx] - from) / pitch_scale, 0.05))
