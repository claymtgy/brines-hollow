class_name TerrainStep
extends RefCounted
## Can a small animal step from one spot to another? Shared by wild animals, raiders and
## livestock so that fences, gaps and gates mean the same thing to all of them.
##
## An animal needs `clearance` voxels of open air above the ground to pass (0.18 m each):
##   stoat 2 · duck 3 · fox 3 · goat / sheep 5
## A rail fence leaves 3 voxels open under its bottom rail: goats and sheep stay in, but
## ducks wander out and foxes and stoats slip in. A Pen Fence (boards to the ground) or a
## closed Pen Gate stops everything.

const VS := VoxelWorld.VS


static func _solid(m: int) -> bool:
	return m != 0 and not Palette.is_foliage(m)


## Top of the ground (metres) at (x, z), searching from `from_y` up `up` and down `down`
## voxels: the highest solid voxel with open air right above it. NAN if none.
static func ground_at(voxel: Callable, x: float, z: float, from_y: float, up: int = 2, down: int = 6) -> float:
	var vx := floori(x / VS)
	var vz := floori(z / VS)
	var y0 := floori(from_y / VS + 0.01)
	for y in range(y0 + up - 1, y0 - down - 1, -1):
		if _solid(voxel.call(vx, y, vz)) and not _solid(voxel.call(vx, y + 1, vz)):
			return (y + 1) * VS
	return NAN


## Ground height (metres) after stepping to `to`, or NAN if the step is blocked: a wall,
## fence, drop-off, or too little head-room for an animal needing `clearance` voxels.
static func step(voxel: Callable, from: Vector3, to: Vector3, clearance: int, up: int = 2, down: int = 6) -> float:
	var g := ground_at(voxel, to.x, to.z, from.y, up, down)
	if is_nan(g):
		return NAN
	var vx := floori(to.x / VS)
	var vz := floori(to.z / VS)
	var gy := roundi(g / VS)
	for k in clearance:
		if _solid(voxel.call(vx, gy + k, vz)):
			return NAN
	return g


## Same, for a body `width` metres wide: the centre and both flanks must pass.
static func step_wide(voxel: Callable, from: Vector3, to: Vector3, clearance: int, width: float) -> float:
	var g := step(voxel, from, to, clearance)
	if is_nan(g) or width <= VS:
		return g
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if d.length() < 0.0001:
		return g
	var side := Vector3(-d.z, 0.0, d.x).normalized() * (width * 0.5)
	for s: Vector3 in [side, -side]:
		if is_nan(step(voxel, from + s, to + s, clearance)):
			return NAN
	return g


## Solid entities (closed gates, chests, boats) in the way of a body at `p`?
static func entity_blocked(p: Vector3, half: float, height: float) -> bool:
	var em := EntityManager.current
	if em == null:
		return false
	return em.blocks(Vector3(p.x - half, p.y + 0.05, p.z - half), Vector3(p.x + half, p.y + height, p.z + half))
