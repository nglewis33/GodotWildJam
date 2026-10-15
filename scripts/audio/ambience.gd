extends Node
## Random background ambience. Every check_interval seconds there is a
## play_chance (1 in 3 by default) that one sound plays, picked by weight.
## Add sounds in the list below and set each one's weight.

@export var sounds: Array[AmbienceEntry] = []
## Seconds between checks.
@export var check_interval := 7.0
## Chance (0 to 1) that a check plays a sound.
@export_range(0.0, 1.0, 0.01) var play_chance := 1.0 / 3.0
## A check is skipped while this many ambience sounds are already playing,
## so long clips don't pile up. Raise it to allow overlap.
@export var max_simultaneous := 1
## Extra volume for everything this node plays.
@export_range(-60.0, 12.0, 0.1) var master_volume_db := 0.0
@export var bus: StringName = &"SFX"
## Roll the first check immediately instead of waiting one interval.
@export var check_on_start := false

var _timer := Timer.new()
var _active := 0


func _ready() -> void:
	_timer.wait_time = check_interval
	_timer.timeout.connect(_check)
	add_child(_timer)
	_timer.start()
	if check_on_start:
		_check()


func _check() -> void:
	if randf() >= play_chance or _active >= max_simultaneous:
		return
	var entry := _pick()
	if entry:
		_play(entry)


func _pick() -> AmbienceEntry:
	var valid := sounds.filter(func(e): return e != null and e.stream != null and e.weight > 0.0)
	if valid.is_empty():
		return null
	var total := 0.0
	for e in valid:
		total += e.weight
	var roll := randf() * total
	for e in valid:
		roll -= e.weight
		if roll <= 0.0:
			return e
	return valid.back()


func _play(entry: AmbienceEntry) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = entry.stream
	player.volume_db = entry.volume_db + master_volume_db
	player.bus = bus
	add_child(player)
	_active += 1
	player.finished.connect(func():
		_active -= 1
		player.queue_free())
	player.play()
