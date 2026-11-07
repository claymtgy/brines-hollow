class_name Creature
extends Node3D
## Base for every creature. The host / server runs `simulate()` (AI + movement); clients
## receive compact snapshots and only interpolate + animate.
## Visuals are rigid voxel parts at 2x terrain detail (like the fisherfolk).

enum State { IDLE, WANDER, FLEE, ALERT, WINDUP, STRIKE, RECOVER, RETURN, LURED, REPELLED, STAGGER, DEAD }
const STATE_NAMES := ["idle", "wander", "flee", "alert", "windup", "strike", "recover", "return",
	"lured", "repelled", "stagger", "dead"]

const VS := VoxelWorld.VS
const U := VoxelWorld.VS * 0.5

static var _mat: StandardMaterial3D
static var _glow: StandardMaterial3D

var cid := 0
var kind := &""
var state := State.IDLE
var state_t := 0.0
var hp := 10.0
var max_hp := 10.0
var hostile := false
var damageable := true
var home := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var target_id := 0
var radius := 0.35            # hit radius (m)
var net: Node = null          # CreatureNet
var rng := RandomNumberGenerator.new()
var authority := true
var last_attacker := 0

var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _has_net := false
var _flash := 0.0
var _telegraph: Label3D
var _visual_root: Node3D


static func materials() -> Array:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.75
		_glow = StandardMaterial3D.new()
		_glow.vertex_color_use_as_albedo = true
		_glow.vertex_color_is_srgb = true
		_glow.emission_enabled = true
		_glow.emission = Color(0.45, 1.0, 0.9)
		_glow.emission_energy_multiplier = 2.5
	return [_mat, _glow]


func setup(p_id: int, p_net: Node, pos: Vector3, p_authority: bool) -> void:
	cid = p_id
	net = p_net
	authority = p_authority
	position = pos
	home = pos
	_net_pos = pos
	rng.seed = p_id * 7919 + 13
	yaw = rng.randf() * TAU
	_visual_root = Node3D.new()
	add_child(_visual_root)
	_build_visuals(_visual_root)
	_telegraph = Label3D.new()
	_telegraph.text = "!"
	_telegraph.font_size = 72
	_telegraph.outline_size = 14
	_telegraph.modulate = Color(1.0, 0.45, 0.3)
	_telegraph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_telegraph.no_depth_test = true
	_telegraph.pixel_size = 0.006
	_telegraph.position = Vector3(0, telegraph_height(), 0)
	_telegraph.visible = false
	add_child(_telegraph)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 70.0
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- overridables

func _build_visuals(_root: Node3D) -> void:
	pass


func telegraph_height() -> float:
	return 0.8


## Host-side AI + movement. ctx: see CreatureNet._context().
func simulate(_dt: float, _ctx: Dictionary) -> void:
	pass


func animate(_dt: float) -> void:
	pass


## Items granted to whoever lands the killing blow.
func drops() -> Array:
	return []


## The non-combat answer, shown once per session the first time you meet one.
func hint() -> String:
	return ""


## Host: a player hit us. Returns true if it registered.
func on_hit(damage: float, from: Vector3, power: float, attacker: int) -> bool:
	if state == State.DEAD:
		return false
	last_attacker = attacker
	if damageable:
		hp -= damage
		var kb := CombatMath.knockback(from, position, power * 0.6)
		vel += Vector3(kb.x, 0.0, kb.z)
	if hp <= 0.0 and damageable:
		set_state(State.DEAD)
	return true


## Host: our attack was parried. Default: stagger.
func on_parried() -> void:
	if state != State.DEAD:
		set_state(State.STAGGER)


# ---------------------------------------------------------------- helpers

func set_state(s: int) -> void:
	if state != s:
		state = s
		state_t = 0.0


func is_staggered() -> bool:
	return state == State.STAGGER


func facing() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func turn_toward(dir: Vector3, rate: float, dt: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return
	yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-rate * dt))


func nearest_player(ctx: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	for p: Dictionary in ctx.players:
		var d: float = position.distance_to(p.pos)
		if d < bd:
			bd = d
			best = p
	if not best.is_empty():
		best = best.duplicate()
		best["dist"] = bd
	return best


func solid_at(p: Vector3) -> bool:
	var m: int = net.voxel(floori(p.x / VS), floori(p.y / VS), floori(p.z / VS))
	return m != 0 and not Palette.is_foliage(m)


## Top of the ground under p (metres), searching `up` above and `down` below. NAN if none.
func ground_under(p: Vector3, up: float = 0.6, down: float = 1.6) -> float:
	var x := floori(p.x / VS)
	var z := floori(p.z / VS)
	var y0 := floori((p.y + up) / VS)
	var y1 := floori((p.y - down) / VS)
	for y in range(y0, y1 - 1, -1):
		var m: int = net.voxel(x, y, z)
		if m != 0 and not Palette.is_foliage(m) and net.voxel(x, y + 1, z) == 0:
			return (y + 1) * VS
	return NAN


## Walk along the ground: returns false if blocked (wall, drop-off, deep water).
func walk(dir: Vector3, speed: float, dt: float, water_y: float, max_wade: float = 0.25) -> bool:
	var step := Vector3(dir.x, 0.0, dir.z)
	if step.length() < 0.001:
		return true
	step = step.normalized() * speed * dt
	var nxt := position + step
	var g := ground_under(nxt, 0.4, 0.8)
	if is_nan(g) or g < water_y - max_wade:
		return false
	position = Vector3(nxt.x, g, nxt.z)
	return true


## Swim inside water cells only (eels). `ceiling` metres above the surface allowed.
func swim(dir: Vector3, speed: float, dt: float, water_y: float, ceiling: float = -0.15) -> bool:
	if dir.length() < 0.001:
		return true
	var nxt := position + dir.normalized() * speed * dt
	if nxt.y > water_y + ceiling or solid_at(nxt):
		return false
	position = nxt
	return true


# ---------------------------------------------------------------- net + visuals

## Client: apply a snapshot from the host.
func apply_net(pos: Vector3, p_yaw: float, p_state: int, hp_frac: float) -> void:
	_net_pos = pos
	_net_yaw = p_yaw
	if p_state != state:
		state = p_state
		state_t = 0.0
	var new_hp := hp_frac * max_hp
	if new_hp < hp - 0.01:
		flash()
	hp = new_hp
	if not _has_net:
		_has_net = true
		position = pos
		yaw = p_yaw


func flash() -> void:
	_flash = 0.18


func _process(delta: float) -> void:
	state_t += delta if not authority else 0.0
	if not authority:
		position = position.lerp(_net_pos, 1.0 - exp(-delta * 12.0))
		yaw = lerp_angle(yaw, _net_yaw, 1.0 - exp(-delta * 12.0))
	_visual_root.rotation.y = yaw
	_telegraph.visible = state == State.WINDUP
	if _flash > 0.0:
		_flash -= delta
		_visual_root.scale = Vector3.ONE * (1.0 + _flash * 0.6)
	else:
		_visual_root.scale = Vector3.ONE
	animate(delta)


## Builds a rigid voxel part (character-voxel scale) under `parent`, offset in U units.
func part(parent: Node3D, g: Prefabs.Grid, offset_u: Vector3) -> MeshInstance3D:
	var m := materials()
	var mi := MeshInstance3D.new()
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, U, m[0], m[1])
	mi.position = offset_u * U
	parent.add_child(mi)
	return mi


func pivot(parent: Node3D, at_u: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at_u * U
	parent.add_child(n)
	return n
