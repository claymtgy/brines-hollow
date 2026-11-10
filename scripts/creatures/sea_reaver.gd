class_name SeaReaver
extends Creature
## Sea-Reavers: marooned pirate castaways holding palisaded outposts on the far islands (see
## ReaverOutposts). Cutlass reavers close in and slash; harpooners keep their distance and
## throw.
##
## Non-combat answers:
##   - They keep watch by sight, not hearing: sneak (Ctrl) and keep out of their eyeline, and
##     at night they see much less far (their own torches aside).
##   - They hold their post: get well clear of the palisade, or swim, and they go back.
##   - The War Horn Totem: while it stands, a beaten garrison is back in a few minutes, and a
##     roused outpost blows it once for help. Beat the guards and topple it (F) and the
##     outpost is yours for good: a forward base with a bunk to wake in.
## Cozy: they never attack; they shout and keep to their posts.
##
## Combat: cutlass 22 HP (a two-cut combo, short windup). Harpooner 16 HP (a long, readable
## wind-up then a throw that reaches 11 m; dodge (C) as the arm comes forward).

const LEASH := 26.0
const GIVE_UP := 34.0
const THROW_RANGE := 11.0
const SIGHT := 16.0
const MAX_ATTACKERS := 2

var harpooner := false
var outpost := -1               # host: index into ReaverOutposts.outposts
var post_center := Vector3.ZERO
var post := Vector3.ZERO        # where this one stands guard (metres)
var roused := false
var walk_speed := 1.3
var chase_speed := 4.2
var strike_range := 1.5
var damage := 4.0
var windup := 0.55
var recover := 0.6
var model: CharacterModel
var _cd := 0.0
var _combo := 0
var _lunge := Vector3.ZERO
var _orbit := 1.0
var _reported := false
var _speed := 0.0
var _last := Vector3.ZERO


func _init(p_harpooner := false) -> void:
	harpooner = p_harpooner
	hostile = true
	if harpooner:
		kind = &"reaver_harpooner"
		max_hp = 16.0
		strike_range = THROW_RANGE
		damage = 5.0
		windup = 1.1
		recover = 1.2
		chase_speed = 3.6
	else:
		kind = &"reaver"
		max_hp = 22.0
		max_poise = 26.0
	hp = max_hp
	poise = max_poise
	radius = 0.4


func _build_visuals(root: Node3D) -> void:
	var cust := CharacterCustomizer.new()
	cust.randomize_appearance(cid * 977 + 3)
	model = CharacterModel.new()
	root.add_child(model)
	model.setup(Palette.DARK_WOOD, Palette.ROOF_RED if not harpooner else Palette.TROUSER, cust)
	model.set_tool(6 if harpooner else 5)


func setup(p_id: int, p_net: Node, pos: Vector3, p_authority: bool) -> void:
	super.setup(p_id, p_net, pos, p_authority)
	_last = pos


func telegraph_height() -> float:
	return 2.15


func hint() -> String:
	if harpooner:
		return "Reaver harpooners throw from range: when the arm draws back (\"!\"), dodge (C). Close in and they're weak."
	return "Sea-Reavers watch by sight: sneak (Ctrl) and keep out of view, more so at night. Topple their War Horn Totem (F) once the guards are down and the outpost is yours."


func drops() -> Array:
	if harpooner:
		return [[&"brass_guilder", 6], [&"iron_ingot", 1]]
	return [[&"brass_guilder", 8], [&"wood_plank", 2]]


func _on_windup_started() -> void:
	CombatAudio.play_sound("tell_roar", position)


func on_hit(dmg: float, from: Vector3, power: float, attacker: int) -> bool:
	var ok := super.on_hit(dmg, from, power, attacker)
	if ok:
		_rouse()
	return ok


func _rouse() -> void:
	roused = true
	if net != null and net.get("outposts") != null and outpost >= 0:
		net.outposts.rouse(outpost)


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	_cd = maxf(0.0, _cd - dt)
	var water_y: float = ctx.water_y
	if state == State.DEAD:
		if not _reported:
			_reported = true
			if net.get("outposts") != null and outpost >= 0:
				net.outposts.on_killed(outpost, self)
		if state_t > 1.4:
			net.despawn(self)
		return
	var p := _nearest_in_reach(ctx)
	var dist: float = p.get("dist", INF)
	match state:
		State.STAGGER:
			if state_t > CombatMath.STAGGER_TIME:
				set_state(State.ALERT)
			return
		State.WINDUP:
			if p.is_empty():
				set_state(State.RETURN)
				return
			turn_toward(p.pos - position, 7.0, dt)
			if state_t >= CombatMath.windup_time(windup, ctx.difficulty):
				_lunge = p.pos - position
				_lunge.y = 0.0
				_lunge = _lunge.normalized()
				set_state(State.STRIKE)
			return
		State.STRIKE:
			if harpooner:
				# the throw: it lands if you're still in range and in front of them
				if not p.is_empty() and dist < THROW_RANGE + 0.5 and facing().dot((p.pos - position).normalized()) > 0.8:
					net.hurt_player(p.id, damage, position + Vector3.UP * 1.4, self)
				set_state(State.RECOVER)
				return
			walk(_lunge, 5.0, dt, water_y)
			if not p.is_empty() and dist < strike_range + 0.2:
				net.hurt_player(p.id, damage, position, self)
				_combo += 1
				if _combo < 2:
					set_state(State.WINDUP)      # the second cut follows fast
					state_t = CombatMath.windup_time(windup, ctx.difficulty) * 0.55
					return
				set_state(State.RECOVER)
			elif state_t > 0.25:
				set_state(State.RECOVER)
			return
		State.RECOVER:
			if state_t > recover:
				_combo = 0
				_cd = rng.randf_range(0.9, 1.8)
				set_state(State.ALERT)
			return
	if not CombatMath.hostiles_allowed(ctx.difficulty):
		_idle(dt, ctx, water_y)
		return
	var noticed := false
	if not p.is_empty():
		var torch := 0.45 if ctx.night > 0.5 else 0.0      # their own torches light the yard
		noticed = roused and dist < 18.0 or Perception.detects(position + Vector3.UP * 1.6, facing(), 150.0, SIGHT,
				p.pos, Perception.noise_radius(p.speed, p.sneaking, p.sprinting, p.in_water) * 0.6,
				maxf(0.0, ctx.darkness - torch))
	if not noticed:
		if state == State.ALERT:
			set_state(State.RETURN)
		_idle(dt, ctx, water_y)
		return
	if not roused:
		_rouse()
	target_id = p.id
	if state != State.ALERT:
		set_state(State.ALERT)
	var to: Vector3 = p.pos - position
	to.y = 0.0
	turn_toward(to, 7.0, dt)
	var my_turn: bool = harpooner or net.get("outposts") == null or net.outposts.attackers(outpost) < MAX_ATTACKERS
	if harpooner:
		# keep 5-9 m off and throw
		if dist < THROW_RANGE and dist > 3.0 and _cd <= 0.0:
			set_state(State.WINDUP)
			return
		var want := 7.0
		var dir := to.normalized() * (1.0 if dist > want + 1.0 else (-1.0 if dist < want - 2.0 else 0.0))
		dir += Vector3(-to.z, 0, to.x).normalized() * 0.4 * _orbit
		if not walk(dir, chase_speed * 0.8, dt, water_y):
			_orbit = -_orbit
		return
	if dist < strike_range and _cd <= 0.0 and my_turn:
		set_state(State.WINDUP)
		return
	if not my_turn and dist < 3.2:
		var tangent := Vector3(-to.z, 0, to.x).normalized() * _orbit
		if not walk(tangent - to.normalized() * (0.5 if dist < 2.4 else 0.0), walk_speed * 1.6, dt, water_y):
			_orbit = -_orbit
		return
	if dist > strike_range * 0.8:
		if not walk(to, chase_speed, dt, water_y):
			if not walk(to.rotated(Vector3.UP, 0.9 * _orbit), chase_speed, dt, water_y):
				_orbit = -_orbit


func _nearest_in_reach(ctx: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	for pl: Dictionary in ctx.players:
		if Vector2(pl.pos.x - post_center.x, pl.pos.z - post_center.z).length() > GIVE_UP:
			continue
		if pl.in_water and pl.pos.y < ctx.water_y - 0.4:
			continue
		var d: float = position.distance_to(pl.pos)
		if d < bd:
			bd = d
			best = pl
	if not best.is_empty():
		best = best.duplicate()
		best["dist"] = bd
	return best


## Back to their post, and stand watch there, looking out.
func _idle(dt: float, ctx: Dictionary, water_y: float) -> void:
	var off := Vector2(position.x - post.x, position.z - post.z).length()
	if off > 0.7:
		if state != State.RETURN:
			set_state(State.RETURN)
		var d := post - position
		d.y = 0.0
		turn_toward(d, 6.0, dt)
		if not walk(d, walk_speed * (2.0 if off > 6.0 else 1.0), dt, water_y):
			if not walk(d.rotated(Vector3.UP, 0.9 * _orbit), walk_speed * 2.0, dt, water_y):
				_orbit = -_orbit
				if state_t > 6.0:
					position = Vector3(post.x, position.y, post.z)
		return
	if state != State.IDLE:
		set_state(State.IDLE)
	# look out from the camp, sweeping slowly
	var out := post - post_center
	out.y = 0.0
	if out.length() < 0.5:
		out = Vector3(sin(yaw), 0, cos(yaw))
	turn_toward(out.rotated(Vector3.UP, sin(state_t * 0.4 + cid) * 1.1), 1.5, dt)


func animate(dt: float) -> void:
	if model == null:
		return
	var moved := Vector2(position.x - _last.x, position.z - _last.z).length() / maxf(dt, 0.0001)
	_last = position
	_speed = lerpf(_speed, moved, 1.0 - exp(-dt * 8.0))
	model.animate(dt, _speed, true, false)
	if state == State.STRIKE and state_t < dt * 1.5:
		model.swing()
	if state == State.WINDUP and model.arm_r != null:
		model.arm_r.rotation.x = lerpf(model.arm_r.rotation.x, -2.4 if harpooner else -1.8, 1.0 - exp(-dt * 12.0))
	if state == State.DEAD:
		_visual_root.rotation.x = lerpf(_visual_root.rotation.x, -PI * 0.5, 1.0 - exp(-dt * 6.0))
