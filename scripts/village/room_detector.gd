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


# ---------------------------------------------------------------- world-scale homes

const HOME_MIN_VOLUME := 900       ## ~5 m^3: a 1.6 x 1.6 x 2 m nook is the smallest home
const HOME_MAX_VOLUME := 45000     ## past this the fill has escaped into a cave or the open
const CEILING_REACH := 24          ## voxels (4.3 m): a cell with no ceiling this close is outdoors
const DOOR_HEIGHT := 10            ## an opening must be this tall (1.8 m) to count as a door


## Flood-fills the room around `start` at world scale (0.18 m voxels).
##   solid.call(p: Vector3i) -> bool        voxel blocks movement (walls, floors, lanterns)
##   ceiling.call(p: Vector3i) -> bool      a roof exists within CEILING_REACH above p
##   fixtures: {Vector3i: "bed" | "light" | "decor"}   entity / lantern cells
## Open doorways are fine: cells without a ceiling are outdoors, so the fill stops one cell
## past any opening. A floor-level opening at least DOOR_HEIGHT tall is the entrance;
## shorter openings (windows) aren't.
static func scan_home(start: Vector3i, solid: Callable, ceiling: Callable, fixtures: Dictionary) -> RoomValidationResult:
	var res := RoomValidationResult.new()
	if solid.call(start) or not ceiling.call(start):
		res.error_message = "Not inside a roofed space."
		res.has_roof = false
		return res
	var visited := {start: true}
	var queue: Array[Vector3i] = [start]
	var head := 0
	var min_b := start
	var max_b := start
	var outdoor_edges := {}       # indoor cell -> true when it touches an outdoor cell sideways
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0)]
	var beds := 0
	var lights := 0
	var decor := 0
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		if queue.size() > HOME_MAX_VOLUME:
			res.error_message = "This space is too big or open to be a home."
			return res
		min_b = Vector3i(mini(min_b.x, c.x), mini(min_b.y, c.y), mini(min_b.z, c.z))
		max_b = Vector3i(maxi(max_b.x, c.x), maxi(max_b.y, c.y), maxi(max_b.z, c.z))
		var f: String = fixtures.get(c, "")
		if f == "bed": beds += 1
		elif f == "light": lights += 1
		elif f == "decor": decor += 1
		for i in 6:
			var n: Vector3i = c + dirs[i]
			if visited.has(n):
				continue
			if solid.call(n):
				if fixtures.get(n, "") == "light":
					lights += 1    # lantern voxels hang as solid cells
					visited[n] = true
				continue
			if not ceiling.call(n):
				if i < 4:
					outdoor_edges[c] = true
				continue
			visited[n] = true
			queue.append(n)
	res.volume = queue.size()
	res.room_bounds_min = min_b
	res.room_bounds_max = max_b
	res.has_bed = beds > 0
	res.has_light = lights > 0
	# Door: an indoor floor-level cell next to the outdoors with DOOR_HEIGHT of headroom.
	var windows := 0
	for c: Vector3i in outdoor_edges:
		var on_floor: bool = solid.call(c + Vector3i(0, -1, 0)) and c.y <= min_b.y + 1
		var tall := true
		for k in DOOR_HEIGHT:
			if solid.call(c + Vector3i(0, k, 0)):
				tall = false
				break
		if on_floor and tall:
			res.has_door = true
		else:
			windows += 1
	if res.volume < HOME_MIN_VOLUME:
		res.error_message = "Too cramped to live in."
	elif not res.has_bed:
		res.error_message = "Needs a bed."
	elif not res.has_light:
		res.error_message = "Needs a light (lantern or lamp)."
	elif not res.has_door:
		res.error_message = "Needs a doorway at least 1.8 m tall."
	else:
		res.is_valid = true
		var vol_score := clampf(float(res.volume) / 120.0, 10.0, 60.0)
		res.quality_score = int(clampf(vol_score + mini(windows, 12) * 1.5 + mini(decor, 6) * 3.0 + mini(lights, 3) * 2.0, 10.0, 100.0))
	return res
