class_name WildlifeDirector
extends RefCounted
## Island wildlife: where ambient animals appear, and the night raids on the farm.
## Owned by CreatureNet; the host / server decides everything here, clients just see the
## creatures (snapshots), the dens (state + RPC) and the alerts.
##
## Ambient (around every player, by habitat):
##   hare     grassland, day & dusk         seal     beach flats at low tide, shallows otherwise
##   puffin   high rock by the sea, day     otter    kelp beds and calm water
##   heron    the shallows, dawn to dusk    whale    deep water far offshore, rare, by day
##
## Raids (night, near players, a few per night depending on difficulty):
##   A fox (ducks) or a stoat (eggs) sets out from a den in the woods toward the weakest
##   pen: the one furthest from any light, that hasn't turned a raider back lately.
##   Cozy       raids only take an egg or some trough feed; animals are never harmed
##   Tidewatch  sometimes a fox carries off a duck; clear warnings when a raid starts
##   Undertow   bolder raids: a fox that reaches a duck nearly always takes it
##   Dens are real places you can find (follow the tracks) and fill in (F): the foxes then
##   move to a wood further from the farm. A turned-back raider remembers that farm.

const LivestockScript := preload("res://scripts/livestock/livestock_animal.gd")
const DEFEND_RADIUS := 30.0
const DEN_MIN := 35.0
const DEN_MAX_REUSE := 90.0
const RAID_RANGE := 60.0
const BUDGET := [1, 2, 3]                  # raids per night by difficulty
const DEFEND_DAYS := {"light": 2, "fence": 3, "chased": 2, "struck": 2, "startled": 2,
	"trapped": 6, "relocated": 6, "nothing": 1, "dog": 3, "cat": 3, "roof": 2, "scarecrow": 2}
const RAT_BUDGET := [1, 2, 3]              # rat raids a night after a storm, by difficulty
const EAGLE_BUDGET := [1, 1, 2]            # eagle stoops a day, by difficulty
const STORM_MEMORY_DAYS := 1               # rats come up the nights after a storm

var net: Node                             # CreatureNet
var rng := RandomNumberGenerator.new()
var dens: Array = []                      # [{"p": Vector3}]
var defended: Array = []                  # [{"p": Vector3, "until": int}]
var den_min_dist := DEN_MIN
var night_id := -999
var raids_left := 0
var _ambient_turn := 0
var _den_nodes: Array = []
var _pending_carried: Array = []
var otter_friends: Dictionary = {}
var last_storm_day := -999
var rat_night := -999
var rat_raids_left := 0
var eagle_day := -999
var eagles_left := 0       # player_key -> true: they have an otter friend

const AMBIENT := [&"hare", &"seal", &"puffin", &"otter", &"heron", &"whale"]
const CAP := {&"hare": 6, &"seal": 6, &"puffin": 10, &"otter": 3, &"heron": 3, &"whale": 1,
	&"fox": 2, &"stoat": 2, &"rat": 3, &"eagle": 1}
const DESPAWN := {&"whale": 240.0, &"puffin": 100.0, &"heron": 90.0}


func _init(p_net: Node) -> void:
	net = p_net
	rng.randomize()


# ---------------------------------------------------------------- access helpers

func _main() -> Node:
	return net.main


func _livestock() -> Node:
	var m := _main()
	return m.get("livestock_mgr") if m != null else null


func _day() -> int:
	var m := _main()
	return m.sky.day if m != null and m.sky != null else 0


func _difficulty() -> int:
	return net.difficulty


func animal(id: int) -> Node3D:
	var ls := _livestock()
	return ls.get_animal_by_id(id) if ls != null else null


func coop_at(coord: Vector3i) -> WorldEntity:
	var em := EntityManager.current
	if em == null:
		return null
	var e: WorldEntity = em.entities.get(coord)
	return e if e != null and e.entity_id == &"poultry_coop" else null


## A chest, crate or barrel at `coord`.
func store_at(coord: Vector3i) -> ChestEntity:
	var em := EntityManager.current
	if em == null or coord == Vector3i.MAX:
		return null
	return em.entities.get(coord) as ChestEntity


func near_scarecrow(pos: Vector3) -> bool:
	var em := EntityManager.current
	if em == null:
		return false
	for e: WorldEntity in em.entities.values():
		if e is ScarecrowEntity and e.position.distance_to(pos) < ScarecrowEntity.RADIUS:
			return true
	return false


## A guard dog or dock cat close enough to see this raider off: it dashes out, and we
## return the defence reason ("dog" / "cat"), or "" if none is on watch.
func guard_check(r: Raider) -> String:
	var em := EntityManager.current
	if em == null:
		return ""
	for e: WorldEntity in em.entities.values():
		if e is GuardAnimalEntity:
			var g := e as GuardAnimalEntity
			if g.guards_against(r.kind) and g.position.distance_to(r.position) < g.guard_radius():
				g.chase(r.position)
				if g.is_dog():
					alert("%s barks and sees the %s off!" % [g.pet_name, kind_word(r.kind)])
				else:
					alert("%s the dock cat chases the %s away!" % [g.pet_name, kind_word(r.kind)])
				return g.species_word()
	return ""


static func kind_word(k: StringName) -> String:
	match k:
		&"stoat": return "stoat"
		&"rat": return "shore rat"
		&"eagle": return "sea eagle"
	return "fox"


func nearest_baited_trap(pos: Vector3, r: float) -> LiveTrapEntity:
	var em := EntityManager.current
	if em == null:
		return null
	var best: LiveTrapEntity = null
	var bd := r
	for e: WorldEntity in em.entities.values():
		if e is LiveTrapEntity and (e as LiveTrapEntity).is_baited():
			var d := e.position.distance_to(pos)
			if d < bd:
				bd = d
				best = e
	return best


func despawn_distance(kind: StringName) -> float:
	return DESPAWN.get(kind, 70.0)


func count(kind: StringName, near: Vector3 = Vector3.ZERO, r: float = 0.0) -> int:
	return net._count(kind, near, r)


func active_raiders() -> int:
	var n := 0
	for c: Creature in net.creatures.values():
		if c is Raider:
			n += 1
	return n


# ---------------------------------------------------------------- defence memory

func mark_defended(pos: Vector3, reason: String) -> void:
	var days: int = DEFEND_DAYS.get(reason, 2)
	if _difficulty() == CombatMath.Difficulty.UNDERTOW:
		days = maxi(1, days - 1)
	for d: Dictionary in defended:
		if (d.p as Vector3).distance_to(pos) < DEFEND_RADIUS * 0.5:
			d.until = maxi(int(d.until), _day() + days)
			return
	defended.append({"p": pos, "until": _day() + days})


func is_defended(pos: Vector3) -> bool:
	var today := _day()
	for d: Dictionary in defended:
		if int(d.until) >= today and (d.p as Vector3).distance_to(pos) < DEFEND_RADIUS:
			return true
	return false


func _prune_memory() -> void:
	var today := _day()
	defended = defended.filter(func(d: Dictionary) -> bool: return int(d.until) >= today)


# ---------------------------------------------------------------- per-second spawning

func spawn_tick(players: Array) -> void:
	if not net.is_authority():
		return
	_restore_carried()
	for pl: Dictionary in players:
		_spawn_ambient(pl.pos)
		_ensure_otter_friend(pl)
	_raid_tick(players)
	_storm_watch()
	_rat_tick(players)
	_eagle_tick(players)


# ---------------------------------------------------------------- otter friends

## The save-stable identity of a connected player (peer ids change between sessions).
func player_key_for(pid: int) -> String:
	var m := _main()
	if m == null or m.get("session") == null:
		return str(pid)
	var s: Node = m.session
	if pid == net.local_id() and String(s.player_key) != "":
		return String(s.player_key)
	return String(s._peer_keys.get(pid, str(pid)))


func remember_otter_friend(pid: int) -> void:
	otter_friends[player_key_for(pid)] = true


func has_otter_friend_here(pid: int) -> bool:
	for c: Creature in net.creatures.values():
		if c is SeaOtter and (c as SeaOtter).friend_id == pid:
			return true
	return false


## A player who befriended an otter gets it back after a reload or rejoin: it swims up
## the next time they are near suitable water.
func _ensure_otter_friend(pl: Dictionary) -> void:
	var pid: int = int(pl.id)
	if not otter_friends.has(player_key_for(pid)) or has_otter_friend_here(pid):
		return
	var water_y: float = _main().sky.water_level_m()
	for t in 6:
		var c := _sample(pl.pos, 4.0, 22.0)
		if c.is_empty():
			continue
		var dep := _depth(c, water_y)
		if dep < 0.5 or dep > 6.0:
			continue
		var o: Creature = net.spawn(&"otter", _at(c, water_y - 0.12))
		if o is SeaOtter:
			(o as SeaOtter).friend_id = pid
			(o as SeaOtter)._gift_t = SeaOtter.GIFT_EVERY * 0.5
			o.set_state(Creature.State.LURED)
		return


func _col(x: int, z: int) -> Dictionary:
	var gen: WorldGen = _main().world.gen
	if x < 0 or z < 0 or x >= VoxelWorld.WX or z >= VoxelWorld.WZ:
		return {}
	return {"h": gen.col_h(x, z), "k": gen.col_k(x, z)}


func _sample(pp: Vector3, rmin: float, rmax: float) -> Dictionary:
	var a := rng.randf() * TAU
	var r := rng.randf_range(rmin, rmax)
	var x := floori((pp.x + cos(a) * r) / VoxelWorld.VS)
	var z := floori((pp.z + sin(a) * r) / VoxelWorld.VS)
	var c := _col(x, z)
	if c.is_empty():
		return {}
	c["x"] = x
	c["z"] = z
	return c


func _ground(c: Dictionary) -> float:
	net._ensure_column(c.x, c.z)
	var top := (int(c.h) + 1) * VoxelWorld.VS
	return TerrainStep.ground_at(net.voxel, (c.x + 0.5) * VoxelWorld.VS, (c.z + 0.5) * VoxelWorld.VS, top, 6, 6)


func _depth(c: Dictionary, water_y: float) -> float:
	return water_y - (int(c.h) + 1) * VoxelWorld.VS


func _at(c: Dictionary, y: float) -> Vector3:
	return Vector3((c.x + 0.5) * VoxelWorld.VS, y, (c.z + 0.5) * VoxelWorld.VS)


func _spawn_ambient(pp: Vector3) -> void:
	var sky: SkyCycle = _main().sky
	var water_y: float = sky.water_level_m()
	var night: float = sky.night_factor()
	_ambient_turn = (_ambient_turn + 1) % AMBIENT.size()
	var kind: StringName = AMBIENT[_ambient_turn]
	if count(kind) >= CAP[kind]:
		return
	match kind:
		&"hare":
			if night > 0.7 or count(kind, pp, 40.0) >= 3:
				return
			for t in 4:
				var c := _sample(pp, 12.0, 35.0)
				if c.is_empty() or not WorldGen.is_grassy(int(c.k)):
					continue
				var g := _ground(c)
				if is_nan(g) or g < water_y + 0.5:
					continue
				var n := 1 + (1 if rng.randf() < 0.4 else 0)
				for i in n:
					net.spawn(&"hare", _at(c, g) + Vector3(i * 0.8, 0, 0))
				return
		&"seal":
			if count(kind, pp, 50.0) >= 3:
				return
			var low_tide := water_y < VoxelWorld.SEA_MID * VoxelWorld.VS
			for t in 6:
				var c := _sample(pp, 15.0, 45.0)
				if c.is_empty():
					continue
				if low_tide and int(c.k) == WorldGen.Kind.BEACH:
					var g := _ground(c)
					if is_nan(g) or g < water_y - 0.05 or g > water_y + 0.7:
						continue
					for i in rng.randi_range(1, 3):
						net.spawn(&"seal", _at(c, g) + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)))
					return
				if not low_tide and _depth(c, water_y) > 0.8 and _depth(c, water_y) < 3.5:
					net.spawn(&"seal", _at(c, water_y - 0.25))
					return
		&"puffin":
			if night > 0.45 or count(kind, pp, 60.0) > 0:
				return
			for t in 6:
				var c := _sample(pp, 15.0, 55.0)
				if c.is_empty() or int(c.k) != WorldGen.Kind.ROCK:
					continue
				var g := _ground(c)
				if is_nan(g) or g < water_y + 2.5 or not _near_sea(int(c.x), int(c.z), water_y, 8):
					continue
				for i in rng.randi_range(3, 6):
					var o := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
					var gy := TerrainStep.ground_at(net.voxel, _at(c, g).x + o.x, _at(c, g).z + o.z, g, 3, 3)
					if not is_nan(gy):
						net.spawn(&"puffin", _at(c, gy) + Vector3(o.x, 0, o.z))
				return
		&"otter":
			if night > 0.8 or count(kind, pp, 60.0) > 0:
				return
			for t in 6:
				var c := _sample(pp, 10.0, 40.0)
				if c.is_empty():
					continue
				var dep := _depth(c, water_y)
				if dep < 0.6 or dep > 4.0:
					continue
				if not (_has_kelp(int(c.x), int(c.z), int(c.h), water_y) or _near_land(int(c.x), int(c.z), water_y, 30)):
					continue
				net.spawn(&"otter", _at(c, water_y - 0.12))
				return
		&"heron":
			if night > 0.6 or count(kind, pp, 50.0) >= 2:
				return
			for t in 6:
				var c := _sample(pp, 14.0, 40.0)
				if c.is_empty():
					continue
				var dep := _depth(c, water_y)
				if dep < 0.05 or dep > 0.45 or not _near_land(int(c.x), int(c.z), water_y, 8):
					continue
				net.spawn(&"heron", _at(c, (int(c.h) + 1) * VoxelWorld.VS))
				return
		&"whale":
			if night > 0.4 or rng.randf() > 0.03:
				return
			for t in 8:
				var c := _sample(pp, 70.0, 150.0)
				if c.is_empty() or _depth(c, water_y) < 3.6:
					continue
				var w := net.spawn(&"whale", _at(c, water_y - 1.4)) as MigratingWhale
				var a := rng.randf() * TAU
				w.heading = Vector3(cos(a), 0, sin(a))
				return


func _near_sea(x: int, z: int, water_y: float, r: int) -> bool:
	var sea := floori(water_y / VoxelWorld.VS)
	for d: Vector2i in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
		var c := _col(x + d.x, z + d.y)
		if not c.is_empty() and int(c.h) < sea - 2:
			return true
	return false


func _near_land(x: int, z: int, water_y: float, r: int) -> bool:
	var sea := floori(water_y / VoxelWorld.VS)
	for d: Vector2i in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
		var c := _col(x + d.x, z + d.y)
		if not c.is_empty() and int(c.h) >= sea:
			return true
	return false


func _has_kelp(x: int, z: int, h: int, water_y: float) -> bool:
	net._ensure_column(x, z)
	for y in range(h + 1, floori(water_y / VoxelWorld.VS)):
		if net.voxel(x, y, z) == Palette.KELP:
			return true
	return false


# ---------------------------------------------------------------- raids

func _night_id() -> int:
	var sky: SkyCycle = _main().sky
	return sky.day if sky.time_of_day >= 0.5 else sky.day - 1


func _raid_tick(players: Array) -> void:
	var sky: SkyCycle = _main().sky
	if sky.night_factor() < 0.6 or _livestock() == null:
		return
	var nid := _night_id()
	if nid != night_id:
		night_id = nid
		raids_left = BUDGET[clampi(_difficulty(), 0, 2)]
		_prune_memory()
	if raids_left <= 0 or active_raiders() > 0 or rng.randf() > 1.0 / 45.0:
		return
	try_start_raid(players)


## Lights a raider would notice (lamps, lantern posts, fires, held lanterns).
func _lights() -> Array:
	return net._context().lights


## Picks the weakest pen near a player and sends a fox or a stoat at it. Returns the raider.
func try_start_raid(players: Array, force_kind: StringName = &"") -> Raider:
	var ls := _livestock()
	if ls == null:
		return null
	var lights := _lights()
	var foxes := []
	var stoats := []
	for a: Node3D in ls.animals:
		if not _near_any(a.position, players, RAID_RANGE) or is_defended(a.position):
			continue
		var lit_d := _nearest_light(a.position, lights)
		if lit_d < Raider.LIGHT_RADIUS:
			continue
		if a.species == &"shore_duck":
			foxes.append([a, lit_d])
			if a.is_egg_ready():
				stoats.append([a, lit_d])
	var em := EntityManager.current
	if em != null:
		for e: WorldEntity in em.entities.values():
			if e.entity_id == &"poultry_coop" and int(e.get("egg_count")) > 0 and _near_any(e.position, players, RAID_RANGE) \
					and not is_defended(e.position):
				var lit_d := _nearest_light(e.position, lights)
				if lit_d >= Raider.LIGHT_RADIUS:
					stoats.append([e, lit_d])
	var kind := force_kind
	if kind == &"":
		if not foxes.is_empty() and (stoats.is_empty() or rng.randf() < 0.6):
			kind = &"fox"
		elif not stoats.is_empty():
			kind = &"stoat"
		else:
			return null
	var pool: Array = foxes if kind == &"fox" else stoats
	if pool.is_empty() or count(kind) >= CAP[kind]:
		return null
	# The weakest pen: darkest, with a little randomness.
	pool.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) > float(y[1]))
	var pick: Array = pool[rng.randi_range(0, mini(1, pool.size() - 1))]
	var target: Node3D = pick[0]
	var den := _den_for(target.position, players)
	var origin := den
	if origin.distance_to(target.position) > DEN_MAX_REUSE:
		origin = _approach_point(target.position, den, players)
	var r := net.spawn(kind, origin) as Raider
	if r == null:
		return null
	r.den = den
	r.raid_site = target.position
	if target is WorldEntity:
		r.target_coop = (target as WorldEntity).grid_coord
	else:
		r.target_animal_id = int(target.get("animal_id"))
	raids_left -= 1
	if kind == &"stoat":
		alert("A stoat is after the eggs!")
	elif _difficulty() == CombatMath.Difficulty.COZY:
		alert("Something is sniffing round the pen tonight...")
	else:
		alert("A fox is circling the pen! Light a lantern, shut the gate, or chase it off.")
	print("[wildlife] %s raid on %s from %s" % [kind, target.position, origin])
	return r


# ---------------------------------------------------------------- shore rats

func _storm_watch() -> void:
	var sky: SkyCycle = _main().sky
	if sky != null and sky.weather != null and int(sky.weather.params.get("state", 0)) == WeatherModel.State.STORM:
		last_storm_day = _day()


func storm_recent() -> bool:
	return _day() - last_storm_day <= STORM_MEMORY_DAYS


func _rat_tick(players: Array) -> void:
	var sky: SkyCycle = _main().sky
	if sky.night_factor() < 0.6 or not storm_recent():
		return
	var nid := _night_id()
	if nid != rat_night:
		rat_night = nid
		rat_raids_left = RAT_BUDGET[clampi(_difficulty(), 0, 2)]
	if rat_raids_left <= 0 or count(&"rat") > 0 or rng.randf() > 1.0 / 40.0:
		return
	try_start_rat_raid(players)


## Open chests and crates holding food near a player (sealed barrels never count).
func raidable_stores(players: Array) -> Array:
	var out: Array = []
	var em := EntityManager.current
	if em == null:
		return out
	var lights := _lights()
	for e: WorldEntity in em.entities.values():
		if not (e is ChestEntity) or (e as ChestEntity).raidable_food().is_empty():
			continue
		if not _near_any(e.position, players, RAID_RANGE) or is_defended(e.position):
			continue
		if _nearest_light(e.position, lights) >= Raider.LIGHT_RADIUS:
			out.append(e)
	return out


## Sends a shore rat (two on Undertow, sometimes) up from the tideline at an open food store.
func try_start_rat_raid(players: Array) -> Raider:
	var stores := raidable_stores(players)
	if stores.is_empty() or count(&"rat") >= CAP[&"rat"]:
		return null
	var target: ChestEntity = stores[rng.randi() % stores.size()]
	var origin := _shore_point(target.position, players)
	var n := 2 if (_difficulty() == CombatMath.Difficulty.UNDERTOW and rng.randf() < 0.5) else 1
	var first: Raider = null
	for i in n:
		var r := net.spawn(&"rat", origin + Vector3(i * 0.6, 0, i * 0.4)) as Raider
		if r == null:
			continue
		r.den = origin
		r.raid_site = target.position
		r.target_store = target.grid_coord
		if first == null:
			first = r
	if first != null:
		rat_raids_left -= 1
		alert("Shore rats are up from the tideline after the storm! Seal your food away.")
		print("[wildlife] rat raid on %s from %s" % [target.position, origin])
	return first


## A spot on the shore, toward the sea and out of sight of players.
func _shore_point(target: Vector3, players: Array) -> Vector3:
	var water_y: float = _main().sky.water_level_m()
	for t in 16:
		var a := rng.randf() * TAU
		var p := target + Vector3(cos(a), 0, sin(a)) * rng.randf_range(18.0, 34.0)
		var g := TerrainStep.ground_at(net.voxel, p.x, p.z, target.y, 30, 30)
		if not is_nan(g) and g > water_y + 0.1 and g < water_y + 1.6 and not _near_any(p, players, 12.0):
			return Vector3(p.x, g, p.z)
	return _approach_point(target, target + Vector3(25, 0, 0), players)


# ---------------------------------------------------------------- sea eagles

func _eagle_tick(players: Array) -> void:
	var sky: SkyCycle = _main().sky
	if sky.night_factor() > 0.2 or _livestock() == null:
		return
	if eagle_day != _day():
		eagle_day = _day()
		eagles_left = EAGLE_BUDGET[clampi(_difficulty(), 0, 2)]
	if eagles_left <= 0 or count(&"eagle") > 0 or rng.randf() > 1.0 / 90.0:
		return
	try_start_eagle(players)


## Ducks out in the open: no roof over them, no scarecrow, nobody standing with them.
func open_ducks(players: Array) -> Array:
	var out: Array = []
	var ls := _livestock()
	if ls == null:
		return out
	for a: Node3D in ls.animals:
		if a.species != &"shore_duck" or not _near_any(a.position, players, RAID_RANGE):
			continue
		if _near_any(a.position, players, SeaEagle.COMPANY_RANGE) or is_defended(a.position):
			continue
		if near_scarecrow(a.position) or roofed(a.position):
			continue
		out.append(a)
	return out


## Anything solid a little above this spot (a roof, an overhang, a tree)?
func roofed(at: Vector3) -> bool:
	var vx := floori(at.x / VoxelWorld.VS)
	var vz := floori(at.z / VoxelWorld.VS)
	var vy := floori(at.y / VoxelWorld.VS)
	net._ensure_column(vx, vz)
	for y in range(vy + 3, vy + 24):
		if net.voxel(vx, y, vz) != 0:
			return true
	return false


func try_start_eagle(players: Array) -> Raider:
	var ducks := open_ducks(players)
	if ducks.is_empty() or count(&"eagle") >= CAP[&"eagle"]:
		return null
	var target: Node3D = ducks[rng.randi() % ducks.size()]
	var a := rng.randf() * TAU
	var origin := target.position + Vector3(cos(a) * 45.0, 24.0, sin(a) * 45.0)
	var r := net.spawn(&"eagle", origin) as Raider
	if r == null:
		return null
	r.den = target.position + Vector3(cos(a + PI) * 120.0, 30.0, sin(a + PI) * 120.0)
	r.raid_site = target.position
	r.target_animal_id = int(target.get("animal_id"))
	eagles_left -= 1
	if _difficulty() == CombatMath.Difficulty.COZY:
		alert("A sea eagle is circling high over the ducks...")
	else:
		alert("A sea eagle is circling over %s! Get them under cover, or go and stand with them." % target.get("animal_name"))
	print("[wildlife] eagle over %s" % target.position)
	return r


func _near_any(p: Vector3, players: Array, r: float) -> bool:
	for pl: Dictionary in players:
		if (pl.pos as Vector3).distance_to(p) < r:
			return true
	return false


func _nearest_light(p: Vector3, lights: Array) -> float:
	var best := INF
	for l: Vector3 in lights:
		best = minf(best, l.distance_to(p))
	return best


## Raiders that lost their target pick another nearby duck (or give up).
func retarget(r: Raider) -> bool:
	var ls := _livestock()
	if ls == null or r.kind != &"fox":
		return false
	var lights := _lights()
	for a: Node3D in ls.animals:
		if a.species == &"shore_duck" and a.position.distance_to(r.raid_site) < 20.0 \
				and _nearest_light(a.position, lights) >= Raider.LIGHT_RADIUS:
			r.target_animal_id = int(a.get("animal_id"))
			return true
	return false


## The raider reached its target: take an egg, some feed, or (not on Cozy) a duck.
func resolve_raid(r: Raider) -> void:
	var ls := _livestock()
	var diff := _difficulty()
	if r.target_coop != Vector3i.MAX:
		var coop := coop_at(r.target_coop)
		if coop != null and int(coop.get("egg_count")) > 0:
			coop.set("egg_count", int(coop.get("egg_count")) - 1)
			if coop.has_method("_refresh_visuals"):
				coop.call("_refresh_visuals")
			if coop.manager != null:
				coop.manager._broadcast_state(coop)
			alert("A stoat stole an egg from the coop.")
		return
	if r.target_store != Vector3i.MAX:
		_rat_raid_store(r)
		return
	var a: Node3D = animal(r.target_animal_id)
	if a == null or ls == null:
		return
	if r.kind == &"eagle":
		if diff != CombatMath.Difficulty.COZY and rng.randf() < (0.7 if diff == CombatMath.Difficulty.UNDERTOW else 0.35):
			r.carried = a.serialize()
			ls.remove_animal(a)
			if WildlifeFX.current != null:
				WildlifeFX.current.feathers(r.position)
			alert("The sea eagle has snatched %s! Hit it to make it let go!" % r.carried.get("name", "a duck"))
			return
		if WildlifeFX.current != null:
			WildlifeFX.current.feathers(a.position)
		a.state = LivestockScript.State.WANDER
		a.yaw += PI
		a.state_t = 3.0
		alert("The sea eagle stooped on %s and missed. The ducks scatter, squawking." % a.animal_name)
		return
	if r.kind == &"fox" and diff != CombatMath.Difficulty.COZY:
		var chance := 0.85 if diff == CombatMath.Difficulty.UNDERTOW else 0.45
		if rng.randf() < chance:
			r.carried = a.serialize()
			ls.remove_animal(a)
			if WildlifeFX.current != null:
				WildlifeFX.current.feathers(r.position)
			alert("A fox has grabbed %s! Chase it before it reaches its den!" % r.carried.get("name", "a duck"))
			return
	if a.is_egg_ready():
		a.yield_timer = a.YIELD_INTERVAL_DUCK
		alert("A %s stole an egg from %s." % [r.kind, a.animal_name])
		return
	if r.kind == &"fox" and _eat_feed(a.position):
		alert("A fox raided the feed trough.")
		return
	alert("The %s sniffed round the pen and slunk off." % r.kind)


## A shore rat got into an open store: it eats a bite or two of the food.
func _rat_raid_store(r: Raider) -> void:
	var st := store_at(r.target_store)
	if st == null:
		return
	var food := st.raidable_food()
	if food.is_empty():
		alert("The shore rat found nothing it could get at.")
		return
	var bites: int = [1, 2, 3][clampi(_difficulty(), 0, 2)]
	var eaten := 0
	for i in bites:
		food = st.raidable_food()
		if food.is_empty():
			break
		var id: StringName = food[rng.randi() % food.size()]
		eaten += st.container.withdraw(id, 1)
	if st.manager != null:
		st.manager._broadcast_state(st)
	alert("A shore rat got into the %s and ate %d of your food. A sealed barrel would keep it out." % [st.entity_name, eaten])


func _eat_feed(near: Vector3) -> bool:
	var em := EntityManager.current
	if em == null:
		return false
	for e: WorldEntity in em.entities.values():
		if e is TroughEntity and e.position.distance_to(near) < 10.0 and (e as TroughEntity).has_feed():
			(e as TroughEntity).consume_feed()
			em._broadcast_state(e)
			return true
	return false


func drop_prey(r: Raider) -> void:
	if not r.is_carrying():
		return
	var ls := _livestock()
	var d: Dictionary = r.carried
	r.carried = {}
	if ls == null:
		return
	var a: Node3D = ls.spawn_animal(StringName(d.get("sp", &"shore_duck")), r.position, String(d.get("name", "")))
	a.deserialize(d)
	a.position = r.position
	alert("The %s dropped %s and fled!" % [kind_word(r.kind), d.get("name", "the duck")])


func prey_lost(r: Raider) -> void:
	if not r.is_carrying():
		return
	alert("The %s got away with %s." % [kind_word(r.kind), r.carried.get("name", "a duck")])
	r.carried = {}


func on_trapped(r: Raider, trap: LiveTrapEntity) -> void:
	mark_defended(r.raid_site, "trapped")
	alert("Something is caught in the live trap!")
	print("[wildlife] %s trapped at %s" % [r.kind, trap.position])


func on_raider_relocated(trap_pos: Vector3) -> void:
	mark_defended(trap_pos, "relocated")


func alert(text: String) -> void:
	net.wild_alert(text)


# ---------------------------------------------------------------- dens

func _den_for(target: Vector3, players: Array) -> Vector3:
	var best := Vector3.INF
	var bd := DEN_MAX_REUSE
	for d: Dictionary in dens:
		var dd := (d.p as Vector3).distance_to(target)
		if dd < bd and dd >= den_min_dist * 0.8:
			bd = dd
			best = d.p
	if best != Vector3.INF:
		return best
	var site := find_den_site(target, players)
	if site != Vector3.INF:
		dens.append({"p": site})
		_dens_changed()
		return site
	return _approach_point(target, target, players)


## A grassy spot in the woods, out of sight of players, `den_min_dist`+ from the farm.
func find_den_site(near: Vector3, players: Array) -> Vector3:
	var water_y: float = _main().sky.water_level_m()
	var best := Vector3.INF
	var best_score := -INF
	for t in 40:
		var c := _sample(near, den_min_dist, den_min_dist + 35.0)
		if c.is_empty() or not WorldGen.is_grassy(int(c.k)):
			continue
		var g := _ground(c)
		if is_nan(g) or g < water_y + 1.0:
			continue
		var p := _at(c, g)
		if _near_any(p, players, 20.0):
			continue
		var score := rng.randf() + (2.0 if _wooded(int(c.x), floori(g / VoxelWorld.VS), int(c.z)) else 0.0)
		if score > best_score:
			best_score = score
			best = p
	return best


func _wooded(x: int, y: int, z: int) -> bool:
	for d: Vector2i in [Vector2i(6, 0), Vector2i(-6, 0), Vector2i(0, 6), Vector2i(0, -6), Vector2i(0, 0)]:
		for dy in range(2, 14, 3):
			var m: int = net.voxel(x + d.x, y + dy, z + d.y)
			if m == Palette.TRUNK or m == Palette.LEAVES or m == Palette.LEAVES_DARK:
				return true
	return false


## Somewhere on land ~30 m from the target toward `from`, out of the players' way.
func _approach_point(target: Vector3, from: Vector3, players: Array) -> Vector3:
	var dir := from - target
	dir.y = 0.0
	if dir.length() < 1.0:
		var a := rng.randf() * TAU
		dir = Vector3(cos(a), 0, sin(a))
	dir = dir.normalized()
	var water_y: float = _main().sky.water_level_m()
	for t in 12:
		var d := dir.rotated(Vector3.UP, rng.randf_range(-1.0, 1.0)) * rng.randf_range(22.0, 32.0)
		var p := target + d
		var g := TerrainStep.ground_at(net.voxel, p.x, p.z, target.y, 30, 30)
		if not is_nan(g) and g > water_y + 0.3 and not _near_any(p, players, 15.0):
			return Vector3(p.x, g, p.z)
	return target + dir * 25.0


## Player `pid` fills in the den nearest `pos` (within reach). Authority.
func fill_den(pos: Vector3) -> bool:
	for i in dens.size():
		if (dens[i].p as Vector3).distance_to(pos) < 2.6:
			var p: Vector3 = dens[i].p
			dens.remove_at(i)
			den_min_dist = maxf(den_min_dist, DEN_MAX_REUSE)
			mark_defended(p, "relocated")
			_dens_changed()
			return true
	return false


func nearest_den(pos: Vector3, r: float) -> int:
	for i in dens.size():
		if (dens[i].p as Vector3).distance_to(pos) < r:
			return i
	return -1


func _dens_changed() -> void:
	rebuild_den_visuals()
	net.broadcast_dens(dens.duplicate(true))


func set_dens(list: Array) -> void:
	dens = list.duplicate(true)
	rebuild_den_visuals()


func rebuild_den_visuals() -> void:
	for n in _den_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_den_nodes.clear()
	if net == null or not net.is_inside_tree():
		return
	for d: Dictionary in dens:
		var n := _den_mesh()
		n.position = d.p
		net.add_child(n)
		_den_nodes.append(n)


static func _den_mesh() -> Node3D:
	var root := Node3D.new()
	root.name = "FoxDen"
	var g := Prefabs.Grid.new(14, 5, 12)
	g.box(0, 0, 0, 13, 1, 11, Palette.DIRT)
	g.box(2, 2, 2, 11, 3, 9, Palette.DIRT)
	g.box(4, 4, 4, 9, 4, 7, Palette.GRASS)
	g.box(5, 0, 10, 8, 2, 11, Palette.BEDROCK)       # the dark entrance
	g.box(5, 0, 8, 8, 1, 9, Palette.BEDROCK)
	for p: Vector3i in [Vector3i(1, 2, 3), Vector3i(12, 2, 6), Vector3i(3, 2, 10), Vector3i(10, 2, 1)]:
		g.setv(p.x, p.y, p.z, Palette.WHITEWASH)    # old bones and feathers
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	var u := VoxelWorld.VS * 0.5
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, u, mat, mat)
	mi.position = Vector3(-g.sx * 0.5, -0.05, -g.sz * 0.5) * u
	mi.visibility_range_end = 80.0
	root.add_child(mi)
	var l := Label3D.new()
	l.text = "Fox den"
	l.font_size = 40
	l.outline_size = 8
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 0.9, 0)
	l.visibility_range_end = 8.0
	root.add_child(l)
	return root


# ---------------------------------------------------------------- persistence

func serialize() -> Dictionary:
	var carried := []
	for c: Creature in net.creatures.values():
		if c is Raider and (c as Raider).is_carrying():
			carried.append((c as Raider).carried)
	return {"dens": dens.duplicate(true), "defended": defended.duplicate(true), "den_min": den_min_dist,
		"night": night_id, "raids_left": raids_left, "carried": carried,
		"otter_friends": otter_friends.keys(), "storm_day": last_storm_day,
		"rat_night": rat_night, "rats_left": rat_raids_left, "eagle_day": eagle_day, "eagles_left": eagles_left}


func deserialize(d: Variant) -> void:
	if not (d is Dictionary):
		return
	set_dens(d.get("dens", []))
	defended = (d.get("defended", []) as Array).duplicate(true)
	den_min_dist = float(d.get("den_min", DEN_MIN))
	night_id = int(d.get("night", -999))
	raids_left = int(d.get("raids_left", 0))
	last_storm_day = int(d.get("storm_day", -999))
	rat_night = int(d.get("rat_night", -999))
	rat_raids_left = int(d.get("rats_left", 0))
	eagle_day = int(d.get("eagle_day", -999))
	eagles_left = int(d.get("eagles_left", 0))
	otter_friends = {}
	for k in d.get("otter_friends", []):
		otter_friends[String(k)] = true
	# A duck that was mid-abduction when the game saved comes home safe (once the
	# livestock has loaded, which may be after us).
	_pending_carried = (d.get("carried", []) as Array).duplicate(true)


func _restore_carried() -> void:
	var ls := _livestock()
	if _pending_carried.is_empty() or ls == null:
		return
	for a: Dictionary in _pending_carried:
		if ls.get_animal_by_id(int(a.get("id", -1))) == null:
			var n: Node3D = ls.spawn_animal(StringName(a.get("sp", &"shore_duck")), a.get("pos", Vector3.ZERO), String(a.get("name", "")))
			n.deserialize(a)
	_pending_carried.clear()
