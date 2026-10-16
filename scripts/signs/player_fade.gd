class_name PlayerFade
extends RefCounted
## Fades the player by swapping in alpha-blended copies of its materials.
## (GeometryInstance3D.transparency is not reliable in the Compatibility renderer.)


static func get_opacity(player: Node) -> float:
	return float(player.get_meta("fade_opacity", 1.0))


static func set_opacity(player: Node, opacity: float) -> void:
	opacity = clampf(opacity, 0.0, 1.0)
	player.set_meta("fade_opacity", opacity)
	for n in player.find_children("*", "MeshInstance3D", true, false):
		_apply(n as MeshInstance3D, opacity)


static func _apply(mi: MeshInstance3D, opacity: float) -> void:
	if mi.mesh == null:
		return
	var has := mi.has_meta("fade_mats")
	if not has:
		if opacity >= 0.999:
			return
		var mats: Array = []
		var orig: Array = []
		for i in mi.mesh.get_surface_count():
			orig.append(mi.get_surface_override_material(i))
			var src := mi.get_active_material(i) as BaseMaterial3D
			if src == null:
				mats.append(null) # custom shader materials (rings, bars) stay as they are
				continue
			var m := src.duplicate() as BaseMaterial3D
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			mats.append(m)
		mi.set_meta("fade_mats", mats)
		mi.set_meta("fade_orig", orig)
	var fm: Array = mi.get_meta("fade_mats")
	var fo: Array = mi.get_meta("fade_orig")
	for i in fm.size():
		var m := fm[i] as BaseMaterial3D
		if m == null:
			continue
		if opacity >= 0.999:
			mi.set_surface_override_material(i, fo[i] as Material)
		else:
			var c := m.albedo_color
			m.albedo_color = Color(c.r, c.g, c.b, opacity)
			mi.set_surface_override_material(i, m)
	if opacity >= 0.999:
		mi.remove_meta("fade_mats")
		mi.remove_meta("fade_orig")
