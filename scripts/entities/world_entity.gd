class_name WorldEntity
extends Node3D
## Base class for interactive non-voxel physical objects in Brine's Hollow.
## Supports spatial positioning, interaction prompts, serialization, and visual styling.

signal interacted(player: Player)
signal state_changed

enum EntityType {
	WORKSTATION,
	CONTAINER,
	BED,
	MIRROR,
	DECOR
}

var entity_id: StringName = &""
var entity_name: String = "Entity"
var entity_type: EntityType = EntityType.DECOR
var grid_coord: Vector3i = Vector3i.ZERO
var rotation_steps: int = 0 ## 0, 1, 2, 3 = 0, 90, 180, 270 deg
var interaction_radius: float = 2.8

var _mesh_instance: MeshInstance3D


func _init(p_id: StringName = &"", p_name: String = "Entity", p_coord: Vector3i = Vector3i.ZERO) -> void:
	entity_id = p_id
	entity_name = p_name
	grid_coord = p_coord
	position = (Vector3(grid_coord) + Vector3(0.5, 0.0, 0.5)) * VoxelWorld.VS


func _ready() -> void:
	_build_visuals()


func _build_visuals() -> void:
	# Default chunky wooden block placeholder if not overridden
	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.7, 0.7)
	_mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.22)
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func get_interaction_prompt(_player: Player) -> String:
	return "F  Interact with %s" % entity_name


func can_interact(_player: Player) -> bool:
	return true


func interact(player: Player) -> void:
	interacted.emit(player)


func tick(_delta: float) -> void:
	pass


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
