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
## Mud-Claw camps on the outer islands (big archipelago only; see plan_camps), voxel units:
## [{island, center: Vector3 (feet), chest: Vector3i, gate: Vector2, domes: [Vector3 feet]}]
var camps: Array = []


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
	_place_lighthouse(Vector2i(best.x, best.z), d, side, dock_o, rack, lamp)
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


## A lighthouse on the coast near the starter hut: on the highest open spot close to the
## water, clear of the hut, pier and yard. Its footprint stays inside one 32-voxel terrain
## column, so a column the player has already built in (which keeps its saved voxels) either
## has the whole lighthouse or none of it. Sets starter.lighthouse (the lantern, in voxels).
const LH_R := 7          # footprint half-width (15 x 15 plinth)
const LH_H := 80         # plinth to the weather vane (~14 m)
const LH_LAMP_Y := 68    # lantern room centre, above the base


func _place_lighthouse(hut: Vector2i, d: Vector2i, side: Vector2i, dock_o: Vector2i, rack: Vector2i, lamp: Vector2i) -> void:
	var avoid: Array = [[hut, 30], [rack, 14], [lamp, 12], [hut + d * 24, 12]]
	for k in range(-4, 36, 4):
		avoid.append([dock_o + d * k, 14])
	var best := _lighthouse_search(hut, avoid, 170, 7, 28, sea_high + 1)
	if best.is_empty():
		# Small or steep home islands (the classic map): look further and accept rougher
		# ground; a rubble foundation fills in under the plinth.
		best = _lighthouse_search(hut, avoid, 260, 16, 44, sea_high - 1)
	if best.is_empty():
		print("[gen] no lighthouse site near the hut")
		return
	var c: Vector2i = best.c
	if int(best.y) - int(best.lo) > 1:
		var fh: int = int(best.y) - int(best.lo) + 1
		var fg := Prefabs.Grid.new(LH_R * 2 + 1, fh, LH_R * 2 + 1)
		for z in LH_R * 2 + 1:
			for x in LH_R * 2 + 1:
				for y in fh:
					fg.setv(x, y, z, Palette.COBBLE if (x + y + z) % 3 != 0 else Palette.STONE)
		native.add_stamp(fg.data, Vector3i(LH_R * 2 + 1, fh, LH_R * 2 + 1), Vector3i(c.x - LH_R, int(best.lo) - 1, c.y - LH_R), 1)
	var base := Vector3i(c.x - LH_R, int(best.y), c.y - LH_R)
	var toward := Vector2(hut - c).normalized()
	native.add_stamp(_lighthouse_grid(toward), Vector3i(LH_R * 2 + 1, LH_H, LH_R * 2 + 1), base, 1)
	var lantern := base + Vector3i(LH_R, LH_LAMP_Y, LH_R)
	stamp_lights.append(lantern)
	starter["lighthouse"] = lantern
	print("[gen] lighthouse at %s (%.0f m from the hut)" % [lantern, Vector2(c - hut).length() * 0.18])


func _lighthouse_search(hut: Vector2i, avoid: Array, max_r: int, rough: int, max_coast: int, min_lo: int) -> Dictionary:
	var best := {}
	for r in range(40, max_r, 6):
		for k in 48:
			var a := TAU * k / 48.0
			var c := hut + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			# keep the whole footprint inside one terrain column
			var lx := posmod(c.x, 32)
			var lz := posmod(c.y, 32)
			c += Vector2i(clampi(lx, LH_R + 1, 30 - LH_R) - lx, clampi(lz, LH_R + 1, 30 - LH_R) - lz)
			var bad := false
			for av: Array in avoid:
				if Vector2(c - (av[0] as Vector2i)).length() < float(av[1]):
					bad = true
					break
			if bad or _near_cave(c.x, c.y):
				continue
			var lo := 999
			var hi := -999
			for dz in range(-LH_R, LH_R + 1, 2):
				for dx in range(-LH_R, LH_R + 1, 2):
					var h := col_h(c.x + dx, c.y + dz)
					lo = mini(lo, h)
					hi = maxi(hi, h)
			if lo < min_lo or hi - lo > rough or hi > sea_high + 45:
				continue
			# on the coast: open water within ~5 m
			var coast := 99
			for j in 16:
				var dir := Vector2(cos(TAU * j / 16.0), sin(TAU * j / 16.0))
				for t in range(LH_R + 2, 30, 2):
					var q := c + Vector2i(roundi(dir.x * t), roundi(dir.y * t))
					if col_h(q.x, q.y) < sea_low:
						coast = mini(coast, t)
						break
			if coast > max_coast:
				continue
			var score := float(hi) * 1.0 - float(coast) * 0.4 - float(r) * 0.05 - float(hi - lo) * 0.5
			if best.is_empty() or score > best.score:
				best = {"c": c, "y": hi + 1, "lo": lo, "score": score}
	return best


## Whitewashed round tower with red bands, a door facing the hut, a gallery, a glazed
## lantern room with the light, and a red cap.
static func _lighthouse_grid(door_dir: Vector2) -> PackedByteArray:
	var n := LH_R * 2 + 1
	var g := Prefabs.Grid.new(n, LH_H, n)
	var cx := LH_R
	g.box(0, 0, 0, n - 1, 2, n - 1, Palette.COBBLE)                       # plinth
	var top := LH_LAMP_Y - 5                                               # gallery floor
	for y in range(3, top):
		var t := float(y - 3) / float(top - 3)
		var ro := lerpf(5.6, 3.9, t)
		var band := ((y - 3) / 9) % 2 == 1
		for z in n:
			for x in n:
				var dd := Vector2(x - cx, z - cx).length()
				if dd <= ro and dd > ro - 1.3:
					g.setv(x, y, z, Palette.ROOF_RED if band else Palette.WHITEWASH)
				elif dd <= ro - 1.3:
					g.setv(x, y, z, Palette.CLEAR)                     # hollow inside
	# door facing the hut, and a few small windows up the tower
	var dx := roundi(door_dir.x * 5.0)
	var dz := roundi(door_dir.y * 5.0)
	for y in range(3, 3 + 13):
		for w in range(-2, 3):
			var px := cx + dx + (w if absi(dz) >= absi(dx) else 0)
			var pz := cx + dz + (w if absi(dx) > absi(dz) else 0)
			g.setv(px, y, pz, Palette.CLEAR)
			g.setv(cx + roundi(door_dir.x * 4.0) + (w if absi(dz) >= absi(dx) else 0), y, cx + roundi(door_dir.y * 4.0) + (w if absi(dx) > absi(dz) else 0), Palette.CLEAR)
	for wy in [24, 40, 54]:
		g.setv(cx - roundi(door_dir.x * 4.6), wy, cx - roundi(door_dir.y * 4.6), Palette.SHUTTER)
	# gallery: a wooden deck all round with a metal rail
	for z in n:
		for x in n:
			var dd := Vector2(x - cx, z - cx).length()
			if dd <= 6.6:
				g.setv(x, top, z, Palette.DARK_WOOD)
			if dd <= 6.6 and dd > 5.7:
				g.setv(x, top + 1, z, Palette.METAL)
				if (x + z) % 2 == 0:
					g.setv(x, top + 2, z, Palette.METAL)
	# lantern room: corner posts, the great lamp, a red cap and a vane
	for y in range(top + 1, LH_LAMP_Y + 5):
		for p: Vector2i in [Vector2i(-3, -3), Vector2i(3, -3), Vector2i(-3, 3), Vector2i(3, 3)]:
			g.setv(cx + p.x, y, cx + p.y, Palette.DARK_WOOD)
	g.box(cx - 1, LH_LAMP_Y - 2, cx - 1, cx + 1, LH_LAMP_Y + 2, cx + 1, Palette.LANTERN)
	g.box(cx - 2, top + 1, cx - 2, cx + 2, top + 2, cx + 2, Palette.METAL)  # lamp pedestal
	for y in range(LH_LAMP_Y + 5, LH_H - 3):
		var rr := 4.6 * (1.0 - float(y - (LH_LAMP_Y + 5)) / float(LH_H - 3 - (LH_LAMP_Y + 5)))
		for z in n:
			for x in n:
				if Vector2(x - cx, z - cx).length() <= rr + 0.3:
					g.setv(x, y, z, Palette.ROOF_RED)
	g.box(cx, LH_H - 3, cx, cx, LH_H - 1, cx, Palette.METAL)
	g.setv(cx + 1, LH_H - 2, cx, Palette.METAL)
	return g.data


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



# ---------------------------------------------------------------- Mud-Claw camps

const CAMP_R := 34              # palisade radius (voxels, ~6 m)
const CAMP_H := 30              # stamp height: floor + the carved space above it
const CAMP_MIN_HOME := 1670     # ~300 m: never this close to the starter hut
const CAMP_MIN_VILLAGE := 420   # ~75 m from any NPC village


## Plan up to `max_camps` Mud-Claw camps: a driftwood palisade round three mud domes, a
## shell totem and a firepit, on a flat patch near the shore of an outer island. Never on
## the home island and never within CAMP_MIN_HOME of the starter hut. Pure function of the
## seed (every peer plans the same camps). Call after plan_villages, before any chunk.
func plan_camps(max_camps := 4) -> void:
	camps.clear()
	if starter.is_empty():
		return
	var hut := Vector2(starter.hut.x, starter.hut.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 104729 + 23
	var village_islands := {}
	for v: Dictionary in villages:
		village_islands[int(v.island)] = true
	var order: Array = []
	for i in islands.size():
		if i == 0 or int(islands[i].type) == 0 or village_islands.has(i):
			continue
		var c: Vector2 = islands[i].center
		if c.distance_to(hut) < CAMP_MIN_HOME:
			continue
		order.append(i)
	# nearest first, so the first camp a player meets is a sail away rather than across the map
	order.sort_custom(func(a: int, b: int) -> bool:
		return (islands[a].center as Vector2).distance_to(hut) < (islands[b].center as Vector2).distance_to(hut))
	for i: int in order:
		if camps.size() >= max_camps:
			break
		var site := _find_camp_site(rng, i, hut)
		if site.is_empty():
			continue
		camps.append(_build_camp(site, i, rng))
	print("[gen] %d Mud-Claw camps planned" % camps.size())


func _find_camp_site(rng: RandomNumberGenerator, island_idx: int, hut: Vector2) -> Dictionary:
	var isl: Dictionary = islands[island_idx]
	var hc: Vector2 = isl.center
	var hr: float = isl.radius
	var best := {}
	for attempt in 700:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(0.15, 0.7) * hr
		var x := int(hc.x + cos(ang) * rad)
		var z := int(hc.y + sin(ang) * rad)
		if Vector2(x, z).distance_to(hut) < CAMP_MIN_HOME + CAMP_R:
			continue
		var h := col_h(x, z)
		if h < sea_high + 2 or h > sea_high + 40:
			continue
		var k0 := col_k(x, z)
		if not is_grassy(k0) and k0 != Kind.BEACH:
			continue
		if _near_cave(x, z):
			continue
		var near_village := false
		for v: Dictionary in villages:
			if Vector2(v.center.x, v.center.z).distance_to(Vector2(x, z)) < CAMP_MIN_VILLAGE:
				near_village = true
		if near_village:
			continue
		var lo := 999
		var hi := -999
		var ok := true
		for dz in range(-CAMP_R, CAMP_R + 1, 6):
			for dx in range(-CAMP_R, CAMP_R + 1, 6):
				if dx * dx + dz * dz > CAMP_R * CAMP_R:
					continue
				var hh := col_h(x + dx, z + dz)
				lo = mini(lo, hh)
				hi = maxi(hi, hh)
				if hi - lo > 6:
					ok = false
					break
			if not ok:
				break
		if not ok or lo < sea_high + 1:
			continue
		# the gate faces the nearest shore
		for k in 8:
			var a := TAU * k / 8.0
			var dir := Vector2(cos(a), sin(a))
			for s in range(CAMP_R, CAMP_R + 110, 3):
				var p := Vector2(x, z) + dir * s
				if col_h(int(p.x), int(p.y)) < sea_low:
					var score := float(s) * 0.2 + (hi - lo) * 3.0
					if best.is_empty() or score < best.score:
						best = {"x": x, "z": z, "y": int(round((lo + hi) * 0.5)), "gate": dir, "score": score}
					break
		if not best.is_empty() and best.score < 12.0:
			break
	return best


func _build_camp(site: Dictionary, island_idx: int, rng: RandomNumberGenerator) -> Dictionary:
	var c := Vector2i(site.x, site.z)
	var fy: int = site.y
	var g: Vector2 = site.gate
	var n := CAMP_R * 2 + 5
	var o := CAMP_R + 2                       # grid centre
	var grid := Prefabs.Grid.new(n, CAMP_H, n)
	var ga := atan2(g.y, g.x)
	# trampled mud floor, carved clear above (bumps, grass and bushes go)
	for z in n:
		for x in n:
			var dd := Vector2(x - o, z - o).length()
			if dd > CAMP_R + 1.5:
				continue
			var mud := Palette.WET_SAND if (hash(Vector2i(x, z) + c) & 7) < 3 else Palette.DIRT
			if dd > CAMP_R - 3 and (hash(Vector2i(z, x) + c) & 3) == 0:
				mud = Palette.GRAVEL
			grid.setv(x, 0, z, mud)
			for y in range(1, CAMP_H):
				grid.setv(x, y, z, Palette.CLEAR)
	# driftwood palisade with a gate towards the shore and a couple of broken gaps
	for z in n:
		for x in n:
			var v := Vector2(x - o, z - o)
			var dd := v.length()
			if dd < CAMP_R - 0.8 or dd > CAMP_R + 0.8:
				continue
			var a := atan2(v.y, v.x)
			if absf(angle_difference(a, ga)) < 0.12:
				continue                                  # the gate
			var post := int(floor((a + PI) * CAMP_R / 1.7))
			var ph := 9 + posmod(hash(post * 31 + c.x), 6)
			if posmod(hash(post * 17 + c.y), 23) == 0:
				ph = 3                                    # a broken stake
			var wood := Palette.TRUNK if posmod(hash(post * 7 + c.x * 3), 3) != 0 else Palette.DRIFTWOOD
			for y in range(1, ph + 1):
				grid.setv(x, y, z, wood)
			grid.setv(x, 5, z, Palette.DARK_WOOD)         # lashing
			if ph > 6 and post % 2 == 0:
				grid.setv(x, ph + 1, z, Palette.SANDSTONE_B)   # a pale point
	# gate posts: taller, capped with shells
	for side: int in [-1, 1]:
		var a := ga + 0.14 * side
		var px := o + roundi(cos(a) * CAMP_R)
		var pz := o + roundi(sin(a) * CAMP_R)
		for y in range(1, 15):
			grid.setv(px, y, pz, Palette.DARK_WOOD)
		grid.setv(px, 15, pz, Palette.SANDSTONE_C)
		grid.setv(px, 16, pz, Palette.BUOY)
	# three mud domes round the back, doors facing the middle
	var domes: Array = []
	for k: int in [-1, 0, 1]:
		var a := ga + PI + 0.95 * k
		var dc := Vector2(cos(a), sin(a)) * (CAMP_R - 12)
		var cx := o + roundi(dc.x)
		var cz := o + roundi(dc.y)
		var rad := 7.5 if k == 0 else 6.5
		var into := -dc.normalized()
		for z in range(cz - 9, cz + 10):
			for x in range(cx - 9, cx + 10):
				for y in range(1, 10):
					var e := Vector3(x - cx, (y - 1) / 0.8, z - cz).length()
					if e > rad:
						continue
					var dv := Vector2(x - cx, z - cz)
					var door := y <= 4 and dv.length() > 0.1 and dv.normalized().dot(into) > 0.82
					if e > rad - 1.4 and not door:
						var m := Palette.DIRT
						if y % 3 == 0:
							m = Palette.WET_SAND
						elif posmod(hash(Vector3i(x, y, z) + Vector3i(c.x, 0, c.y)), 11) == 0:
							m = Palette.KELP          # weed thatch
						grid.setv(x, y, z, m)
		domes.append(Vector3(c.x + cx - o + 0.5, fy + 1, c.y + cz - o + 0.5))
	# the shell totem behind the chest: banded shell, two raised claws, glowing eyes
	var tv := -g * 12.0
	var tx := o + roundi(tv.x)
	var tz := o + roundi(tv.y)
	var bands := [Palette.SANDSTONE_C, Palette.BUOY, Palette.ROOF_RED, Palette.SANDSTONE_C]
	for y in range(1, 17):
		for dz in 2:
			for dx in 2:
				grid.setv(tx + dx, y, tz + dz, bands[(y / 3) % bands.size()])
	var side := Vector2(-g.y, g.x)
	for s: int in [-1, 1]:
		for t in 5:
			var sx := tx + roundi(side.x * s * (2 + t * 0.5))
			var sz := tz + roundi(side.y * s * (2 + t * 0.5))
			grid.setv(sx, 13 + t, sz, Palette.ROOF_RED)
		grid.setv(tx + roundi(side.x * s * 3.0 + g.x), 18, tz + roundi(side.y * s * 3.0 + g.y), Palette.BUOY)
	grid.setv(tx + roundi(g.x * 1.6), 12, tz + roundi(g.y * 1.6), Palette.GLOW_TEAL)
	grid.setv(tx + 1 + roundi(g.x * 1.6), 12, tz + 1 + roundi(g.y * 1.6), Palette.GLOW_TEAL)
	# firepit towards the gate: a cobble ring round smouldering embers and charred logs
	var fv := g * 9.0
	var fx := o + roundi(fv.x)
	var fz := o + roundi(fv.y)
	for z in range(fz - 3, fz + 4):
		for x in range(fx - 3, fx + 4):
			var dd := Vector2(x - fx, z - fz).length()
			if dd <= 3.2 and dd > 2.1:
				grid.setv(x, 1, z, Palette.COBBLE)
			elif dd <= 1.2:
				grid.setv(x, 1, z, Palette.LANTERN)
	grid.setv(fx - 1, 2, fz, Palette.DARK_WOOD)
	grid.setv(fx + 1, 2, fz, Palette.DARK_WOOD)
	grid.setv(fx, 2, fz - 1, Palette.DARK_WOOD)
	# shell middens: what the claws pick off the reef
	for k in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(6.0, CAMP_R - 3.0)
		var mx := o + roundi(cos(a) * r)
		var mz := o + roundi(sin(a) * r)
		if grid.getv(mx, 1, mz) == Palette.CLEAR:
			grid.setv(mx, 1, mz, [Palette.SANDSTONE_C, Palette.BUOY, Palette.SANDSTONE_B][k % 3])
	var base := Vector3i(c.x - o, fy, c.y - o)
	native.add_stamp(grid.data, Vector3i(n, CAMP_H, n), base, 1)
	if native.has_method("add_tree_clear"):
		native.add_tree_clear(c.x, c.y, CAMP_R + 14)   # no half-carved trees: crowns reach ~12
	var cv := -g * 6.0
	var chest := Vector3i(c.x + roundi(cv.x), fy + 1, c.y + roundi(cv.y))
	return {"island": island_idx, "center": Vector3(c.x + 0.5, fy + 1, c.y + 0.5), "chest": chest,
		"gate": g, "domes": domes}


# ---------------------------------------------------------------- brass mines, sumps, springs

const MINE_GR := 11            # gallery radius (voxels)
const MINE_TW := 3             # adit half-width
const MINE_TH := 12            # adit height to the lintel (11 clear: the player is 9)
## Old brass mines: [{island, entrance: Vector3 (feet), dir: Vector2i, gallery: Vector3i, chest: Vector3i}]
var mines: Array = []
## Flooded sumps under karst caverns: [{top: Vector3i, chest: Vector3i, depth: int}]
var sumps: Array = []
## Freshwater springs on karst cavern floors (voxel positions)
var springs: Array = []


## Plan the rest of the underground (big archipelago): up to three abandoned brass mines
## driven into hillsides on the outer islands (timbered adits, a gallery crusted with
## calamine and copper), and for each karst cavern a flooded sump below its floor (a shaft
## and a drowned passage to a chamber with a cache) and a freshwater spring. Pure function
## of the seed. Never on the home island. Call after plan_camps, before any chunk.
func plan_underground(max_mines := 3) -> void:
	mines.clear()
	sumps.clear()
	springs.clear()
	if starter.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 15485863 + 41
	var hut := Vector2(starter.hut.x, starter.hut.z)
	var avoid: Array = []
	for v: Dictionary in villages:
		avoid.append([Vector2(v.center.x, v.center.z), 300.0])
	for c: Dictionary in camps:
		avoid.append([Vector2(c.center.x, c.center.z), 200.0])
	var order: Array = []
	for i in islands.size():
		if i != 0 and int(islands[i].type) == 1:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return (islands[a].center as Vector2).distance_to(hut) < (islands[b].center as Vector2).distance_to(hut))
	for i: int in order:
		if mines.size() >= max_mines:
			break
		var site := _find_mine_site(rng, i, avoid)
		if not site.is_empty():
			mines.append(_build_mine(site, i))
			avoid.append([Vector2(site.x, site.z), 160.0])
	for s: Dictionary in cave_sites():
		if int(s.kind) != 1:
			continue
		var sp := _plan_sump(rng, s.pos)
		if not sp.is_empty():
			sumps.append(sp)
	print("[gen] %d brass mines, %d flooded sumps, %d springs planned" % [mines.size(), sumps.size(), springs.size()])


func _find_mine_site(rng: RandomNumberGenerator, island_idx: int, avoid: Array) -> Dictionary:
	var isl: Dictionary = islands[island_idx]
	var hc: Vector2 = isl.center
	var hr: float = isl.radius
	for attempt in 900:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(0.2, 0.85) * hr
		var x := int(hc.x + cos(ang) * rad)
		var z := int(hc.y + sin(ang) * rad)
		var h0 := col_h(x, z)
		if h0 < sea_high + 3 or h0 > sea_high + 70:
			continue
		var bad := false
		for av: Array in avoid:
			if Vector2(x, z).distance_to(av[0]) < float(av[1]):
				bad = true
		if bad:
			continue
		var d0 := rng.randi_range(0, 3)
		for k in 4:
			var d: Vector2i = _DIRS4[(d0 + k) % 4]
			var p := Vector2i(x, z)
			# an open hillside face in front of the adit...
			if col_h(p.x - d.x * 4, p.y - d.y * 4) > h0 + 1 or col_h(p.x - d.x * 8, p.y - d.y * 8) > h0 + 2:
				continue
			# ...and a hill to drive into: rock over the adit, more over the gallery
			var length := -1
			for L in range(30, 64, 4):
				var ok := true
				for s in range(14, L + 1, 4):
					var q := p + d * s
					if col_h(q.x, q.y) < h0 + MINE_TH + 4 or _near_cave(q.x, q.y):
						ok = false
						break
				if not ok:
					break
				var g := p + d * (L + MINE_GR)
				var roof := true
				for t in 9:
					var a := TAU * t / 8.0
					var rr := 0.0 if t == 8 else float(MINE_GR + 2)
					var q := g + Vector2i(roundi(cos(a) * rr), roundi(sin(a) * rr))
					if col_h(q.x, q.y) < h0 + 22 or _near_cave(q.x, q.y):
						roof = false
						break
				if roof:
					length = L
					break
			if length > 0:
				return {"x": x, "z": z, "y": h0, "dir": d, "len": length}
	return {}


func _build_mine(site: Dictionary, island_idx: int) -> Dictionary:
	var d: Vector2i = site.dir
	var perp := Vector2i(absi(d.y), absi(d.x))
	var L: int = site.len
	var W := MINE_GR * 2 + 5
	var c := W / 2
	var Lt := L + MINE_GR * 2 + 3
	var H := MINE_GR + 9
	var e := Vector2i(site.x, site.z)
	var h0: int = site.y
	var sx := Lt if d.x != 0 else W
	var sz := W if d.x != 0 else Lt
	var minx := e.x + mini(0, d.x * (Lt - 1)) - perp.x * c
	var minz := e.y + mini(0, d.y * (Lt - 1)) - perp.y * c
	var grid := Prefabs.Grid.new(sx, H, sz)
	var put := func(u: int, y: int, v: int, m: int) -> void:
		grid.setv(e.x + d.x * v + perp.x * (u - c) - minx, y, e.y + d.y * v + perp.y * (u - c) - minz, m)
	# the adit: square-cut, gravel floor with two rail lines, a timber frame every 6
	for v in range(0, L + 2):
		for u in range(c - MINE_TW, c + MINE_TW + 1):
			put.call(u, 0, v, Palette.DARK_WOOD if absi(u - c) == 2 else Palette.GRAVEL)
			for y in range(1, MINE_TH + 1):
				put.call(u, y, v, Palette.CLEAR)
		if v % 6 == 1:
			for y in range(1, MINE_TH + 1):
				put.call(c - MINE_TW, y, v, Palette.DARK_WOOD)
				put.call(c + MINE_TW, y, v, Palette.DARK_WOOD)
			for u in range(c - MINE_TW, c + MINE_TW + 1):
				put.call(u, MINE_TH, v, Palette.DARK_WOOD)
			if v % 12 == 7:
				put.call(c, MINE_TH - 1, v, Palette.LANTERN)
	# the portal: heavier timbers and a lintel
	for y in range(1, MINE_TH + 3):
		put.call(c - MINE_TW - 1, y, 0, Palette.TRUNK)
		put.call(c + MINE_TW + 1, y, 0, Palette.TRUNK)
	for u in range(c - MINE_TW - 2, c + MINE_TW + 3):
		put.call(u, MINE_TH + 1, 0, Palette.TRUNK)
		put.call(u, MINE_TH + 2, 0, Palette.DARK_WOOD)
	# the gallery: a domed chamber, its walls crusted with calamine and copper
	var gv := L + MINE_GR + 1
	for v in range(gv - MINE_GR - 2, gv + MINE_GR + 3):
		for u in range(0, W):
			for y in range(0, H):
				var ell := Vector3(u - c, (y - 1) * 0.75, v - gv).length()
				if ell <= MINE_GR and y >= 1:
					put.call(u, y, v, Palette.CLEAR)
				elif y == 0 and Vector2(u - c, v - gv).length() <= MINE_GR:
					put.call(u, y, v, Palette.GRAVEL)
				elif ell <= MINE_GR + 1.6 and y >= 1:
					var hv := posmod(hash(Vector3i(u, y, v) + Vector3i(e.x, h0, e.y)), 100)
					if hv < 24:
						put.call(u, y, v, Palette.CALAMINE)
					elif hv < 40:
						put.call(u, y, v, Palette.COPPER_VEIN)
	# pit props, lamps, and an ore cart left half full
	for pp: Vector2i in [Vector2i(-5, -4), Vector2i(5, -4), Vector2i(-5, 5), Vector2i(5, 5)]:
		for y in range(1, 16):
			put.call(c + pp.x, y, gv + pp.y, Palette.DARK_WOOD)
		put.call(c + pp.x, 11, gv + pp.y + (1 if pp.y < 0 else -1), Palette.LANTERN)
	for u in range(c - 2, c + 3):
		for v in range(gv - MINE_GR + 2, gv - MINE_GR + 6):
			put.call(u, 1, v, Palette.METAL if absi(u - c) == 2 else Palette.DARK_WOOD)
			var rim := absi(u - c) == 2 or v == gv - MINE_GR + 2 or v == gv - MINE_GR + 5
			put.call(u, 2, v, Palette.DARK_WOOD if rim else Palette.CALAMINE)
	native.add_stamp(grid.data, Vector3i(sx, H, sz), Vector3i(minx, h0, minz), 0)
	if native.has_method("add_tree_clear"):
		native.add_tree_clear(e.x - d.x * 16, e.y - d.y * 16, 34)   # keep the approach to the portal clear
	var g2 := e + d * gv
	var chest := Vector3i(g2.x + perp.x * 4 + d.x * 6, h0 + 1, g2.y + perp.y * 4 + d.y * 6)
	return {"island": island_idx, "entrance": Vector3(e.x + 0.5, h0 + 1, e.y + 0.5), "dir": d,
		"gallery": Vector3i(g2.x, h0 + 1, g2.y), "chest": chest}


## Below a karst cavern's first chamber: a shaft down past the lowest tide, a drowned passage,
## and a flooded chamber with a cache. Also notes a spring on the cavern floor.
func _plan_sump(rng: RandomNumberGenerator, site: Vector3i) -> Dictionary:
	var floor_y := sea_high + 3
	var a := rng.randf() * TAU
	var dir := Vector2(cos(a), sin(a))
	var shaft := Vector2(site.x, site.z) + dir * 6.0
	var bot := sea_low - 12
	var pass_len := 14.0
	var ch := shaft + dir * (pass_len + 7.0)
	springs.append(Vector3i(roundi(site.x - dir.x * 9.0), site.y, roundi(site.z - dir.y * 9.0)))
	# buried deep enough the whole way (no breaking out into the sea)
	for t in 12:
		var q := shaft.lerp(ch + dir * 8.0, t / 11.0)
		if col_h(int(q.x), int(q.y)) < sea_high + 8:
			return {}
	var lo := Vector2i(int(minf(shaft.x, ch.x)) - 10, int(minf(shaft.y, ch.y)) - 10)
	var hi := Vector2i(int(maxf(shaft.x, ch.x)) + 11, int(maxf(shaft.y, ch.y)) + 11)
	var y0 := bot - 7
	var y1 := floor_y + 2
	var g := Prefabs.Grid.new(hi.x - lo.x, y1 - y0, hi.y - lo.y)
	for z in g.sz:
		for x in g.sx:
			var w := Vector2(lo.x + x + 0.5, lo.y + z + 0.5)
			var ds := w.distance_to(shaft)
			var t := clampf((w - shaft).dot(dir) / pass_len, 0.0, 1.0)
			var dp := w.distance_to(shaft + dir * pass_len * t)
			for y in g.sy:
				var wy := y0 + y
				var carve := false
				if ds <= 3.2 and wy >= bot and wy <= floor_y:
					carve = true
				elif dp <= 3.4 and absf(wy - (bot + 3)) <= 5.5:
					carve = true
				else:
					var el := Vector3(w.x - ch.x, (wy - (bot + 3)) / 0.85, w.y - ch.y).length()
					if el <= 8.0 and wy > bot - 3:
						carve = true
					elif el <= 9.0 and wy < floor_y - 4:
						var hv := posmod(hash(Vector3i(lo.x + x, wy, lo.y + z)), 100)
						if hv < 7:
							g.setv(x, y, z, Palette.GLOW_TEAL)
						elif wy <= bot - 2 and hv < 60:
							g.setv(x, y, z, Palette.GRAVEL)
				if carve:
					g.setv(x, y, z, Palette.CLEAR)
	native.add_stamp(g.data, Vector3i(g.sx, g.sy, g.sz), Vector3i(lo.x, y0, lo.y), 0)
	return {"top": Vector3i(roundi(shaft.x), floor_y, roundi(shaft.y)),
		"chest": Vector3i(roundi(ch.x), bot - 1, roundi(ch.y)), "depth": floor_y - (bot - 2)}


# ---------------------------------------------------------------- shipwrecks

const WRECK_L := 44            # hull length (voxels, ~7.9 m)
const WRECK_B := 8             # half-beam
const WRECK_D := 11            # keel to gunwale
const WRECK_MIN_HOME := 420    # ~75 m: never on the doorstep, but one may lie down the home coast
## Beached wrecks: [{island, center: Vector3i, dir: Vector2i (toward the sea), chest: Vector3i}]
var wrecks: Array = []


## Plan the beached shipwrecks (big archipelago): up to `max_wrecks` broken hulls heeled over
## on the tideline of different islands, each with a locker of salvage and a rare recipe
## scroll. Pure function of the seed. Call after plan_underground, before any chunk.
func plan_wrecks(max_wrecks := 6) -> void:
	wrecks.clear()
	if starter.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 97
	var hut := Vector2(starter.hut.x, starter.hut.z)
	var avoid: Array = [[hut, float(WRECK_MIN_HOME)]]
	for v: Dictionary in villages:
		avoid.append([Vector2(v.center.x, v.center.z), 160.0])
	for c: Dictionary in camps:
		avoid.append([Vector2(c.center.x, c.center.z), 90.0])
	for m: Dictionary in mines:
		avoid.append([Vector2(m.entrance.x, m.entrance.z), 70.0])
	var order: Array = []
	for i in islands.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return (islands[a].center as Vector2).distance_to(hut) < (islands[b].center as Vector2).distance_to(hut))
	for i: int in order:
		if wrecks.size() >= max_wrecks:
			break
		var site := _find_wreck_site(rng, i, avoid)
		if site.is_empty():
			continue
		wrecks.append(_build_wreck(site, i, rng))
		avoid.append([Vector2(site.x, site.z), 300.0])
	print("[gen] %d shipwrecks planned" % wrecks.size())


## A stretch of beach on the tideline: dry sand behind, open water in front, flat along the shore.
func _find_wreck_site(rng: RandomNumberGenerator, island_idx: int, avoid: Array) -> Dictionary:
	var isl: Dictionary = islands[island_idx]
	var hc: Vector2 = isl.center
	var hr: float = isl.radius
	for attempt in 500:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(0.6, 1.1) * hr
		var x := int(hc.x + cos(ang) * rad)
		var z := int(hc.y + sin(ang) * rad)
		var h0 := col_h(x, z)
		if h0 < sea_low or h0 > sea_high + 2 or col_k(x, z) != Kind.BEACH:
			continue
		var bad := false
		for av: Array in avoid:
			if Vector2(x, z).distance_to(av[0]) < float(av[1]):
				bad = true
		if bad or _near_cave(x, z):
			continue
		for k in 4:
			var d: Vector2i = _DIRS4[k]
			# the sea in front, the land behind
			if col_h(x + d.x * 18, z + d.y * 18) >= sea_low - 1 or col_h(x - d.x * 16, z - d.y * 16) < sea_high:
				continue
			var p := Vector2i(absi(d.y), absi(d.x))
			var ok := true
			for s in range(-WRECK_L / 2, WRECK_L / 2 + 1, 6):
				var hh := col_h(x + p.x * s, z + p.y * s)
				if absi(hh - h0) > 3:
					ok = false
					break
			if ok:
				return {"x": x, "z": z, "y": h0, "dir": d}
	return {}


## A trading cutter driven ashore: heeled toward the sea, the stern stove in, planks sprung,
## ribs showing, the mast snapped and lying on the sand. Half-buried; tides wash through it.
func _build_wreck(site: Dictionary, island_idx: int, rng: RandomNumberGenerator) -> Dictionary:
	var d: Vector2i = site.dir                       # across the hull, toward the sea
	var perp := Vector2i(absi(d.y), absi(d.x))       # along the hull
	var c := Vector2i(site.x, site.z)
	var h0: int = site.y
	var base := h0 - 3                               # keel is buried this deep
	var heel := rng.randf_range(0.32, 0.5)           # list toward the sea (radians)
	var bow := 1 if rng.randf() < 0.5 else -1        # which end of the hull is the bow
	var ch := cos(heel)
	var sh := sin(heel)
	var AW := WRECK_B + WRECK_D + 4                  # across half-size of the box
	var AL := WRECK_L / 2 + 12                       # along half-size (room for the fallen mast)
	var H := WRECK_D + 14
	var minx := c.x - (perp.x * AL + absi(d.x) * AW)
	var minz := c.y - (perp.y * AL + absi(d.y) * AW)
	var sx := (perp.x * AL + absi(d.x) * AW) * 2 + 1
	var sz := (perp.y * AL + absi(d.y) * AW) * 2 + 1
	var grid := Prefabs.Grid.new(sx, H, sz)
	var put := func(w: int, y: int, l: int, m: int) -> void:
		var gx := c.x + d.x * w + perp.x * l - minx
		var gz := c.y + d.y * w + perp.y * l - minz
		if gx >= 0 and gz >= 0 and gx < sx and gz < sz and y >= 0 and y < H:
			grid.setv(gx, y, gz, m)
	var seed_h := Vector3i(c.x, h0, c.y)
	for l in range(-WRECK_L / 2, WRECK_L / 2 + 1):
		var t := float(l * bow + WRECK_L / 2) / float(WRECK_L)      # 0 stern .. 1 bow
		var taper := minf(1.0, (1.0 - t) * 3.2) * minf(1.0, 0.55 + t * 3.0)
		if t < 0.12:
			continue                                                  # the stern is gone
		var rib := posmod(l, 4) == 0
		# the sheer rises to a high bow; the keel rocks up toward both ends
		var top := WRECK_D + 5.0 * pow(maxf(0.0, t - 0.5) / 0.5, 2.0)
		var keel := 7.0 * pow(maxf(0.0, t - 0.7) / 0.3, 2.0) + 3.0 * pow(maxf(0.0, 0.3 - t) / 0.3, 2.0)
		for y in range(0, H):
			for w in range(-AW, AW + 1):
				# hull space: across (hw) and up (hu) from the keel, undoing the heel
				var dy := float(y) - 1.0
				var hw := float(w) * ch - dy * sh
				var hu := float(w) * sh + dy * ch
				if hu < keel or hu > top:
					continue
				var half := WRECK_B * taper * sqrt(clampf(0.25 + 0.75 * (hu - keel) / maxf(1.0, top - keel), 0.0, 1.0))
				if absf(hw) > half + 0.5:
					continue
				var inner := absf(hw) <= half - 0.7 and hu >= keel + 1.0
				var hv := posmod(hash(Vector3i(w, y, l) + seed_h), 100)
				if inner:
					if y >= 4:
						# the hold: open to the air, a rib every few planks, half a deck at the bow
						if rib and absf(absf(hw) - (half - 1.2)) < 0.8:
							put.call(w, y, l, Palette.DARK_WOOD)
						elif hu >= top - 1.0 and t > 0.62 and hv < 80:
							put.call(w, y, l, Palette.PLANK)
						else:
							put.call(w, y, l, Palette.CLEAR)
					continue
				# planking, sprung and stove in toward the broken stern
				var holes := 10 + int(maxf(0.0, 0.45 - t) * 120.0)
				if hu > keel + 2.0 and hv < holes:
					if y >= 4:
						put.call(w, y, l, Palette.CLEAR)
					continue
				var m := Palette.DARK_WOOD
				if hu < keel + 2.5:
					m = Palette.KELP if hv < 30 and y < 6 else Palette.DARK_WOOD      # weed on the bottom
				elif hu > top - 1.5:
					m = Palette.PLANK                                              # the gunwale
				elif hv % 7 == 0:
					m = Palette.DRIFTWOOD
				put.call(w, y, l, m)
	# the mast: a snapped stump in its step, and the rest lying on the sand landward
	var ml := roundi(WRECK_L * 0.1) * bow
	for k in 7:
		var hu := 1.0 + k
		var w := roundi(hu * sh)
		var y := 1 + roundi(hu * ch)
		put.call(w, y, ml, Palette.TRUNK)
	var fall := -WRECK_B - 3
	for k in 18:
		put.call(fall, 4, ml - bow * (k + 2), Palette.TRUNK)
	for k in range(3, 10):
		for w2: int in [fall - 1, fall - 2, fall + 1]:
			if posmod(k + w2, 3) != 0:
				put.call(w2, 4, ml - bow * k, Palette.WHITEWASH)        # the torn sail, half under sand
	# spilled planks and barrel staves on the sand behind the stern
	for k in 10:
		var l3 := -bow * (WRECK_L / 2 + rng.randi_range(-4, 9))
		var w3 := rng.randi_range(-AW + 2, -WRECK_B)
		for s in rng.randi_range(2, 5):
			put.call(w3, 4, l3 + s * -bow, Palette.PLANK if k % 3 != 0 else Palette.DARK_WOOD)
	native.add_stamp(grid.data, Vector3i(sx, H, sz), Vector3i(minx, base, minz), 0)
	native.add_tree_clear(c.x, c.y, AL + 4)
	# the captain's locker, in the lee of the bow under what is left of the deck
	var lk := c + perp * roundi(WRECK_L * 0.12) * bow - d * 2
	return {"island": island_idx, "center": Vector3i(c.x, h0, c.y), "dir": d, "along": perp * bow,
		"chest": Vector3i(lk.x, h0 + 1, lk.y)}


# ---------------------------------------------------------------- Sea-Reaver outposts

const OUT_H := 44               # stamp height: floor + the carved space (the watchtower reaches ~36)
const OUT_MIN_HOME := 2200      # ~400 m: further out than the Mud-Claws
const OUT_TOWER_Y := 26         # lookout platform height above the yard floor (~4.7 m)
## Sea-Reaver outposts (big archipelago), voxel units:
## [{island, center: Vector3 (feet), gate: Vector2, totem: Vector3i, chest: Vector3i,
##   bunk: Vector3i, posts: [Vector3 feet], tower: Vector3 (feet, on the platform)}]
var outposts: Array = []


## Plan the Sea-Reaver outposts: up to `max_out` palisaded pirate camps on far islands that
## have no village or Mud-Claw camp, each with a watchtower, tents, torches, a strongbox and
## the War Horn Totem (an entity, placed by EntityManager). Pure function of the seed. Call
## after plan_wrecks (so older worlds keep their camps, mines and wrecks where they were).
func plan_outposts(max_out := 2) -> void:
	outposts.clear()
	if starter.is_empty():
		return
	var hut := Vector2(starter.hut.x, starter.hut.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 15485863 + 41
	var taken := {}
	for v: Dictionary in villages:
		taken[int(v.island)] = true
	for c: Dictionary in camps:
		taken[int(c.island)] = true
	var order: Array = []
	for i in islands.size():
		if i == 0 or int(islands[i].type) == 0 or taken.has(i):
			continue
		if (islands[i].center as Vector2).distance_to(hut) < OUT_MIN_HOME:
			continue
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return (islands[a].center as Vector2).distance_to(hut) < (islands[b].center as Vector2).distance_to(hut))
	for i: int in order:
		if outposts.size() >= max_out:
			break
		var site := _find_camp_site(rng, i, hut)
		if site.is_empty():
			continue
		var clash := false
		for m: Dictionary in mines:
			if Vector2(m.entrance.x, m.entrance.z).distance_to(Vector2(site.x, site.z)) < 120.0:
				clash = true
		for w: Dictionary in wrecks:
			if Vector2(w.center.x, w.center.z).distance_to(Vector2(site.x, site.z)) < 90.0:
				clash = true
		if clash or Vector2(site.x, site.z).distance_to(hut) < OUT_MIN_HOME:
			continue
		outposts.append(_build_outpost(site, i, rng))
	print("[gen] %d Sea-Reaver outposts planned" % outposts.size())


func _build_outpost(site: Dictionary, island_idx: int, rng: RandomNumberGenerator) -> Dictionary:
	var c := Vector2i(site.x, site.z)
	var fy: int = site.y
	var g: Vector2 = site.gate
	var side := Vector2(-g.y, g.x)
	var R := CAMP_R
	var n := R * 2 + 7
	var o := R + 3
	var grid := Prefabs.Grid.new(n, OUT_H, n)
	var ga := atan2(g.y, g.x)
	# packed earth and gravel, a boardwalk to the gate; carved clear above
	for z in n:
		for x in n:
			var v := Vector2(x - o, z - o)
			if v.length() > R + 1.5:
				continue
			var m := Palette.DIRT if (hash(Vector2i(x, z) + c) & 3) != 0 else Palette.GRAVEL
			if absf(v.dot(side)) < 2.5 and v.dot(g) > -8.0:
				m = Palette.PLANK
			grid.setv(x, 0, z, m)
			for y in range(1, OUT_H):
				grid.setv(x, y, z, Palette.CLEAR)
	# a tall stockade of sharpened trunks, tarred and lashed, with a wide gate
	for z in n:
		for x in n:
			var v := Vector2(x - o, z - o)
			var dd := v.length()
			if dd < R - 0.8 or dd > R + 0.8:
				continue
			var a := atan2(v.y, v.x)
			if absf(angle_difference(a, ga)) < 0.15:
				continue
			var post := int(floor((a + PI) * R / 1.5))
			var ph := 15 + posmod(hash(post * 13 + c.x), 3)
			for y in range(1, ph + 1):
				grid.setv(x, y, z, Palette.TRUNK if post % 3 != 0 else Palette.DARK_WOOD)
			grid.setv(x, 4, z, Palette.DARK_WOOD)
			grid.setv(x, 11, z, Palette.DARK_WOOD)
			grid.setv(x, ph + 1, z, Palette.SANDSTONE_C)
	# gate towers: square posts with a lantern each
	for s: int in [-1, 1]:
		var a := ga + 0.19 * s
		var px := o + roundi(cos(a) * R)
		var pz := o + roundi(sin(a) * R)
		for y in range(1, 21):
			grid.box(px - 1, y, pz - 1, px, y, pz, Palette.DARK_WOOD)
		grid.setv(px, 21, pz, Palette.LANTERN)
		stamp_lights.append(Vector3i(c.x + px - o, fy + 21, c.y + pz - o))
	# the watchtower, beside the gate inside the wall, with a plank stair up to the lookout
	var twx := o + roundi(g.x * (R - 9) + side.x * 11.0)
	var twz := o + roundi(g.y * (R - 9) + side.y * 11.0)
	for dz: int in [-3, 3]:
		for dx: int in [-3, 3]:
			for y in range(1, OUT_TOWER_Y + 9):
				grid.setv(twx + dx, y, twz + dz, Palette.TRUNK)
	grid.box(twx - 4, OUT_TOWER_Y, twz - 4, twx + 4, OUT_TOWER_Y, twz + 4, Palette.PLANK)
	for k in range(-4, 5):
		for e: Vector2i in [Vector2i(k, -4), Vector2i(k, 4), Vector2i(-4, k), Vector2i(4, k)]:
			if posmod(k, 2) == 0:
				grid.setv(twx + e.x, OUT_TOWER_Y + 1, twz + e.y, Palette.DARK_WOOD)
			grid.setv(twx + e.x, OUT_TOWER_Y + 2, twz + e.y, Palette.DARK_WOOD)
	for z in range(-4, 5):
		for x in range(-4, 5):
			grid.setv(twx + x, OUT_TOWER_Y + 9 + (4 - maxi(absi(x), absi(z))) / 2, twz + z,
					Palette.ROOF_RED if posmod(x + z, 3) != 0 else Palette.WHITEWASH)
	grid.setv(twx, OUT_TOWER_Y + 1, twz, Palette.LANTERN)
	stamp_lights.append(Vector3i(c.x + twx - o, fy + OUT_TOWER_Y + 1, c.y + twz - o))
	# the stair: climbing toward the gate, one voxel up per voxel along, onto the platform
	var sd := g
	var foot := Vector2(twx, twz) - side * 6.0 - sd * float(OUT_TOWER_Y + 2)
	for k in OUT_TOWER_Y:
		for w in range(-1, 2):
			var q := foot + sd * float(k) + side * float(w)
			grid.setv(roundi(q.x), k + 1, roundi(q.y), Palette.PLANK)
	for k in range(0, 6):
		for w in range(-1, 2):
			var q := foot + sd * float(OUT_TOWER_Y - 1 + k) + side * float(w)
			grid.setv(roundi(q.x), OUT_TOWER_Y, roundi(q.y), Palette.PLANK)
	for k in range(0, 6):
		var q := Vector2(twx, twz) - side * float(k + 3)
		grid.setv(roundi(q.x), OUT_TOWER_Y, roundi(q.y), Palette.PLANK)
	var tower := Vector3(c.x + twx - o + 0.5, fy + OUT_TOWER_Y + 1, c.y + twz - o + 0.5)
	# three striped canvas tents round the back, open toward the yard
	var tents: Array = []
	for k: int in [-1, 0, 1]:
		var a := ga + PI + 0.85 * k
		var along := Vector2(cos(a), sin(a))
		var across := Vector2(-along.y, along.x)
		var tc := Vector2(o, o) + along * float(R - 12)
		for l in range(-5, 6):
			for w in range(-6, 7):
				var hgt := 8 - absi(w)
				if hgt < 1:
					continue
				var q := tc + along * float(l) + across * float(w)
				var m := Palette.WHITEWASH if posmod(l, 2) == 0 else Palette.ROOF_RED
				grid.setv(roundi(q.x), hgt, roundi(q.y), m)
				if l == 5:
					for yy in range(1, hgt):
						grid.setv(roundi(q.x), yy, roundi(q.y), Palette.WHITEWASH)
		tents.append(Vector3i(c.x + roundi(tc.x) - o, fy + 1, c.y + roundi(tc.y) - o))
	# a firepit in the yard; crates and barrels; torch posts round the wall
	var fpx := o + roundi(g.x * 4.0)
	var fpz := o + roundi(g.y * 4.0)
	for z in range(fpz - 3, fpz + 4):
		for x in range(fpx - 3, fpx + 4):
			var dd := Vector2(x - fpx, z - fpz).length()
			if dd <= 3.2 and dd > 2.1:
				grid.setv(x, 1, z, Palette.COBBLE)
			elif dd <= 1.2:
				grid.setv(x, 1, z, Palette.LANTERN)
	stamp_lights.append(Vector3i(c.x + fpx - o, fy + 1, c.y + fpz - o))
	for k in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(10.0, R - 6.0)
		var qx := o + roundi(cos(a) * r)
		var qz := o + roundi(sin(a) * r)
		if Vector2(qx - twx, qz - twz).length() < 9.0 or Vector2(qx - o, qz - o).dot(g) > R - 16:
			continue
		var h := 3 if k % 3 != 0 else 5
		grid.box(qx - 1, 1, qz - 1, qx + 1, h, qz + 1, Palette.PLANK if k % 2 == 0 else Palette.DARK_WOOD)
		grid.setv(qx, h, qz, Palette.DARK_WOOD)
	for k in 4:
		var a := ga + PI * 0.5 + PI * k * 0.5 + 0.4
		var qx := o + roundi(cos(a) * (R - 5))
		var qz := o + roundi(sin(a) * (R - 5))
		for y in range(1, 11):
			grid.setv(qx, y, qz, Palette.DARK_WOOD)
		grid.setv(qx, 11, qz, Palette.LANTERN)
		stamp_lights.append(Vector3i(c.x + qx - o, fy + 11, c.y + qz - o))
	native.add_stamp(grid.data, Vector3i(n, OUT_H, n), Vector3i(c.x - o, fy, c.y - o), 1)
	native.add_tree_clear(c.x, c.y, R + 14)
	var feet := func(v: Vector2) -> Vector3: return Vector3(c.x + v.x + 0.5, fy + 1, c.y + v.y + 0.5)
	var posts: Array = [feet.call(g * (R - 4) + side * 4.0), feet.call(g * (R - 4) - side * 4.0),
		feet.call(-side * 14.0), feet.call(-g * 12.0 + side * 8.0), feet.call(g * 8.0 - side * 9.0),
		feet.call(-g * 6.0 - side * 12.0), feet.call(side * 3.0), feet.call(-g * 3.0 - side * 3.0)]
	var tv := -g * 15.0
	var cv := -g * 12.0 + side * 6.0
	return {"island": island_idx, "center": Vector3(c.x + 0.5, fy + 1, c.y + 0.5), "gate": g,
		"totem": Vector3i(c.x + roundi(tv.x), fy + 1, c.y + roundi(tv.y)),
		"chest": Vector3i(c.x + roundi(cv.x), fy + 1, c.y + roundi(cv.y)),
		"bunk": tents[1] if tents.size() > 1 else Vector3i(c.x, fy + 1, c.y),
		"posts": posts, "tower": tower}


# ---------------------------------------------------------------- the Barnacled Hulk's strand

const HULK_MIN_HOME := 2600     # ~470 m: the far side of the archipelago
## The Hollow Flats boss lair (big archipelago), voxel units, or {} if none:
## {island, lair: Vector3 (feet), dir: Vector2 (toward the sea), boulders: [Vector3i (feet, on the rocks)]}
var hulk := {}


## Plan the Barnacled Hulk's strand: a low beach (below half tide, so it floods and drains)
## on a far island, with two rock outcrops landward that hold loose boulders. Pure function
## of the seed. Call after plan_outposts.
func plan_hulk() -> void:
	hulk = {}
	if starter.is_empty():
		return
	var hut := Vector2(starter.hut.x, starter.hut.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 3571 + 7
	var taken := {}
	for v: Dictionary in villages:
		taken[int(v.island)] = true
	for o: Dictionary in outposts:
		taken[int(o.island)] = true
	var order: Array = []
	for i in islands.size():
		if i == 0 or taken.has(i) or (islands[i].center as Vector2).distance_to(hut) < HULK_MIN_HOME:
			continue
		order.append(i)
	# the farthest island first
	order.sort_custom(func(a: int, b: int) -> bool:
		return (islands[a].center as Vector2).distance_to(hut) > (islands[b].center as Vector2).distance_to(hut))
	for i: int in order:
		var site := _find_flats(rng, i)
		if not site.is_empty():
			hulk = _build_strand(site, i)
			break
	print("[gen] Barnacled Hulk lair: %s" % ("island %d" % int(hulk.island) if not hulk.is_empty() else "none"))


## A broad, low, flat beach: sand between low tide and half tide for 8 m around, the sea
## beyond it and land behind.
func _find_flats(rng: RandomNumberGenerator, island_idx: int) -> Dictionary:
	var isl: Dictionary = islands[island_idx]
	var hc: Vector2 = isl.center
	var hr: float = isl.radius
	var mid := int(sea_mid)
	for attempt in 900:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(0.55, 1.1) * hr
		var x := int(hc.x + cos(ang) * rad)
		var z := int(hc.y + sin(ang) * rad)
		var h0 := col_h(x, z)
		if h0 < sea_low or h0 > mid - 1 or col_k(x, z) != Kind.BEACH:
			continue
		var flat := 0
		for k in 12:
			var a := TAU * k / 12.0
			var hh := col_h(x + int(cos(a) * 32), z + int(sin(a) * 32))
			if hh <= mid + 3 and hh >= sea_low - 8:
				flat += 1
		if flat < 6 or _near_cave(x, z):
			continue
		var land := Vector2(hc.x - x, hc.y - z).normalized()
		var dry := false
		for r in [60, 100, 150, 220]:
			if col_h(x + int(land.x * r), z + int(land.y * r)) >= sea_high:
				dry = true
		if not dry:
			continue
		return {"x": x, "z": z, "y": h0, "dir": -land}
	return {}


func _build_strand(site: Dictionary, island_idx: int) -> Dictionary:
	var c := Vector2i(site.x, site.z)
	var h0: int = site.y
	var sea: Vector2 = site.dir
	var land := -sea
	var side := Vector2(-sea.y, sea.x)
	var boulders: Array = []
	# two rock outcrops on the landward edge of the flats, each topped by a loose boulder
	for s: int in [-1, 1]:
		var oc := Vector2(c) + land * 30.0 + side * (18.0 * s)
		var R := 9
		var H := 15
		var n := R * 2 + 3
		var grid := Prefabs.Grid.new(n, H + 4, n)
		for z in n:
			for x in n:
				var d := Vector2(x - R - 1, z - R - 1).length()
				if d > R + 0.5:
					continue
				var top := int(round(H * (1.0 - pow(d / float(R + 1), 2.2))))
				# a sheer face toward the strand, a slope behind
				var toward := Vector2(x - R - 1, z - R - 1).dot(sea)
				if toward > 0.0:
					top = mini(H, top + 2)
				for y in range(0, top + 1):
					var m := Palette.STONE if (x + y * 3 + z) % 5 != 0 else Palette.SANDSTONE_A
					if y == top:
						m = Palette.SANDSTONE_C if toward > 0.0 else Palette.GRASS_DRY
					grid.setv(x, y, z, m)
		var base := Vector3i(int(oc.x) - R - 1, h0, int(oc.y) - R - 1)
		native.add_stamp(grid.data, Vector3i(n, H + 4, n), base, 1)
		# the boulder sits on the strand-side lip of the outcrop
		var lip := oc + sea * 3.0
		boulders.append(Vector3i(int(lip.x), h0 + H + 1, int(lip.y)))
	native.add_tree_clear(c.x, c.y, 60)
	return {"island": island_idx, "lair": Vector3(c.x + 0.5, h0 + 1, c.y + 0.5), "dir": sea, "boulders": boulders}
