extends SceneTree
## Headless checks for archipelago streaming:
##   godot --headless --path . -s tests/world_check.gd
## 1. per-column generation is order independent (fresh generator, reversed order)
## 2. walking 300 m streams without long main-thread frames and unloads behind us
## 3. edits survive unload + reload, and edits far away generate their columns first

var world: VoxelWorld


func _init() -> void:
	world = VoxelWorld.new()
	root.add_child(world)
	_run.call_deferred()


func _frame() -> float:
	var t := Time.get_ticks_usec()
	await process_frame
	return (Time.get_ticks_usec() - t) / 1000.0


func _run() -> void:
	await world.generate(1106)
	var ok := true
	var gen: WorldGen = world.gen
	var spawn_m: Vector3 = gen.spawn * VoxelWorld.VS

	# 1. order independence
	var cols := [Vector2i(83, 70), Vector2i(84, 70), Vector2i(83, 71), Vector2i(90, 90)]
	var a := []
	for c in cols:
		a.append(gen.native.generate_column_debug(c.x, c.y))
	var g2 := WorldGen.new(1106, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, VoxelWorld.SEA_MID, VoxelWorld.TIDE_AMP)
	g2.plan_starter()
	var b := []
	for i in range(cols.size() - 1, -1, -1):
		b.push_front(g2.native.generate_column_debug(cols[i].x, cols[i].y))
	for i in cols.size():
		if a[i] != b[i]:
			ok = false
			print("[check] FAIL order independence at ", cols[i])
	print("[check] order independence: ", "ok" if ok else "FAIL")

	# 3a. edit at spawn
	var cell := Vector3i(gen.spawn) + Vector3i(4, -1, 4)
	world.apply_command({"t": "dig", "p": cell, "r": 2})
	var dug_before := world.get_voxel(cell.x, cell.y, cell.z)

	# 2. walk 300 m along +x at 7 m/s (60 fps)
	var worst := 0.0
	var total := 0.0
	var frames := 0
	var p := spawn_m
	while p.x < spawn_m.x + 300.0:
		p.x += 7.0 / 60.0
		world.focus_points = [p]
		var ms: float = await _frame()
		worst = maxf(worst, ms)
		total += ms
		frames += 1
	for i in 30:
		world.focus_points = [p]
		await _frame()
	var gen_cols := world.store.get_generated_columns().size()
	print("[check] walk: %d frames, avg %.2f ms, worst %.2f ms, generated columns %d, chunks %d, meshed chunks %d, verts %d" % [
		frames, total / frames, worst, gen_cols, world.store.get_chunk_count(), world.nodes.size(), world.stats_vertices])
	print("[check] main-thread usec totals [want, stream, remesh+sweep, lod] = ", world.prof, " worst = ", world.prof_max)
	print("[check] spawn column loaded after walking away: ", world.store.is_column_generated(Vector2i(cell.x >> 5, cell.z >> 5)), " (edited columns stay)")

	# 3b. far-away edit on an ungenerated column must generate first
	var far := Vector3i(int(gen.islands[2].center.x), 0, int(gen.islands[2].center.y))
	far.y = gen.col_h(far.x, far.z)
	var was := world.store.is_column_generated(Vector2i(far.x >> 5, far.z >> 5))
	world.apply_command({"t": "place", "p": far + Vector3i(0, 1, 0), "r": 0, "m": Palette.BUOY})
	print("[check] far edit: column generated before=%s after=%s, voxel=%d" % [was, world.store.is_column_generated(Vector2i(far.x >> 5, far.z >> 5)), world.get_voxel(far.x, far.y + 1, far.z)])

	# walk back and verify the spawn edit survived
	while p.x > spawn_m.x:
		p.x -= 7.0 / 60.0
		world.focus_points = [p]
		await _frame()
	for i in 30:
		await _frame()
	var dug_after := world.get_voxel(cell.x, cell.y, cell.z)
	print("[check] edit persistence: before=%d after=%d -> %s" % [dug_before, dug_after, "ok" if dug_before == dug_after and dug_after == 0 else "FAIL"])
	print("[check] static memory: %.1f MB" % (OS.get_static_memory_usage() / 1048576.0))
	quit()
