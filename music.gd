extends AudioStreamPlayer
## Background music: plays the track, waits a random gap, then plays it again.
## Gap lengths follow a normal (bell-curve) distribution around gap_mean.

@export_group("Gaps between plays")
## Average silence between plays, in seconds.
@export var gap_mean := 20.0
## Spread of the gaps. About 68% of gaps land within one standard deviation
## of the mean, and about 95% within two. Gaps never go below 0.
@export var gap_std_dev := 6.0
## Delay before the very first play, in seconds.
@export var start_delay := 0.0

## To slow the music down (and lower its pitch), use this node's Pitch Scale
## in the Inspector: below 1.0 is slower.
## The bus is set here in code because the editor can reset a bus it doesn't
## know about yet.
@export var music_bus: StringName = &"Music"

var _timer := Timer.new()


func _ready() -> void:
	bus = music_bus
	_timer.one_shot = true
	_timer.timeout.connect(play)
	add_child(_timer)
	finished.connect(_on_finished)
	if start_delay > 0.0:
		_timer.start(start_delay)
	else:
		play()


func _on_finished() -> void:
	_timer.start(maxf(randfn(gap_mean, gap_std_dev), 0.1))
