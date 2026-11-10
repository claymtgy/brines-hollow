class_name WhirlpoolHazard
extends Node3D
## Dynamic Maritime Hazard: a swirling ocean vortex that spawns in open channels during storms.
## Generates strong centripetal suction and rotational current that pulls boats and swimmers inward.

const RADIUS := 28.0
const SUCTION_FORCE := 3.2
const ROTATION_FORCE := 4.0

static var active_whirlpools: Array[WhirlpoolHazard] = []

var _swirl_mesh: MeshInstance3D
var _rot := 0.0
var _lap_t := 0.0


func _ready() -> void:
	active_whirlpools.append(self)
	_build_visuals()


func _exit_tree() -> void:
	active_whirlpools.erase(self)


func _build_visuals() -> void:
	_swirl_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.5
	torus.outer_radius = 8.5
	torus.rings = 24
	torus.ring_segments = 16
	_swirl_mesh.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.45, 0.65, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_swirl_mesh.material_override = mat
	_swirl_mesh.position = Vector3(0, -0.2, 0)
	add_child(_swirl_mesh)


func _process(dt: float) -> void:
	_rot += dt * 3.5
	if _swirl_mesh != null:
		_swirl_mesh.rotation = Vector3(0, _rot, 0)

	_lap_t -= dt
	if _lap_t <= 0.0:
		_lap_t = randf_range(1.2, 2.0)
		var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
		if cam != null and position.distance_to(cam.global_position) < 40.0:
			CombatAudio.play_sound("water_lap", position, -3.0)


## Calculate current acceleration (xz m/s^2) and angular torque at a given position
static func get_vortex_effect(pos: Vector3) -> Dictionary:
	if active_whirlpools.is_empty():
		return {}
	var total_force := Vector2.ZERO
	var total_torque := 0.0
	for wp in active_whirlpools:
		if not is_instance_valid(wp):
			continue
		var to_center := Vector2(wp.position.x - pos.x, wp.position.z - pos.z)
		var d := to_center.length()
		if d < RADIUS and d > 0.2:
			var factor := pow(1.0 - (d / RADIUS), 1.5)
			# Radial pull inward
			var inward := to_center.normalized() * (SUCTION_FORCE * factor)
			# Tangential swirl (clockwise)
			var tang := Vector2(-to_center.y, to_center.x).normalized() * (ROTATION_FORCE * factor)
			total_force += inward + tang
			total_torque += 2.5 * factor
	if total_torque == 0.0 and total_force == Vector2.ZERO:
		return {}
	return {"force": total_force, "torque": total_torque}
