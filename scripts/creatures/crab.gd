class_name TideCrab
extends Creature
## Tide-crab: scuttles on the intertidal flats at low tide, buries itself as the water returns.
##
## Non-combat answers:
##   - It flees from footsteps: sneak (Ctrl / back paddle) to get close.
##   - Hold kelp or a raw fish as bait: it creeps up to you; press F to catch it by hand.
## Combat: weak (8 HP). Only pinches when cornered (never on Cozy).

const WANDER_SPEED := 0.9
const FLEE_SPEED := 2.8
const LURE_RANGE := 7.0
const SCARE_RANGE := 5.0

var claw_l: Node3D
var claw_r: Node3D
var body: Node3D
var _wander_dir := Vector3.ZERO
var _wander_t := 0.0
var _blocked_t := 0.0
var _phase := 0.0


func _init() -> void:
	kind = &"crab"
	max_hp = 8.0
	hp = 8.0
	radius = 0.3


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	var shell := Prefabs.Grid.new(6, 3, 5)
	shell.box(0, 0, 0, 5, 1, 4, Palette.ROOF_RED)
	shell.box(1, 2, 1, 4, 2, 3, Palette.BUOY)
	shell.setv(2, 2, 4, Palette.EYE)
	shell.setv(3, 2, 4, Palette.EYE)
	# legs: three each side
	for z in [0, 2, 4]:
		shell.setv(0, 0, z, Palette.SANDSTONE_B)
		shell.setv(5, 0, z, Palette.SANDSTONE_B)
	part(body, shell, Vector3(-3, 0.6, -2.5))
	var legs := Prefabs.Grid.new(8, 1, 5)
	for z in [0, 2, 4]:
		legs.setv(0, 0, z, Palette.ROOF_RED)
		legs.setv(7, 0, z, Palette.ROOF_RED)
	part(body, legs, Vector3(-4, 0, -2.5))
	claw_l = pivot(body, Vector3(-2, 1.2, 2.5))
	claw_r = pivot(body, Vector3(2, 1.2, 2.5))
	for c: Node3D in [claw_l, claw_r]:
		var g := Prefabs.Grid.new(2, 2, 3)
		g.box(0, 0, 0, 1, 1, 2, Palette.BUOY)
		g.setv(0, 1, 2, Palette.WHITEWASH)
		part(c, g, Vector3(-1, -0.5, 0))


func telegraph_height() -> float:
	return 0.55


func hint() -> String:
	return "Tide-crabs flee from footsteps. Sneak (Ctrl) to get close, or hold kelp or fish as bait and press F to catch one."


func drops() -> Array:
	return [[&"shore_crab", 1]]


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	var water_y: float = ctx.water_y
	# The tide is coming in: bury and vanish.
	if water_y > position.y + 0.35 and state != State.DEAD:
		net.despawn(self)
		return
	if state == State.DEAD:
		if state_t > 0.6:
			net.despawn(self)
		return
	var p := nearest_player(ctx)
	var dist: float = p.get("dist", INF)
	match state:
		State.STAGGER:
			if state_t > CombatMath.STAGGER_TIME * 0.7:
				set_state(State.FLEE)
			return
		State.WINDUP:
			turn_toward(p.pos - position if not p.is_empty() else facing(), 10.0, dt)
			if state_t >= CombatMath.windup_time(0.55, ctx.difficulty):
				set_state(State.STRIKE)
			return
		State.STRIKE:
			if not p.is_empty() and dist < 1.25:
				net.hurt_player(p.id, 2.0, position, self)
			set_state(State.RECOVER)
			return
		State.RECOVER:
			if state_t > 0.6:
				set_state(State.FLEE)
			return
	# Bait beats fear.
	if not p.is_empty() and p.has_bait and dist < LURE_RANGE:
		set_state(State.LURED)
		var to: Vector3 = p.pos - position
		turn_toward(to, 6.0, dt)
		if dist > 0.9:
			walk(to, WANDER_SPEED * 1.4, dt, water_y)
		return
	var heard := not p.is_empty() and Perception.detects(position + Vector3.UP * 0.2, facing(), 220.0, 2.0,   # poor eyesight: sneaking works
			p.pos, Perception.noise_radius(p.speed, p.sneaking, p.sprinting, p.in_water), ctx.darkness)
	if heard and dist < SCARE_RANGE:
		var away: Vector3 = position - p.pos
		away.y = 0.0
		if state != State.FLEE:
			set_state(State.FLEE)
		# Crabs run sideways.
		turn_toward(away.rotated(Vector3.UP, PI * 0.5), 8.0, dt)
		if walk(away, FLEE_SPEED, dt, water_y):
			_blocked_t = 0.0
		else:
			_blocked_t += dt
			# Cornered and someone's right on top of us: pinch (never on Cozy).
			if _blocked_t > 0.5 and dist < 1.4 and CombatMath.hostiles_allowed(ctx.difficulty):
				target_id = p.id
				set_state(State.WINDUP)
			elif not walk(away.rotated(Vector3.UP, 1.2), FLEE_SPEED, dt, water_y):
				walk(away.rotated(Vector3.UP, -1.2), FLEE_SPEED, dt, water_y)
		return
	# Wander lazily.
	if state != State.WANDER:
		set_state(State.WANDER)
	_wander_t -= dt
	if _wander_t <= 0.0:
		_wander_t = rng.randf_range(1.5, 3.5)
		var back := (home - position)
		back.y = 0.0
		_wander_dir = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		if back.length() > 6.0:
			_wander_dir = back.normalized()
		if rng.randf() < 0.35:
			_wander_dir = Vector3.ZERO  # pause
	if _wander_dir != Vector3.ZERO:
		turn_toward(_wander_dir.rotated(Vector3.UP, PI * 0.5), 4.0, dt)
		if not walk(_wander_dir, WANDER_SPEED, dt, water_y):
			_wander_t = 0.0


func animate(dt: float) -> void:
	var moving := state in [State.WANDER, State.FLEE, State.LURED]
	_phase += dt * (16.0 if state == State.FLEE else 9.0) * (1.0 if moving else 0.0)
	body.position.y = absf(sin(_phase)) * 0.02 if moving else 0.0
	var claw := 0.0
	if state == State.WINDUP:
		claw = -1.1   # claws raised: readable telegraph
	elif state == State.STRIKE or state == State.RECOVER:
		claw = 0.4
	elif state == State.DEAD:
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, PI, 1.0 - exp(-dt * 10.0))
	claw_l.rotation.x = lerpf(claw_l.rotation.x, claw + sin(_phase * 0.5) * 0.15, 1.0 - exp(-dt * 14.0))
	claw_r.rotation.x = lerpf(claw_r.rotation.x, claw - sin(_phase * 0.5) * 0.15, 1.0 - exp(-dt * 14.0))
