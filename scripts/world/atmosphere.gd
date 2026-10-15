@tool
extends Node3D
## Night atmosphere: dark sky and ambient light, moonlight, distance fog,
## volumetric fog (shows light beams) and low ground fog.
## Everything is configured from the exports below. After changing one in the
## editor, press "Apply / Refresh" to preview it; the game applies it on start.
## Volumetric fog and ground fog need the Forward+ renderer.

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

@export_group("Volumetric Fog")
## Lets fog catch light (flashlight and moon beams). Also required for ground fog.
@export var volumetric_enabled := true
@export_range(0.0, 0.2, 0.001) var volumetric_density := 0.02
@export var volumetric_color := Color(0.55, 0.65, 0.8)
## Higher = fog glows more when looking toward a light.
@export_range(-0.9, 0.9, 0.01) var volumetric_anisotropy := 0.4
## How far from the camera volumetric fog extends.
@export var volumetric_length := 40.0

@export_group("Ground Fog")
@export var ground_fog_enabled := true
## If set, the fog covers the whole map (in game).
@export var ground_grid: GroundGrid
## Fog area when no ground_grid is set (and in the editor preview).
@export var ground_fog_size := Vector2(60, 60)
## How tall the fog layer is. It is densest at the bottom and fades upward.
@export var ground_fog_height := 2.5
## Raise or lower the layer to sit on the terrain.
@export var ground_fog_base_offset := 0.0
@export_range(0.0, 4.0, 0.01) var ground_fog_density := 0.5
@export var ground_fog_color := Color(0.65, 0.72, 0.85)
## 0 = even density; higher = fog hugs the ground more tightly.
@export_range(0.0, 8.0, 0.01) var ground_fog_falloff := 1.5


func _ready() -> void:
	apply()


func apply() -> void:
	_apply_environment()
	_apply_moon()
	_apply_ground_fog()


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

	env.volumetric_fog_enabled = volumetric_enabled
	env.volumetric_fog_density = volumetric_density
	env.volumetric_fog_albedo = volumetric_color
	env.volumetric_fog_anisotropy = volumetric_anisotropy
	env.volumetric_fog_length = volumetric_length
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


func _apply_ground_fog() -> void:
	var fog := get_node_or_null("GroundFog") as FogVolume
	if fog == null:
		return
	fog.visible = ground_fog_enabled

	var area := ground_fog_size
	var center := global_position
	# In the editor a non-tool script like GroundGrid is only a placeholder,
	# so the map size is read in game only.
	if ground_grid and not Engine.is_editor_hint():
		var map_size := ground_grid.get_map_size()
		if map_size.x > 0.0 and map_size.y > 0.0:
			area = map_size
			var c := ground_grid.get_map_center()
			center = Vector3(c.x, ground_grid.global_position.y, c.z)

	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.size = Vector3(area.x, ground_fog_height, area.y)
	fog.global_position = Vector3(
		center.x,
		center.y + ground_fog_base_offset + ground_fog_height * 0.5,
		center.z)

	var mat := FogMaterial.new()
	mat.density = ground_fog_density
	mat.albedo = ground_fog_color
	mat.height_falloff = ground_fog_falloff
	fog.material = mat
