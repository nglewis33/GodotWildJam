extends SpotLight3D
## Player flashlight: a cone pointing where the character faces.
## F toggles it. Tune the beam with this node's SpotLight3D properties
## (range, angle, energy, color, shadows).
## Volumetric fog isn't available in the Compatibility renderer, so the visible
## light beam is a faint see-through cone mesh that matches the spot's range
## and angle.

@export var toggle_key: Key = KEY_F
@export var starts_on := true
@export_group("Visible beam")
@export var beam_enabled := true
@export var beam_color := Color(1.0, 0.95, 0.8)
## Brightness of the beam (it adds to what's behind it).
@export_range(0.0, 1.0, 0.01) var beam_strength := 0.16

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 beam_color : source_color = vec4(1.0);
uniform float strength = 0.15;
uniform float cone_height = 15.0;
varying float along;
void vertex() {
	// Cylinder axis is Y; the apex (radius 0) is at +Y.
	along = clamp((cone_height * 0.5 - VERTEX.y) / cone_height, 0.0, 1.0);
}
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = pow(1.0 - along, 1.6) * smoothstep(0.0, 0.12, along) * pow(facing, 1.4);
	ALBEDO = beam_color.rgb * a * strength;
	ALPHA = 1.0;
}
"""

var _beam: MeshInstance3D


func _ready() -> void:
	visible = starts_on
	if beam_enabled:
		_build_beam()


func _build_beam() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = spot_range * tan(deg_to_rad(spot_angle))
	cone.height = spot_range
	cone.radial_segments = 24
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = 5
	mat.set_shader_parameter("beam_color", beam_color)
	mat.set_shader_parameter("strength", beam_strength)
	mat.set_shader_parameter("cone_height", spot_range)
	_beam = MeshInstance3D.new()
	_beam.mesh = cone
	_beam.material_override = mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Spot lights shine along -Z; put the cone's apex at the light.
	_beam.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_beam.position = Vector3(0.0, 0.0, -spot_range * 0.5)
	add_child(_beam)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == toggle_key:
		var player := get_parent()
		# Ignore the key while the free camera has taken over input.
		if player and player.get("input_enabled") == false:
			return
		visible = not visible
