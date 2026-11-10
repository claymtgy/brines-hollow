class_name GloomCrawler
extends Creature
## Gloom-Crawlers: pale, long-legged cave hunters that cling to cavern ceilings in the dark.
## Blind: they hunt by sound alone.
##
## Non-combat answers:
##   - Sneak (Ctrl) or stand still and they can't hear you. Walk softly past one and it never
##     drops; it hisses and turns its head after footsteps it can only half hear.
##   - Light: they won't drop on anyone holding a lantern, and on the ground they back away
##     from torchlight and lit lamps, then climb back to the dark.
##   - Lose them: once on the ground, a crawler that stops hearing you (sneak, or keep still)
##     gives up after a few seconds and climbs back up.
## Never on Cozy (like cave eels).
##
## Combat: 16 HP. The drop is the dangerous part: a hiss and a "!" while it gathers itself
## on the ceiling, then it falls on where it last heard you. Dodge (C) when it hisses. On
## the ground it bites with a short windup.

const HEAR_MULT := 1.6          # keen ears: hears further than most creatures
const KEEP_OFF_LIGHT := 5.5
const GIVE_UP_SEC := 4.0
const DROP_HURT_R := 1.1

var on_ceiling := true
var ceiling := Vector3.ZERO     # where it clings (metres; the underside of the rock)
var heard := Vector3.ZERO       # last place it heard a player
var _lost := 0.0
var _vy := 0.0
var _cd := 0.0
var _lunge := Vector3.ZERO
var _orbit := 1.0
var _phase := 0.0
var body: Node3D
var legs: Array[Node3D] = []
var chase_speed := 3.8
var damage := 3.0
var drop_damage := 4.5


func _init() -> void:
	hostile = true
	kind = &"gloomcrawler"
	max_hp = 16.0
	hp = max_hp
	radius = 0.4
	max_poise = 14.0
	poise = max_poise


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	# a flat, pale carapace: no eyes, a row of faint glowing pores
	var b := Prefabs.Grid.new(6, 3, 8)
	b.box(0, 0, 1, 5, 1, 6, Palette.SANDSTONE_C)
	b.box(1, 2, 1, 4, 2, 5, Palette.WHITEWASH)
	b.box(1, 0, 7, 4, 1, 7, Palette.STONE)            # the head: a blunt, eyeless wedge
	for z in [2, 4]:
		b.setv(1, 2, z, Palette.GLOW_TEAL)
		b.setv(4, 2, z, Palette.GLOW_TEAL)
	b.setv(2, 0, 7, Palette.EYE)                       # mandibles
	b.setv(3, 0, 7, Palette.EYE)
	part(body, b, Vector3(-3, 2, -4))
	# four long legs a side, jointed high like a harvestman's
	for side: int in [-1, 1]:
		for k in 4:
			var lg := pivot(body, Vector3(side * 3, 3, -2.5 + k * 1.8))
			var g := Prefabs.Grid.new(5, 4, 1)
			for i in 4:
				g.setv(i, 3 - absi(i - 1), 0, Palette.SANDSTONE_C if i < 3 else Palette.STONE)
			g.setv(4, 0, 0, Palette.STONE)
			var mi := part(lg, g, Vector3(0 if side > 0 else -5, -3, -0.5))
			if side < 0:
				mi.scale.x = 1.0
			legs.append(lg)


func telegraph_height() -> float:
	return -0.6 if on_ceiling else 0.8


func hint() -> String:
	return "Gloom-Crawlers are blind and hunt by sound. Sneak (Ctrl) or stand still and they can't hear you; carry a lantern and they won't drop on you. When one hisses on the ceiling, dodge (C)."


func drops() -> Array:
	return [[&"gloom_gland", 1], [&"chitin_plate", 1]]


## Host: spawned clinging to the rock at `at` (the underside of a ceiling voxel).
func cling(at: Vector3) -> void:
	ceiling = at
	position = at
	home = at
	on_ceiling = true


func _on_windup_started() -> void:
	CombatAudio.play_sound("tell_screech", position)


func on_hit(dmg: float, from: Vector3, power: float, attacker: int) -> bool:
	var ok := super.on_hit(dmg, from, power, attacker)
	if ok and on_ceiling and state != State.DEAD:
		_start_fall()        # knocked off the ceiling
	return ok


func _start_fall() -> void:
	on_ceiling = false
	_vy = 0.0


func _repelled(p: Dictionary, ctx: Dictionary) -> bool:
	if not p.is_empty() and p.get("has_light", false) and p.dist < KEEP_OFF_LIGHT + 1.0:
		return true
	return Perception.is_lit(position, ctx.lights, KEEP_OFF_LIGHT)


func _hears(p: Dictionary) -> bool:
	if p.is_empty():
		return false
	var r := Perception.noise_radius(p.speed, p.sneaking, p.sprinting, p.in_water) * HEAR_MULT
	return p.dist <= r or p.dist < 0.9


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	_cd = maxf(0.0, _cd - dt)
	var water_y: float = ctx.water_y
	if state == State.DEAD:
		if not on_ceiling:
			_fall(dt)
		elif state_t < 0.05:
			_start_fall()
		if state_t > 1.2:
			net.despawn(self)
		return
	var p := nearest_player(ctx)
	# Falling (dropped, knocked down): land, and hurt whoever it lands on.
	if not on_ceiling and _vy != 0.0 or (not on_ceiling and _airborne()):
		var landed := _fall(dt)
		if landed:
			if state == State.STRIKE and not p.is_empty() and Vector2(p.pos.x - position.x, p.pos.z - position.z).length() < DROP_HURT_R:
				net.hurt_player(p.id, drop_damage, position + Vector3.UP, self)
			if state in [State.STRIKE, State.WINDUP, State.IDLE]:
				set_state(State.RECOVER)
		return
	match state:
		State.STAGGER:
			if state_t > CombatMath.STAGGER_TIME * 0.7:
				set_state(State.ALERT)
			return
		State.WINDUP:
			if on_ceiling:
				# the hiss before the drop
				if not p.is_empty() and _repelled(p, ctx):
					set_state(State.REPELLED)
					return
				if state_t >= CombatMath.windup_time(0.6, ctx.difficulty):
					if not p.is_empty():
						heard = p.pos
					var aim := heard - position
					aim.y = 0.0
					if aim.length() < 2.2:
						position += aim * 0.85      # it falls on where it heard you
					_start_fall()
					set_state(State.STRIKE)
				return
			if p.is_empty():
				set_state(State.ALERT)
				return
			turn_toward(p.pos - position, 10.0, dt)
			if state_t >= CombatMath.windup_time(0.45, ctx.difficulty):
				_lunge = p.pos - position
				_lunge.y = 0.0
				_lunge = _lunge.normalized()
				set_state(State.STRIKE)
			return
		State.STRIKE:
			walk(_lunge, 6.0, dt, water_y)
			if not p.is_empty() and p.dist < 1.0:
				net.hurt_player(p.id, damage, position, self)
				set_state(State.RECOVER)
			elif state_t > 0.25:
				set_state(State.RECOVER)
			return
		State.RECOVER:
			if state_t > 0.8:
				_cd = rng.randf_range(0.8, 1.6)
				set_state(State.ALERT)
			return
	if on_ceiling:
		_ceiling_tick(p, ctx, dt)
	else:
		_ground_tick(p, ctx, dt, water_y)


## Clinging to the rock: listen. A heard footstep below, with no light about, and it drops.
func _ceiling_tick(p: Dictionary, ctx: Dictionary, dt: float) -> void:
	if not CombatMath.hostiles_allowed(ctx.difficulty):
		return
	if not _hears(p):
		if state != State.IDLE:
			set_state(State.IDLE)
		return
	turn_toward(p.pos - position, 3.0, dt)
	if _repelled(p, ctx):
		if state != State.REPELLED:
			set_state(State.REPELLED)       # hisses, but won't come down into the light
		return
	var below := Vector2(p.pos.x - position.x, p.pos.z - position.z).length()
	if below < 3.5:
		heard = p.pos
		set_state(State.WINDUP)


## On the cave floor: chase what it can hear, flinch from light, climb home when it loses you.
func _ground_tick(p: Dictionary, ctx: Dictionary, dt: float, water_y: float) -> void:
	if _repelled(p, ctx):
		if state != State.REPELLED:
			set_state(State.REPELLED)
		var src: Vector3 = p.pos if not p.is_empty() else heard
		var away := position - src
		away.y = 0.0
		if not walk(away, chase_speed, dt, water_y):
			walk(away.rotated(Vector3.UP, 1.2 * _orbit), chase_speed, dt, water_y)
		_lost += dt
		if _lost > GIVE_UP_SEC * 0.5:
			_climb_home(dt, water_y)
		return
	if _hears(p):
		heard = p.pos
		_lost = 0.0
	else:
		_lost += dt
	if _lost > GIVE_UP_SEC:
		_climb_home(dt, water_y)
		return
	if state != State.ALERT:
		set_state(State.ALERT)
	var to := heard - position
	to.y = 0.0
	turn_toward(to, 8.0, dt)
	if not p.is_empty() and p.dist < 1.3 and _cd <= 0.0 and _lost == 0.0:
		target_id = p.id
		set_state(State.WINDUP)
		return
	if to.length() > 0.6:
		if not walk(to, chase_speed, dt, water_y):
			if not walk(to.rotated(Vector3.UP, 1.0 * _orbit), chase_speed, dt, water_y):
				_orbit = -_orbit


func _climb_home(dt: float, water_y: float) -> void:
	if state != State.RETURN:
		set_state(State.RETURN)
	var to := ceiling - position
	to.y = 0.0
	if to.length() < 0.6 or state_t > 8.0:
		position = ceiling            # scuttles up the wall into the dark
		on_ceiling = true
		_lost = 0.0
		set_state(State.IDLE)
		return
	turn_toward(to, 6.0, dt)
	if not walk(to, chase_speed * 0.8, dt, water_y):
		if not walk(to.rotated(Vector3.UP, 1.0 * _orbit), chase_speed * 0.8, dt, water_y):
			_orbit = -_orbit


func _airborne() -> bool:
	var g := ground_under(position, 0.1, 0.12)
	return is_nan(g)


## Gravity. True on the frame it lands.
func _fall(dt: float) -> bool:
	_vy -= 22.0 * dt
	var nxt := position.y + _vy * dt
	var g := ground_under(position, 0.1, maxf(0.2, -_vy * dt + 0.2))
	if not is_nan(g) and nxt <= g:
		position.y = g
		_vy = 0.0
		return true
	position.y = nxt
	if position.y < -10.0:
		net.despawn(self)
	return false


## Clients don't get `on_ceiling`: rock just above and air just below means it's clinging.
func _clinging_visual() -> bool:
	if authority:
		return on_ceiling
	return solid_at(position + Vector3.UP * 0.08) and not solid_at(position - Vector3.UP * 0.3)


func animate(dt: float) -> void:
	var up := _clinging_visual()
	_visual_root.rotation.z = lerpf(_visual_root.rotation.z, PI if up else 0.0, 1.0 - exp(-dt * 10.0))
	var moving := state in [State.ALERT, State.REPELLED, State.RETURN, State.STRIKE]
	_phase += dt * (16.0 if moving else 2.0)
	for i in legs.size():
		var lg := legs[i]
		var off := sin(_phase + i * 1.3) * (0.35 if moving else 0.06)
		lg.rotation.z = off * (1.0 if i < 4 else -1.0)
	if state == State.WINDUP:
		body.rotation.x = sin(state_t * 40.0) * 0.08     # the shiver of a hiss
		body.position.y = -0.05
	else:
		body.rotation.x = lerpf(body.rotation.x, 0.0, 1.0 - exp(-dt * 8.0))
		body.position.y = 0.0
	if state == State.DEAD and not up:
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, PI, 1.0 - exp(-dt * 6.0))
