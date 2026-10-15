class_name Rain
extends Node3D
## Light rain that follows the player. Particles + looping sound (SFX bus).

@export var stream: AudioStream
@export var amount := 500
@export var area := Vector2(24, 24)
@export var height := 10.0
@export var fall_speed := 13.0
@export var drop_length := 0.45
@export var drop_alpha := 0.22
@export var volume_db := -25.0
@export var fade_in := 4.0

var _player: Node3D


func _ready() -> void:
	_build_particles()
	_build_audio()


func _build_particles() -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = height / fall_speed + 0.3
	p.local_coords = false
	p.preprocess = p.lifetime # already raining when it starts
	p.custom_aabb = AABB(Vector3(-area.x, -height - 2.0, -area.y), Vector3(area.x * 2.0, height + 4.0, area.y * 2.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area.x * 0.5, 0.1, area.y * 0.5)
	pm.direction = Vector3(0.05, -1, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = fall_speed * 0.9
	pm.initial_velocity_max = fall_speed * 1.1
	pm.gravity = Vector3.ZERO
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, drop_length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.85, 1.0, drop_alpha)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)


func _build_audio() -> void:
	if stream == null:
		return
	var s := stream.duplicate()
	if "loop" in s:
		s.loop = true
	var a := AudioStreamPlayer.new()
	a.stream = s
	a.volume_db = -60.0
	if AudioServer.get_bus_index("SFX") >= 0:
		a.bus = &"SFX"
	add_child(a)
	a.play()
	create_tween().tween_property(a, "volume_db", volume_db, fade_in)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player:
		global_position = _player.global_position + Vector3.UP * height
