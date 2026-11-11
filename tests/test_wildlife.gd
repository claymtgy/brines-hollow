extends SceneTree
## Wildlife, farm raids and their answers:  godot --headless --path . -s tests/test_wildlife.gd

var passed := 0
var total := 0
const VS := VoxelWorld.VS
const FLOOR := 20                  # fake ground: solid at or below this voxel y


## A flat sandy world. `walls` maps Vector2i(x, z) -> [from_y, to_y] solid voxel spans
## (relative to the first air row), so fences can be drawn.
class FakeNet:
	extends Node
	var main: Node
	var creatures := {}
	var wildlife: WildlifeDirector
	var difficulty := CombatMath.Difficulty.TIDEWATCH
	var walls := {}
	var despawned := []
	var alerts := []
	var gifts := []
	var water_floor := -1           # columns with x < this are sea (seabed at FLOOR - 8)
	var _next := 1

	func voxel(x: int, y: int, z: int) -> int:
		var top := FLOOR
		if x < water_floor:
			top = FLOOR - 8
		if y <= top:
			return Palette.SAND
		var w: Variant = walls.get(Vector2i(x, z))
		if w != null and y - (FLOOR + 1) >= int(w[0]) and y - (FLOOR + 1) <= int(w[1]):
			return Palette.PLANK
		return 0

	func is_authority() -> bool:
		return true

	func despawn(c: Creature) -> void:
		despawned.append(c)
		creatures.erase(c.cid)

	func spawn(kind: StringName, pos: Vector3, _cid := -1) -> Creature:
		var c: Creature
		match kind:
			&"fox": c = RedFox.new()
			&"stoat": c = Stoat.new()
			&"puffin": c = Puffin.new()
			_: return null
		c.setup(_next, self, pos, true)
		creatures[_next] = c
		_next += 1
		return c

	func _count(kind: StringName, near: Vector3, r: float) -> int:
		var n := 0
		for c: Creature in creatures.values():
			if c.kind == kind and (r <= 0.0 or c.position.distance_to(near) < r):
				n += 1
		return n

	var lights := []
	func _context() -> Dictionary:
		return {"lights": lights}

	func _ensure_column(_x: int, _z: int) -> void:
		pass

	func wild_alert(text: String) -> void:
		alerts.append(text)

	func wild_gift(pid: int, items: Array, _toast: String) -> void:
		gifts.append([pid, items])

	func broadcast_dens(_list: Array) -> void:
		pass


class FakeMain:
	extends Node
	var sky := SkyCycle.new()
	var livestock_mgr: Node
	var world = null


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


func player(pos: Vector3, opts := {}) -> Dictionary:
	var p := {"id": 7, "pos": pos, "speed": 4.0, "sneaking": false, "sprinting": false, "in_water": false,
		"has_bait": false, "has_light": false, "holding_fish": false}
	p.merge(opts, true)
	return p


func ctx(players: Array, opts := {}) -> Dictionary:
	var c := {"players": players, "lights": [], "water_y": (FLOOR - 2) * VS, "night": 0.0, "darkness": 0.0,
		"difficulty": CombatMath.Difficulty.TIDEWATCH}
	c.merge(opts, true)
	return c


func run(c: Creature, cx: Dictionary, seconds: float, net: FakeNet = null) -> void:
	var t := 0.0
	while t < seconds:
		if net != null and not net.creatures.has(c.cid):
			return
		c.simulate(0.05, cx)
		t += 0.05


func make_net() -> FakeNet:
	var net := FakeNet.new()
	var m := FakeMain.new()
	m.livestock_mgr = LivestockManager.new()
	net.main = m
	net.wildlife = WildlifeDirector.new(net)
	return net


func make(cls, net: FakeNet, pos: Vector3) -> Creature:
	var c: Creature = cls.new()
	c.setup(net._next, net, pos, true)
	net.creatures[net._next] = c
	net._next += 1
	return c


## A square ring of fence voxels around (cx, cz), half-size `r`, voxel span [y0, y1].
func ring(net: FakeNet, cx: int, cz: int, r: int, y0: int, y1: int) -> void:
	for i in range(-r, r + 1):
		for p: Vector2i in [Vector2i(cx + i, cz - r), Vector2i(cx + i, cz + r), Vector2i(cx - r, cz + i), Vector2i(cx + r, cz + i)]:
			net.walls[p] = [y0, y1]


func duck(net: FakeNet, pos: Vector3, egg := false) -> Node3D:
	var a: Node3D = net.main.livestock_mgr.spawn_animal(&"shore_duck", pos, "Pip")
	a.yield_timer = 0.0 if egg else 100.0
	return a


func raider(net: FakeNet, kind: StringName, pos: Vector3, target: Node3D) -> Raider:
	var r: Raider = net.spawn(kind, pos)
	r.den = pos + Vector3(-30, 0, 0)
	r.raid_site = target.position
	r.target_animal_id = target.animal_id
	return r


func _init() -> void:
	VoxelWorld.push_palette()
	ItemDB.init_db()
	Placeables.register_builtin()
	var ground := (FLOOR + 1) * VS
	var night := {"night": 1.0, "darkness": 1.0}

	print("-- terrain steps: fences, gaps and head-room")
	var net := make_net()
	var v := net.voxel
	var a := Vector3(10.05, ground, 10.05)
	check(is_equal_approx(TerrainStep.step(v, a, a + Vector3(0.3, 0, 0), 3), ground), "flat ground is walkable")
	net.walls[Vector2i(57, 55)] = [0, 6]     # solid board fence, full height
	var at := Vector3(56.5 * VS, ground, 55.5 * VS)
	var over := Vector3(57.5 * VS, ground, 55.5 * VS)
	check(is_nan(TerrainStep.step(v, at, over, 2)), "a boarded fence stops even a stoat")
	net.walls[Vector2i(57, 55)] = [3, 5]     # rail fence: open under the bottom rail
	check(not is_nan(TerrainStep.step(v, at, over, 3)), "a fox (3 voxels) slips under a rail fence")
	check(is_nan(TerrainStep.step(v, at, over, 5)), "a goat (5 voxels) can't")
	net.walls[Vector2i(57, 55)] = [2, 5]     # 2-voxel gap
	check(not is_nan(TerrainStep.step(v, at, over, 2)) and is_nan(TerrainStep.step(v, at, over, 3)), "a stoat fits a gap a fox can't")
	net.walls.clear()
	check(LivestockAnimal.new(&"shore_duck").clearance_voxels() == 3 and LivestockAnimal.new(&"salt_goat").clearance_voxels() == 5,
			"ducks need 3 voxels of head-room, goats 5")

	print("-- gates")
	var em := EntityManager.new()
	EntityManager.current = em
	var gate: GateEntity = em.spawn_entity(&"pen_gate", Vector3i(100, FLOOR + 1, 100), 0)
	var gp := gate.position
	check(gate.solid and TerrainStep.entity_blocked(gp, 0.15, 0.5), "a closed gate blocks animals")
	gate.server_action(&"toggle", {}, 1)
	check(gate.is_open and not TerrainStep.entity_blocked(gp, 0.15, 0.5), "an open gate lets them through")
	var gd := gate.serialize()
	var gate2 := GateEntity.new()
	gate2.deserialize(gd)
	check(gate2.is_open and not gate2.solid and gate2.entity_id == &"pen_gate", "gate state saves and loads")
	em.remove_entity(gate.grid_coord)

	print("-- ambient wildlife")
	var hare: CoastalHare = make(CoastalHare, net, a)
	run(hare, ctx([player(a + Vector3(4, 0, 0))]), 0.3)
	check(hare.state == Creature.State.FLEE, "a walking player makes the hare bolt")
	var p0 := hare.position
	run(hare, ctx([player(a + Vector3(4, 0, 0))]), 1.0)
	check(hare.position.distance_to(a + Vector3(4, 0, 0)) > p0.distance_to(a + Vector3(4, 0, 0)), "it runs away")
	hare = make(CoastalHare, net, a)
	run(hare, ctx([player(a + Vector3(4, 0, 0), {"sneaking": true, "speed": 1.0})]), 0.5)
	check(hare.state != Creature.State.FLEE, "a sneaking player can watch it graze")
	check(not hare.damageable and hare.on_hit(10.0, a, 1.0, 7) and hare.hp == hare.max_hp, "ambient animals can't be harmed (they just startle)")

	var puffins := []
	for i in 4:
		puffins.append(make(Puffin, net, a + Vector3(i * 0.4, 0, 20)))
	run(puffins[0], ctx([player(a + Vector3(0, 0, 16))]), 0.1)
	var all_up := true
	for pf: Puffin in puffins:
		all_up = all_up and pf.state == Creature.State.FLEE
	check(all_up, "startle one puffin and the whole colony goes up")

	var heron: GreyHeron = make(GreyHeron, net, a + Vector3(0, 0, 40))
	run(heron, ctx([player(a + Vector3(0, 0, 33))]), 0.2)
	check(heron.state == Creature.State.FLEE, "the heron lifts off when you walk up")
	heron = make(GreyHeron, net, a + Vector3(0, 0, 60))
	run(heron, ctx([player(a + Vector3(0, 0, 54), {"sneaking": true, "speed": 1.0})]), 0.5)
	check(heron.state != Creature.State.FLEE, "...but not if you sneak")

	net.water_floor = 80                     # x < 80 voxels is sea
	var sea := Vector3(40 * VS, (FLOOR - 2) * VS, 40 * VS)
	var otter: SeaOtter = make(SeaOtter, net, sea)
	var swim_ctx := ctx([player(sea + Vector3(2, 0, 0), {"speed": 0.0})])
	run(otter, swim_ctx, 0.2)
	check(otter.state != Creature.State.FLEE, "an otter lets a still player come near")
	otter.befriend(7)
	check(otter.is_friend(), "offering a fish befriends it")
	run(otter, ctx([player(sea + Vector3(6, 0, 0), {"speed": 0.0})]), 1.5)
	check(otter.position.distance_to(sea + Vector3(6, 0, 0)) < 5.0, "a friendly otter follows you along the water")
	run(otter, ctx([player(otter.position + Vector3(1, 0, 0), {"speed": 0.0})]), 50.0)
	check(net.gifts.size() >= 1 and int(net.gifts[0][0]) == 7, "...and brings you gifts from the seabed")
	var wild: SeaOtter = make(SeaOtter, net, sea + Vector3(0, 0, 4))
	run(wild, ctx([player(sea + Vector3(1, 0, 4), {"speed": 4.0, "sprinting": true})]), 0.2)
	check(wild.state == Creature.State.FLEE, "splashing about makes a wild otter dive")

	var seal_pos := Vector3(82 * VS, ground, 40 * VS)    # on the shore next to the sea
	var seal: HarbourSeal = make(HarbourSeal, net, seal_pos)
	run(seal, ctx([player(seal_pos + Vector3(5, 0, 0))]), 0.3)
	check(seal.state == Creature.State.FLEE, "a hauled-out seal startles at footsteps")
	run(seal, ctx([player(seal_pos + Vector3(5, 0, 0))]), 4.0)
	check(seal.position.x < seal_pos.x, "...and humps back toward the sea")
	net.water_floor = -1

	print("-- raids: answers that work")
	var site := Vector3(150.5 * VS, ground, 150.5 * VS)
	net = make_net()
	net.difficulty = CombatMath.Difficulty.COZY
	var d := duck(net, site, true)
	var fox := raider(net, &"fox", site + Vector3(8, 0, 0), d)
	run(fox, ctx([], night), 10.0, net)
	check(fox.state == Creature.State.REPELLED and d.yield_timer > 0.0, "a fox that reaches an unguarded duck on Cozy takes only an egg")

	net = make_net()
	net.difficulty = CombatMath.Difficulty.COZY
	var carried_on_cozy := 0
	for i in 12:
		d = duck(net, site, false)
		fox = raider(net, &"fox", site + Vector3(6, 0, 0), d)
		run(fox, ctx([], night), 8.0, net)
		if fox.is_carrying() or net.main.livestock_mgr.get_animal_by_id(d.animal_id) == null:
			carried_on_cozy += 1
	check(carried_on_cozy == 0, "Cozy: foxes never take an animal")

	net = make_net()
	net.difficulty = CombatMath.Difficulty.UNDERTOW
	var took := false
	for i in 8:
		d = duck(net, site, false)
		fox = raider(net, &"fox", site + Vector3(6, 0, 0), d)
		run(fox, ctx([], night), 3.0, net)
		if fox.is_carrying():
			took = true
			break
	check(took and fox.state == Creature.State.RETURN, "Undertow: a fox carries a duck off toward its den")
	var ducks_before: int = net.main.livestock_mgr.animals.size()
	run(fox, ctx([player(fox.position + Vector3(3, 0, 0))], night), 0.2, net)
	check(not fox.is_carrying() and net.main.livestock_mgr.animals.size() == ducks_before + 1 and fox.state == Creature.State.FLEE,
			"chasing it makes the fox drop the duck and bolt")
	check(net.wildlife.is_defended(fox.raid_site), "...and it remembers this farm is defended")

	net = make_net()
	d = duck(net, site, true)
	fox = raider(net, &"fox", site + Vector3(10, 0, 0), d)
	run(fox, ctx([], {"night": 1.0, "darkness": 1.0, "lights": [site + Vector3(0, 0.8, 1.0)]}), 2.0, net)
	check(fox.state == Creature.State.REPELLED and d.yield_timer == 0.0, "a lantern by the pen turns the fox back")
	check(net.wildlife.is_defended(site), "the lit farm is remembered as defended")

	net = make_net()
	var cx := 150
	ring(net, cx, cx, 8, 0, 6)               # a boarded Pen Fence all the way round
	d = duck(net, site, true)
	fox = raider(net, &"fox", site + Vector3(14 * VS + 2.0, 0, 0), d)
	run(fox, ctx([], night), Raider.GIVE_UP_AFTER + 5.0, net)
	check(fox.state == Creature.State.REPELLED and d.yield_timer == 0.0, "a closed Pen Fence keeps the fox out; it gives up")

	net = make_net()
	net.difficulty = CombatMath.Difficulty.COZY   # egg, not the duck: deterministic
	ring(net, cx, cx, 8, 3, 5)               # a rail fence: gap underneath
	d = duck(net, site, true)
	fox = raider(net, &"fox", site + Vector3(14 * VS + 2.0, 0, 0), d)
	run(fox, ctx([], night), 15.0, net)
	check(d.yield_timer > 0.0, "a rail fence doesn't: the fox slips under it")

	net = make_net()
	em = EntityManager.new()
	EntityManager.current = em
	var trap_coord := Vector3i(floori(site.x / VS) + 20, FLOOR + 1, floori(site.z / VS))
	var trap: LiveTrapEntity = em.spawn_entity(&"live_trap", trap_coord, 0)
	trap.server_action(&"bait", {"item": &"kelp_frond"}, 1)
	check(trap.is_baited(), "a trap can be baited")
	d = duck(net, site, true)
	fox = raider(net, &"fox", site + Vector3(8, 0, 0), d)
	run(fox, ctx([], night), 10.0, net)
	check(trap.trap_state == LiveTrapEntity.TrapState.CAUGHT and trap.caught_kind == &"fox" and not net.creatures.has(fox.cid),
			"a baited live trap catches the fox unharmed")
	check(d.yield_timer == 0.0, "...before it reaches the pen")
	var res := trap.server_action(&"release", {}, 1)
	check(res.get("changed", false) and trap.trap_state == LiveTrapEntity.TrapState.EMPTY, "releasing it on a far islet empties the trap")
	var td := trap.serialize()
	var trap2 := LiveTrapEntity.new()
	trap2.deserialize(td)
	check(trap2.entity_id == &"live_trap" and trap2.trap_state == LiveTrapEntity.TrapState.EMPTY, "trap state saves and loads")
	em.remove_entity(trap_coord)
	EntityManager.current = null

	net = make_net()
	d = duck(net, site, true)
	var stoat := raider(net, &"stoat", site + Vector3(8, 0, 0), d)
	run(stoat, ctx([], night), 8.0, net)
	check(d.yield_timer > 0.0 and net.main.livestock_mgr.get_animal_by_id(d.animal_id) != null, "a stoat steals an egg but never the duck")

	print("-- director: memory, dens, persistence")
	net = make_net()
	var w := net.wildlife
	w.mark_defended(site, "light")
	check(w.is_defended(site + Vector3(5, 0, 0)) and not w.is_defended(site + Vector3(80, 0, 0)), "defence memory covers the farm, not the island")
	net.main.sky.day += 5
	check(not w.is_defended(site), "...for a few days only")
	w.dens = [{"p": site + Vector3(40, 0, 0)}]
	check(w.fill_den(site + Vector3(41, 0, 0)) and w.dens.is_empty() and w.den_min_dist >= WildlifeDirector.DEN_MAX_REUSE,
			"filling in a den moves the foxes further off")
	w.dens = [{"p": Vector3(1, 2, 3)}]
	w.mark_defended(site, "fence")
	var saved := w.serialize()
	var w2 := WildlifeDirector.new(net)
	w2.deserialize(saved)
	check(w2.dens.size() == 1 and w2.defended.size() == saved.defended.size(), "dens and memory save and load")
	d = duck(net, site)
	stoat = raider(net, &"fox", site, d)
	stoat.carried = d.serialize()
	net.main.livestock_mgr.remove_animal(d)
	var with_carried := w.serialize()
	var w3 := WildlifeDirector.new(net)
	w3.deserialize(with_carried)
	w3._restore_carried()
	check(net.main.livestock_mgr.get_animal_by_id(d.animal_id) != null, "a duck mid-abduction at save time comes home safe on load")

	print("-- lights from placed entities")
	check(LanternEntity.new().emits_light() and StationEntity.new(&"campfire", "Campfire").emits_light()
			and not StationEntity.new(&"workbench", "Workbench").emits_light(), "lanterns and fires count as light, workbenches don't")
	check(Placeables.build_cost(&"lantern_post").size() > 0 and Placeables.build_cost(&"pen_gate").size() > 0
			and Placeables.build_cost(&"live_trap").size() > 0, "lantern post, pen gate and live trap are buildable")
	# Blueprint ids are saved in worlds, so existing ones must keep their slot (new ones append after).
	check(Prefabs.count() > 12 and Prefabs.all()[12].name == "Pen Fence", "Pen Fence blueprint exists at its saved id (12)")
	var saved_ids := ["Plank Wall", "Window Wall", "Door Wall", "Deck Floor", "Stairs", "Fisher's Hut", "Dock",
		"Lamp Post", "Fence", "Stone Arch", "Drying Rack", "Rowboat", "Pen Fence"]
	var ids_ok := Prefabs.count() >= saved_ids.size()
	for i in saved_ids.size():
		ids_ok = ids_ok and Prefabs.all()[i].name == saved_ids[i]
	check(ids_ok, "existing blueprint ids unchanged (new blueprints only appended)")

	print("-- polish: merchant visits survive a reload, gamepad dodge/sneak")
	var tm := TradeManager.new()
	var tmain := FakeMain.new()
	tm.main = tmain
	tmain.sky.time_of_day = (TradeManager.DOCKED_FROM + TradeManager.DOCKED_UNTIL) * 0.5
	tm._visits = 3
	tm.merchant = MerchantBoat.new("Test Peddler", MerchantBoat.MerchantType.RAFT_PEDDLER)
	var first: StringName = tm.merchant.stock.slots[0].item_id
	tm.merchant.stock.remove_item(first, 1)
	var left: int = tm.merchant.stock.get_item_count(first)
	var tsave := tm._save_state()
	var tm2 := TradeManager.new()
	tm2.main = tmain
	tm2._load_state(tsave)
	check(tm2._visits == 3 and tm2.merchant != null and tm2.merchant.stock.get_item_count(first) == left and tm2._was_docked,
			"a docked merchant keeps its stock (and doesn't restock) across a save")
	tmain.sky.time_of_day = 0.05
	check(not tm._save_state().has("merchant"), "no ship is saved when none is docked")
	ControllerManager.new().setup_input_map()
	var pad_dodge := false
	var pad_sneak := false
	var sprint_on_b := false
	for ev in InputMap.action_get_events(&"dodge"):
		pad_dodge = pad_dodge or (ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_B)
	for ev in InputMap.action_get_events(&"sneak"):
		pad_sneak = pad_sneak or (ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_RIGHT_STICK)
	for ev in InputMap.action_get_events(&"sprint"):
		sprint_on_b = sprint_on_b or (ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_B)
	check(pad_dodge and pad_sneak and not sprint_on_b, "gamepad: B/Circle dodges, R3 sneaks, B no longer sprints")

	print("Wildlife suite: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
