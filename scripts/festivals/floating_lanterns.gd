class_name FloatingLanternManager
extends Node3D
## Night of the Floating Lanterns: atmospheric floating paper lanterns that drift
## seaward on the falling tide during Equinox festival nights.
## Players can also place their own lantern into the water with a wish!

const MAX_LANTERNS := 32
const SPAWN_RADIUS := 45.0

class LanternItem:
	var root: Node3D
	var mesh: MeshInstance3D
	var light: OmniLight3D
	var pos: Vector3
	var vel: Vector3
	var phase: float
	var lifetime: float
	var is_player_wish: bool = false

var world: VoxelWorld
var sky: SkyCycle
var player: Player
var _lanterns: Array[LanternItem] = []
var _lantern_mesh: BoxMesh = null
var _lantern_mat: StandardMaterial3D = null


func setup(p_world: VoxelWorld, p_sky: SkyCycle, p_player: Player) -> void:
	world = p_world
	sky = p_sky
	player = p_player
	_build_lantern_template()


func _build_lantern_template() -> void:
	_lantern_mesh = BoxMesh.new()
	_lantern_mesh.size = Vector3(0.35, 0.42, 0.35)
	_lantern_mat = StandardMaterial3D.new()
	_lantern_mat.albedo_color = Color(1.0, 0.88, 0.55, 0.95)
	_lantern_mat.emission_enabled = true
	_lantern_mat.emission = Color(1.0, 0.72, 0.28)
	_lantern_mat.emission_energy_multiplier = 2.2
	_lantern_mat.roughness = 0.6
	_lantern_mesh.material = _lantern_mat


func spawn_player_wish_lantern(origin: Vector3) -> void:
	var water_y := sky.water_level_m() if sky != null else origin.y
	var p := Vector3(origin.x, water_y, origin.z)
	var li := _create_lantern(p, true)
	if li != null:
		li.lifetime = 180.0
		if player != null and player.hud != null:
			player.hud.show_toast("Released your floating festival lantern with a quiet wish...")


func _create_lantern(pos: Vector3, is_wish: bool = false) -> LanternItem:
	if _lanterns.size() >= MAX_LANTERNS:
		# Recycle oldest
		var oldest: LanternItem = _lanterns.pop_front()
		if oldest != null and is_instance_valid(oldest.root):
			oldest.root.queue_free()

	var li := LanternItem.new()
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var mi := MeshInstance3D.new()
	mi.mesh = _lantern_mesh
	mi.position.y = 0.21
	root.add_child(mi)

	var ol := OmniLight3D.new()
	ol.light_color = Color(1.0, 0.78, 0.35)
	ol.light_energy = 0.85 if is_wish else 0.55
	ol.omni_range = 4.5 if is_wish else 3.2
	ol.omni_attenuation = 1.2
	ol.position.y = 0.25
	root.add_child(ol)

	li.root = root
	li.mesh = mi
	li.light = ol
	li.pos = pos
	li.phase = randf() * TAU
	li.lifetime = randf_range(90.0, 180.0)
	li.is_player_wish = is_wish
	# Gentle drift seaward away from coast
	li.vel = Vector3(randf_range(-0.15, 0.15), 0, randf_range(-0.15, 0.15))
	_lanterns.append(li)
	return li


func _find_shore_water_spot(origin: Vector3) -> Vector3:
	var water_y := sky.water_level_m() if sky != null else 18.0
	for _attempt in 10:
		var ang := randf() * TAU
		var dist := randf_range(8.0, SPAWN_RADIUS)
		var p := origin + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		p.y = water_y
		return p
	return origin + Vector3(0, -0.5, 0)


func _process(delta: float) -> void:
	if sky == null or player == null:
		return

	var is_fest: bool = sky.is_floating_lantern_festival()
	var water_y := sky.water_level_m()
	var p_pos := player.position

	# During festival, maintain ambient flotilla near the shore
	if is_fest and _lanterns.size() < 18 and randf() < 0.05:
		var spawn_spot := _find_shore_water_spot(p_pos)
		_create_lantern(spawn_spot, false)

	# Update active lanterns
	for i in range(_lanterns.size() - 1, -1, -1):
		var li: LanternItem = _lanterns[i]
		li.phase += delta * 1.8
		li.lifetime -= delta

		if li.lifetime <= 0.0 or (!is_fest and not li.is_player_wish and li.lifetime < 120.0):
			if is_instance_valid(li.root):
				li.root.queue_free()
			_lanterns.remove_at(i)
			continue

		# Water bobbing
		var bob := sin(li.phase) * 0.04
		li.pos.x += li.vel.x * delta
		li.pos.z += li.vel.z * delta
		li.pos.y = water_y + bob

		if is_instance_valid(li.root):
			li.root.position = li.pos
			li.root.rotation.y = sin(li.phase * 0.5) * 0.2
			li.root.rotation.z = cos(li.phase * 0.7) * 0.05
