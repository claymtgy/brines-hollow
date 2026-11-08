class_name WildAnimal
extends Creature
## Base for island wildlife (ambient animals and farm raiders). Adds fence-aware ground
## movement (TerrainStep), surface swimming, fleeing, lazy wandering and paw tracks.
## Wild animals never hurt players. Ambient ones can't be harmed either.

var clearance := 3            # voxels of head-room needed to pass (see TerrainStep)
var body_width := 0.0         # > VS: both flanks must fit through a gap too
var leaves_tracks := false
var track_size := 0.07

var _wander_dir := Vector3.ZERO
var _wander_t := 0.0
var _last_track := Vector3.INF
var _track_side := 1.0


func _init() -> void:
	damageable = false
	hostile = false


## Ambient animals just startle when swung at.
func on_hit(damage: float, from: Vector3, power: float, attacker: int) -> bool:
	if damageable:
		return super.on_hit(damage, from, power, attacker)
	last_attacker = attacker
	startle(from)
	return true


## Override: react to a fright from `from` (a swing, a sprinting player...).
func startle(_from: Vector3) -> void:
	set_state(State.FLEE)


func _voxel() -> Callable:
	return net.voxel


## Walk on land, respecting fences, gaps, gates and head-room. False if blocked.
func ground_move(dir: Vector3, speed: float, dt: float, water_y: float, max_wade: float = 0.15) -> bool:
	var step := Vector3(dir.x, 0.0, dir.z)
	if step.length() < 0.001:
		return true
	step = step.normalized() * speed * dt
	var nxt := position + step
	var g := TerrainStep.step_wide(_voxel(), position, nxt, clearance, body_width)
	if is_nan(g) or g < water_y - max_wade:
		return false
	var half := maxf(body_width, 0.16) * 0.5
	if TerrainStep.entity_blocked(Vector3(nxt.x, g, nxt.z), half, clearance * VS * 0.8):
		return false
	position = Vector3(nxt.x, g, nxt.z)
	return true


## Try straight ahead, then progressively wider detours. Returns the direction taken or ZERO.
func ground_move_around(dir: Vector3, speed: float, dt: float, water_y: float, prefer_side: float = 1.0) -> Vector3:
	for a in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var d := dir.rotated(Vector3.UP, a * prefer_side)
		if ground_move(d, speed, dt, water_y):
			return d
	return Vector3.ZERO


## Swim along the surface (seals, otters, whales). Stays in water deeper than `min_depth`.
func surface_swim(dir: Vector3, speed: float, dt: float, water_y: float, min_depth: float = 0.35, bob: float = 0.0) -> bool:
	var step := Vector3(dir.x, 0.0, dir.z)
	if step.length() < 0.001:
		position.y = water_y + bob
		return true
	var nxt := position + step.normalized() * speed * dt
	if depth_at(nxt, water_y) < min_depth:
		return false
	position = Vector3(nxt.x, water_y + bob, nxt.z)
	return true


## Water depth (metres) at p, 0 on land.
func depth_at(p: Vector3, water_y: float) -> float:
	var vx := floori(p.x / VS)
	var vz := floori(p.z / VS)
	var y := floori(water_y / VS)
	var n := 0
	while n < 40 and y - n > 0:
		var m: int = net.voxel(vx, y - n, vz)
		if m != 0 and not Palette.is_foliage(m) and m != Palette.KELP:
			break
		n += 1
	return n * VS


## Run directly away from `from`, swerving round obstacles. Returns false if cornered.
func flee_from(from: Vector3, speed: float, dt: float, water_y: float) -> bool:
	var away := position - from
	away.y = 0.0
	if away.length() < 0.01:
		away = facing()
	var d := ground_move_around(away.normalized(), speed, dt, water_y)
	if d != Vector3.ZERO:
		turn_toward(d, 10.0, dt)
		return true
	return false


## Amble about within `radius` of home, pausing often.
func wander(dt: float, water_y: float, speed: float, radius: float = 6.0, pause_chance: float = 0.4) -> void:
	_wander_t -= dt
	if _wander_t <= 0.0:
		_wander_t = rng.randf_range(1.5, 4.0)
		var back := home - position
		back.y = 0.0
		_wander_dir = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		if back.length() > radius:
			_wander_dir = back.normalized()
		elif rng.randf() < pause_chance:
			_wander_dir = Vector3.ZERO
	if _wander_dir != Vector3.ZERO:
		turn_toward(_wander_dir, 4.0, dt)
		if not ground_move(_wander_dir, speed, dt, water_y):
			_wander_t = 0.0


func is_moving_state() -> bool:
	return state in [State.WANDER, State.FLEE, State.LURED, State.RETURN, State.ALERT, State.REPELLED]


## Lay paw prints as we go (every peer does this from what it sees).
func _lay_tracks() -> void:
	if not leaves_tracks or WildlifeFX.current == null:
		return
	if _last_track == Vector3.INF:
		_last_track = position
		return
	if Vector2(position.x - _last_track.x, position.z - _last_track.z).length() < 0.55:
		return
	_last_track = position
	_track_side = -_track_side
	var side := Vector3(cos(yaw), 0, -sin(yaw)) * 0.06 * _track_side
	WildlifeFX.current.track(position + side, yaw, track_size)


func _process(delta: float) -> void:
	super._process(delta)
	_lay_tracks()
