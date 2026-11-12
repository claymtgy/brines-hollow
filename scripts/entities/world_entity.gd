class_name WorldEntity
extends Node3D
## Base class for interactive non-voxel objects (stations, chests, beds, crab pots...).
##
## Authority model (see EntityManager):
##   * The host / dedicated server owns entity state. Clients never change it directly.
##   * A player interaction runs `client_interact(player)` on the player's machine. Entities
##     with shared state turn that into `manager.request_action(self, action, args)`, which runs
##     `server_action()` on the authority; the result's state is broadcast to everyone and any
##     items are granted only to the requesting player.
##   * Older entity types that just call `interact()` locally still work: the default
##     `client_interact` runs `interact()` and pushes the resulting state ("trusted" path).
##   * `server_tick()` runs only on the authority; return true when state changed so it is
##     re-broadcast (throttled).
##
## Subclasses usually override: _build_visuals, get_interaction_prompt, client_interact,
## server_action, server_tick, serialize/deserialize, pickup_items.

signal interacted(player: Player)
signal state_changed

enum EntityType {
	WORKSTATION,
	CONTAINER,
	BED,
	MIRROR,
	DECOR,
	TRAP,
}

var entity_id: StringName = &""
var entity_name: String = "Entity"
var entity_type: EntityType = EntityType.DECOR
var grid_coord: Vector3i = Vector3i.ZERO
var rotation_steps: int = 0 ## 0, 1, 2, 3 = 0, 90, 180, 270 deg
var interaction_radius: float = 2.8

## Placeable item that is returned when the entity is picked up (&"" = cannot pick up).
var item_id: StringName = &""
## Collision box in metres (x = width, y = height, z = depth before rotation).
var size: Vector3 = Vector3(0.7, 0.7, 0.7)
## Solid entities block players and boats.
var solid: bool = true
## Set by EntityManager when spawned.
var manager: Node = null

var _mesh_instance: MeshInstance3D


func _init(p_id: StringName = &"", p_name: String = "Entity", p_coord: Vector3i = Vector3i.ZERO) -> void:
	entity_id = p_id
	entity_name = p_name
	grid_coord = p_coord
	position = (Vector3(grid_coord) + Vector3(0.5, 0.0, 0.5)) * VoxelWorld.VS


func _ready() -> void:
	_build_visuals()
	# Placeholder box meshes are centred on their origin: lift them to sit on the ground.
	if _mesh_instance != null and _mesh_instance.position == Vector3.ZERO and _mesh_instance.mesh is BoxMesh:
		_mesh_instance.position.y = (_mesh_instance.mesh as BoxMesh).size.y * 0.5


func _build_visuals() -> void:
	# Default chunky wooden block placeholder if not overridden
	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.22)
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


## Voxel-art model helper: builds a mesh from a Prefabs.Grid at character resolution (0.09 m),
## centred on x/z and resting on the ground.
func _voxel_model(g: Prefabs.Grid, scale: float = VoxelWorld.VS * 0.5) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	var mi := MeshInstance3D.new()
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, scale, mat, mat)
	mi.position = Vector3(-g.sx * 0.5, 0.0, -g.sz * 0.5) * scale
	add_child(mi)
	return mi


# ---------------------------------------------------------------- interaction

func get_interaction_prompt(_player: Player) -> String:
	return "F  Interact with %s" % entity_name


func can_interact(_player: Player) -> bool:
	return true


## Runs on the interacting player's machine. Default: legacy local interaction, then push
## the resulting state to the authority (trusted path for simple entity types).
func client_interact(player: Player) -> void:
	interact(player)
	if manager != null:
		manager.push_state(self)


## Legacy/local interaction (kept for older entity types and unit tests).
func interact(player: Player) -> void:
	interacted.emit(player)


## Authority only. Returns {"grant": [[item_id, count], ...], "toast": String, "changed": bool,
## "gathered": bool}. "gathered" = the grant is a harvest (counts toward "collect N" quests);
## leave it off for chest withdrawals, refunds and the like.
func server_action(_action: StringName, _args: Dictionary, _peer: int) -> Dictionary:
	return {}


func tick(_delta: float) -> void:
	pass


## Light sources (lanterns, fires) keep cave eels and farm raiders at bay.
func emits_light() -> bool:
	return false


## Authority only. `env` = {"tide_vox": float, "daylight": bool, "time": float}. Return true if
## state changed and should be broadcast.
func server_tick(_delta: float, _env: Dictionary) -> bool:
	return false


## Items returned to the player who picks this entity up (the item itself + any contents).
func pickup_items() -> Array:
	return [[item_id, 1]] if item_id != &"" else []


## World-space collision box.
func get_aabb() -> AABB:
	var s := size
	if rotation_steps % 2 == 1:
		s = Vector3(size.z, size.y, size.x)
	return AABB(position - Vector3(s.x * 0.5, 0.0, s.z * 0.5), s)


func is_authority() -> bool:
	return manager == null or manager.is_authority()


# ---------------------------------------------------------------- persistence

func serialize() -> Dictionary:
	return {
		"id": String(entity_id),
		"name": entity_name,
		"type": int(entity_type),
		"x": grid_coord.x,
		"y": grid_coord.y,
		"z": grid_coord.z,
		"rot": rotation_steps
	}


func deserialize(data: Dictionary) -> void:
	entity_id = StringName(data.get("id", ""))
	entity_name = data.get("name", "Entity")
	entity_type = data.get("type", EntityType.DECOR) as EntityType
	grid_coord = Vector3i(int(data.get("x", 0)), int(data.get("y", 0)), int(data.get("z", 0)))
	rotation_steps = int(data.get("rot", 0))
	position = (Vector3(grid_coord) + Vector3(0.5, 0.0, 0.5)) * VoxelWorld.VS
	rotation.y = rotation_steps * (PI * 0.5)
