class_name ScatterEntry
extends Resource
## One scene the scatterer may place, plus how likely and how big it is.

@export var scene: PackedScene
## Relative chance of being picked (2.0 is twice as likely as 1.0).
@export_range(0.0, 100.0, 0.1, "or_greater") var weight := 1.0
## Footprint radius for the no-overlap check (unscaled).
## 0 = measure automatically from the scene's meshes.
@export var radius := 0.0
@export var min_scale := 1.0
@export var max_scale := 1.0

enum ColliderShape {
	## Thin pillar down the middle: for tree trunks.
	TRUNK,
	## Cylinder as wide as the whole footprint.
	CYLINDER,
	## The scene's bounding box.
	BOX,
	## Wraps the actual mesh: the best fit for rocks.
	CONVEX_HULL,
}

@export_group("Hard objects only")
## Generate a collider so the player can't walk through.
## Turn off if the scene already has its own collision.
@export var add_collider := true
@export var collider_shape := ColliderShape.TRUNK
## TRUNK / CYLINDER only. 0 = auto (TRUNK: 20% of the footprint, CYLINDER: the full footprint).
@export var collider_radius := 0.0
## TRUNK / CYLINDER only. 0 = auto (the scene's full height).
@export var collider_height := 0.0
