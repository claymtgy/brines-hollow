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
## Validated player spawn points spread around the starter island:
## [{id: int, name: String, pos: Vector3, yaw: float, is_primary: bool}]
var starter_spawns: Array = []
## Boats to spawn as entities: [{pos: Vector3 (metres, water level), yaw: float}]
var boat_spawns: Array = []
## Lamp light positions (voxel coords) for stamped prefabs; VoxelWorld creates the lights.
var stamp_lights: Array = []
var islands: Array = []
## Starter-area layout for the village systems (voxel units):
## {hut: Vector3i origin, hut_r: int, front: Vector2i, side: Vector2i, dock_o: Vector2i, dock_y: int}
var starter := {}
## NPC villages on other islands (big archipelago only; see plan_villages):
## [{island, center, front, side, cottages: [{origin, door}], dock_end, field, spots: {role: Vector3}}]
## Positions are in voxel units (feet height for spots and doors).
var villages: Array = []


## `layout` holds the native layout parameters (VoxelWorld.layout_params); empty = layout 1.
func _init(p_seed: int, sx: int, sy: int, sz: int, p_sea_mid: float, tide_amp: float, layout: Dictionary = {}) -> void:
	seed_value = p_seed
	wx = sx; wy = sy; wz = sz
	sea_mid = p_sea_mid
	sea_low = int(p_sea_mid - tide_amp)
	sea_high = int(p_sea_mid + tide_amp)
	var mats := PackedByteArray([
		Palette.BEDROCK, Palette.STONE, Palette.SANDSTONE_A, Palette.SANDSTONE_B, Palette.SANDSTONE_C,
		Palette.SAND, Palette.WET_SAND, Palette.GRAVEL, Palette.DIRT, Palette.GRASS, Palette.GRASS_DRY,
		Palette.KELP, Palette.LEAVES, Palette.LEAVES_DARK, Palette.TRUNK, Palette.FLOWER_Y, Palette.FLOWER_P,
		Palette.DRIFTWOOD, Palette.GLOW_TEAL, Palette.COBBLE, Palette.DARK_WOOD,
		Palette.COPPER_VEIN, Palette.IRON_VEIN, Palette.TUFT_GRASS, Palette.TUFT_DRY])
	if not layout.is_empty():
		native.set_layout(layout)
	native.configure(p_seed, Vector3i(sx, sy, sz), p_sea_mid, tide_amp, mats)
	islands = native.get_islands()


## Cave chest spots from the native generator (layout 2+; empty for classic worlds).
func cave_sites() -> Array:
	return native.call("get_cave_sites") if native.has_method("get_cave_sites") else []


func _near_cave(x: int, z: int) -> bool:
	return native.has_method("cave_near") and bool(native.call("cave_near", x, z, 24))


static func is_grassy(k: int) -> bool:
	return k == Kind.GRASS or k == Kind.GRASS_DRY


func col_h(x: int, z: int) -> int:
	return native.column_height(x, z)


func col_k(x: int, z: int) -> int:
	return native.column_kind(x, z)


## Register a prefab as a generation stamp (same placement rules as VoxelWorld.apply_prefab).
func _stamp(id: int, origin: Vector3i, rot: int, lights := true) -> void:
	var pf := Prefabs.rotated(id, rot)
	var base: Vector3i = origin - (pf.anchor as Vector3i)
	var f := 0
	match pf.foundation:
		"solid": f = 1
		"posts": f = 2
	native.add_stamp(pf.data, pf.size, base, f)
	if lights:
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
		if _near_cave(x, z):
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
	starter = {"hut": origin, "hut_r": hut_r, "front": d, "side": side, "dock_o": dock_o, "dock_y": sea_high + 3}
	var sp := Vector2i(best.x, best.z) + d * 24
	spawn_yaw = atan2(float(d.x), float(d.y))
	spawn = Vector3(sp.x + 0.5, col_h(sp.x, sp.y) + 2, sp.y + 0.5)
	print("[gen] boat spawn ", boat_spawns[0])
	print("[gen] %d islands; hut at %s facing %s, shore %d, spawn %s" % [islands.size(), origin, d, s0, spawn])

	starter_spawns.clear()
	starter_spawns.append({
		"id": 0,
		"name": "Homestead Pier",
		"pos": spawn,
		"yaw": spawn_yaw,
		"is_primary": true
	})
	_generate_starter_spawns(home)


## Finds diverse, scenic, and safe coastal spawn points spread all around the starter island perimeter.
func _generate_starter_spawns(home: Dictionary) -> void:
	var hc: Vector2 = home.center
	var hr: float = home.radius
	var sector_names := [
		"East Shingle Beach",
		"South-East Tide Shallows",
		"South Sandspit",
		"South-West Kelp Cove",
		"West Driftwood Strand",
		"North-West Dunes",
		"North Pines Reach",
		"North-East Shell Bank",
		"East Meadow Point",
		"South Pebble Shore",
		"West Tidepool Terrace",
		"North Windward Ridge"
	]

	var total_sectors := 12
	for i in total_sectors:
		var ang := float(i) * TAU / float(total_sectors)
		var dir := Vector2(cos(ang), sin(ang))
		var best_cand := {}
		var min_diff := 999.0

		for r in range(int(hr * 0.25), int(hr * 0.75), 4):
			var x := int(hc.x + dir.x * r)
			var z := int(hc.y + dir.y * r)
			var h := col_h(x, z)
			var k := col_k(x, z)
			if h >= sea_high + 1 and (is_grassy(k) or k == Kind.BEACH):
				var diff := absf(h - (sea_high + 2))
				if diff < min_diff:
					min_diff = diff
					# Calculate yaw facing toward island center
					var to_center := (hc - Vector2(x, z)).normalized()
					var yaw := atan2(to_center.x, to_center.y)
					best_cand = {
						"id": starter_spawns.size(),
						"name": sector_names[i % sector_names.size()],
						"pos": Vector3(x + 0.5, h + 1, z + 0.5),
						"yaw": yaw,
						"is_primary": false
					}
					if diff <= 1.0:
						break
		if not best_cand.is_empty():
			var dist: float = (Vector2(best_cand.pos.x, best_cand.pos.z) - Vector2(spawn.x, spawn.z)).length()
			if dist > 30.0: # At least ~5.5m away from the primary hut
				starter_spawns.append(best_cand)

	print("[gen] registered %d diverse coastal starter spawns around home island" % starter_spawns.size())


## Returns a random spawn location from the diverse starter island spawns.
func get_random_spawn(rng_seed: int = -1) -> Dictionary:
	if starter_spawns.is_empty():
		return {"id": 0, "name": "Homestead Pier", "pos": spawn, "yaw": spawn_yaw, "is_primary": true}
	var rng := RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	return starter_spawns[rng.randi_range(0, starter_spawns.size() - 1)]


## Returns a distinct distributed spawn for a multiplayer peer or local player.
func get_spawn_for_player(peer_id: int) -> Dictionary:
	if starter_spawns.is_empty():
		return {"id": 0, "name": "Homestead Pier", "pos": spawn, "yaw": spawn_yaw, "is_primary": true}
	if peer_id <= 0:
		# Single player: randomize around starter island
		return get_random_spawn()
	elif peer_id == 1:
		# Host / Player 1: choose random or primary
		return starter_spawns[0]
	else:
		# Distribute peer IDs across distinct sectors around the starter island
		var total := starter_spawns.size()
		var step := maxi(2, total / 4)
		var idx := posmod(1 + (peer_id - 1) * step, total)
		return starter_spawns[idx]


func get_spawn_by_index(idx: int) -> Dictionary:
	if starter_spawns.is_empty():
		return {"id": 0, "name": "Homestead Pier", "pos": spawn, "yaw": spawn_yaw, "is_primary": true}
	return starter_spawns[posmod(idx, starter_spawns.size())]


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


# ---------------------------------------------------------------- NPC villages

## Village sites prefer gentle ground: meadow, hills, atoll, mesa, crags.
const _VILLAGE_STYLE_PREF := {0: 0, 2: 1, 1: 2, 4: 3, 3: 4}
const _DIRS4 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


## Plan up to `max_villages` fishing villages on the larger islands (not the home island):
## cottages, a pier, lamps, a drying rack and a wheat field, stamped into the terrain.
## Pure function of the seed, so every peer plans the same villages. Call once, after
## plan_starter and before any chunk is generated.
func plan_villages(max_villages := 3) -> void:
	villages.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 11
	var order: Array = []
	for i in islands.size():
		if int(islands[i].type) == 1:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var pa: int = _VILLAGE_STYLE_PREF.get(int(islands[a].style), 5)
		var pb: int = _VILLAGE_STYLE_PREF.get(int(islands[b].style), 5)
		return pa < pb or (pa == pb and a < b))
	for i: int in order:
		if villages.size() >= max_villages:
			break
		var site := _find_village_site(rng, islands[i])
		if site.is_empty():
			continue
		var v := _build_village(site, i)
		if not v.is_empty():
			villages.append(v)
	print("[gen] %d NPC villages planned" % villages.size())


func _find_village_site(rng: RandomNumberGenerator, isl: Dictionary) -> Dictionary:
	var hc: Vector2 = isl.center
	var hr: float = isl.radius
	var best := {}
	for attempt in 2500:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(0.30, 0.64) * hr
		var x := int(hc.x + cos(ang) * rad)
		var z := int(hc.y + sin(ang) * rad)
		var h := col_h(x, z)
		if h < sea_high + 1 or h > sea_high + 18:
			continue
		var k0 := col_k(x, z)
		if not is_grassy(k0) and k0 != Kind.BEACH:
			continue
		if _near_cave(x, z):
			continue
		var lo := 999
		var hi := -999
		var ok := true
		for dz in range(-30, 31, 6):
			for dx in range(-30, 31, 6):
				var hh := col_h(x + dx, z + dz)
				lo = mini(lo, hh)
				hi = maxi(hi, hh)
				if hi - lo > 12:
					ok = false
					break
			if not ok:
				break
		if not ok or lo < sea_high:
			continue
		for di in 4:
			var d: Vector2i = _DIRS4[di]
			for s in range(20, 120, 2):
				var ph := col_h(x + d.x * s, z + d.y * s)
				if ph > hi + 4:
					break
				if ph < sea_low - 1:
					var wet := 0
					for t in range(s, s + 160, 8):
						if col_h(x + d.x * t, z + d.y * t) < int(sea_mid) - 5:
							wet += 1
					if wet < 19:
						break
					var score := s + (hi - lo) * 2
					if best.is_empty() or score < best.score:
						best = {"x": x, "z": z, "dir": d, "r": di, "score": score}
					break
		if not best.is_empty() and best.score < 45:
			break
	return best


## Footprint (lo, hi) of the ground under a 26 x 20 cottage centred on p.
func _footprint(p: Vector2i) -> Vector2i:
	var lo := 999
	var hi := -999
	for dz in range(-12, 13, 4):
		for dx in range(-12, 13, 4):
			var hh := col_h(p.x + dx, p.y + dz)
			lo = mini(lo, hh)
			hi = maxi(hi, hh)
	return Vector2i(lo, hi)


func _feet(p: Vector2i) -> Vector3:
	return Vector3(p.x + 0.5, col_h(p.x, p.y) + 1, p.y + 0.5)


func _build_village(site: Dictionary, island_idx: int) -> Dictionary:
	var d: Vector2i = site.dir
	var side := Vector2i(-d.y, d.x)
	var r: int = site.r
	var c := Vector2i(site.x, site.z)
	# Cottages around a little square, all facing the sea.
	var homes: Array = []
	for off: Vector2i in [Vector2i(0, 0), Vector2i(0, -32), Vector2i(0, 32), Vector2i(-30, -16), Vector2i(-30, 16)]:
		var p: Vector2i = c + d * off.x + side * off.y
		var fp := _footprint(p)
		if fp.y - fp.x > 8 or fp.x < sea_high or _near_cave(p.x, p.y):
			continue
		homes.append({"origin": Vector3i(p.x, fp.y + 1, p.y), "door": _feet(p + d * 14)})
	if homes.size() < 3:
		return {}
	# Pier: from the shoreline out to sea, like the home pier.
	var s0 := -1
	for s in range(14, 140):
		if col_h(c.x + d.x * s, c.y + d.y * s) <= sea_high:
			s0 = s
			break
	if s0 < 0:
		return {}
	for hm: Dictionary in homes:
		_stamp(PREFAB_HUT, hm.origin, r, false)
	var dock_r: int = {Vector2i(0, 1): 0, Vector2i(-1, 0): 1, Vector2i(0, -1): 2, Vector2i(1, 0): 3}[d]
	var dock_o := c + d * (s0 - 2)
	_stamp(PREFAB_DOCK, Vector3i(dock_o.x, sea_high + 3, dock_o.y), dock_r, false)
	for lp: Vector2i in [c + d * 20 + side * 16, c + d * 20 - side * 16, dock_o + side * 7]:
		_stamp(PREFAB_LAMP, Vector3i(lp.x, col_h(lp.x, lp.y) + 1, lp.y), 0, false)
	var rack := c + d * 22 + side * 26
	_stamp(PREFAB_RACK, Vector3i(rack.x, col_h(rack.x, rack.y) + 1, rack.y), (r + 1) % 4, false)
	# Wheat field behind the cottages: rows of ripe wheat on tilled earth, grass paths between.
	var f := c - d * 60
	var cells: Array = []
	for a in range(-7, 8):
		for b in range(-10, 11):
			var p: Vector2i = f + d * a + side * b
			var h := col_h(p.x, p.y)
			if h < sea_high + 1 or not is_grassy(col_k(p.x, p.y)) or _near_cave(p.x, p.y):
				continue
			cells.append([p, h, posmod(b, 3) == 2])
	var field := Vector3.INF
	if cells.size() >= 200:
		var row := PackedByteArray([Palette.DIRT, Palette.TUFT_DRY])
		for cl: Array in cells:
			if not cl[2]:
				native.add_stamp(row, Vector3i(1, 2, 1), Vector3i(cl[0].x, cl[1], cl[0].y), 0)
		field = _feet(f)
	var dock_end := Vector3(dock_o.x + d.x * 26 + 0.5, sea_high + 4, dock_o.y + d.y * 26 + 0.5)
	var spots := {
		"trader": _feet(c + d * 24 + side * 8),
		"elder": _feet(c + d * 24 - side * 8),
		"fisher": dock_end,
		"mender": _feet(rack + d * 4),
		"farmer": field if field != Vector3.INF else _feet(c + d * 30),
	}
	return {"island": island_idx, "center": _feet(c + d * 24), "front": d, "side": side,
		"cottages": homes, "dock_end": dock_end, "field": field, "spots": spots}

