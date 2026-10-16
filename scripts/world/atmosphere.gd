@tool
extends Node3D
## Night atmosphere: dark sky and ambient light, moonlight, distance fog and
## cheap low mist (a few drifting see-through layers around the player).
## Everything is configured from the exports below. After changing one in the
## editor, press "Apply / Refresh" to preview it; the game applies it on start.
## (Volumetric fog and fog volumes aren't available in the Compatibility
## renderer, so the flashlight beam is a cone mesh and the mist is faked.)

@export_tool_button("Apply / Refresh", "Reload") var _refresh_button = apply

@export_group("Night")
@export var background_color := Color(0.01, 0.015, 0.03)
@export var ambient_color := Color(0.1, 0.13, 0.22)
@export_range(0.0, 2.0, 0.01) var ambient_energy := 0.5
@export_range(0.0, 2.0, 0.01) var saturation := 0.85

@export_group("Moon")
@export var moon_color := Color(0.6, 0.7, 1.0)
@export_range(0.0, 2.0, 0.01) var moon_energy := 0.3
@export var moon_rotation_degrees := Vector3(-55, 35, 0)
@export var moon_shadows := true

@export_group("Distance Fog")
@export var fog_enabled := true
@export var fog_color := Color(0.06, 0.08, 0.14)
## Higher = thicker haze, shorter view distance.
@export_range(0.0, 0.2, 0.001) var fog_density := 0.02

@export_group("Mist")
## Drifting layers of low mist around the player (game only).
@export var mist_enabled := true
@export var mist_color := Color(0.65, 0.72, 0.85)
## Opacity of each layer (they stack).
@export_range(0.0, 1.0, 0.01) var mist_opacity := 0.18
@export_range(1, 6) var mist_layers := 3
## Height of the top layer above the player's feet.
@export var mist_height := 1.6
## Width of the mist square that follows the player.
@export var mist_size := 140.0


func _ready() -> void:
	apply()


func apply() -> void:
	_apply_environment()
	_apply_moon()
	_apply_mist()


func _apply_environment() -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = saturation

	env.fog_enabled = fog_enabled
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.fog_sky_affect = 1.0
	we.environment = env


func _apply_moon() -> void:
	var moon := get_node_or_null("Moon") as DirectionalLight3D
	if moon == null:
		return
	moon.light_color = moon_color
	moon.light_energy = moon_energy
	moon.rotation_degrees = moon_rotation_degrees
	moon.shadow_enabled = moon_shadows
	moon.directional_shadow_max_distance = 60.0


func _apply_mist() -> void:
	var mist := get_node_or_null("GroundMist") as Node3D
	if mist == null:
		return
	# GroundMist isn't a tool script, so in the editor it's only a placeholder.
	if Engine.is_editor_hint():
		mist.visible = false
		return
	mist.visible = mist_enabled
	mist.set("color", mist_color)
	mist.set("opacity", mist_opacity)
	mist.set("layers", mist_layers)
	mist.set("height", mist_height)
	mist.set("size", mist_size)
	mist.call("rebuild")
