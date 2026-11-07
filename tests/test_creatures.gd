extends SceneTree
## Creatures & optional combat:  godot --headless --path . -s tests/test_creatures.gd

var passed := 0
var total := 0
const VS := VoxelWorld.VS


class FakeNet:
	extends Node
	var floor_y := 20            # solid at or below this voxel y
	var walls_around := Vector3i(-999, 0, 0)   # solid ring (Chebyshev dist >= 2) around this cell
	var hurts := []
	var despawned := []
	var stolen := []
	var difficulty := CombatMath.Difficulty.TIDEWATCH

	func voxel(x: int, y: int, z: int) -> int:
		if y <= floor_y:
			return Palette.SAND
		if walls_around.x > -999 and y <= floor_y + 4 and maxi(absi(x - walls_around.x), absi(z - walls_around.z)) >= 2:
			return Palette.STONE
		return 0

	func hurt_player(pid: int, base: float, _from: Vector3, _c: Creature) -> void:
		hurts.append([pid, CombatMath.incoming_damage(base, difficulty)])

	func despawn(c: Creature) -> void:
		despawned.append(c)

	func steal_fish(pid: int, _g: Creature) -> void:
		stolen.append(pid)


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
	var c := {"players": players, "lights": [], "water_y": 3.0, "night": 0.0, "darkness": 0.0,
		"difficulty": CombatMath.Difficulty.TIDEWATCH}
	c.merge(opts, true)
	return c


func run(c: Creature, cx: Dictionary, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		c.simulate(0.05, cx)
		t += 0.05


var _made: Array = []


func make(cls, net: FakeNet, pos: Vector3) -> Creature:
	var c: Creature = cls.new()
	c.setup(1, net, pos, true)
	_made.append(c)
	return c


func _init() -> void:
	VoxelWorld.push_palette()
	ItemDB.init_db()
	var ground := (20 + 1) * VS   # top of the fake floor

	print("-- combat math")
	check(CombatMath.incoming_damage(6.0, CombatMath.Difficulty.COZY) == 0.0, "Cozy: creatures never hurt players")
	check(is_equal_approx(CombatMath.incoming_damage(6.0, CombatMath.Difficulty.UNDERTOW), 9.6), "Undertow: 1.6x damage")
	check(not CombatMath.hostiles_allowed(CombatMath.Difficulty.COZY), "Cozy: no hostiles allowed")
	var cut := CombatMath.weapon_stats(ItemDB.get_item(&"rusty_cutlass"))
	check(cut.damage == 15.0 and cut.reach_m == 2.0, "rusty cutlass stats come from its weapon_data")
	check(CombatMath.weapon_stats(null).damage == 4, "unarmed fallback")
	check(is_equal_approx(CombatMath.outgoing_damage(cut, true, false), 22.5), "staggered targets take 1.5x")
	check(CombatMath.outgoing_damage(cut, false, true) < 15.0, "underwater swings are weaker")
	var o := Vector3.ZERO
	check(CombatMath.in_swing_arc(o, Vector3.FORWARD, Vector3(0, 0, -1.5), 2.0), "target in front within reach is hit")
	check(not CombatMath.in_swing_arc(o, Vector3.FORWARD, Vector3(0, 0, 1.5), 2.0), "target behind is not hit")
	check(not CombatMath.in_swing_arc(o, Vector3.FORWARD, Vector3(0, 0, -4.0), 2.0), "target out of reach is not hit")
	check(CombatMath.parry_succeeds(0.1, o, Vector3.FORWARD, Vector3(0, 0, -2)), "parry in window vs frontal attack succeeds")
	check(not CombatMath.parry_succeeds(0.5, o, Vector3.FORWARD, Vector3(0, 0, -2)), "late parry fails")
	check(not CombatMath.parry_succeeds(0.1, o, Vector3.FORWARD, Vector3(0, 0, 2)), "parry can't block attacks from behind")
	check(CombatMath.dodge_protects(0.2) and not CombatMath.dodge_protects(0.5) and not CombatMath.dodge_protects(-1.0), "dodge i-frames only during the roll")

	print("-- perception")
	var sneak := Perception.noise_radius(3.0, true, false, false)
	var walk := Perception.noise_radius(3.0, false, false, false)
	var sprint := Perception.noise_radius(6.0, false, true, false)
	check(sneak < walk and walk < sprint, "sneaking < walking < sprinting noise")
	check(Perception.can_see(o, Vector3.FORWARD, 90.0, 8.0, Vector3(0, 0, -5)), "sees target in cone")
	check(not Perception.can_see(o, Vector3.FORWARD, 90.0, 8.0, Vector3(0, 0, 5)), "doesn't see behind")
	check(not Perception.can_see(o, Vector3.FORWARD, 90.0, 8.0, Vector3(0, 0, -5), 1.0), "darkness shortens sight")
	check(Perception.is_lit(Vector3(1, 0, 0), [Vector3.ZERO]) and not Perception.is_lit(Vector3(9, 0, 0), [Vector3.ZERO]), "light radius")

	print("-- tide-crab")
	var net := FakeNet.new()
	var cpos := Vector3(10, ground, 10)
	var crab: TideCrab = make(TideCrab, net, cpos)
	run(crab, ctx([player(cpos + Vector3(2.5, 0, 0))]), 0.3)
	check(crab.state == Creature.State.FLEE, "walking player nearby scares the crab")
	crab = make(TideCrab, net, cpos)
	run(crab, ctx([player(cpos + Vector3(2.5, 0, 0), {"sneaking": true, "speed": 1.5})]), 0.3)
	check(crab.state != Creature.State.FLEE, "sneaking player doesn't scare it (if unseen)")
	crab = make(TideCrab, net, cpos)
	var bait_p := cpos + Vector3(4, 0, 0)
	run(crab, ctx([player(bait_p, {"has_bait": true})]), 2.0)
	check(crab.state == Creature.State.LURED and crab.position.distance_to(bait_p) < 2.0, "bait lures the crab close")
	net.walls_around = Vector3i(floori(cpos.x / VS), 0, floori(cpos.z / VS))
	crab = make(TideCrab, net, cpos)
	run(crab, ctx([player(cpos + Vector3(0.6, 0, 0))]), 2.5)
	check(net.hurts.size() >= 1 and net.hurts[0][1] > 0.0, "cornered crab telegraphs, then pinches (Tidewatch)")
	net.hurts.clear()
	crab = make(TideCrab, net, cpos)
	run(crab, ctx([player(cpos + Vector3(0.6, 0, 0))], {"difficulty": CombatMath.Difficulty.COZY}), 2.5)
	check(net.hurts.is_empty() and crab.state != Creature.State.WINDUP, "Cozy: cornered crab never pinches")
	net.walls_around = Vector3i(-999, 0, 0)
	crab = make(TideCrab, net, cpos)
	run(crab, ctx([], {"water_y": ground + 1.0}), 0.1)
	check(net.despawned.has(crab), "rising tide makes the crab bury itself (despawn)")
	crab = make(TideCrab, net, cpos)
	crab.on_hit(20.0, cpos + Vector3(1, 0, 0), 1.0, 7)
	check(crab.state == Creature.State.DEAD and crab.drops()[0][0] == &"shore_crab" and crab.last_attacker == 7, "killing a crab drops shore crab for the attacker")

	print("-- cave eel")
	net = FakeNet.new()
	net.floor_y = 2
	var wy := 5.4
	var epos := Vector3(20, 4.2, 20)
	var eel: CaveEel = make(CaveEel, net, epos)
	eel.yaw = 0.0   # facing +z
	var edge := player(epos + Vector3(0, 1.4, 2.5), {"speed": 3.0})
	run(eel, ctx([edge], {"water_y": wy, "night": 1.0, "darkness": 1.0}), 0.15)
	check(eel.state == Creature.State.ALERT or eel.state == Creature.State.WINDUP, "eel notices a player at the water's edge")
	run(eel, ctx([edge], {"water_y": wy, "night": 1.0, "darkness": 1.0}), 1.6)
	check(net.hurts.size() >= 1 and is_equal_approx(net.hurts[0][1], CaveEel.BITE), "after a readable windup the eel bites")
	net.hurts.clear()
	eel = make(CaveEel, net, epos)
	run(eel, ctx([edge], {"water_y": wy, "night": 1.0, "darkness": 1.0, "lights": [epos + Vector3(1, 1, 0)]}), 2.5)
	check(net.hurts.is_empty() and eel.state == Creature.State.REPELLED, "light by the water repels the eel")
	eel = make(CaveEel, net, epos)
	eel.yaw = 0.0
	run(eel, ctx([player(epos + Vector3(0, 1.4, -3.0), {"sneaking": true, "speed": 1.2})], {"water_y": wy, "night": 1.0, "darkness": 1.0}), 1.5)
	check(net.hurts.is_empty() and eel.state != Creature.State.WINDUP, "sneaking past behind the eel goes unnoticed")
	eel = make(CaveEel, net, epos)
	run(eel, ctx([edge], {"water_y": wy, "night": 1.0, "difficulty": CombatMath.Difficulty.COZY}), 2.5)
	check(net.hurts.is_empty(), "Cozy: eel never attacks")
	eel = make(CaveEel, net, epos)
	eel.set_state(Creature.State.WINDUP)
	eel.on_parried()
	check(eel.state == Creature.State.STAGGER and eel.is_staggered(), "parry staggers the eel")
	var hp0 := eel.hp
	eel.on_hit(10.0, epos + Vector3(0, 1, 2), 1.0, 3)
	check(eel.hp == hp0 - 10.0, "hits reduce eel health")
	eel.on_hit(999.0, epos, 1.0, 3)
	check(eel.state == Creature.State.DEAD and eel.drops()[0][0] == &"lightning_eel", "dead eel drops a lightning eel")

	print("-- gulls")
	net = FakeNet.new()
	var gull: Gull = make(Gull, net, Vector3(0, 10, 0))
	gull.flock_center = Vector3(0, 3, 0)
	var ghp := gull.hp
	gull.on_hit(50.0, Vector3.ZERO, 1.0, 1)
	check(gull.state == Creature.State.FLEE and gull.hp == ghp, "gulls scatter but can't be harmed")
	run(gull, ctx([], {"night": 1.0}), 0.1)
	check(net.despawned.has(gull), "gulls roost (despawn) at night")
	gull = make(Gull, net, Vector3(0, 10, 0))
	gull.set_state(Creature.State.WINDUP)
	run(gull, ctx([player(Vector3(0, 3, 0), {"holding_fish": true, "speed": 0.0})]), 3.0)
	check(net.stolen.has(7), "a gull swoops on a still player holding fish")

	print("-- faint & respawn")
	var v := VitalityController.new()
	var fainted := [false]
	v.player_defeated.connect(func(_p: Vector3) -> void: fainted[0] = true)
	v.take_damage(999.0, &"physical", Vector3.ZERO)
	check(v.is_defeated and fainted[0], "lethal damage faints the player (signal for respawn)")
	v.revive(Vector3(1, 2, 3))
	check(not v.is_defeated and v.current_hp == v.get_max_hp(), "revive restores the player")

	for c: Creature in _made:
		c.free()
	print("Summary: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
