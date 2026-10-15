class_name Campfire
extends CampProp
## Campfire: plays the model's built-in flame animation, adds a warm crackling
## light and a few drifting embers.

@export_group("Fire")
@export var fire_animation := "" ## Empty = first animation found.
@export var animation_speed := 1.0
@export var light_color := Color(1.0, 0.55, 0.22)
@export var light_energy := 2.5
@export var light_range := 9.0
@export var light_height := 0.5
@export_range(0.0, 1.0) var flicker_amount := 0.25
@export var flicker_speed := 6.0
## Chance per second of a sudden "pop" of brightness.
@export var crackle_rate := 1.5
@export var embers := true

var _light: OmniLight3D
var _noise := FastNoiseLite.new()
var _t := 0.0
var _pop := 0.0


func _ready() -> void:
	super._ready()
	_noise.seed = randi()
	_noise.frequency = 1.0
	_start_animation()
	_build_light()
	if embers:
		_build_embers()


func _start_animation() -> void:
	if model == null:
		return
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	var clip := fire_animation
	if clip == "":
		for a in ap.get_animation_list():
			if a != "RESET":
				clip = a
				break
	if clip == "" or not ap.has_animation(clip):
		return
	ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	ap.speed_scale = animation_speed
	ap.play(clip)


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.omni_range = light_range
	_light.position = Vector3(0, light_height, 0)
	add_child(_light)


func _process(delta: float) -> void:
	if _light == null:
		return
	_t += delta
	if randf() < crackle_rate * delta:
		_pop = randf_range(0.4, 0.9)
	_pop = maxf(_pop - delta * 5.0, 0.0)
	var f := 1.0 + _noise.get_noise_1d(_t * flicker_speed) * flicker_amount * 2.0 + _pop
	_light.light_energy = light_energy * f


func _build_embers() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.3, 0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7, 0.25, 1.0))
	grad.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp

	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	quad.material = mat

	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.6
	p.process_material = pm
	p.draw_pass_1 = quad
	p.position = Vector3(0, light_height * 0.5, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
