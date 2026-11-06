class_name RoomDetector
extends RefCounted
## 3D flood-fill room validator for NPC housing.
## Scans voxel space from an interior coordinate to verify walls, ceiling,
## doors, lighting, and sleeping quarters.

const MIN_ROOM_VOLUME := 16   ## Minimum volume in voxels (~1.5 m^3)
const MAX_ROOM_VOLUME := 600  ## Maximum volume before considering it an open outdoors leak

## Special voxel/entity markers for room validation
const V_AIR := 0
const V_DOOR := Palette.SHUTTER      ## Shutter or Door material
const V_BED := Palette.COAT_A        ## Bed cushion/mattress material
const V_LIGHT := Palette.LANTERN     ## Emissive lantern material

class RoomValidationResult:
	var is_valid: bool = false
	var volume: int = 0
	var has_bed: bool = false
	var has_light: bool = false
	var has_door: bool = false
	var has_roof: bool = true
	var error_message: String = ""
	var room_bounds_min: Vector3i = Vector3i.ZERO
	var room_bounds_max: Vector3i = Vector3i.ZERO
	var quality_score: int = 0


## Validates an enclosed room using a voxel query callback:
##   query_voxel.call(pos: Vector3i) -> int (Palette material ID)
static func validate_room(start_pos: Vector3i, query_voxel: Callable) -> RoomValidationResult:
	var res := RoomValidationResult.new()

	# Start position must be air inside the room
	if query_voxel.call(start_pos) != V_AIR:
		res.error_message = "Start point is not an interior air cell."
		return res

	var visited: Dictionary = {} # Vector3i -> true
	var queue: Array[Vector3i] = [start_pos]
	visited[start_pos] = true

	var min_bound := start_pos
	var max_bound := start_pos

	var volume := 0
	var has_bed := false
	var has_light := false
	var has_door := false

	var directions := [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)
	]

	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		volume += 1

		# Expand bounding box
		min_bound.x = min(min_bound.x, current.x)
		min_bound.y = min(min_bound.y, current.y)
		min_bound.z = min(min_bound.z, current.z)
		max_bound.x = max(max_bound.x, current.x)
		max_bound.y = max(max_bound.y, current.y)
		max_bound.z = max(max_bound.z, current.z)

		# Leak check: if volume exceeds maximum threshold, room is not enclosed
		if volume > MAX_ROOM_VOLUME:
			res.error_message = "Room is too large or leaks into the open sky."
			res.has_roof = false
			return res

		# Inspect neighbors
		for d in directions:
			var neighbor: Vector3i = current + d
			if visited.has(neighbor):
				continue

			var mat: int = int(query_voxel.call(neighbor))

			# Check fixture markers on room boundaries or interior
			if mat == V_BED:
				has_bed = true
			elif mat == V_LIGHT or mat == Palette.GLOW_TEAL:
				has_light = true
			elif mat == V_DOOR:
				has_door = true

			# If air, continue flood filling
			if mat == V_AIR:
				visited[neighbor] = true
				queue.append(neighbor)
			else:
				# Neighbor is a solid wall/floor/ceiling or fixture; does not expand
				visited[neighbor] = true

	res.volume = volume
	res.has_bed = has_bed
	res.has_light = has_light
	res.has_door = has_door
	res.room_bounds_min = min_bound
	res.room_bounds_max = max_bound

	# Validation criteria
	if volume < MIN_ROOM_VOLUME:
		res.error_message = "Room is too cramped (volume %d < %d)." % [volume, MIN_ROOM_VOLUME]
		return res

	if not has_bed:
		res.error_message = "Room lacks a bed or sleeping mat."
		return res

	if not has_light:
		res.error_message = "Room lacks a light source (lamp or lantern)."
		return res

	if not has_door:
		res.error_message = "Room lacks an entrance door."
		return res

	res.is_valid = true
	# Quality score scales with volume, lighting, and space
	res.quality_score = int(clamp(float(volume) / 5.0, 10.0, 100.0))
	return res
