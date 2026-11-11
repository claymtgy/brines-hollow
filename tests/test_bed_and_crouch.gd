extends SceneTree
## Standing on beds (tops that end mid-voxel) is steady; sneaking crouches the character.

const VS := VoxelWorld.VS
const FLOOR_Y := 10     # stone at y=10, so ground level is 11 * VS

var counts := {"total": 0, "passed": 0}


func check(name: String, cond: bool) -> void:
	counts.total += 1
	if cond:
		counts.passed += 1
		print("  [PASS] %s" % name)
	else:
		print("  [FAIL] %s" % name)


func _init() -> void:
	print("\n== Beds and crouching ==")
	process_frame.connect(_run, CONNECT_ONE_SHOT)


## Runs real player physics for `frames` and returns [min y, max y, frames on ground] over the
## last half (after it has settled).
func _settle(p: Player, frames: int) -> Array:
	var lo := INF
	var hi := -INF
	var grounded := 0
	for i in frames:
		p._physics_process(1.0 / 60.0)
		if i >= frames / 2:
			lo = minf(lo, p.position.y)
			hi = maxf(hi, p.position.y)
			grounded += 1 if p.on_ground else 0
	return [lo, hi, grounded]


func _run() -> void:
	var world := VoxelWorld.new()
	root.add_child(world)
	world.store.setup(Vector3i(64, 64, 64), VS)
	for x in range(0, 40):
		for z in range(0, 40):
			world.store.set_voxel(x, FLOOR_Y, z, Palette.STONE)
	world.ready_for_play = true

	var ents := EntityManager.new()
	root.add_child(ents)
	var bed_cell := Vector3i(20, FLOOR_Y + 1, 20)
	var bed: WorldEntity = ents.spawn_entity(&"fisher_bed", bed_cell)
	var bed_top := bed.get_aabb().end.y
	check("Bed top is mid-voxel (the old bounce)", absf(fmod(bed_top, VS)) > 0.01)

	var p := Player.new()
	p.rig = CameraRig.new()
	p.rig.cam = Camera3D.new()
	p.rig.add_child(p.rig.cam)
	root.add_child(p)
	p.world = world
	p.entities = ents
	p.input_enabled = false
	await process_frame

	# --- dropped onto the bed
	p.position = bed.position + Vector3(0, 1.0, 0)
	var r := _settle(p, 240)
	check("Lands on the bed's real top", absf(float(r[0]) - bed_top) < 0.005)
	check("No bounce: height steady while standing", float(r[1]) - float(r[0]) < 0.001)
	check("On the ground every frame", int(r[2]) == 120)

	# --- the floor still works
	p.position = Vector3(5.5, FLOOR_Y + 4, 5.5) * VS
	r = _settle(p, 240)
	check("Floor: lands on the voxel top", absf(float(r[0]) - (FLOOR_Y + 1) * VS) < 0.005 and float(r[1]) - float(r[0]) < 0.001)

	# --- stepping onto the bed from the floor
	var start := Vector3(bed.position.x, (FLOOR_Y + 1) * VS, bed.get_aabb().position.z - 0.4)
	p.position = start
	_settle(p, 20)
	var y0 := p.position.y
	for i in 40:
		p._move_horizontal(2, 0.03)
		p._physics_process(1.0 / 60.0)
	r = _settle(p, 120)
	check("Walking into the bed steps up onto it", absf(p.position.y - bed_top) < 0.005 and y0 < bed_top)
	check("And stays put on top after the step", float(r[1]) - float(r[0]) < 0.001 and int(r[2]) == 60)

	# --- tall furniture is still a wall, not a step
	var chest_cell := Vector3i(30, FLOOR_Y + 1, 30)
	var crate: WorldEntity = ents.spawn_entity(&"storage_crate", chest_cell)
	crate.size.y = 1.2
	p.position = Vector3(crate.position.x, (FLOOR_Y + 1) * VS, crate.get_aabb().position.z - 0.4)
	_settle(p, 20)
	for i in 40:
		p._move_horizontal(2, 0.03)
		p._physics_process(1.0 / 60.0)
	check("A 1.2 m crate blocks instead of being climbed", p.position.y < (FLOOR_Y + 1) * VS + 0.01)

	# --- sneaking crouches (combat normally comes from CreatureNet; a bare one is enough here)
	var cb := PlayerCombat.new()
	cb.player = p
	cb.set_process(false)
	cb.set_physics_process(false)
	cb.set_process_input(false)
	cb.set_process_unhandled_input(false)
	p.add_child(cb)
	p.combat = cb
	p.position = Vector3(5.5, FLOOR_Y + 1, 5.5) * VS
	_settle(p, 30)
	var m := p.model
	check("Standing: not crouching", not p.is_crouching())
	p.combat.sneaking = true
	check("Sneak on the ground crouches", p.is_crouching())
	for i in 60:
		m.crouching = p.is_crouching()
		m.animate(1.0 / 60.0, 0.0, true, false)
	check("Body drops into the crouch", m.body.position.y < -0.05)
	check("Torso leans forward", m.body.rotation.x > 0.3)
	check("Legs go into a stride (one forward, one back)",
		m.leg_l.rotation.x + m.body.rotation.x < -0.5 and m.leg_r.rotation.x + m.body.rotation.x > 0.5)
	# Feet on the ground: each foot's world height ~ 0 with the hips lowered.
	var foot_ok := true
	for leg: Node3D in [m.leg_l, m.leg_r]:
		var hip := m.body.transform * leg.position
		var ang := m.body.rotation.x + leg.rotation.x
		var foot_y := hip.y - 5.0 * CharacterModel.U * cos(ang)
		if absf(foot_y) > 0.03:
			foot_ok = false
			print("    foot at %.3f" % foot_y)
	check("Feet stay on the ground in the crouch", foot_ok)
	check("Camera lowers while crouched", p.eye_drop() > 0.12)
	p.position.y += 0.5
	p.on_ground = false
	check("In the air: no crouch", not p.is_crouching())
	p.combat.sneaking = false
	p.on_ground = true
	for i in 60:
		m.crouching = p.is_crouching()
		m.animate(1.0 / 60.0, 0.0, true, false)
	check("Let go: stands back up", absf(m.body.position.y) < 0.02 and p.eye_drop() < 0.001)

	# --- remote players see it
	var rp := RemotePlayer.new()
	root.add_child(rp)
	rp.setup(2)
	rp.apply_state(Vector3.ZERO, 0.0, 0.0, 1 | 4, 0, 0)
	check("Remote crouch flag reaches their model", rp.model.crouching)
	rp.apply_state(Vector3.ZERO, 0.0, 0.0, 1, 0, 0)
	check("And clears", not rp.model.crouching)

	print("Results: %d/%d passed" % [counts.passed, counts.total])
	quit(0 if counts.passed == counts.total else 1)
