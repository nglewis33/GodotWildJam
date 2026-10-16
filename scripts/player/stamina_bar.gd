class_name StaminaBar
extends MeshInstance3D
## Small green bar just below the jump ring (same width as the ring). Only
## shows while stamina is changing, then fades out.

@export_range(0.5, 4.0, 0.05) var width_ratio := 2.0 ## Bar width as a multiple of the ring's diameter.
@export_range(0.01, 0.5, 0.01) var height_ratio := 0.14 ## Bar height as a fraction of the ring's diameter.
@export_range(0.0, 0.5, 0.01) var gap_ratio := 0.15 ## Gap under the ring, as a fraction of the ring's diameter.
@export var color := Color(0.25, 0.9, 0.35, 0.6)
@export_range(0.0, 1.0, 0.01) var track_alpha := 0.35 ## Opacity of the empty part, relative to the bar.
@export var hold_time := 0.3 ## Stays visible this long after stamina stops changing.
@export var fade_time := 0.4
@export_group("Exhausted flash")
## While refilling after running out, the bar pulses between these opacities.
@export_range(0.0, 1.0, 0.01) var flash_low := 0.15
@export var flash_speed := 2.0 ## Pulses per second.

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
uniform float y_shift = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.y -= y_shift; // down on the screen
}
uniform float progress = 1.0;
uniform vec4 bar_color : source_color = vec4(1.0);
uniform float track_alpha = 0.35;
uniform float fade = 1.0;
uniform float flash = 1.0;
void fragment() {
	float fill = step(UV.x, progress);
	ALBEDO = mix(vec3(0.03), bar_color.rgb, fill);
	ALPHA = mix(track_alpha, 1.0, fill) * bar_color.a * fade * flash;
}
"""

var _mat: ShaderMaterial
var _prev := 1.0
var _since_change := 99.0
var _fade := 0.0
var _time := 0.0


func _ready() -> void:
	var ring_d := 0.2
	var offset := Vector3(-0.28, 0.12, 0.0)
	for sibling in get_parent().get_children():
		if sibling is JumpRing:
			ring_d = sibling.diameter
			offset = sibling.foot_offset
			break
	var width := ring_d * width_ratio
	var h := ring_d * height_ratio
	var quad := QuadMesh.new()
	quad.size = Vector2(width, h)
	mesh = quad
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = 10
	_mat.set_shader_parameter("y_shift", ring_d * 0.5 + ring_d * gap_ratio + h * 0.5)
	_mat.set_shader_parameter("bar_color", color)
	_mat.set_shader_parameter("track_alpha", track_alpha)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position = offset
	visible = false
	var p := get_parent()
	if p.has_method("stamina_fraction"):
		_prev = p.stamina_fraction()


func _process(delta: float) -> void:
	var p := get_parent()
	if not p.has_method("stamina_fraction"):
		return
	var f: float = p.stamina_fraction()
	if absf(f - _prev) > 0.00001:
		_since_change = 0.0
	else:
		_since_change += delta
	_prev = f
	var showing := _since_change < hold_time
	_fade = move_toward(_fade, 1.0 if showing else 0.0, delta / maxf(fade_time, 0.001))
	visible = _fade > 0.0
	_mat.set_shader_parameter("progress", f)
	_mat.set_shader_parameter("fade", _fade)
	var flash := 1.0
	if p.get("exhausted"):
		_time += delta
		flash = lerpf(flash_low, 1.0, 0.5 + 0.5 * sin(_time * TAU * flash_speed))
	else:
		_time = 0.0
	_mat.set_shader_parameter("flash", flash)
