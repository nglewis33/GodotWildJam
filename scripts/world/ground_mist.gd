class_name GroundMist
extends Node3D
## Cheap stand-in for ground fog (fog volumes need Forward+): a few large
## see-through planes of drifting noise that follow the player at knee height.
## The noise is anchored to the world, so the mist doesn't move with the player.

@export var color := Color(0.65, 0.72, 0.85)
@export_range(0.0, 1.0, 0.01) var opacity := 0.18
@export_range(1, 6) var layers := 3
@export var height := 1.6
@export var size := 140.0
## Size of the mist patches (higher = smaller patches).
@export var patch_scale := 0.025
## How fast the mist drifts, in noise units per second.
@export var drift := Vector2(0.006, 0.003)

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 mist_color : source_color = vec4(1.0);
uniform float opacity = 0.2;
uniform float patch_scale = 0.025;
uniform vec2 drift = vec2(0.006, 0.003);
uniform vec2 offset = vec2(0.0);
uniform float radius = 70.0;
varying vec3 wpos;
varying float rdist;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rdist = length(VERTEX.xz);
}
void fragment() {
	vec2 uv = wpos.xz * patch_scale + offset + drift * TIME;
	float n = texture(noise_tex, uv).r * 0.65 + texture(noise_tex, uv * 2.3 - drift * TIME * 1.7).r * 0.35;
	float m = smoothstep(0.38, 0.75, n);
	float edge = 1.0 - smoothstep(radius * 0.5, radius, rdist);
	ALBEDO = mist_color.rgb;
	ALPHA = m * edge * opacity;
}
"""

var _meshes: Array[MeshInstance3D] = []
var _noise_tex: ImageTexture


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.queue_free()
	_meshes.clear()
	if _noise_tex == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		noise.seed = 7
		noise.fractal_octaves = 3
		_noise_tex = ImageTexture.create_from_image(noise.get_seamless_image(256, 256))
	var shader := Shader.new()
	shader.code = SHADER
	for i in layers:
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(size, size)
		mi.mesh = plane
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.render_priority = -1 - i
		mat.set_shader_parameter("noise_tex", _noise_tex)
		mat.set_shader_parameter("mist_color", color)
		mat.set_shader_parameter("opacity", opacity)
		mat.set_shader_parameter("patch_scale", patch_scale * (1.0 + 0.15 * i))
		mat.set_shader_parameter("drift", drift * (1.0 + 0.4 * i) * (1.0 if i % 2 == 0 else -1.0))
		mat.set_shader_parameter("offset", Vector2(0.37 * i, 0.61 * i))
		mat.set_shader_parameter("radius", size * 0.5)
		mi.material_override = mat
		add_child(mi)
		_meshes.append(mi)
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	if player == null:
		return
	var base := player.global_position
	for i in _meshes.size():
		var t := float(i + 1) / _meshes.size()
		_meshes[i].global_position = Vector3(base.x, base.y + 0.1 + height * t, base.z)
