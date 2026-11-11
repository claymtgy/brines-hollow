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
signal tree_felled(base_pos: Vector3, height_m: float, canopy_radius_m: float, is_pine: bool, trunk_voxels: int)
signal loading_progress(text: String, frac: float)

const VS := 0.18           # voxel size in metres (~1/10 of player height)
const CS := 32             # chunk size in voxels
const TIDE_AMP := 7.0      # +-1.26 m tide

## World layout, stored per world in world.json ("layout"). Worlds saved before layouts
## existed are layout 1; new worlds use LAYOUT_NEW. The sizes below are set by
## apply_layout() before a world is generated and stay fixed while it is played.
##   layout 1: 5632 voxels (1014 m) across, 128 tall (23 m), sea at 30 (5.4 m)
##   layout 2: 14336 voxels (2580 m) across, 256 tall (46 m), sea at 64 (11.5 m);
##             home island ~700 m across, other islands 1.6x larger, land twice as tall
const LAYOUT_NEW := 2
static var layout := 1
static var NCX := 176
static var NCY := 4
static var NCZ := 176
static var WX := 5632      # NCX * CS
static var WY := 128       # NCY * CS
static var WZ := 5632
static var SEA_MID := 30.0 # in voxels


## Native generator parameters for a layout (ArchipelagoGen.set_layout). Layout 1 = defaults.
static func layout_params(v: int) -> Dictionary:
	if v >= 2:
		return {"home_r": 2760.0, "std_rmin": 608.0, "std_rmax": 896.0, "islet_rmin": 152.0,
			"islet_rmax": 304.0, "std_count": 8, "islet_count": 18, "vscale": 2.0, "floor_depth": 21.0, "caves": true}
	return {}


static func apply_layout(v: int) -> void:
	layout = 2 if v >= 2 else 1
	if layout == 2:
		NCX = 448; NCY = 8; NCZ = 448; SEA_MID = 64.0
	else:
		NCX = 176; NCY = 4; NCZ = 176; SEA_MID = 30.0
	WX = NCX * CS
	WY = NCY * CS
	WZ = NCZ * CS

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
var sky: SkyCycle = null

var _water_conn_cache: Dictionary = {}
var _water_mask_image: Image = null
var _water_mask_tex: ImageTexture = null
var _water_mask_rect: Vector4 = Vector4.ZERO
var _water_mask_center: Vector2 = Vector2(-99999, -99999)
var _water_mask_t: float = 0.0
var _dirty_water_mask: bool = true
var _last_mask_water_level: float = -999.0
var _tree_hits: Dictionary = {}
var last_felled_grid: Prefabs.Grid = null
var last_felled_grid_offset: Vector3 = Vector3.ZERO
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
		flags.append((1 if Palette.is_emissive(m) else 0) | (2 if Palette.is_foliage(m) else 0) | (4 if Palette.is_plant(m) else 0) | (8 if Palette.is_leafy(m) else 0))
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
// Foliage fade: leaves near the line from the camera (fade_eye) to the player's head
// (fade_target) are dithered away so trees never hide your character.
uniform bool fade_enabled = true;
uniform vec3 fade_eye = vec3(0.0);
uniform vec3 fade_target = vec3(0.0);
uniform float fade_radius = 1.6;
uniform float leaf_holes = 0.34;   // fraction of each leaf face that's open
uniform vec3 view_pos = vec3(0.0); // the player's camera (also used in the shadow pass)
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
varying vec3 lin_col;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	lin_col = to_linear(COLOR.rgb);   // once per vertex, not per pixel
}
const float BAYER[16] = float[](0.0, 0.5, 0.125, 0.625, 0.75, 0.25, 0.875, 0.375,
		0.1875, 0.6875, 0.0625, 0.5625, 0.9375, 0.4375, 0.8125, 0.3125);
void fragment() {
	// Vertex alpha = colour-variation amount, +0.5 when the voxel is foliage, +0.75 for leaf blocks.
	bool foliage = COLOR.a >= 0.5;
	bool leafy = COLOR.a >= 0.75;
	float variation = leafy ? COLOR.a - 0.75 : (foliage ? COLOR.a - 0.5 : COLOR.a);
	if (leafy && leaf_holes > 0.0) {
		// Leaves are partly see-through: a fixed scatter of small gaps (a quarter-voxel
		// grid, anchored to the world so it doesn't swim), thinning out with distance so far
		// trees read as solid. Shadows get the same gaps: dappled light under the trees.
		vec3 lp = wpos / (voxel * 0.25) - wnrm * 0.1;
		uint g = hash3(ivec3(floor(lp)) + ivec3(7, 131, 17));
		float far_k = 1.0 - smoothstep(28.0, 60.0, length(wpos - view_pos));
		if (float(g) / 65535.0 < leaf_holes * far_k) { discard; }
	}
	if (foliage && fade_enabled) {
		vec3 ab = fade_target - fade_eye;
		float t = dot(wpos - fade_eye, ab) / max(dot(ab, ab), 1e-4);
		if (t > -0.1 && t < 1.0) {
			float d = distance(wpos, fade_eye + ab * clamp(t, 0.0, 1.0));
			float k = smoothstep(fade_radius, fade_radius * 0.4, d) * 0.9;
			ivec2 fc = ivec2(FRAGCOORD.xy) & ivec2(3);
			if (k > BAYER[fc.x + fc.y * 4]) { discard; }
		}
	}
	ivec3 cell = ivec3(floor(wpos / voxel - wnrm * 0.5));
	ivec3 med_cell = ivec3(floor(wpos / (voxel * 0.5) - wnrm * 0.5));
	ivec3 sub_cell = ivec3(floor(wpos / (voxel * 0.25) - wnrm * 0.5));
	float h_block = float(hash3(cell)) / 65535.0 - 0.5;
	float h_med = float(hash3(med_cell + ivec3(19, 47, 73))) / 65535.0 - 0.5;
	float h_sub = float(hash3(sub_cell + ivec3(101, 211, 307))) / 65535.0 - 0.5;
	float h_tint = float(hash3(sub_cell + ivec3(53, 89, 137))) / 65535.0 - 0.5;
	float var_amt = max(variation, 0.045);
	float b = 1.0 + (h_block * 0.95 + h_med * 0.65 + h_sub * 0.85) * var_amt;
	vec3 tint_shift = vec3(1.0 + h_tint * var_amt * 0.55, 1.0 + h_tint * var_amt * 0.15, 1.0 - h_tint * var_amt * 0.55);
	vec3 uv3 = fract(wpos / voxel - wnrm * 0.02);
	vec3 edge3 = min(uv3, 1.0 - uv3);
	float face_edge = min(min(edge3.x + abs(wnrm.x), edge3.y + abs(wnrm.y)), edge3.z + abs(wnrm.z));
	float bevel = mix(0.955, 1.0, smoothstep(0.0, 0.09, face_edge));
	ALBEDO = clamp(lin_col * tint_shift * pow(max(b, 0.2), 2.2) * bevel, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(0.91 - h_sub * 0.12, 0.72, 0.98);
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
	invalidate_water()


func is_solid_at(p: Vector3) -> bool:
	var m := store.get_voxel(floori(p.x / VS), floori(p.y / VS), floori(p.z / VS))
	return m != 0 and not Palette.is_plant(m)


func invalidate_water() -> void:
	_dirty_water_mask = true
	_water_conn_cache.clear()


func is_water_at(world_pos: Vector3, water_level_m: float = -1.0) -> bool:
	if water_level_m < 0.0:
		water_level_m = sky.water_level_m() if sky != null else SEA_MID * VS
	if world_pos.y >= water_level_m:
		return false
	var vx := floori(world_pos.x / VS)
	var vy := floori(world_pos.y / VS)
	var vz := floori(world_pos.z / VS)
	if vx < 0 or vx >= WX or vz < 0 or vz >= WZ or vy < 0 or vy >= WY:
		return false
	if store.get_voxel(vx, vy, vz) != 0:
		return false
	var sea_vox := floori(water_level_m / VS)
	if gen != null:
		var nat_h: int = gen.col_h(vx, vz)
		if nat_h < sea_vox - 1:
			var has_roof := false
			for ty in range(vy + 1, min(vy + 10, WY)):
				if store.get_voxel(vx, ty, vz) != 0:
					has_roof = true
					break
			if not has_roof:
				return true
	return _is_cell_connected_to_sea(Vector3i(vx, vy, vz), sea_vox)


func _is_cell_connected_to_sea(cell: Vector3i, sea_vox: int) -> bool:
	var key: int = (cell.x & 0x3FFF) | ((cell.z & 0x3FFF) << 14) | ((cell.y & 0xFF) << 28)
	if _water_conn_cache.has(key):
		return _water_conn_cache[key]

	if _water_conn_cache.size() > 8000:
		_water_conn_cache.clear()

	var visited := {}
	var visited_keys: Array[int] = []
	var queue: Array[Vector3i] = [cell]
	visited[cell] = true
	visited_keys.append(key)
	var is_connected := false
	var steps := 0
	const MAX_STEPS := 256

	while not queue.is_empty() and steps < MAX_STEPS:
		steps += 1
		var curr: Vector3i = queue.pop_front()

		# Check if curr reaches open ocean
		if gen != null and gen.col_h(curr.x, curr.z) < sea_vox - 1:
			var roof := false
			for ty in range(curr.y + 1, min(curr.y + 8, WY)):
				if store.get_voxel(curr.x, ty, curr.z) != 0:
					roof = true
					break
			if not roof:
				is_connected = true
				break

		# Explore adjacent air voxels
		for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
			var n: Vector3i = curr + offset
			# Water cannot flow over a rim/lip higher than sea level
			if n.y > sea_vox or n.y < 0:
				continue
			if n.x < 0 or n.x >= WX or n.z < 0 or n.z >= WZ:
				continue
			if visited.has(n):
				continue
			visited[n] = true
			if store.get_voxel(n.x, n.y, n.z) == 0:
				var k: int = (n.x & 0x3FFF) | ((n.z & 0x3FFF) << 14) | ((n.y & 0xFF) << 28)
				visited_keys.append(k)
				queue.append(n)

	for k in visited_keys:
		_water_conn_cache[k] = is_connected

	return is_connected


func update_water_mask(center_m: Vector3, force := false) -> void:
	if gen == null or sky == null or sky.water_mat == null:
		return
	var c_xz := Vector2(center_m.x, center_m.z)
	var water_changed: bool = absf(sky.water_level_vox - _last_mask_water_level) >= 0.08
	if not force and not _dirty_water_mask and not water_changed and (_water_mask_center.distance_squared_to(c_xz) < 36.0):
		return
	if water_changed:
		_water_conn_cache.clear()
	_water_mask_center = c_xz
	_dirty_water_mask = false
	_last_mask_water_level = sky.water_level_vox

	var size_m := 160.0
	var origin_x := center_m.x - size_m * 0.5
	var origin_z := center_m.z - size_m * 0.5
	_water_mask_rect = Vector4(origin_x, origin_z, size_m, size_m)

	var N := 192
	var step_m := size_m / float(N)
	var sea_vox: int = floori(sky.water_level_vox)

	var bytes := PackedByteArray()
	bytes.resize(N * N)

	for pz in N:
		var wz := origin_z + (float(pz) + 0.5) * step_m
		var vz := floori(wz / VS)
		var row_start := pz * N
		for px in N:
			var wx := origin_x + (float(px) + 0.5) * step_m
			var vx := floori(wx / VS)

			if vx < 0 or vx >= WX or vz < 0 or vz >= WZ:
				bytes[row_start + px] = 255
				continue

			var nat_h: int = gen.col_h(vx, vz)
			if nat_h < sea_vox - 1:
				if store.get_voxel(vx, sea_vox, vz) != 0:
					bytes[row_start + px] = 0
				else:
					bytes[row_start + px] = 255
			else:
				# Island landmass: dry unless excavated air cell connects to the sea
				if store.get_voxel(vx, sea_vox, vz) == 0 and _is_cell_connected_to_sea(Vector3i(vx, sea_vox, vz), sea_vox):
					bytes[row_start + px] = 255
				else:
					bytes[row_start + px] = 0

	if _water_mask_image == null or _water_mask_image.get_width() != N:
		_water_mask_image = Image.create_from_data(N, N, false, Image.FORMAT_R8, bytes)
		_water_mask_tex = ImageTexture.create_from_image(_water_mask_image)
	else:
		_water_mask_image.set_data(N, N, false, Image.FORMAT_R8, bytes)
		_water_mask_tex.update(_water_mask_image)

	sky.water_mat.set_shader_parameter("water_mask", _water_mask_tex)
	sky.water_mat.set_shader_parameter("water_mask_rect", _water_mask_rect)


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
	store.setup(Vector3i(WX, WY, WZ), VS)   # the layout may have changed since _ready
	if sky != null and sky.has_method("fit_to_world"):
		sky.fit_to_world()
	gen = WorldGen.new(seed_value, WX, WY, WZ, SEA_MID, TIDE_AMP, layout_params(layout))
	gen.plan_starter()
	if layout >= 2:
		gen.plan_villages()
		gen.plan_camps()
		gen.plan_underground()
		gen.plan_wrecks()
		gen.plan_outposts()
		gen.plan_hulk()
		gen.plan_siren()
		gen.plan_sunken_ruins()
		gen.plan_frost_shoals()
		gen.plan_maelstrom_spire()
		gen.plan_calamity_galleons()
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
	if ready_for_play and sky != null:
		var water_changed: bool = absf(sky.water_level_vox - _last_mask_water_level) >= 0.08
		_water_mask_t -= delta
		if _water_mask_t <= 0.0 or _dirty_water_mask or water_changed:
			_water_mask_t = 0.35
			var c_m: Vector3 = focus_points[0] if not focus_points.is_empty() else Vector3(WX * 0.5 * VS, 0.0, WZ * 0.5 * VS)
			update_water_mask(c_m)


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
			# "fell": only a hatchet brings a whole tree down (older commands without the flag did).
			_dig(cmd.p, cmd.r, bool(cmd.get("allow_stone", true)), bool(cmd.get("allow_wood", true)), bool(cmd.get("fell", true)), int(cmd.get("tool_tier", 0)))
		"flatten":
			_flatten(cmd.p, int(cmd.get("r", 2)), int(cmd.get("target_y", cmd.p.y)))
		"place":
			_place(cmd.p, cmd.r, cmd.m)
		"prefab":
			apply_prefab(cmd.id, cmd.p, cmd.r, true)
		"grow_tree":
			grow_tree_at(cmd.p, int(cmd.get("s", 1)))


const STONE_MATS := [Palette.STONE, Palette.SANDSTONE_A, Palette.SANDSTONE_B, Palette.SANDSTONE_C, Palette.COBBLE,
	Palette.COPPER_VEIN, Palette.IRON_VEIN, Palette.CALAMINE]
const WOOD_MATS := [Palette.TRUNK, Palette.PLANK, Palette.DARK_WOOD, Palette.ROOF_RED, Palette.ROOF_BLUE, Palette.SHUTTER]


static func is_stone_mat(m: int) -> bool:
	return m in STONE_MATS


static func is_wood_mat(m: int) -> bool:
	return m in WOOD_MATS


func _dig(c: Vector3i, r: int, allow_stone: bool = true, allow_wood: bool = true, fell: bool = true, tool_tier: int = 0) -> void:
	var center_mat := store.get_voxel(c.x, c.y, c.z)
	var removed_count := 0
	var primary_mat := center_mat
	var felled_trunk_count := 0

	# Detect if any tree trunk voxel is touched by this cut BEFORE removing the sphere
	var hit_trunk := false
	var trunk_seed := c
	if allow_wood and fell:
		if center_mat == Palette.TRUNK:
			hit_trunk = true
			trunk_seed = c
		else:
			var scan_r := maxi(r, 1)
			for dy in range(-scan_r, scan_r + 1):
				if hit_trunk:
					break
				for dz in range(-scan_r, scan_r + 1):
					if hit_trunk:
						break
					for dx in range(-scan_r, scan_r + 1):
						if store.get_voxel(c.x + dx, c.y + dy, c.z + dz) == Palette.TRUNK:
							hit_trunk = true
							trunk_seed = Vector3i(c.x + dx, c.y + dy, c.z + dz)
							break

	# Locate the true horizontal center and bottom-most root of the trunk before digging
	var tree_cx := trunk_seed.x
	var tree_cz := trunk_seed.z
	var tree_base_y := trunk_seed.y
	if hit_trunk:
		var sum_x := 0
		var sum_z := 0
		var sample_n := 0
		for dy in range(-2, 4):
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					if store.get_voxel(trunk_seed.x + dx, trunk_seed.y + dy, trunk_seed.z + dz) == Palette.TRUNK:
						sum_x += trunk_seed.x + dx
						sum_z += trunk_seed.z + dz
						sample_n += 1
		if sample_n > 0:
			tree_cx = roundi(float(sum_x) / float(sample_n))
			tree_cz = roundi(float(sum_z) / float(sample_n))
		# Walk downward to the very bottom of the trunk
		for dy in range(1, 20):
			var check_y := trunk_seed.y - dy
			if check_y <= 1:
				break
			var has_trunk_layer := false
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if store.get_voxel(tree_cx + dx, check_y, tree_cz + dz) == Palette.TRUNK:
						has_trunk_layer = true
						break
				if has_trunk_layer:
					break
			if has_trunk_layer:
				tree_base_y = check_y
			else:
				break

	# Ore veins in the dig get their own drops, even when most of the dig is plain stone.
	var vein_counts := {}
	if allow_stone:
		for dz in range(-r, r + 1):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dy * dy + dz * dz <= r * r:
						var vm := store.get_voxel(c.x + dx, c.y + dy, c.z + dz)
						if vm == Palette.COPPER_VEIN or vm == Palette.IRON_VEIN or vm == Palette.CALAMINE:
							vein_counts[vm] = int(vein_counts.get(vm, 0)) + 1

	if allow_stone and allow_wood:
		var res_all: Dictionary = store.dig_sphere(c, r)
		removed_count = int(res_all.count)
		primary_mat = int(res_all.mat)
	else:
		var min_col := Vector2i(maxi(0, (c.x - r) >> 5), maxi(0, (c.z - r) >> 5))
		var max_col := Vector2i(mini(NCX - 1, (c.x + r) >> 5), mini(NCZ - 1, (c.z + r) >> 5))
		for cz in range(min_col.y, max_col.y + 1):
			for cx in range(min_col.x, max_col.x + 1):
				var col := Vector2i(cx, cz)
				if not store.is_column_generated(col):
					store.generate_column(col)
		var r2 := r * r
		var mat_counts := {}
		for dz in range(-r, r + 1):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dy * dy + dz * dz > r2:
						continue
					var vx := c.x + dx
					var vy := c.y + dy
					var vz := c.z + dz
					if vx < 0 or vx >= WX or vy <= 1 or vy >= WY or vz < 0 or vz >= WZ:
						continue
					var m := store.get_voxel(vx, vy, vz)
					if m == 0:
						continue
					if not allow_stone and is_stone_mat(m):
						continue
					if not allow_wood and is_wood_mat(m):
						continue
					store.set_voxel(vx, vy, vz, 0)
					removed_count += 1
					mat_counts[m] = int(mat_counts.get(m, 0)) + 1
		if primary_mat == 0 or (not allow_stone and is_stone_mat(primary_mat)) or (not allow_wood and is_wood_mat(primary_mat)):
			var best_m := 0
			var best_n := 0
			for m_key in mat_counts.keys():
				if int(mat_counts[m_key]) > best_n:
					best_n = int(mat_counts[m_key])
					best_m = int(m_key)
			primary_mat = best_m

	# If chopping a tree trunk, fell the ENTIRE tree (base stump, full trunk, branches, and full canopy)!
	if allow_wood and fell and (hit_trunk or center_mat == Palette.TRUNK or primary_mat == Palette.TRUNK):
		# Durability hits: lower tier axes require more hits before the tree falls
		if tool_tier > 0:
			var t_key := Vector2i(tree_cx, tree_cz)
			if not _tree_hits.has(t_key):
				# Tier 1 (driftwood): 6 hits; Tier 2 (stone): 4 hits; Tier 3 (copper): 3 hits; Tier 4 (iron): 2 hits
				_tree_hits[t_key] = maxi(1, 7 - tool_tier)
			_tree_hits[t_key] -= 1
			if int(_tree_hits[t_key]) > 0:
				# Not felled yet: play wood chip hit fx and do not fell tree
				dug.emit((Vector3(c) + Vector3.ONE * 0.5) * VS, Palette.TRUNK, 1)
				return
			_tree_hits.erase(t_key)

		var canopy_rad := 14
		var grid_r := canopy_rad
		var grid_sx := grid_r * 2 + 1
		var grid_sz := grid_r * 2 + 1
		var grid_sy := 46
		var tree_grid := Prefabs.Grid.new(grid_sx, grid_sy, grid_sz)

		var t_min_col := Vector2i(maxi(0, (tree_cx - canopy_rad) >> 5), maxi(0, (tree_cz - canopy_rad) >> 5))
		var t_max_col := Vector2i(mini(NCX - 1, (tree_cx + canopy_rad) >> 5), mini(NCZ - 1, (tree_cz + canopy_rad) >> 5))
		for cz in range(t_min_col.y, t_max_col.y + 1):
			for cx in range(t_min_col.x, t_max_col.x + 1):
				var col := Vector2i(cx, cz)
				if not store.is_column_generated(col):
					store.generate_column(col)

		var top_y := tree_base_y
		var max_leaf_r2 := 9
		var dark_leaves := 0
		var light_leaves := 0
		var empty_layers := 0

		for vy in range(maxi(2, tree_base_y - 1), mini(WY - 1, tree_base_y + 44)):
			var found_layer := false
			var dy := vy - tree_base_y
			var scan_rad := 4 if dy < 3 else canopy_rad
			for dz in range(-scan_rad, scan_rad + 1):
				for dx in range(-scan_rad, scan_rad + 1):
					var d2 := dx * dx + dz * dz
					if d2 > scan_rad * scan_rad:
						continue
					var vx := tree_cx + dx
					var vz := tree_cz + dz
					if vx < 0 or vx >= WX or vz < 0 or vz >= WZ:
						continue
					var m := store.get_voxel(vx, vy, vz)
					if m == Palette.TRUNK and abs(dx) <= 4 and abs(dz) <= 4:
						tree_grid.setv(dx + grid_r, dy, dz + grid_r, m)
						store.set_voxel(vx, vy, vz, 0)
						felled_trunk_count += 1
						found_layer = true
						top_y = maxi(top_y, vy)
					elif (m == Palette.LEAVES or m == Palette.LEAVES_DARK) and dy >= 2:
						tree_grid.setv(dx + grid_r, dy, dz + grid_r, m)
						store.set_voxel(vx, vy, vz, 0)
						found_layer = true
						top_y = maxi(top_y, vy)
						max_leaf_r2 = maxi(max_leaf_r2, d2)
						if m == Palette.LEAVES_DARK:
							dark_leaves += 1
						else:
							light_leaves += 1
			if dy > 6:
				if not found_layer:
					empty_layers += 1
					if empty_layers >= 3:
						break
				else:
					empty_layers = 0

		if felled_trunk_count > 0 or dark_leaves + light_leaves > 0:
			last_felled_grid = tree_grid
			last_felled_grid_offset = Vector3(-grid_r, 0, -grid_r)
			primary_mat = Palette.TRUNK
			removed_count += maxi(12, felled_trunk_count * 4)
			var base_world_pos := Vector3(float(tree_cx) + 0.5, float(tree_base_y), float(tree_cz) + 0.5) * VS
			var height_m := clampf(float(top_y - tree_base_y + 1) * VS, 2.5, 7.5)
			var canopy_r_m := clampf(sqrt(float(max_leaf_r2)) * VS, 0.9, 2.4)
			var is_pine := dark_leaves > light_leaves
			tree_felled.emit(base_world_pos, height_m, canopy_r_m, is_pine, felled_trunk_count)

	var res := {"count": removed_count, "mat": primary_mat}
	if false:
		pass
	if res.count <= 0:
		return
	# Remove lamp lights whose voxel was dug away.
	for p: Vector3i in _lights.keys():
		if (p - c).length_squared() <= (r + 1) * (r + 1) and store.get_voxel(p.x, p.y, p.z) == 0:
			_lights[p].queue_free()
			_lights.erase(p)
	dug.emit((Vector3(c) + Vector3.ONE * 0.5) * VS, res.mat, res.count)
	for vm: int in vein_counts:
		if vm != res.mat:
			dug.emit((Vector3(c) + Vector3.ONE * 0.5) * VS, vm, int(vein_counts[vm]))
	invalidate_water()


func _place(c: Vector3i, r: int, m: int) -> void:
	store.place_sphere(c, r, m)
	invalidate_water()
	if Palette.is_emissive(m) and r == 0:
		_add_light(c, m)


func _flatten(c: Vector3i, r: int, target_y: int) -> void:
	var min_col := Vector2i(maxi(0, (c.x - r) >> 5), maxi(0, (c.z - r) >> 5))
	var max_col := Vector2i(mini(NCX - 1, (c.x + r) >> 5), mini(NCZ - 1, (c.z + r) >> 5))
	for cz in range(min_col.y, max_col.y + 1):
		for cx in range(min_col.x, max_col.x + 1):
			var col := Vector2i(cx, cz)
			if not store.is_column_generated(col):
				store.generate_column(col)

	var removed_count := 0
	var primary_mat := 0
	var max_reach_y := target_y + 16
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r + 1:
				continue
			var vx := c.x + dx
			var vz := c.z + dz
			for vy in range(target_y + 1, max_reach_y + 1):
				var m := store.get_voxel(vx, vy, vz)
				if m != 0:
					store.set_voxel(vx, vy, vz, 0)
					removed_count += 1
					if primary_mat == 0:
						primary_mat = m

	if removed_count > 0:
		for cz in range(min_col.y, max_col.y + 1):
			for cx in range(min_col.x, max_col.x + 1):
				var col := Vector2i(cx, cz)
				for cy in range(maxi(0, target_y >> 5), mini(NCY - 1, max_reach_y >> 5) + 1):
					_requeue[Vector3i(cx, cy, cz)] = true
		dug.emit((Vector3(c.x, target_y, c.z) + Vector3.ONE * 0.5) * VS, primary_mat, removed_count)
		invalidate_water()


func apply_prefab(id: int, origin: Vector3i, rot: int, _mark := true) -> void:
	if id < 0 or id >= Prefabs.count():
		return
	var pf := Prefabs.rotated(id, rot)
	var s: Vector3i = pf.size
	var base: Vector3i = origin - (pf.anchor as Vector3i)
	var data: PackedByteArray = pf.data
	store.stamp(data, s, base)
	invalidate_water()
	# Foundations so prefabs sit nicely on uneven ground.
	match pf.foundation:
		"solid", "solid_stone":
			for z in s.z:
				for x in s.x:
					var m := data[x + s.x * z]
					if m == 0 or m == Palette.CLEAR:
						continue
					store.fill_down(base.x + x, base.y - 1, base.z + z, Palette.COBBLE, 36)
		"solid_timber", "solid_wood":
			for z in s.z:
				for x in s.x:
					var m := data[x + s.x * z]
					if m == 0 or m == Palette.CLEAR:
						continue
					store.fill_down(base.x + x, base.y - 1, base.z + z, Palette.DARK_WOOD, 36)
		"posts":
			for c: Vector2i in [Vector2i(0, 0), Vector2i(s.x - 1, 0), Vector2i(0, s.z - 1), Vector2i(s.x - 1, s.z - 1)]:
				store.fill_down(base.x + c.x, base.y - 1, base.z + c.y, Palette.DARK_WOOD, 36)
	for l: Vector3i in pf.lights:
		_add_light(base + l, Palette.LANTERN)


func grow_tree_at(origin: Vector3i, tree_seed: int = 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var trunk_h := rng.randi_range(17, 23)
	var total_h := trunk_h + 5
	var rad := 8
	var sx := rad * 2 + 1
	var sz := rad * 2 + 1
	var g := Prefabs.Grid.new(sx, total_h, sz)
	var cx := rad
	var cz := rad
	# Each grown pine leans a little its own way, and its tiers are ragged and off-centre.
	var lean_a := rng.randf() * TAU
	var lean := rng.randf_range(0.0, 0.07)
	var bend := func(y: int) -> Vector2i:
		var sc := float(y) * (1.0 + float(y) * 0.03) * lean
		return Vector2i(clampi(roundi(cos(lean_a) * sc), -2, 2), clampi(roundi(sin(lean_a) * sc), -2, 2))

	# Tiered conical pine canopy
	var tier_k := 1.0
	for y in range(5, total_h):
		if (y - 5) % 4 == 0:
			tier_k = rng.randf_range(0.78, 1.18)
		var frac := float(y - 5) / float(maxi(1, total_h - 6))
		var tier_wave := 0.85 + 0.30 * (1.0 - fmod(float(y - 5), 4.0) / 3.5)
		var max_r := minf(lerpf(5.2, 0.8, frac) * tier_wave * tier_k, 5.8)
		var off: Vector2i = bend.call(y)
		var jx := rng.randf_range(-0.7, 0.7)
		var jz := rng.randf_range(-0.7, 0.7)
		var r_int := int(ceil(max_r * 1.2)) + 1
		for dz in range(-r_int, r_int + 1):
			for dx in range(-r_int, r_int + 1):
				var px := off.x + dx
				var pz := off.y + dz
				if absi(px) > rad or absi(pz) > rad:
					continue
				var dist := Vector2(float(dx) - jx, float(dz) - jz).length()
				var rim := max_r * (1.0 + 0.2 * sin(float(dx) * 1.7 + float(y) * 0.9 + float(dz) * 2.3 + float(tree_seed % 97)))
				if dist <= rim:
					var is_outer := dist >= rim - 0.85 or y >= total_h - 2
					var leaf_mat := Palette.LEAVES if (is_outer and ((dx + y + dz) & 1) == 0) else Palette.LEAVES_DARK
					g.setv(cx + px, y, cz + pz, leaf_mat)

	# Root flare and main trunk (overwrites inner leaves so the trunk core is solid)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if abs(dx) + abs(dz) <= 1:
				g.setv(cx + dx, 0, cz + dz, Palette.TRUNK)
				g.setv(cx + dx, 1, cz + dz, Palette.TRUNK)
	for y in range(0, trunk_h):
		var o: Vector2i = bend.call(y)
		g.setv(cx + o.x, y, cz + o.y, Palette.TRUNK)
		if y < trunk_h - 3:
			g.setv(cx + o.x + 1, y, cz + o.y, Palette.TRUNK)
			g.setv(cx + o.x, y, cz + o.y + 1, Palette.TRUNK)
			if y < trunk_h / 2:
				g.setv(cx + o.x + 1, y, cz + o.y + 1, Palette.TRUNK)

	var base := Vector3i(origin.x - cx, origin.y, origin.z - cz)
	store.stamp(g.data, Vector3i(sx, total_h, sz), base)


func _add_light(p: Vector3i, m: int) -> void:
	if _lights.has(p) or _lights.size() > 48:
		return
	var l := OmniLight3D.new()
	l.position = (Vector3(p) + Vector3.ONE * 0.5) * VS
	l.light_color = Color(1.0, 0.78, 0.48) if m == Palette.LANTERN else Color(0.45, 1.0, 0.9)
	l.omni_range = 7.0
	l.omni_attenuation = 1.4
	l.light_energy = 0.0
	l.visible = false             # SkyCycle switches lamps on at dusk
	l.distance_fade_enabled = true  # far lamps drop out of the lighting pass
	l.distance_fade_begin = 45.0
	l.distance_fade_length = 15.0
	l.shadow_enabled = false
	l.add_to_group("lamps")
	lamps_root.add_child(l)
	_lights[p] = l
