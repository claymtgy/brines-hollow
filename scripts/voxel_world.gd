class_name VoxelWorld
extends Node3D
## Scene-side wrapper around the native VoxelStore + ArchipelagoGen (C++, native/src/).
## C++ owns voxel data, generation, meshing, raycasts, collision and brush edits; this node
## streams chunk columns around focus points, uploads meshes, draws distant islands as
## low-detail LOD meshes, and owns the edit-command layer used by co-op.
## Edits travel over the network as small commands (dig sphere, place sphere,
## place prefab) — never as raw voxel data. Any edit first generates the columns it
## touches, so replaying commands anywhere in the world gives the same result on every peer.

signal dug(pos: Vector3, mat: int, count: int)
signal loading_progress(text: String, frac: float)

const VS := 0.18           # voxel size in metres (~1/10 of player height)
const CS := 32             # chunk size in voxels
const NCX := 176
const NCY := 4
const NCZ := 176
const WX := NCX * CS       # 5632 voxels = 1014 m (whole archipelago)
const WY := NCY * CS       # 128 voxels = 23 m
const WZ := NCZ * CS
const SEA_MID := 30.0      # in voxels
const TIDE_AMP := 7.0      # +-1.26 m tide

## Streaming radii in chunk columns (1 column = 5.76 m).
var mesh_radius := 10                  # full-detail meshes
var gen_margin := 1                    # data generated one ring further (correct border faces)
var unload_margin := 3                 # hysteresis before freeing
const MAX_GEN_TASKS := 10
const MAX_MESH_TASKS := 8
const MAX_UPLOAD_PER_FRAME := 4
const MAX_REMESH_PER_FRAME := 16

## LOD
const LOD_REGION := 256                # voxels per LOD region (46 m)
var lod_steps := [[110.0, 4], [300.0, 8], [INF, 16]]   # [max distance m, voxel step]

var store := VoxelStore.new()
var gen: WorldGen
var ready_for_play := false
## Positions (metres) that keep terrain loaded. Main sets this every frame.
var focus_points: Array = []

var terrain_mat: ShaderMaterial
var glow_mat: ShaderMaterial
var lod_mat: ShaderMaterial

var nodes := {}            # Vector3i chunk -> MeshInstance3D
var _meshed_cols := {}     # Vector2i -> true
var _want: Array = []      # Vector2i columns, nearest first
var _want_center := Vector2i(-99999, -99999)
var _gen_tasks := {}       # task id -> Vector2i
var _gen_inflight := {}    # Vector2i -> true
var _mesh_tasks := {}      # task id -> Vector2i
var _mesh_inflight := {}   # Vector2i -> true
var _col_results := {}     # Vector2i -> [[Vector3i, arrays], ...]
var _uploads: Array = []   # Vector2i ready to upload
var _pending := {}         # remesh task id -> Vector3i chunk
var _results := {}         # Vector3i chunk -> mesh arrays
var _requeue := {}         # dirty chunks waiting for a remesh slot
var _mutex := Mutex.new()
var _sweep_t := 0.0
var _loaded_radius := 0.0      # columns: contiguous fully-meshed disc around the focus

var _lod_regions: Array = []
var _lod_nodes := {}       # Vector2i -> MeshInstance3D
var _lod_level := {}       # Vector2i -> step currently shown/in flight
var _lod_tasks := {}       # task id -> [Vector2i, step]
var _lod_results := {}     # Vector2i -> [step, arrays]
var _lod_t := 0.0

var _lights := {}          # Vector3i -> OmniLight3D
var lamps_root: Node3D

var stats_vertices := 0
var stats_lod_vertices := 0
## Main-thread cost (usec) of [want, stream, remesh+sweep, lod]: totals and worst frame.
var prof := [0, 0, 0, 0]
var prof_max := [0, 0, 0, 0]


static func push_palette() -> void:
	var flags := PackedByteArray()
	var vari := PackedFloat32Array()
	for m in Palette.COLORS.size():
		flags.append((1 if Palette.is_emissive(m) else 0) | (2 if Palette.is_foliage(m) else 0))
		vari.append(Palette.VARIATION[m])
	VoxelStore.set_palette(Palette.COLORS, vari, flags)


func _ready() -> void:
	push_palette()
	Prefabs.all()
	store.setup(Vector3i(WX, WY, WZ), VS)
	# Terrain: vertex colour = material colour x AO, vertex alpha = variation amount.
	# Faces are greedy-merged natively, so the per-voxel brightness jitter is done here,
	# from the world-space voxel cell under each fragment.
	terrain_mat = ShaderMaterial.new()
	var tsh := Shader.new()
	tsh.code = """
shader_type spatial;
uniform float voxel = 0.18;
varying vec3 wpos;
varying vec3 wnrm;
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
uint hash3(ivec3 p) {
	uint h = uint(p.x) * 374761393u + uint(p.y) * 668265263u + uint(p.z) * 1442695041u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h = h ^ (h >> 16u);
	return h & 65535u;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	ivec3 cell = ivec3(floor(wpos / voxel - wnrm * 0.5));
	float b = 1.0 + (float(hash3(cell)) / 65535.0 - 0.5) * 2.0 * COLOR.a;
	ALBEDO = to_linear(clamp(COLOR.rgb * b, 0.0, 1.0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
"""
	terrain_mat.shader = tsh
	glow_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode specular_disabled;
uniform float strength = 2.2;
void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * strength;
}
"""
	glow_mat.shader = sh
	lod_mat = ShaderMaterial.new()
	var lsh := Shader.new()
	lsh.code = """
shader_type spatial;
render_mode specular_disabled, shadows_disabled;
// Full-detail terrain is drawn inside these circles (xz centre, radius in .z).
uniform vec4 holes[4];
uniform int hole_count = 0;
varying vec3 wp;
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	for (int i = 0; i < hole_count; i++) {
		if (distance(wp.xz, holes[i].xy) < holes[i].z) { discard; }
	}
	ALBEDO = to_linear(COLOR.rgb);
	ROUGHNESS = 0.95;
}
"""
	lod_mat.shader = lsh
	lamps_root = Node3D.new()
	lamps_root.name = "Lamps"
	add_child(lamps_root)


# ---------------------------------------------------------------- access

func get_voxel(x: int, y: int, z: int) -> int:
	return store.get_voxel(x, y, z)


## `mark` is kept for API compatibility; the store tracks dirty chunks itself.
func set_voxel(x: int, y: int, z: int, m: int, _mark := true) -> void:
	store.set_voxel(x, y, z, m)


func is_solid_at(p: Vector3) -> bool:
	return store.get_voxel(floori(p.x / VS), floori(p.y / VS), floori(p.z / VS)) != 0


## True if the terrain column under `p` (metres) has been generated.
## Queries elsewhere are answered from the height field (solid below ground, air above).
func is_loaded_at(p: Vector3) -> bool:
	return store.is_column_generated(Vector2i(floori(p.x / VS) >> 5, floori(p.z / VS) >> 5))


func aabb_collides(min_m: Vector3, max_m: Vector3) -> bool:
	return store.aabb_collides(min_m, max_m)


## Voxel DDA. Returns {} on miss, else {cell: Vector3i, normal: Vector3i, dist: float}.
func raycast(origin: Vector3, dir: Vector3, max_dist: float, see_through_foliage := false) -> Dictionary:
	return store.raycast(origin, dir, max_dist, see_through_foliage)


# ---------------------------------------------------------------- generation / startup

func generate(seed_value: int) -> void:
	ready_for_play = false
	var t0 := Time.get_ticks_msec()
	loading_progress.emit("Charting the archipelago...", 0.05)
	await get_tree().process_frame
	gen = WorldGen.new(seed_value, WX, WY, WZ, SEA_MID, TIDE_AMP)
	gen.plan_starter()
	store.set_generator(gen.native)
	for p: Vector3i in gen.stamp_lights:
		_add_light(p, Palette.LANTERN)
	var t1 := Time.get_ticks_msec()

	# Stream in the area around spawn before handing over control.
	focus_points = [gen.spawn * VS]
	_refresh_want(true)
	var need := 0
	for c: Vector2i in _want:
		if _col_dist(c) <= mesh_radius:
			need += 1
	while true:
		_stream_step(MAX_GEN_TASKS * 2, MAX_MESH_TASKS * 2, 64)
		var done := _meshed_cols.size()
		loading_progress.emit("Washing ashore... (%d/%d)" % [mini(done, need), need], 0.1 + 0.8 * float(done) / maxf(1.0, need))
		if done >= need and _uploads.is_empty():
			break
		await get_tree().process_frame
	var t2 := Time.get_ticks_msec()

	loading_progress.emit("Sighting distant islands...", 0.92)
	_lod_regions = gen.native.land_regions(LOD_REGION)
	_update_lod(true)
	while not _lod_tasks.is_empty():
		_collect_lod()
		await get_tree().process_frame
	_collect_lod()
	var t3 := Time.get_ticks_msec()
	store.take_dirty()
	print("[world] plan %d ms, spawn area %d ms (%d columns, %d chunks), lod %d ms (%d regions), verts %d near + %d lod" % [
		t1 - t0, t2 - t1, _meshed_cols.size(), nodes.size(), t3 - t2, _lod_regions.size(), stats_vertices, stats_lod_vertices])
	ready_for_play = true


# ---------------------------------------------------------------- streaming

var _fc: Array = []        # focus points as chunk columns (refreshed each frame)


func _focus_cols() -> Array:
	var out := []
	for p: Vector3 in focus_points:
		out.append(Vector2i(floori(p.x / VS) >> 5, floori(p.z / VS) >> 5))
	return out


func _col_dist(c: Vector2i) -> float:
	var best := INF
	for f: Vector2i in _fc:
		best = minf(best, Vector2(c - f).length())
	return best


func _refresh_want(force := false) -> void:
	var fc := _focus_cols()
	_fc = fc
	if fc.is_empty():
		return
	var key: Vector2i = fc[0]
	for f: Vector2i in fc:
		key += f * 7919  # cheap signature of all focus columns
	if not force and key == _want_center:
		return
	_want_center = key
	var r := mesh_radius + gen_margin
	var seen := {}
	var list := []
	for f: Vector2i in fc:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r + r:
					continue
				var c := Vector2i(f.x + dx, f.y + dz)
				if c.x < 0 or c.y < 0 or c.x >= NCX or c.y >= NCZ or seen.has(c):
					continue
				seen[c] = true
				list.append(c)
	var dist := {}
	for c: Vector2i in list:
		dist[c] = _col_dist(c)
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return dist[a] < dist[b])
	_want = list


func _process(delta: float) -> void:
	if gen == null:
		return
	if ready_for_play:
		var t0 := Time.get_ticks_usec()
		_refresh_want()
		var t1 := Time.get_ticks_usec()
		_stream_step(MAX_GEN_TASKS, MAX_MESH_TASKS, MAX_UPLOAD_PER_FRAME)
		var t2 := Time.get_ticks_usec()
		_remesh_dirty()
		_sweep_t -= delta
		if _sweep_t <= 0.0:
			_sweep_t = 1.0
			_sweep()
		var t3 := Time.get_ticks_usec()
		_lod_t -= delta
		if _lod_t <= 0.0:
			_lod_t = 0.5
			_update_lod(false)
		_collect_lod()
		var t4 := Time.get_ticks_usec()
		for k in 4:
			var dt: int = [t1 - t0, t2 - t1, t3 - t2, t4 - t3][k]
			prof[k] += dt
			prof_max[k] = maxi(prof_max[k], dt)
	_update_lod_holes()


func _stream_step(max_gen: int, max_mesh: int, max_upload: int) -> void:
	# Finished generation tasks.
	for t in _gen_tasks.keys():
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			_gen_inflight.erase(_gen_tasks[t])
			_gen_tasks.erase(t)
	# Finished mesh tasks -> upload queue.
	for t in _mesh_tasks.keys():
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			var c: Vector2i = _mesh_tasks[t]
			_mesh_tasks.erase(t)
			_uploads.append(c)
	# Upload a few columns per frame.
	var n := 0
	while not _uploads.is_empty() and n < max_upload:
		var c: Vector2i = _uploads.pop_front()
		_mesh_inflight.erase(c)
		_mutex.lock()
		var res: Array = _col_results.get(c, [])
		_col_results.erase(c)
		_mutex.unlock()
		if _col_dist(c) > mesh_radius + unload_margin:
			continue
		for pair: Array in res:
			_apply_mesh(pair[0], pair[1])
		_meshed_cols[c] = true
		n += 1
	_update_loaded_radius()
	# Dispatch generation, nearest first.
	for c: Vector2i in _want:
		if _gen_tasks.size() >= max_gen:
			break
		if _gen_inflight.has(c) or store.is_column_generated(c):
			continue
		_gen_inflight[c] = true
		_gen_tasks[WorkerThreadPool.add_task(store.generate_column.bind(c))] = c
	# Dispatch meshing for columns whose neighbours all exist.
	for c: Vector2i in _want:
		if _mesh_tasks.size() >= max_mesh:
			break
		if _meshed_cols.has(c) or _mesh_inflight.has(c) or _col_dist(c) > mesh_radius:
			continue
		var ok := true
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var nb := Vector2i(c.x + dx, c.y + dz)
				if nb.x < 0 or nb.y < 0 or nb.x >= NCX or nb.y >= NCZ:
					continue
				if not store.is_column_generated(nb):
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue
		_mesh_inflight[c] = true
		_mesh_tasks[WorkerThreadPool.add_task(_mesh_column_job.bind(c))] = c


func _update_loaded_radius() -> void:
	# _want is sorted by distance: the first unmeshed column bounds the solid disc.
	var r := float(mesh_radius) + 0.5
	for c: Vector2i in _want:
		var d := _col_dist(c)
		if d > mesh_radius:
			break
		if not _meshed_cols.has(c):
			r = d
			break
	_loaded_radius = r


func _mesh_column_job(c: Vector2i) -> void:
	var out := []
	for cy in NCY:
		var ch := Vector3i(c.x, cy, c.y)
		if store.has_chunk(ch):
			out.append([ch, store.mesh_chunk(ch)])
	_mutex.lock()
	_col_results[c] = out
	_mutex.unlock()


func _sweep() -> void:
	var far := mesh_radius + unload_margin
	for c: Vector2i in _meshed_cols.keys():
		if _col_dist(c) > far:
			for cy in NCY:
				var ch := Vector3i(c.x, cy, c.y)
				var mi: MeshInstance3D = nodes.get(ch)
				if mi != null:
					stats_vertices -= mi.get_meta("verts", 0)
					mi.queue_free()
					nodes.erase(ch)
			_meshed_cols.erase(c)
	for c: Vector2i in store.get_generated_columns():
		if _col_dist(c) > far + gen_margin and not _gen_inflight.has(c) and not _mesh_inflight.has(c):
			store.unload_column(c)  # keeps edited columns in memory


func _apply_mesh(c: Vector3i, res: Array) -> void:
	var mi: MeshInstance3D = nodes.get(c)
	if mi != null:
		stats_vertices -= mi.get_meta("verts", 0)
	if res[0] == null and res[1] == null:
		if mi != null:
			mi.queue_free()
			nodes.erase(c)
		return
	var mesh := ArrayMesh.new()
	var verts := 0
	if res[0] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res[0])
		mesh.surface_set_material(mesh.get_surface_count() - 1, terrain_mat)
		verts += (res[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if res[1] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res[1])
		mesh.surface_set_material(mesh.get_surface_count() - 1, glow_mat)
		verts += (res[1][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if mi == null:
		mi = MeshInstance3D.new()
		mi.position = Vector3(c * CS) * VS
		add_child(mi)
		nodes[c] = mi
	mi.mesh = mesh
	mi.set_meta("verts", verts)
	stats_vertices += verts


func _remesh_dirty() -> void:
	# Collect finished remesh jobs.
	for t in _pending.keys():
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			var c: Vector3i = _pending[t]
			_pending.erase(t)
			_mutex.lock()
			var res = _results.get(c)
			_results.erase(c)
			_mutex.unlock()
			if res != null and _meshed_cols.has(Vector2i(c.x, c.z)):
				_apply_mesh(c, res)
	for c: Vector3i in store.take_dirty():
		_requeue[c] = true
	if _requeue.is_empty():
		return
	var busy := {}
	for t in _pending:
		busy[_pending[t]] = true
	var launched := 0
	for c: Vector3i in _requeue.keys():
		var col := Vector2i(c.x, c.z)
		if busy.has(c) or _mesh_inflight.has(col):
			continue  # retry next frame
		_requeue.erase(c)
		if not _meshed_cols.has(col):
			continue  # not displayed; it will be meshed fresh when it streams in
		var t := WorkerThreadPool.add_task(_mesh_job.bind(c))
		_pending[t] = c
		launched += 1
		if launched >= MAX_REMESH_PER_FRAME:
			break


func _mesh_job(c: Vector3i) -> void:
	var res := store.mesh_chunk(c)
	_mutex.lock()
	_results[c] = res
	_mutex.unlock()


# ---------------------------------------------------------------- distant detail (LOD)

func _lod_step_for(r: Vector2i, cam: Vector3) -> int:
	var centre := (Vector2(r) + Vector2(0.5, 0.5)) * LOD_REGION * VS
	var d := centre.distance_to(Vector2(cam.x, cam.z))
	for pair: Array in lod_steps:
		if d < pair[0]:
			return pair[1]
	return 16


func _lod_eye() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return focus_points[0] if not focus_points.is_empty() else Vector3.ZERO


func _update_lod(all_now: bool) -> void:
	var eye := _lod_eye()
	for r: Vector2i in _lod_regions:
		var step := _lod_step_for(r, eye)
		if _lod_level.get(r, -1) == step:
			continue
		if not all_now and _lod_tasks.size() >= 6:
			break
		_lod_level[r] = step
		var t := WorkerThreadPool.add_task(_lod_job.bind(r, step))
		_lod_tasks[t] = [r, step]


func _lod_job(r: Vector2i, step: int) -> void:
	var arrays: Array = gen.native.build_lod(r, LOD_REGION, step)
	_mutex.lock()
	_lod_results[r] = [step, arrays]
	_mutex.unlock()


func _collect_lod() -> void:
	for t in _lod_tasks.keys():
		if not WorkerThreadPool.is_task_completed(t):
			continue
		WorkerThreadPool.wait_for_task_completion(t)
		var r: Vector2i = _lod_tasks[t][0]
		_lod_tasks.erase(t)
		_mutex.lock()
		var pr: Array = _lod_results.get(r, [])
		_lod_results.erase(r)
		_mutex.unlock()
		if pr.is_empty() or pr[0] != _lod_level.get(r, -1):
			continue
		var mi: MeshInstance3D = _lod_nodes.get(r)
		if mi != null:
			stats_lod_vertices -= mi.get_meta("verts", 0)
		var arrays: Array = pr[1]
		if arrays.is_empty():
			if mi != null:
				mi.queue_free()
				_lod_nodes.erase(r)
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, lod_mat)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(r.x * LOD_REGION, 0, r.y * LOD_REGION) * VS
			add_child(mi)
			_lod_nodes[r] = mi
		mi.mesh = mesh
		var nv := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		mi.set_meta("verts", nv)
		stats_lod_vertices += nv


func _update_lod_holes() -> void:
	if lod_mat == null:
		return
	var holes := PackedVector4Array()
	# Only cut the LOD where full-detail terrain actually exists (no sea-holes while loading).
	var radius := maxf(0.0, _loaded_radius - 1.0) * CS * VS
	for p: Vector3 in focus_points:
		if holes.size() >= 4:
			break
		holes.append(Vector4(p.x, p.z, radius, 0.0))
	while holes.size() < 4:
		holes.append(Vector4.ZERO)
	lod_mat.set_shader_parameter("holes", holes)
	lod_mat.set_shader_parameter("hole_count", mini(focus_points.size(), 4))


# ---------------------------------------------------------------- commands

## cmd: {t: "dig"|"place"|"prefab", p: Vector3i, r: int, m: int, id: int}
func apply_command(cmd: Dictionary) -> void:
	match cmd.get("t", ""):
		"dig":
			_dig(cmd.p, cmd.r)
		"place":
			_place(cmd.p, cmd.r, cmd.m)
		"prefab":
			apply_prefab(cmd.id, cmd.p, cmd.r, true)


func _dig(c: Vector3i, r: int) -> void:
	var res: Dictionary = store.dig_sphere(c, r)
	if res.count <= 0:
		return
	# Remove lamp lights whose voxel was dug away.
	for p: Vector3i in _lights.keys():
		if (p - c).length_squared() <= (r + 1) * (r + 1) and store.get_voxel(p.x, p.y, p.z) == 0:
			_lights[p].queue_free()
			_lights.erase(p)
	dug.emit((Vector3(c) + Vector3.ONE * 0.5) * VS, res.mat, res.count)


func _place(c: Vector3i, r: int, m: int) -> void:
	store.place_sphere(c, r, m)
	if Palette.is_emissive(m) and r == 0:
		_add_light(c, m)


func apply_prefab(id: int, origin: Vector3i, rot: int, _mark := true) -> void:
	if id < 0 or id >= Prefabs.count():
		return
	var pf := Prefabs.rotated(id, rot)
	var s: Vector3i = pf.size
	var base: Vector3i = origin - (pf.anchor as Vector3i)
	var data: PackedByteArray = pf.data
	store.stamp(data, s, base)
	# Foundations so prefabs sit nicely on uneven ground.
	match pf.foundation:
		"solid":
			for z in s.z:
				for x in s.x:
					var m := data[x + s.x * z]
					if m == 0 or m == Palette.CLEAR:
						continue
					store.fill_down(base.x + x, base.y - 1, base.z + z, Palette.COBBLE, 24)
		"posts":
			for c: Vector2i in [Vector2i(0, 0), Vector2i(s.x - 1, 0), Vector2i(0, s.z - 1), Vector2i(s.x - 1, s.z - 1)]:
				store.fill_down(base.x + c.x, base.y - 1, base.z + c.y, Palette.DARK_WOOD, 24)
	for l: Vector3i in pf.lights:
		_add_light(base + l, Palette.LANTERN)


func _add_light(p: Vector3i, m: int) -> void:
	if _lights.has(p) or _lights.size() > 48:
		return
	var l := OmniLight3D.new()
	l.position = (Vector3(p) + Vector3.ONE * 0.5) * VS
	l.light_color = Color(1.0, 0.78, 0.48) if m == Palette.LANTERN else Color(0.45, 1.0, 0.9)
	l.omni_range = 7.0
	l.omni_attenuation = 1.4
	l.light_energy = 0.0
	l.shadow_enabled = false
	l.add_to_group("lamps")
	lamps_root.add_child(l)
	_lights[p] = l
