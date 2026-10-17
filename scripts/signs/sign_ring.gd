class_name SignRing
extends MeshInstance3D
## White ring that fills up while the flashlight is held on a sign
## (same look as the jump ring). Always faces the camera.

@export var diameter := 0.5
@export_range(0.5, 0.98) var inner_ratio := 0.8
@export var color := Color(1, 1, 1, 0.95)
@export var track_alpha := 0.2

var _mat: ShaderMaterial


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(diameter, diameter)
	mesh = quad
	var sh := Shader.new()
	sh.code = JumpRing.SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = 10
	_mat.set_shader_parameter("inner_ratio", inner_ratio)
	_mat.set_shader_parameter("ring_color", color)
	_mat.set_shader_parameter("track_alpha", track_alpha)
	_mat.set_shader_parameter("fade", 1.0)
	_mat.set_shader_parameter("progress", 0.0)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	visible = false


## 0 = hidden, 1 = full.
func set_progress(p: float) -> void:
	visible = p > 0.001
	if _mat:
		_mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))
