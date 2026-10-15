class_name AmbienceEntry
extends Resource
## One background sound the ambience manager may play.

@export var stream: AudioStream
## Relative chance of being picked (2.0 is twice as likely as 1.0).
@export_range(0.0, 100.0, 0.1, "or_greater") var weight := 1.0
@export_range(-60.0, 12.0, 0.1) var volume_db := 0.0
