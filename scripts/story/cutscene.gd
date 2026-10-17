class_name Cutscene
extends RefCounted
## Tracks whether a cutscene or dialogue is running, so other interactions
## (reading a sign, talking to someone) stay off until it's over.

static var depth := 0


static func begin() -> void:
	depth += 1


static func finish() -> void:
	depth = maxi(depth - 1, 0)


static func busy() -> bool:
	return depth > 0


static func reset() -> void:
	depth = 0
