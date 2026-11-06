class_name WorldGen
extends RefCounted
## Archipelago world setup. Terrain, trees, kelp, boulders and the sea cave are generated
## per chunk column by the native ArchipelagoGen (native/src/archipelago.cpp), so any column
## can be produced on demand, in any order, identically on every peer.
## This script only plans the starter area (hut, dock, lamps) on the home island and
## registers it as stamps that the native generator applies wherever they overlap.

enum Kind { BEACH, GRASS, ROCK, SEABED, GRASS_DRY }

const PREFAB_HUT := 5
const PREFAB_DOCK := 6
const PREFAB_LAMP := 7
const PREFAB_RACK := 10

var native := ArchipelagoGen.new()
var seed_value: int
var wx: int
var wy: int
var wz: int
var sea_mid: float
var sea_low: int
var sea_high: int

var spawn := Vector3.ZERO     # in voxel units
var spawn_yaw := 0.0          # camera yaw that looks at the starter hut
## Boats to spawn as entities: [{pos: Vector3 (metres, water level), yaw: float}]
var boat_spawns: Array = []
## Lamp light positions (voxel coords) for stamped prefabs; VoxelWorld creates the lights.
var stamp_lights: Array = []
var islands: Array = []


func _init(p_seed: int, sx: int, sy: int, sz: int, p_sea_mid: float, tide_amp: float) -> void:
	seed_value = p_seed
	wx = sx; wy = sy; wz = sz
	sea_mid = p_sea_mid
	sea_low = int(p_sea_mid - tide_amp)
	sea_high = int(p_sea_mid + tide_amp)
	var mats := PackedByteArray([
		Palette.BEDROCK, Palette.STONE, Palette.SANDSTONE_A, Palette.SANDSTONE_B, Palette.SANDSTONE_C,
		Palette.SAND, Palette.WET_SAND, Palette.GRAVEL, Palette.DIRT, Palette.GRASS, Palette.GRASS_DRY,
		Palette.KELP, Palette.LEAVES, Palette.LEAVES_DARK, Palette.TRUNK, Palette.FLOWER_Y, Palette.FLOWER_P,
		Palette.DRIFTWOOD, Palette.GLOW_TEAL, Palette.COBBLE, Palette.DARK_WOOD])
	native.configure(p_seed, Vector3i(sx, sy, sz), p_sea_mid, tide_amp, mats)
	islands = native.get_islands()


static func is_grassy(k: int) -> bool:
	return k == Kind.GRASS or k == Kind.GRASS_DRY


func col_h(x: int, z: int) -> int:
	return native.column_height(x, z)


func col_k(x: int, z: int) -> int:
	return native.column_kind(x, z)


## Register a prefab as a generation stamp (same placement rules as VoxelWorld.apply_prefab).
func _stamp(id: int, origin: Vector3i, rot: int) -> void:
	var pf := Prefabs.rotated(id, rot)
	var base: Vector3i = origin - (pf.anchor as Vector3i)
	var f := 0
	match pf.foundation:
		"solid": f = 1
		"posts": f = 2
	native.add_stamp(pf.data, pf.size, base, f)
	for l: Vector3i in pf.lights:
		stamp_lights.append(base + l)


## Plan the starter area on the home island. Call once, before any chunk is generated.
func plan_starter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 3
	var home: Dictionary = islands[0]
	var hc: Vector2 = home.center
	var hr: float = home.radius
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var best := {}
	for attempt in 6000:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(0.35, 0.70) * hr
		var x := int(hc.x + cos(ang) * rad)
		var z := int(hc.y + sin(ang) * rad)
		var h := col_h(x, z)
		if h < sea_high + 1 or h > sea_high + 22:
			continue
		var k0 := col_k(x, z)
		if not is_grassy(k0) and k0 != Kind.BEACH:
			continue
		# reasonably flat footprint (foundation fills the rest)
		var lo := 999
		var hi := -999
		var ok := true
		for dz in range(-14, 15, 4):
			for dx in range(-14, 15, 4):
				var hh := col_h(x + dx, z + dz)
				lo = mini(lo, hh)
				hi = maxi(hi, hh)
				if hi - lo > 9:
					ok = false
					break
			if not ok:
				break
		if not ok or lo < sea_high:
			continue
		# open water within reach in one of four directions, without cliffs in between
		for di in 4:
			var d: Vector2i = dirs[di]
			for s in range(16, 100, 2):
				var px := x + d.x * s
				var pz := z + d.y * s
				var ph := col_h(px, pz)
				if ph > hi + 4:
					break
				if ph < sea_low - 1:
					# must be the open sea, not a lagoon: ~29 m of water further out
					var wet := 0
					for t in range(s, s + 160, 8):
						if col_h(x + d.x * t, z + d.y * t) < int(sea_mid) - 5:
							wet += 1
					if wet < 19:
						break
					var score := s + (hi - lo) * 3
					if best.is_empty() or score < best.score:
						best = {"x": x, "z": z, "y": hi + 1, "dir": d, "r": di, "shore": s, "score": score}
					break
		if not best.is_empty() and best.score < 30:
			break
	if best.is_empty():
		push_warning("[gen] no hut site found")
		var c := Vector2i(hc)
		spawn = Vector3(c.x + 0.5, col_h(c.x, c.y) + 2, c.y + 0.5)
		return
	var d: Vector2i = best.dir
	var origin := Vector3i(best.x, best.y, best.z)
	# Hut front (-Z at r0) faces d: r0:-z r1:+x r2:+z r3:-x
	var hut_r: int = best.r
	_stamp(PREFAB_HUT, origin, hut_r)
	var side := Vector2i(-d.y, d.x)
	var lamp := Vector2i(best.x, best.z) + d * 16 + side * 9
	_stamp(PREFAB_LAMP, Vector3i(lamp.x, col_h(lamp.x, lamp.y) + 1, lamp.y), 0)
	# Dock: starts where the beach meets the high-tide line and runs out to sea.
	var s0 := 14
	for s in range(14, 100):
		if col_h(best.x + d.x * s, best.z + d.y * s) <= sea_high:
			s0 = s
			break
	var dock_r: int = {Vector2i(0, 1): 0, Vector2i(-1, 0): 1, Vector2i(0, -1): 2, Vector2i(1, 0): 3}[d]
	var dock_o := Vector2i(best.x, best.z) + d * (s0 - 2)
	_stamp(PREFAB_DOCK, Vector3i(dock_o.x, sea_high + 3, dock_o.y), dock_r)
	var dock_lamp := dock_o + side * 7
	_stamp(PREFAB_LAMP, Vector3i(dock_lamp.x, col_h(dock_lamp.x, dock_lamp.y) + 1, dock_lamp.y), 0)
	var rack := Vector2i(best.x, best.z) + d * 16 - side * 12
	_stamp(PREFAB_RACK, Vector3i(rack.x, col_h(rack.x, rack.y) + 1, rack.y), (hut_r + 1) % 4)
	# Boat entity (spawned by the boat system): near the dock end, bow toward open water.
	boat_spawns = [_find_mooring(dock_o, d, side)]
	var sp := Vector2i(best.x, best.z) + d * 24
	spawn_yaw = atan2(float(d.x), float(d.y))
	spawn = Vector3(sp.x + 0.5, col_h(sp.x, sp.y) + 2, sp.y + 0.5)
	print("[gen] boat spawn ", boat_spawns[0])
	print("[gen] %d islands; hut at %s facing %s, shore %d, spawn %s" % [islands.size(), origin, d, s0, spawn])


## Water deep enough for the hull at mid tide (keel ~0.6 m below the surface, plus margin).
func _is_open_water(x: int, z: int) -> bool:
	return col_h(x, z) < int(sea_mid) - 6


## Clear run (voxels) from (x, z) along unit heading `h`, through a corridor +-6 voxels wide.
func _clear_run(x: int, z: int, h: Vector2, max_len: int) -> int:
	var perp := Vector2(-h.y, h.x)
	for s in range(0, max_len, 2):
		for w in range(-6, 7, 3):
			var q := Vector2(x, z) + h * s + perp * w
			if not _is_open_water(int(q.x), int(q.y)):
				return s
	return max_len


## Pick a boat spawn near the dock end with ~8 m (44+ voxels) of clear water ahead.
func _find_mooring(dock_o: Vector2i, d: Vector2i, side: Vector2i) -> Dictionary:
	const NEED := 46
	var dock_end := dock_o + d * 32
	var base_h := atan2(float(d.x), float(d.y))
	var best := {}
	var best_score := INF
	for fwd in range(4, 60, 4):
		for lat in [0, 10, -10, 16, -16, 24, -24]:
			if lat == 0 and fwd < 8:
				continue  # right at the dock's tip
			var p: Vector2i = dock_end + d * fwd + side * lat
			# hull footprint (~1.4 x 3.6 m) must already be afloat
			var afloat := true
			for oz in range(-12, 13, 4):
				for ox in range(-6, 7, 3):
					if not _is_open_water(p.x + ox, p.y + oz):
						afloat = false
						break
				if not afloat:
					break
			if not afloat:
				continue
			for k in 16:
				var yaw := base_h + (k - 8) * TAU / 16.0
				var hv := Vector2(sin(yaw), cos(yaw))
				if _clear_run(p.x, p.y, hv, 64) < NEED:
					continue
				var score := fwd + absf(lat) * 1.5 + absf(k - 8) * 6.0
				if score < best_score:
					best_score = score
					best = {"pos": Vector3((p.x + 0.5) * VoxelWorld.VS, sea_mid * VoxelWorld.VS, (p.y + 0.5) * VoxelWorld.VS), "yaw": yaw}
	if best.is_empty():
		push_warning("[gen] no clear mooring found; using dock end")
		var p := dock_end + d * 8
		best = {"pos": Vector3((p.x + 0.5) * VoxelWorld.VS, sea_mid * VoxelWorld.VS, (p.y + 0.5) * VoxelWorld.VS), "yaw": base_h}
	return best
