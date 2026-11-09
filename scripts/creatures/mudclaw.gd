class_name MudClaw
extends Creature
## Mud-Claws: crab-folk who hold driftwood camps on the outer islands (see MudClawCamps).
## Swarmers are small, quick and come in a pack; the brute is a slow, heavily plated guard.
##
## Non-combat answers:
##   - Light: swarmers will not close on anyone carrying a lantern (or near a lamp). They
##     circle and click, but keep their distance. The brute does not care.
##   - Daytime: the camp dozes in its mud domes. They only wake to noise, so sneak (Ctrl)
##     and you can reach the camp chest. Running or fighting wakes the whole camp.
##   - They are tied to their camp: leave the palisade far behind, or take to the water,
##     and they give up and go home.
## Cozy: they never attack; they scuttle back into their domes when you come close.
##
## Combat: swarmer 12 HP, quick pinch (short windup). Brute 48 HP, high poise, a big
## overhead slam with a long, readable windup and a long recovery to punish.

const LEASH := 22.0             # metres from the camp centre they will chase to
const GIVE_UP := 30.0           # a player this far from the camp centre is let go
const KEEP_OFF_LIGHT := 5.0
const MAX_ATTACKERS := 2       # swarmers winding up or striking at once

var brute := false
var camp := -1                  # host: index into MudClawCamps.camps
var camp_center := Vector3.ZERO
var dome := Vector3.ZERO        # where this one dozes (metres)
var roused := false
var walk_speed := 1.1
var chase_speed := 4.4
var strike_range := 1.25
var damage := 2.5
var windup := 0.5
var recover := 0.7

var body: Node3D
var claw_l: Node3D
var claw_r: Node3D
var _phase := 0.0
var _cd := 0.0
var _lunge := Vector3.ZERO
var _orbit := 1.0
var _wander_t := 0.0
var _wander_to := Vector3.ZERO
var _reported := false


func _init(p_brute := false) -> void:
	brute = p_brute
	hostile = true
	if brute:
		kind = &"mudbrute"
		max_hp = 48.0
		radius = 0.6
		max_poise = 45.0
		walk_speed = 0.8
		chase_speed = 2.9
		strike_range = 2.0
		damage = 7.0
		windup = 1.05
		recover = 1.3
	else:
		kind = &"mudclaw"
		max_hp = 12.0
		radius = 0.32
		max_poise = 12.0
	hp = max_hp
	poise = max_poise


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	if brute:
		body.scale = Vector3.ONE * 1.9
	var shell_m := Palette.DARK_WOOD
	var trim := Palette.COBBLE if brute else Palette.SANDSTONE_B
	# a squat, upright crab body: domed shell, pale belly, eyes on stalks
	var b := Prefabs.Grid.new(6, 5, 5)
	b.box(0, 0, 1, 5, 2, 4, Palette.SANDSTONE_B)
	b.box(0, 1, 0, 5, 4, 3, shell_m)
	b.box(1, 4, 1, 4, 4, 2, trim)
	if brute:
		b.box(1, 2, 4, 4, 4, 4, Palette.SANDSTONE_C)   # a shell mask
		b.setv(0, 4, 0, Palette.COBBLE)
		b.setv(5, 3, 1, Palette.COBBLE)
	b.setv(1, 5 - 1, 4, Palette.EYE)
	b.setv(4, 5 - 1, 4, Palette.EYE)
	part(body, b, Vector3(-3, 2, -2.5))
	var stalks := Prefabs.Grid.new(6, 2, 1)
	stalks.setv(1, 0, 0, Palette.ROOF_RED)
	stalks.setv(4, 0, 0, Palette.ROOF_RED)
	stalks.setv(1, 1, 0, Palette.EYE)
	stalks.setv(4, 1, 0, Palette.EYE)
	part(body, stalks, Vector3(-3, 7, 1))
	# legs, three a side
	var legs := Prefabs.Grid.new(8, 2, 5)
	for z in [0, 2, 4]:
		legs.setv(0, 0, z, Palette.ROOF_RED)
		legs.setv(7, 0, z, Palette.ROOF_RED)
		legs.setv(1, 1, z, Palette.ROOF_RED)
		legs.setv(6, 1, z, Palette.ROOF_RED)
	part(body, legs, Vector3(-4, 0, -2.5))
	claw_l = pivot(body, Vector3(-3, 4, 2))
	claw_r = pivot(body, Vector3(3, 4, 2))
	for c: Node3D in [claw_l, claw_r]:
		var g := Prefabs.Grid.new(3, 3, 4)
		g.box(0, 0, 0, 2, 2, 2, Palette.BUOY if not brute else Palette.ROOF_RED)
		g.setv(0, 2, 3, Palette.WHITEWASH)
		g.setv(2, 2, 3, Palette.WHITEWASH)
		g.setv(1, 0, 3, Palette.BUOY)
		part(c, g, Vector3(-1.5, -1.5, 0))


func telegraph_height() -> float:
	return 1.75 if brute else 0.85


func hint() -> String:
	if brute:
		return "The Mud-Claw brute guards the camp. Its slam is slow: dodge (C) when it rears up, then strike while it recovers. Light won't stop it."
	return "Mud-Claws: carry a lantern and the swarmers keep back. By day the camp dozes, so sneak (Ctrl) to the chest. They won't follow you far from camp, or into the water."


func drops() -> Array:
	if brute:
		return [[&"chitin_plate", 3], [&"sea_glass", 2]]
	return [[&"chitin_plate", 1]]


func on_hit(dmg: float, from: Vector3, power: float, attacker: int) -> bool:
	var ok := super.on_hit(dmg, from, power, attacker)
	if ok:
		_rouse_camp()
	return ok


func _rouse_camp() -> void:
	roused = true
	if net != null and net.get("camps") != null and camp >= 0:
		net.camps.rouse(camp)


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	_cd = maxf(0.0, _cd - dt)
	var water_y: float = ctx.water_y
	if state == State.DEAD:
		if not _reported:
			_reported = true
			if net.get("camps") != null and camp >= 0:
				net.camps.on_killed(camp, self)
		if state_t > 1.0:
			net.despawn(self)
		return
	var p := _nearest_in_reach(ctx)
	var dist: float = p.get("dist", INF)
	var hostile_ok := CombatMath.hostiles_allowed(ctx.difficulty)
	match state:
		State.STAGGER:
			if state_t > CombatMath.STAGGER_TIME * (0.6 if brute else 0.8):
				set_state(State.ALERT)
			return
		State.WINDUP:
			if p.is_empty():
				set_state(State.RETURN)
				return
			turn_toward(p.pos - position, 9.0 if not brute else 4.0, dt)
			if not brute and _repelled_by(p, ctx):
				set_state(State.REPELLED)
				return
			if state_t >= CombatMath.windup_time(windup, ctx.difficulty):
				_lunge = (p.pos - position)
				_lunge.y = 0.0
				_lunge = _lunge.normalized()
				set_state(State.STRIKE)
			return
		State.STRIKE:
			if brute:
				# one heavy slam in front of it
				if not p.is_empty() and dist < strike_range + 0.4 and facing().dot((p.pos - position).normalized()) > 0.3:
					net.hurt_player(p.id, damage, position, self)
				set_state(State.RECOVER)
				return
			walk(_lunge, 6.5, dt, water_y)
			if not p.is_empty() and dist < 1.05:
				net.hurt_player(p.id, damage, position, self)
				set_state(State.RECOVER)
			elif state_t > 0.22:
				set_state(State.RECOVER)
			return
		State.RECOVER:
			if state_t > recover:
				_cd = rng.randf_range(1.0, 2.0) if not brute else 1.2
				set_state(State.ALERT)
			return
	# Cozy: never fight; scuttle home and stay put.
	if not hostile_ok:
		if not p.is_empty() and dist < 8.0:
			_go(dome, chase_speed * 0.8, dt, water_y)
			if state != State.FLEE:
				set_state(State.FLEE)
		else:
			_idle(dt, ctx, water_y)
		return
	# Dozing by day until something wakes us (noise only: eyes shut).
	var day: bool = ctx.night < 0.3
	if day and not roused:
		if not p.is_empty() and dist <= Perception.noise_radius(p.speed, p.sneaking, p.sprinting, p.in_water):
			_rouse_camp()
		else:
			_idle(dt, ctx, water_y)
			return
	# Awake: look for someone near the camp.
	var noticed := false
	if not p.is_empty():
		noticed = roused and dist < 14.0 or Perception.detects(position + Vector3.UP * 0.4, facing(), 200.0, 11.0,
				p.pos, Perception.noise_radius(p.speed, p.sneaking, p.sprinting, p.in_water), ctx.darkness)
	if not noticed:
		if state in [State.ALERT, State.REPELLED]:
			set_state(State.RETURN)
		_idle(dt, ctx, water_y)
		return
	if not roused:
		_rouse_camp()
	target_id = p.id
	if not brute and _repelled_by(p, ctx):
		# Circle at a safe distance, clicking.
		if state != State.REPELLED:
			set_state(State.REPELLED)
		var away: Vector3 = position - p.pos
		away.y = 0.0
		var want: Vector3 = away.normalized() * KEEP_OFF_LIGHT - away
		var tangent := Vector3(-away.z, 0, away.x).normalized() * _orbit
		turn_toward(-away, 6.0, dt)
		if not walk(want * 0.8 + tangent, walk_speed * 1.6, dt, water_y):
			_orbit = -_orbit
		return
	if state != State.ALERT:
		set_state(State.ALERT)
	var to: Vector3 = p.pos - position
	to.y = 0.0
	turn_toward(to, 8.0 if not brute else 3.5, dt)
	# Only two swarmers go for you at once; the rest circle, clicking, waiting their turn.
	var my_turn: bool = brute or net.get("camps") == null or net.camps.attackers(camp) < MAX_ATTACKERS
	if dist < strike_range and _cd <= 0.0 and my_turn:
		set_state(State.WINDUP)
		return
	if not my_turn and dist < 2.6:
		var tangent := Vector3(-to.z, 0, to.x).normalized() * _orbit
		var back := -to.normalized() * (0.6 if dist < 2.0 else 0.0)
		if not walk(tangent + back, walk_speed * 1.8, dt, water_y):
			_orbit = -_orbit
		return
	if dist > strike_range * 0.8:
		# swarmers come at you from the sides
		var dir := to.normalized()
		if not brute and dist > 2.0:
			dir = (dir + Vector3(-dir.z, 0, dir.x) * 0.45 * _orbit).normalized()
		if not walk(dir, chase_speed, dt, water_y):
			if not walk(dir.rotated(Vector3.UP, 1.0 * _orbit), chase_speed, dt, water_y):
				_orbit = -_orbit


## The nearest player still inside the camp's reach (beyond it: we let them go).
func _nearest_in_reach(ctx: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	for pl: Dictionary in ctx.players:
		if Vector2(pl.pos.x - camp_center.x, pl.pos.z - camp_center.z).length() > GIVE_UP:
			continue
		if pl.in_water and pl.pos.y < ctx.water_y - 0.4:
			continue                      # swimming: out of reach
		var d: float = position.distance_to(pl.pos)
		if d < bd:
			bd = d
			best = pl
	if not best.is_empty():
		best = best.duplicate()
		best["dist"] = bd
	return best


func _repelled_by(p: Dictionary, ctx: Dictionary) -> bool:
	if p.get("has_light", false) and p.dist < KEEP_OFF_LIGHT + 1.0:
		return true
	return Perception.is_lit(position, ctx.lights, KEEP_OFF_LIGHT)


## Home, or pottering round the camp (awake at night), or asleep in a dome (day).
func _idle(dt: float, ctx: Dictionary, water_y: float) -> void:
	var off := Vector2(position.x - camp_center.x, position.z - camp_center.z).length()
	if state == State.RETURN or state == State.FLEE or off > LEASH:
		if state != State.RETURN and state != State.FLEE:
			set_state(State.RETURN)
		if _go(dome if ctx.night < 0.3 else camp_center, walk_speed * 2.2, dt, water_y):
			set_state(State.IDLE)
		return
	if ctx.night < 0.3 and not roused:
		if position.distance_to(dome) > 0.6:
			_go(dome, walk_speed, dt, water_y)
		elif state != State.IDLE:
			set_state(State.IDLE)
		return
	_wander_t -= dt
	if _wander_t <= 0.0:
		_wander_t = rng.randf_range(2.0, 5.0)
		var a := rng.randf() * TAU
		_wander_to = camp_center + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, 4.5)
		if rng.randf() < 0.3:
			_wander_to = position
	if position.distance_to(_wander_to) > 0.4:
		if state != State.WANDER:
			set_state(State.WANDER)
		if not _go(_wander_to, walk_speed, dt, water_y) and state_t > 0.5:
			_wander_t = 0.0
	elif state != State.IDLE:
		set_state(State.IDLE)


## Step toward `to`. True once there (or stuck right next to it).
func _go(to: Vector3, speed: float, dt: float, water_y: float) -> bool:
	var d := to - position
	d.y = 0.0
	if d.length() < 0.5:
		return true
	turn_toward(d, 6.0, dt)
	if not walk(d, speed, dt, water_y):
		if not walk(d.rotated(Vector3.UP, 0.9 * _orbit), speed, dt, water_y):
			_orbit = -_orbit
			return d.length() < 1.2
	return false


func animate(dt: float) -> void:
	var moving := state in [State.WANDER, State.FLEE, State.ALERT, State.RETURN, State.REPELLED, State.STRIKE]
	_phase += dt * (15.0 if state in [State.ALERT, State.FLEE] else 8.0) * (1.0 if moving else 0.2)
	body.position.y = absf(sin(_phase)) * (0.03 if moving else 0.005)
	var claw := sin(_phase * 0.5) * 0.12
	if state == State.WINDUP:
		claw = -1.6 if brute else -1.1          # raised high: the telegraph
		body.rotation.x = lerpf(body.rotation.x, -0.25 if brute else -0.1, 1.0 - exp(-dt * 8.0))
	elif state == State.STRIKE:
		claw = 0.9
		body.rotation.x = lerpf(body.rotation.x, 0.3 if brute else 0.15, 1.0 - exp(-dt * 20.0))
	elif state == State.REPELLED:
		claw = -0.5 + sin(_phase * 3.0) * 0.4   # click, click
	else:
		body.rotation.x = lerpf(body.rotation.x, 0.0, 1.0 - exp(-dt * 6.0))
	if state == State.DEAD:
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, PI, 1.0 - exp(-dt * 8.0))
	claw_l.rotation.x = lerpf(claw_l.rotation.x, claw, 1.0 - exp(-dt * 14.0))
	claw_r.rotation.x = lerpf(claw_r.rotation.x, claw if state == State.WINDUP else -claw, 1.0 - exp(-dt * 14.0))
