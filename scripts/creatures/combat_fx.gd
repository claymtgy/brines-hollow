class_name CombatFX
extends Node
## Procedural visual combat effects: dynamic weapon slash trails (ribbon arcs),
## directional hit sparks/chitin splinters, parry starbursts, and plunge shockwaves.

static var _mat_light_slash: StandardMaterial3D
static var _mat_charged_slash: StandardMaterial3D
static var _mat_riposte_slash: StandardMaterial3D
static var _mat_parry_ring: StandardMaterial3D
static var _mat_shockwave: StandardMaterial3D
static var _init_done := false


static func init_materials() -> void:
	if _init_done:
		return
	_init_done = true
	if DisplayServer.get_name() == "headless":
		return

	_mat_light_slash = _create_additive_mat(Color(0.85, 0.95, 1.0, 0.65))
	_mat_charged_slash = _create_additive_mat(Color(1.0, 0.78, 0.28, 0.85))
	_mat_riposte_slash = _create_additive_mat(Color(0.35, 0.88, 1.0, 0.95))
	_mat_parry_ring = _create_additive_mat(Color(1.0, 0.92, 0.45, 0.9))
	_mat_shockwave = _create_additive_mat(Color(0.9, 0.85, 0.75, 0.6))


static func _create_additive_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	return m


## Spawns a procedural glowing slash trail arc along the weapon's trajectory.
static func spawn_slash_trail(parent: Node3D, origin: Vector3, facing_rad: float, combo_step: int, weapon_type: int, is_charged: bool, is_riposte: bool) -> void:
	if DisplayServer.get_name() == "headless" or parent == null:
		return
	if not _init_done:
		init_materials()

	var mi := MeshInstance3D.new()
	var mat := _mat_riposte_slash if is_riposte else (_mat_charged_slash if is_charged else _mat_light_slash)
	mi.material_override = mat

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	var is_thrust := (weapon_type == WeaponDef.WeaponType.HARPOON)
	var is_overhead := (combo_step == 3 or is_charged or weapon_type == WeaponDef.WeaponType.ANCHOR_MAUL)

	var segments := 12
	var r_in := 0.6
	var r_out := 2.2 if not is_thrust else 3.4

	if is_thrust:
		# Linear pierce cone
		for k in range(segments + 1):
			var frac := float(k) / segments
			var z := frac * r_out
			var spread := (1.0 - frac) * 0.35
			var alpha := sin(frac * PI) * 0.8
			var c := Color(1, 1, 1, alpha)
			st.set_color(c)
			st.add_vertex(Vector3(-spread, 0.0, z))
			st.set_color(c)
			st.add_vertex(Vector3(spread, 0.0, z))
	elif is_overhead:
		# Vertical downward cleave arc
		var arc_angle := 1.8 # radians vertical arc
		for k in range(segments + 1):
			var frac := float(k) / segments
			var ang := lerpf(1.1, -0.7, frac)
			var y := sin(ang) * r_out
			var z := cos(ang) * r_out
			var y_in := sin(ang) * r_in
			var z_in := cos(ang) * r_in
			var alpha := pow(frac, 0.7) * 0.85
			var c := Color(1, 1, 1, alpha)
			st.set_color(c)
			st.add_vertex(Vector3(-0.08, y_in, z_in))
			st.set_color(c)
			st.add_vertex(Vector3(0.08, y, z))
	else:
		# Horizontal slash arc (step 1 right-to-left, step 2 left-to-right)
		var flip := (combo_step == 2)
		var a_start := 1.2 if flip else -1.2
		var a_end := -1.2 if flip else 1.2
		var tilt := -0.2 if flip else 0.15
		for k in range(segments + 1):
			var frac := float(k) / segments
			var ang := lerpf(a_start, a_end, frac)
			var x := sin(ang) * r_out
			var z := cos(ang) * r_out
			var x_in := sin(ang) * r_in
			var z_in := cos(ang) * r_in
			var y_offset := (frac - 0.5) * tilt
			var alpha := pow(frac, 0.6) * 0.75
			var c := Color(1, 1, 1, alpha)
			st.set_color(c)
			st.add_vertex(Vector3(x_in, y_offset - 0.08, z_in))
			st.set_color(c)
			st.add_vertex(Vector3(x, y_offset + 0.08, z))

	mi.mesh = st.commit()
	mi.position = origin
	mi.rotation.y = facing_rad
	parent.add_child(mi)

	# Smoothly fade out over 0.16s
	var tree := mi.get_tree()
	if tree != null:
		var tween := tree.create_tween()
		tween.tween_property(mi, "transparency", 1.0, 0.16)
		tween.tween_callback(mi.queue_free)
	else:
		mi.queue_free()


## Spawns directional impact sparks / fragments on creature hit.
static func spawn_hit_sparks(parent: Node3D, pos: Vector3, hit_normal: Vector3, is_shell: bool = false, is_crit: bool = false) -> void:
	if DisplayServer.get_name() == "headless" or parent == null:
		return

	var p := CPUParticles3D.new()
	p.position = pos
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.28
	p.amount = 18 if is_crit else (14 if is_shell else 10)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	p.material_override = mat

	# Color: golden sparks for shell/crit, vibrant orange/amber for normal
	var spark_color := Color(1.0, 0.9, 0.4, 1.0) if (is_shell or is_crit) else Color(1.0, 0.5, 0.2, 0.9)
	p.color = spark_color

	p.direction = hit_normal if hit_normal.length() > 0.1 else Vector3.UP
	p.spread = 55.0
	p.gravity = Vector3(0, -9.8, 0)
	p.initial_velocity_min = 4.0 if not is_crit else 7.0
	p.initial_velocity_max = 7.0 if not is_crit else 11.0
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.09

	parent.add_child(p)
	p.emitting = true

	var tree := p.get_tree()
	if tree != null:
		tree.create_timer(0.35, true, false, true).timeout.connect(p.queue_free)
	else:
		p.queue_free()


## Spawns a brilliant radial starburst and expanding ring on a precision parry.
static func spawn_parry_spark(parent: Node3D, pos: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or parent == null:
		return
	if not _init_done:
		init_materials()

	# 1. Radial spark particles
	var p := CPUParticles3D.new()
	p.position = pos
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.32
	p.amount = 26
	p.material_override = _mat_parry_ring
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 9.5
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	parent.add_child(p)
	p.emitting = true

	# 2. Expanding golden ring
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.25
	torus.outer_radius = 0.35
	ring.mesh = torus
	ring.material_override = _mat_parry_ring
	ring.position = pos
	parent.add_child(ring)

	var tree := parent.get_tree()
	if tree != null:
		var tween := tree.create_tween()
		tween.tween_property(ring, "scale", Vector3(3.5, 3.5, 3.5), 0.22)
		tween.parallel().tween_property(ring, "transparency", 1.0, 0.22)
		tween.tween_callback(ring.queue_free)
		tree.create_timer(0.4, true, false, true).timeout.connect(p.queue_free)
	else:
		ring.queue_free()
		p.queue_free()


## Spawns an expanding dust & water shockwave ring on plunge landing.
static func spawn_plunge_shockwave(parent: Node3D, pos: Vector3, max_radius: float = 3.5) -> void:
	if DisplayServer.get_name() == "headless" or parent == null:
		return
	if not _init_done:
		init_materials()

	# Expanding ground ring
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.6
	ring.mesh = torus
	ring.material_override = _mat_shockwave
	ring.position = pos + Vector3.UP * 0.08
	parent.add_child(ring)

	var target_scale := max_radius / 0.6
	var tree := parent.get_tree()
	if tree != null:
		var tween := tree.create_tween()
		tween.tween_property(ring, "scale", Vector3(target_scale, 1.0, target_scale), 0.28)
		tween.parallel().tween_property(ring, "transparency", 1.0, 0.28)
		tween.tween_callback(ring.queue_free)
	else:
		ring.queue_free()
