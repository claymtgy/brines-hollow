class_name LighthouseBeam
extends Node3D
## The sweeping beams of the starter lighthouse: two long, soft shafts of light turning
## slowly around the lantern, from dusk to dawn. Purely visual (each peer runs its own; the
## sweep is a function of the synced time of day, so everyone sees it point the same way).

const LENGTH := 70.0
const TURNS_PER_GAME_HOUR := 6.0
const MAX_FUEL_SEC := 2160.0 # 3 full in-game days of fuel

var sky: SkyCycle
var fuel_sec: float = 720.0  # Starts with 1 full in-game day (720s) of fuel
var lantern_pos: Vector3 = Vector3.ZERO
var _beams: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D
var _glow: OmniLight3D


func setup(p_sky: SkyCycle, lantern_m: Vector3) -> void:
	sky = p_sky
	lantern_pos = lantern_m
	name = "LighthouseBeam"
	position = lantern_m
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	_mat.disable_receive_shadows = true
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _cone_mesh()
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.y = PI * i
		add_child(mi)
		_beams.append(mi)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.84, 0.52)
	_glow.omni_range = 9.0
	_glow.light_energy = 0.55
	_glow.shadow_enabled = false
	add_child(_glow)
	visible = false


## A widening shaft along +Z: bright at the lamp, fading to nothing at the far end.
func _cone_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var r0 := 0.35
	var r1 := 6.0
	var c0 := Color(1.0, 0.88, 0.55, 0.045)
	var c1 := Color(1.0, 0.88, 0.55, 0.0)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p00 := Vector3(cos(a0) * r0, sin(a0) * r0 * 0.6, 0.6)
		var p01 := Vector3(cos(a1) * r0, sin(a1) * r0 * 0.6, 0.6)
		var p10 := Vector3(cos(a0) * r1, sin(a0) * r1 * 0.6, LENGTH)
		var p11 := Vector3(cos(a1) * r1, sin(a1) * r1 * 0.6, LENGTH)
		for v: Array in [[p00, c0], [p10, c1], [p11, c1], [p00, c0], [p11, c1], [p01, c0]]:
			st.set_color(v[1])
			st.add_vertex(v[0])
	return st.commit()


func add_fuel(sec: float = 720.0) -> float:
	fuel_sec = clampf(fuel_sec + sec, 0.0, MAX_FUEL_SEC)
	return fuel_sec


func can_refuel() -> bool:
	return fuel_sec < MAX_FUEL_SEC


func fuel_hours_left() -> float:
	# 720s per game day = 30s per game hour
	return fuel_sec / 30.0


func _process(delta: float) -> void:
	if sky == null:
		return
	var t := sky.time_of_day
	var night := t < 0.27 or t > 0.80
	var foggy := false
	if sky.weather != null:
		foggy = sky.weather.params.fog > 0.35

	var should_light := (night or foggy) and fuel_sec > 0.0
	visible = should_light
	if _glow != null:
		_glow.light_energy = 0.55 if should_light else 0.0

	if not visible:
		return

	# Burn fuel while beam is active
	fuel_sec = maxf(0.0, fuel_sec - delta)

	rotation.y = t * 24.0 * TURNS_PER_GAME_HOUR * TAU
	rotation.x = -0.04   # tipped a touch down towards the sea
