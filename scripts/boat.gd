class_name Boat
extends Node3D
## Boat entity (not terrain): the rowboat (kind 0) and the outrigger sailing skiff
## (kind 1). Floats on the tide plane, collides with terrain/docks via voxel queries and
## grounds itself in the shallows. The rowboat rows with pulsed strokes; the skiff sails
## on the weather's wind (see sail_efficiency) and can paddle when the wind is foul.
##
## Networking: exactly one peer simulates a boat at a time (its driver, or the host
## when nobody is rowing). Everyone else interpolates the snapshots BoatManager relays.
## Boat-local axes: +Z = bow (forward), +X = starboard... rotated by `yaw` about Y.

const VS := VoxelWorld.VS
const DRAFT := 0.08            # hull bottom below the waterline (m)
const HULL_PREFAB := 11        # "Rowboat" voxel grid (8 x 6 x 20)
const HALF_BEAM := 0.62
const HALF_LEN := 1.70
## Seat positions in boat space, at the character's feet origin. 0 = rower, 1 = passenger.
const SEATS := [Vector3(0.0, 0.01, 0.36), Vector3(0.0, 0.01, -0.72)]
const STROKES_PER_SEC := 1.1
const THRUST := 5.0
const TURN := 1.9
const KIND_ROWBOAT := 0
const KIND_SKIFF := 1
## Skiff: sail drive at full wind on a beam reach (m/s^2), paddle drive, seat layout.
const SAIL_ACCEL := 14.0
const PADDLE_ACCEL := 1.6
const SKIFF_SEATS := [Vector3(0.0, 0.01, -1.15), Vector3(0.0, 0.01, 0.55)]
## Tier-2 workboats. The Tide-Barge: flat-bottomed and beamy, rowed with long sweeps; it
## floats over tidal mud a skiff would ground on, wind barely moves it, it seats four, and
## its cargo hold carries 27 stacks between islands. The Coastal Sloop: a single big
## gaff sail on a deep keel; faster than the skiff and points higher (only ~30 degrees
## off the wind is "in irons"), with a little cuddy cabin forward. Seats three.
const KIND_BARGE := 2
const KIND_SLOOP := 3
const BARGE_SEATS := [Vector3(0.0, 0.01, -1.9), Vector3(-0.55, 0.01, 0.3), Vector3(0.55, 0.01, 0.3), Vector3(0.0, 0.01, 1.4)]
const SLOOP_SEATS := [Vector3(0.0, 0.01, -2.05), Vector3(-0.4, 0.01, -1.1), Vector3(0.4, 0.01, -1.1)]
const HOLD_SLOTS := 27
const SLOOP_SAIL := 1.35        # sail force relative to the skiff

var id := 0
var kind := KIND_ROWBOAT
var half_beam := HALF_BEAM
var half_len := HALF_LEN
var yaw := 0.0
var vel := Vector2.ZERO        # xz, m/s
var yaw_vel := 0.0
var row_phase := 0.0
var row_power := 0.0
var occupants := [0, 0]        # peer id per seat (0 = empty)
var grounded := false
var world: VoxelWorld
var sky: SkyCycle

var visual: Node3D
var _oar_l: Node3D
var _oar_r: Node3D
var _t := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_vel := Vector2.ZERO
var _has_net := false
var _wake: CPUParticles3D
var _sail: Node3D               # skiff: the yard + sail, swung about the mast
var sail_angle := 0.0           # skiff: boom angle the sail has swung to (radians)
var hold: Inventory = null      # barge: the cargo hold (authority's copy is the truth)
var moored := false             # empty and tied up at a mooring bollard: no drifting
var _moor_t := 0.0


func setup(p_id: int, p_world: VoxelWorld, p_sky: SkyCycle, pos: Vector3, p_yaw: float, p_kind := KIND_ROWBOAT) -> void:
	id = p_id
	kind = p_kind
	if kind == KIND_SKIFF:
		half_beam = 1.15     # the outrigger float sits out to port
		half_len = 2.3
	elif kind == KIND_BARGE:
		half_beam = 1.15
		half_len = 2.6
		occupants = [0, 0, 0, 0]
		hold = Inventory.new(HOLD_SLOTS)
	elif kind == KIND_SLOOP:
		half_beam = 0.95
		half_len = 2.9
		occupants = [0, 0, 0]
	world = p_world
	sky = p_sky
	position = pos
	yaw = p_yaw
	_net_pos = pos
	_net_yaw = p_yaw
	_build_visual()


func is_skiff() -> bool:
	return kind == KIND_SKIFF


func is_barge() -> bool:
	return kind == KIND_BARGE


## Skiff and sloop: driven by the wind (W/S work the sail).
func has_sail() -> bool:
	return kind == KIND_SKIFF or kind == KIND_SLOOP


func display_name() -> String:
	match kind:
		KIND_SKIFF: return "skiff"
		KIND_BARGE: return "Tide-Barge"
		KIND_SLOOP: return "Coastal Sloop"
	return "rowboat"


func seats_list() -> Array:
	match kind:
		KIND_SKIFF: return SKIFF_SEATS
		KIND_BARGE: return BARGE_SEATS
		KIND_SLOOP: return SLOOP_SEATS
	return SEATS


func hold_used() -> int:
	if hold == null:
		return 0
	var n := 0
	for s: ItemSlot in hold.slots:
		if not s.is_empty():
			n += 1
	return n


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	if is_skiff():
		_build_skiff(mat)
		_build_wake()
		return
	if kind == KIND_SLOOP:
		_build_sloop(mat)
		_build_wake()
		return
	if kind == KIND_BARGE:
		_build_barge(mat)
		var u2 := VS * 0.5
		var sg := Prefabs.Grid.new(34, 1, 3)
		sg.box(0, 0, 1, 27, 0, 1, Palette.HANDLE)
		sg.box(0, 0, 1, 2, 0, 1, Palette.DARK_WOOD)
		sg.box(28, 0, 0, 33, 0, 2, Palette.PLANK)
		var sweep_mesh := Mesher.mesh_from_grid(sg.data, sg.sx, sg.sy, sg.sz, u2, mat, mat)
		_oar_r = _make_oar(sweep_mesh, u2, 1.0)
		_oar_l = _make_oar(sweep_mesh, u2, -1.0)
		_build_wake()
		return
	var pf := Prefabs.rotated(HULL_PREFAB, 0)
	var s: Vector3i = pf.size
	var hull := MeshInstance3D.new()
	hull.mesh = Mesher.mesh_from_grid(pf.data, s.x, s.y, s.z, VS, mat, mat)
	hull.position = Vector3(-s.x * 0.5 * VS, -DRAFT, -s.z * 0.5 * VS)
	visual.add_child(hull)
	# Oars, built at character detail (2x terrain resolution).
	var u := VS * 0.5
	var g := Prefabs.Grid.new(26, 1, 3)
	g.box(0, 0, 1, 19, 0, 1, Palette.HANDLE)
	g.box(0, 0, 1, 2, 0, 1, Palette.DARK_WOOD)       # grip
	g.box(20, 0, 0, 25, 0, 2, Palette.PLANK)          # blade
	g.box(24, 0, 0, 25, 0, 2, Palette.ROOF_BLUE)      # painted tip
	var oar_mesh := Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, u, mat, mat)
	_oar_r = _make_oar(oar_mesh, u, 1.0)
	_oar_l = _make_oar(oar_mesh, u, -1.0)
	_build_wake()


## Outrigger skiff: a long narrow dugout, a float on two booms out to port, a mast with
## a striped lateen sail on a swinging yard. Built at terrain resolution like the rowboat.
func _build_skiff(mat: Material) -> void:
	var g := Prefabs.Grid.new(14, 4, 28)
	# hull: x 1..5 (centre 3), tapering to a point at both ends
	for z in range(0, 28):
		var w := 2 if z > 3 and z < 24 else 1
		if z == 0 or z == 27:
			w = 0
		g.box(3 - w, 0, z, 3 + w, 0, z, Palette.DARK_WOOD)              # keel / floor
		g.box(3 - w, 1, z, 3 - w, 2, z, Palette.PLANK)                   # sides
		g.box(3 + w, 1, z, 3 + w, 2, z, Palette.PLANK)
		if w > 0:
			g.box(3 - w + 1, 1, z, 3 + w - 1, 1, z, Palette.DARK_WOOD)   # inside floor boards
	g.box(1, 2, 4, 1, 2, 23, Palette.ROOF_BLUE)                          # painted gunwale
	g.box(5, 2, 4, 5, 2, 23, Palette.ROOF_BLUE)
	g.box(3, 2, 0, 3, 3, 0, Palette.DARK_WOOD)                           # stern post
	g.box(3, 2, 27, 3, 3, 27, Palette.DARK_WOOD)                         # bow post
	g.box(2, 1, 5, 4, 2, 7, Palette.KELP)                                # live-well (kelp-lined)
	# two booms out to the float (port = -x in boat space; the grid is offset so x=13 is port)
	for bz in [7, 20]:
		g.box(5, 3, bz, 11, 3, bz, Palette.HANDLE)
	g.box(11, 0, 4, 12, 1, 23, Palette.DRIFTWOOD)                        # outrigger float
	g.box(11, 1, 3, 12, 1, 3, Palette.DRIFTWOOD)
	var hull := MeshInstance3D.new()
	hull.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, mat, mat)
	# grid x=3 is the hull's centreline; flip so the float lies to port (-x)
	hull.scale = Vector3(-1, 1, 1)
	hull.position = Vector3(3.5 * VS, -DRAFT, -14 * VS)
	visual.add_child(hull)
	# mast
	var mg := Prefabs.Grid.new(1, 30, 1)
	mg.box(0, 0, 0, 0, 29, 0, Palette.DARK_WOOD)
	var mast := MeshInstance3D.new()
	mast.mesh = Mesher.mesh_from_grid(mg.data, 1, 30, 1, VS, mat, mat)
	mast.position = Vector3(-0.5 * VS, 1 * VS - DRAFT, 3.5 * VS)
	visual.add_child(mast)
	# sail on a pivot at the mast: a triangle of canvas, striped, along the boat's length
	_sail = Node3D.new()
	_sail.position = Vector3(0, 3 * VS - DRAFT, 4 * VS)
	visual.add_child(_sail)
	var sg := Prefabs.Grid.new(1, 26, 18)
	for y in 26:
		var span := int(round(17.0 * (1.0 - float(y) / 26.0)))   # wide at the foot, a point at the top
		for z in range(0, span + 1):
			var c := Palette.WHITEWASH if (y / 4) % 2 == 0 else Palette.ROOF_RED
			sg.setv(0, y, 17 - z, c)
	var sail_mi := MeshInstance3D.new()
	sail_mi.mesh = Mesher.mesh_from_grid(sg.data, 1, 26, 18, VS, mat, mat)
	sail_mi.position = Vector3(-0.5 * VS, 0, -17 * VS)    # the sail's leading edge sits at the mast
	sail_mi.name = "Canvas"
	_sail.add_child(sail_mi)
	var yard := MeshInstance3D.new()
	var yg := Prefabs.Grid.new(1, 1, 20)
	yg.box(0, 0, 0, 0, 0, 19, Palette.HANDLE)
	yard.mesh = Mesher.mesh_from_grid(yg.data, 1, 1, 20, VS, mat, mat)
	yard.position = Vector3(-0.5 * VS, -1 * VS, -18 * VS)
	_sail.add_child(yard)


## Tide-Barge: a broad, flat-bottomed scow with low sides, square ends, a cargo well of
## crates amidships and a pair of long sweeps.
func _build_barge(mat: Material) -> void:
	var g := Prefabs.Grid.new(14, 4, 30)
	for z in 30:
		var end := z == 0 or z == 29
		for x in 14:
			g.setv(x, 0, z, Palette.DARK_WOOD)
			if x == 0 or x == 13 or end:
				g.setv(x, 1, z, Palette.PLANK)
				g.setv(x, 2, z, Palette.DARK_WOOD if end else Palette.PLANK)
		g.setv(0, 3, z, Palette.ROOF_BLUE if z % 6 == 0 else Palette.AIR)
		g.setv(13, 3, z, Palette.ROOF_BLUE if z % 6 == 0 else Palette.AIR)
	g.box(1, 1, 1, 12, 1, 28, Palette.PLANK)                 # deck boards
	for c: Vector3i in [Vector3i(3, 2, 11), Vector3i(8, 2, 11), Vector3i(3, 2, 16), Vector3i(8, 2, 16)]:
		g.box(c.x, c.y, c.z, c.x + 2, c.y + 1, c.z + 3, Palette.TRUNK if (c.x + c.z) % 2 == 0 else Palette.DRIFTWOOD)
	g.box(6, 2, 27, 7, 3, 28, Palette.METAL)                 # a mooring cleat on the bow
	var hull := MeshInstance3D.new()
	hull.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, mat, mat)
	hull.position = Vector3(-7 * VS, -DRAFT * 0.5, -15 * VS)
	visual.add_child(hull)


## Coastal Sloop: a deep-keeled day-sailer, cuddy cabin forward, one tall mast with a big
## striped gaff sail that swings on its boom.
func _build_sloop(mat: Material) -> void:
	var g := Prefabs.Grid.new(11, 6, 32)
	for z in 32:
		var t := float(z) / 31.0
		var w := int(round(5.0 * sin(clampf(t * 1.15, 0.05, 1.0) * PI * 0.95)))
		if z >= 30:
			w = maxi(0, 31 - z)
		w = maxi(w, 1)
		g.box(5 - w + 1, 0, z, 5 + w - 1, 0, z, Palette.DARK_WOOD)
		for y in range(1, 4):
			g.setv(5 - w, y, z, Palette.WHITEWASH if y < 3 else Palette.ROOF_BLUE)
			g.setv(5 + w, y, z, Palette.WHITEWASH if y < 3 else Palette.ROOF_BLUE)
		g.box(5 - w + 1, 1, z, 5 + w - 1, 1, z, Palette.PLANK)
	g.box(3, 2, 20, 7, 4, 27, Palette.PLANK)                 # the cuddy cabin
	g.box(3, 5, 20, 7, 5, 27, Palette.ROOF_RED)
	g.setv(3, 3, 23, Palette.SHUTTER)
	g.setv(7, 3, 23, Palette.SHUTTER)
	g.box(5, 1, 0, 5, 3, 0, Palette.DARK_WOOD)               # rudder post
	var hull := MeshInstance3D.new()
	hull.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, mat, mat)
	hull.position = Vector3(-5.5 * VS, -DRAFT, -16 * VS)
	visual.add_child(hull)
	var mg := Prefabs.Grid.new(1, 40, 1)
	mg.box(0, 0, 0, 0, 39, 0, Palette.DARK_WOOD)
	var mast := MeshInstance3D.new()
	mast.mesh = Mesher.mesh_from_grid(mg.data, 1, 40, 1, VS, mat, mat)
	mast.position = Vector3(-0.5 * VS, 1 * VS - DRAFT, 2.5 * VS)
	visual.add_child(mast)
	_sail = Node3D.new()
	_sail.position = Vector3(0, 3 * VS - DRAFT, 3 * VS)
	visual.add_child(_sail)
	var sg := Prefabs.Grid.new(1, 34, 22)
	for y in 34:
		var span := int(round(21.0 * (1.0 - float(y) / 40.0)))   # a gaff: the head stays wide
		for z in range(0, span + 1):
			sg.setv(0, y, 21 - z, Palette.WHITEWASH if (y / 5) % 2 == 0 else Palette.ROOF_BLUE)
	var sail_mi := MeshInstance3D.new()
	sail_mi.mesh = Mesher.mesh_from_grid(sg.data, 1, 34, 22, VS, mat, mat)
	sail_mi.position = Vector3(-0.5 * VS, 0, -21 * VS)
	sail_mi.name = "Canvas"
	_sail.add_child(sail_mi)
	var boom := MeshInstance3D.new()
	var bg := Prefabs.Grid.new(1, 1, 24)
	bg.box(0, 0, 0, 0, 0, 23, Palette.HANDLE)
	boom.mesh = Mesher.mesh_from_grid(bg.data, 1, 1, 24, VS, mat, mat)
	boom.position = Vector3(-0.5 * VS, -1 * VS, -22 * VS)
	_sail.add_child(boom)


func _build_wake() -> void:
	# Little wake while moving.
	_wake = CPUParticles3D.new()
	_wake.amount = 24
	_wake.lifetime = 1.2
	_wake.emitting = false
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * VS * 0.35
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.95, 0.97, 0.95)
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = wm
	_wake.mesh = bm
	_wake.position = Vector3(0, 0.02, -half_len)
	_wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wake.emission_box_extents = Vector3(minf(half_beam, 0.62), 0.01, 0.1)
	_wake.direction = Vector3(0, 0.3, -1)
	_wake.spread = 25.0
	_wake.initial_velocity_min = 0.2
	_wake.initial_velocity_max = 0.6
	_wake.gravity = Vector3(0, -1.5, 0)
	_wake.scale_amount_min = 0.5
	_wake.scale_amount_max = 1.0
	visual.add_child(_wake)


func _make_oar(mesh: Mesh, u: float, side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(side * 0.74, 4 * VS - DRAFT, SEATS[0].z + 0.15)
	if kind == KIND_BARGE:
		pivot.position = Vector3(side * 1.22, 3 * VS - DRAFT, BARGE_SEATS[0].z + 0.4)
	visual.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(-7 * u, -0.5 * u, -1.5 * u)   # oarlock ~0.63 m from the grip
	pivot.add_child(mi)
	pivot.set_meta("side", side)
	return pivot


# ---------------------------------------------------------------- queries

func forward2() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


func water_y() -> float:
	# [weather] the hull rides the same swell the water shader draws
	return (sky.water_level_m() + sky.wave_offset_at(position)) if sky != null else VoxelWorld.SEA_MID * VS


func seat_transform(i: int) -> Transform3D:
	var seats: Array = seats_list()
	return visual.global_transform * Transform3D(Basis(), seats[clampi(i, 0, seats.size() - 1)])


func seat_position(i: int) -> Vector3:
	return seat_transform(i).origin


func free_seat() -> int:
	for i in occupants.size():
		if occupants[i] == 0:
			return i
	return -1


func seat_of(peer: int) -> int:
	return occupants.find(peer)


func authority() -> int:
	return occupants[0] if occupants[0] != 0 else 1


func _solid(p: Vector3) -> bool:
	if world.has_method("is_loaded_at") and not world.call("is_loaded_at", p):
		# Not streamed in yet (a fast skiff can outrun streaming): use the generator's
		# height map, which matches unedited terrain. With no generator, treat it as solid.
		if world.gen == null:
			return true
		return float(world.gen.col_h(floori(p.x / VS), floori(p.z / VS))) * VS > p.y
	var m := world.get_voxel(floori(p.x / VS), floori(p.y / VS), floori(p.z / VS))
	if m != 0 and not Palette.is_foliage(m):
		return true
	# Entities (Agent A): placed entities and other boats are obstacles too.
	return EntityManager.current != null and EntityManager.current.point_solid(p, self)


## Number of hull sample points overlapping terrain at a candidate pose.
## Samples the keel (grounding), the gunwale (docks, cliffs) and seated-head height.
func blocked_count(pos: Vector3, p_yaw: float, water: float) -> int:
	var f := Vector3(sin(p_yaw), 0, cos(p_yaw))
	var r := Vector3(cos(p_yaw), 0, -sin(p_yaw))
	var n := 0
	for zi in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var half := HALF_BEAM * (0.55 if absf(zi) == 1.0 else 1.0)  # tapered bow/stern
		for xi in [-1.0, 0.0, 1.0]:
			var side := half
			if is_skiff():
				side = half_beam if xi < 0.0 and absf(zi) < 1.0 else 0.45   # float to port
			elif kind != KIND_ROWBOAT:
				side = half_beam * (0.7 if absf(zi) == 1.0 and kind == KIND_SLOOP else 1.0)
			var base: Vector3 = Vector3(pos.x, 0, pos.z) + f * (zi * half_len) + r * (xi * side)
			# the barge's flat bottom floats over mud a keel would ground on
			var keel := (0.04 if kind == KIND_BARGE else -DRAFT - 0.03)
			for h in [keel, 0.3, 1.25]:
				if _solid(base + Vector3(0, water + h, 0)):
					n += 1
	return n


## Where a seated player can step off: a nearby spot with floor under it and room above.
func find_exit_spot() -> Variant:
	var water := water_y()
	var top := floori((water + 1.8) / VS)
	var bottom := floori((water - 0.25) / VS)
	for r in [1.1, 1.5, 1.9, 2.4, 3.0, 3.6]:
		for k in 20:
			var a := TAU * k / 20.0
			var p := Vector3(position.x + cos(a) * r, 0, position.z + sin(a) * r)
			for vy in range(top, bottom - 1, -1):
				var y := vy * VS
				var lo := Vector3(p.x - Player.HW + 0.002, y + 0.002, p.z - Player.HW + 0.002)
				var hi := Vector3(p.x + Player.HW - 0.002, y + Player.H, p.z + Player.HW - 0.002)
				# Entities (Agent A): ignore=world (nothing) so the spot also clears this boat's own hull.
				if world.aabb_collides(lo, hi) or (EntityManager.current != null and EntityManager.current.blocks(lo, hi, world)):
					continue
				if world.aabb_collides(Vector3(p.x - 0.18, y - 0.06, p.z - 0.18), Vector3(p.x + 0.18, y - 0.01, p.z + 0.18)):
					if y >= water - 0.2:
						return Vector3(p.x, y, p.z)
					break
	return null


## Open water beside the hull to slip into and swim from, when there is no floor nearby.
func find_swim_exit_spot() -> Variant:
	var water := water_y()
	var y := water - Player.H * 0.6   # head and shoulders above the surface
	for r in [1.4, 1.8, 2.3, 2.9]:
		# Starboard and port first (over the gunwale), working round to bow and stern.
		for k in [0, 8, 1, 15, 7, 9, 2, 14, 6, 10, 3, 13, 5, 11, 4, 12]:
			var d: Vector2 = Vector2(cos(yaw), -sin(yaw)).rotated(TAU * float(k) / 16.0) * float(r)
			var p := Vector3(position.x + d.x, y, position.z + d.y)
			var lo := Vector3(p.x - Player.HW, y, p.z - Player.HW)
			var hi := Vector3(p.x + Player.HW, y + Player.H, p.z + Player.HW)
			if world.aabb_collides(lo, hi):
				continue
			if EntityManager.current != null and EntityManager.current.blocks(lo, hi, world):
				continue
			return p
	return null


# ---------------------------------------------------------------- simulation

## Wind over the boat (metres/second-ish, xz): the weather's direction, never quite calm.
func wind_vec() -> Vector2:
	if sky == null or sky.weather == null:
		return Vector2(1, 0) * 0.3
	var w: float = sky.weather.params.wind
	var d: Vector2 = sky.weather.params.wind_dir
	return d.normalized() * clampf(w, 0.22, 1.0)


## How well a sail drives a boat pointing along `heading` with the wind blowing towards
## `wind_to`: nothing head to wind ("in irons", within ~40 degrees), best across the wind
## (a beam reach), a bit less dead downwind (a run).
static func sail_efficiency(heading: Vector2, wind_to: Vector2, irons := 140.0) -> float:
	if wind_to.length() < 0.001:
		return 0.0
	var off := rad_to_deg(heading.normalized().angle_to(wind_to.normalized()))
	off = absf(off)                      # 0 = running downwind, 180 = head to wind
	if off <= 90.0:
		return lerpf(0.7, 1.0, off / 90.0)
	return clampf((irons - off) / (irons - 90.0), 0.0, 1.0)


static func point_of_sail(heading: Vector2, wind_to: Vector2) -> String:
	var off := absf(rad_to_deg(heading.normalized().angle_to(wind_to.normalized())))
	if off < 30.0:
		return "Running"
	if off < 70.0:
		return "Broad reach"
	if off < 110.0:
		return "Beam reach"
	if off < 140.0:
		return "Close-hauled"
	return "In irons"


## Skiff drive: W/S raise and lower the sail (row_power holds how far it's up), A/D steer
## with the rudder (needs way on), Shift paddles.
func _sail_drive(delta: float, f: float, t: float, hard: bool) -> void:
	if f > 0.1:
		row_power = minf(1.0, row_power + delta * 0.8)
	elif f < -0.1:
		row_power = maxf(0.0, row_power - delta * 1.2)
	var fwd := forward2()
	var wind := wind_vec()
	var sloop := kind == KIND_SLOOP
	var eff := sail_efficiency(fwd, wind, 150.0 if sloop else 140.0)
	vel += fwd * row_power * eff * wind.length() * SAIL_ACCEL * (SLOOP_SAIL if sloop else 1.0) * delta
	if hard:
		row_phase += delta * TAU * 1.2
		vel += fwd * maxf(0.0, sin(row_phase)) * PADDLE_ACCEL * 2.0 * delta
	var speed := absf(vel.dot(fwd))
	yaw_vel += t * TURN * (0.35 + minf(speed, 6.0) * 0.18) * delta
	# The boom swings out to leeward, further off the wind.
	var rel := fwd.angle_to(wind)        # signed
	var want := clampf(PI - absf(rel), 0.15, 1.35) * (1.0 if rel > 0.0 else -1.0) * 0.8
	sail_angle = lerp_angle(sail_angle, want, 1.0 - exp(-delta * 2.0))


## Authority-side physics step. f: -1..1 row, t: -1..1 turn (+ = left), hard: Shift.
func simulate(delta: float, f: float, t: float, hard: bool) -> void:
	var water := water_y()
	if has_sail():
		_sail_drive(delta, f, t, hard)
		_integrate(delta, water)
		return
	var rowing := absf(f) > 0.01 or absf(t) > 0.01
	var cadence := STROKES_PER_SEC * (1.45 if hard else 1.0)
	row_power = lerpf(row_power, 1.0 if rowing else 0.0, 1.0 - exp(-delta * 4.0))
	if rowing or sin(row_phase) > 0.05:
		row_phase += delta * TAU * cadence * maxf(row_power, 0.35)
	var pulse := maxf(0.0, sin(row_phase))
	var fwd := forward2()
	var heavy := 0.8 if kind == KIND_BARGE else 1.0        # the barge's sweeps: slow but steady
	vel += fwd * f * pulse * THRUST * heavy * (1.45 if hard else 1.0) * delta
	yaw_vel += t * (0.45 + pulse) * TURN * (0.75 if kind == KIND_BARGE else 1.0) * delta
	_integrate(delta, water)


## Drag, drift, terrain collision and grounding (shared by both kinds of boat).
func _integrate(delta: float, water: float) -> void:
	var fwd := forward2()
	# Drag: keel resists sideways motion far more than forward motion.
	var along := vel.dot(fwd)
	var lat := vel - fwd * along
	along *= exp(-0.5 * delta)
	along -= signf(along) * along * along * 0.09 * delta
	lat *= exp(-3.5 * delta)
	vel = fwd * along + lat
	yaw_vel *= exp(-2.4 * delta)
	# A lazy current so an empty boat drifts a little.
	var drift := Vector2(sin(_t * 0.05 + id * 1.7), cos(_t * 0.037 + id)) * 0.04
	if sky != null and not (has_sail() and row_power > 0.05):
		drift += sky.wind_drift() * (0.2 if kind == KIND_BARGE else 1.0)  # [weather] storms push boats downwind
	_moor_t -= delta
	if _moor_t <= 0.0:
		_moor_t = 0.5
		moored = occupants.max() == 0 and near_bollard()
	if moored:
		drift = Vector2.ZERO
		vel *= exp(-4.0 * delta)
		yaw_vel *= exp(-4.0 * delta)
	vel += (drift - vel * 0.02) * delta

	var old_blocked := blocked_count(position, yaw, water)
	grounded = old_blocked > 0
	var new_pos := position + Vector3(vel.x, 0, vel.y) * delta
	var new_yaw := yaw + yaw_vel * delta
	var nb := blocked_count(new_pos, new_yaw, water)
	if nb == 0 or nb < old_blocked:
		position = new_pos
		yaw = new_yaw
	elif blocked_count(position, new_yaw, water) <= old_blocked and old_blocked == 0:
		yaw = new_yaw
		vel *= -0.2  # bump
	else:
		# Try sliding along each axis before giving up.
		var px := position + Vector3(vel.x * delta, 0, 0)
		var pz := position + Vector3(0, 0, vel.y * delta)
		if blocked_count(px, yaw, water) <= old_blocked and blocked_count(px, yaw, water) == 0:
			position = px
			vel.y *= 0.3
		elif blocked_count(pz, yaw, water) == 0:
			position = pz
			vel.x *= 0.3
		else:
			vel *= -0.2
			yaw_vel *= 0.3
	if grounded:
		vel *= exp(-6.0 * delta)
		yaw_vel *= exp(-6.0 * delta)
	position.y = water
	_clamp_to_world()


## A mooring bollard within a boat length: an empty boat here is tied up and won't drift.
func near_bollard() -> bool:
	var em := EntityManager.current
	if em == null:
		return false
	for e: WorldEntity in em.entities.values():
		if e.entity_id == &"mooring_bollard" and Vector2(e.position.x - position.x, e.position.z - position.z).length() < half_len + 2.5:
			return true
	return false


func _clamp_to_world() -> void:
	var lim := Vector2(VoxelWorld.WX, VoxelWorld.WZ) * VS
	if "store" in world and world.store != null:
		var sz: Vector3i = world.store.get_size()
		lim = Vector2(sz.x, sz.z) * VS
	position.x = clampf(position.x, 2.0, lim.x - 2.0)
	position.z = clampf(position.z, 2.0, lim.y - 2.0)


## Non-authority side: ease toward the last snapshot (dead-reckoned by its velocity).
func interpolate(delta: float) -> void:
	if not _has_net:
		position.y = water_y()
		return
	_net_pos += Vector3(_net_vel.x, 0, _net_vel.y) * delta
	var k := 1.0 - exp(-delta * 10.0)
	position = position.lerp(Vector3(_net_pos.x, water_y(), _net_pos.z), k)
	if position.distance_to(_net_pos) > 6.0:
		position = Vector3(_net_pos.x, water_y(), _net_pos.z)
	yaw = lerp_angle(yaw, _net_yaw, k)
	vel = _net_vel


## Snapshots carry the sail state for remote viewers; the swing is recomputed locally.
var _local_auth := true


func is_authority_local() -> bool:
	return _local_auth


func apply_snapshot(pos: Vector3, p_yaw: float, p_vel: Vector2, phase: float, power: float) -> void:
	_net_pos = pos
	_net_yaw = p_yaw
	_net_vel = p_vel
	row_phase = phase
	row_power = power
	_has_net = true


func _process(delta: float) -> void:
	_t += delta
	rotation = Vector3(0, yaw, 0)
	# Bob, roll and speed-dependent pitch (bow lifts when moving).
	var speed := vel.length()
	var bob := sin(_t * 1.3 + id) * 0.035
	var roll := sin(_t * 0.9 + id * 2.0) * 0.035 - yaw_vel * 0.08
	var pitch := -clampf(vel.dot(forward2()), -1.0, 3.0) * 0.025 + sin(_t * 1.1) * 0.015
	# [weather] pitch/roll follow the swell slope under the hull
	if sky != null and not grounded:
		var fw := Vector3(sin(yaw), 0, cos(yaw))
		var rt := Vector3(fw.z, 0, -fw.x)
		pitch += (sky.wave_offset_at(position - fw * 1.6) - sky.wave_offset_at(position + fw * 1.6)) * 0.3
		roll += (sky.wave_offset_at(position - rt * 0.7) - sky.wave_offset_at(position + rt * 0.7)) * 0.5
		bob *= 1.0 + sky.sea_roughness() * 2.0
	if grounded:
		bob *= 0.2
		roll = 0.06
	visual.position.y = bob
	visual.rotation = Vector3(pitch, 0, roll)
	if has_sail():
		if _sail != null:
			if not is_authority_local():
				var rel := forward2().angle_to(wind_vec())
				sail_angle = lerp_angle(sail_angle, clampf(PI - absf(rel), 0.15, 1.35) * (1.0 if rel > 0.0 else -1.0) * 0.8, 1.0 - exp(-delta * 2.0))
			_sail.rotation = Vector3(0, sail_angle, 0)
			_sail.scale = Vector3(1, maxf(0.08, row_power), 1)   # furled down to the yard
			_sail.visible = row_power > 0.02
		_wake.emitting = speed > 0.6 and not grounded
		return
	# Oars: sweep fore/aft on the stroke, lift the blade on the recovery.
	for o: Node3D in [_oar_l, _oar_r]:
		var side: float = o.get_meta("side")
		var sweep := cos(row_phase) * 0.55 * row_power
		var lift := maxf(0.0, -sin(row_phase)) * 0.28 * row_power
		var rest := (1.0 - row_power) * 0.55  # tucked alongside when idle
		var ry := -sweep + rest
		o.rotation = Vector3(0, ry if side > 0 else PI - ry, -0.38 + lift - (1.0 - row_power) * 0.1)
	_wake.emitting = speed > 0.6 and not grounded
