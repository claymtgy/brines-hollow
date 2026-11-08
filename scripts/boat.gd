class_name Boat
extends Node3D
## Rowboat entity (not terrain). Floats on the tide plane, rows with pulsed strokes,
## collides with terrain/docks via voxel queries and grounds itself in the shallows.
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

var id := 0
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


func setup(p_id: int, p_world: VoxelWorld, p_sky: SkyCycle, pos: Vector3, p_yaw: float) -> void:
	id = p_id
	world = p_world
	sky = p_sky
	position = pos
	yaw = p_yaw
	_net_pos = pos
	_net_yaw = p_yaw
	_build_visual()


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
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
	_wake.position = Vector3(0, 0.02, -HALF_LEN)
	_wake.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_wake.emission_box_extents = Vector3(HALF_BEAM, 0.01, 0.1)
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
	return visual.global_transform * Transform3D(Basis(), SEATS[clampi(i, 0, 1)])


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
		return true  # never sail into unloaded chunks
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
			var base: Vector3 = Vector3(pos.x, 0, pos.z) + f * (zi * HALF_LEN) + r * (xi * half)
			for h in [-DRAFT - 0.03, 0.3, 1.25]:
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

## Authority-side physics step. f: -1..1 row, t: -1..1 turn (+ = left), hard: Shift.
func simulate(delta: float, f: float, t: float, hard: bool) -> void:
	var water := water_y()
	var rowing := absf(f) > 0.01 or absf(t) > 0.01
	var cadence := STROKES_PER_SEC * (1.45 if hard else 1.0)
	row_power = lerpf(row_power, 1.0 if rowing else 0.0, 1.0 - exp(-delta * 4.0))
	if rowing or sin(row_phase) > 0.05:
		row_phase += delta * TAU * cadence * maxf(row_power, 0.35)
	var pulse := maxf(0.0, sin(row_phase))
	var fwd := forward2()
	vel += fwd * f * pulse * THRUST * (1.45 if hard else 1.0) * delta
	yaw_vel += t * (0.45 + pulse) * TURN * delta
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
	if sky != null:
		drift += sky.wind_drift()  # [weather] storms push boats downwind
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
	# Oars: sweep fore/aft on the stroke, lift the blade on the recovery.
	for o: Node3D in [_oar_l, _oar_r]:
		var side: float = o.get_meta("side")
		var sweep := cos(row_phase) * 0.55 * row_power
		var lift := maxf(0.0, -sin(row_phase)) * 0.28 * row_power
		var rest := (1.0 - row_power) * 0.55  # tucked alongside when idle
		var ry := -sweep + rest
		o.rotation = Vector3(0, ry if side > 0 else PI - ry, -0.38 + lift - (1.0 - row_power) * 0.1)
	_wake.emitting = speed > 0.6 and not grounded
