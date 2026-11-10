class_name PhosphorBrazierEntity
extends WorldEntity
## Submerged or shore Phosphor Brazier: a heavy brass basin fueled by phosphor ore.
## When lit, it emits a brilliant chemical turquoise flare that illuminates dark trenches
## and overloads the deep-sea eyes of the Abyssal Siren, stunning it for 8 seconds.

const U := VoxelWorld.VS * 0.5
const FLARE_DURATION := 15.0
const STUN_RADIUS := 32.0

var lit := false
var flare_timer := 0.0

var _basin: Node3D
var _light: OmniLight3D
var _flame_mesh: MeshInstance3D


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"phosphor_brazier", "Phosphor Brazier", p_coord)
	entity_type = EntityType.DECOR
	item_id = &"phosphor_brazier"
	size = Vector3(8, 14, 8) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(8, 14, 8)
	g.box(1, 0, 1, 6, 2, 6, Palette.COBBLE)            # stone anchor base
	g.box(2, 3, 2, 5, 8, 5, Palette.METAL)             # heavy brass pedestal
	g.box(0, 9, 0, 7, 13, 7, Palette.FLOWER_Y)         # flared brass cup
	g.box(1, 10, 1, 6, 12, 6, Palette.BEDROCK)         # phosphor fuel bed
	_mesh_instance = _voxel_model(g)

	# Underwater chemical flame / glow mesh
	_flame_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.65
	_flame_mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.2, 0.95, 0.85, 0.85)
	_flame_mesh.material_override = mat
	_flame_mesh.position = Vector3(0, 14 * U, 0)
	_flame_mesh.visible = false
	add_child(_flame_mesh)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.25, 0.95, 0.85)
	_light.light_energy = 0.0
	_light.omni_range = 16.0
	_light.position = Vector3(0, 14 * U, 0)
	add_child(_light)


func _process(dt: float) -> void:
	if lit:
		flare_timer -= dt
		if flare_timer <= 0.0:
			extinguish()
		else:
			var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.012)
			if _light != null:
				_light.light_energy = 2.4 * pulse
			if _flame_mesh != null:
				_flame_mesh.scale = Vector3.ONE * pulse


func ignite() -> void:
	lit = true
	flare_timer = FLARE_DURATION
	if _light != null:
		_light.light_energy = 2.4
	if _flame_mesh != null:
		_flame_mesh.visible = true

	CombatAudio.play_sound("parry", position)

	# Stun nearby Abyssal Siren
	var net: CreatureNet = CreatureNet.current
	if net == null and EntityManager.current != null and EntityManager.current.main != null:
		net = EntityManager.current.main.creatures
	if net != null and not net.creatures.is_empty():
		for c in net.creatures.values():
			if is_instance_valid(c) and c.has_method("on_phosphor_stun") and position.distance_to(c.position) <= STUN_RADIUS:
				c.on_phosphor_stun()


func extinguish() -> void:
	lit = false
	flare_timer = 0.0
	if _light != null:
		_light.light_energy = 0.0
	if _flame_mesh != null:
		_flame_mesh.visible = false


func get_interaction_prompt(_player: Player) -> String:
	if lit:
		return "Phosphor Brazier · Burning chemical flare"
	return "F  Ignite Phosphor Brazier · Blinds & stuns the Abyssal Siren"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if manager != null:
		manager.request_action(self, &"ignite", {})


func server_action(action: StringName, _args: Dictionary, _peer: int) -> Dictionary:
	if action == &"ignite":
		if not lit:
			ignite()
			return {"toast": "The phosphor flares with dazzling turquoise light!"}
		return {"toast": "The brazier is already flaring."}
	return {}
