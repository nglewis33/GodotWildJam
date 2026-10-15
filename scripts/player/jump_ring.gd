class_name JumpRing
extends MeshInstance3D
## Ring at the player's feet that fills up while the jump cooldown runs.

@export var diameter := 0.2
@export_range(0.5, 0.98) var inner_ratio := 0.66 ## Inner radius / outer radius (higher = thinner ring).
@export var color := Color(0.85, 0.95, 1.0, 0.9)
@export var track_alpha := 0.15 ## Faint full circle behind the filling arc (0 = none).
@export var foot_offset := Vector3(-0.28, 0.12, 0.0) ## Local to the player; -X is the character's right foot.
@export var fade_time := 0.4 ## Fade-out after the ring completes.

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
uniform float progress = 0.0;
uniform float inner_ratio = 0.86;
uniform vec4 ring_color : source_color = vec4(1.0);
uniform float track_alpha = 0.15;
uniform float fade = 1.0;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	float aa = fwidth(r) * 1.5;
	float band = smoothstep(inner_ratio - aa, inner_ratio + aa, r) * (1.0 - smoothstep(1.0 - 2.0 * aa, 1.0, r));
	float t = fract(atan(p.x, -p.y) / TAU); // 0 at top, clockwise
	float arc = 1.0 - smoothstep(progress - 0.004, progress + 0.004, t);
	float a = band * mix(track_alpha, 1.0, arc) * ring_color.a * fade;
	ALBEDO = ring_color.rgb;
	ALPHA = a;
}
"""

var _mat: ShaderMaterial
var _fade := 0.0


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(diameter, diameter)
	mesh = quad
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = 10
	_mat.set_shader_parameter("inner_ratio", inner_ratio)
	_mat.set_shader_parameter("ring_color", color)
	_mat.set_shader_parameter("track_alpha", track_alpha)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position = foot_offset
	visible = false


func _process(delta: float) -> void:
	var p := get_parent()
	if not p.has_method("jump_cooldown_progress"):
		return
	var prog: float = p.jump_cooldown_progress()
	var active := prog < 1.0
	if active:
		_fade = 1.0
	else:
		_fade = maxf(_fade - delta / maxf(fade_time, 0.001), 0.0)
	visible = _fade > 0.0
	_mat.set_shader_parameter("progress", prog)
	_mat.set_shader_parameter("fade", _fade)
