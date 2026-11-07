class_name CaveEel
extends Creature
## Night-cave eel: lurks in the flooded sea cave after dark and lunges at anyone at the
## water's edge. The dangerous one.
##
## Non-combat answers:
##   - Light: it will not come within ~4.5 m of a lamp, lantern voxel or a held lantern staff.
##     Place a Lamp Post or Lantern Glow by the water and the cave is safe.
##   - Sneak along the ledges: in the dark it mostly hunts by sound.
##   - Timing: it only hunts at night (Undertow: any time) - come back by day.
## Combat: 40 HP, slow readable windup (eyes flare, head rears, "!"), parry it to stagger it.

const SEGMENTS := 7
const SWIM_SPEED := 1.1
const LUNGE_SPEED := 7.5
const STRIKE_RANGE := 3.6
const BITE := 6.0

var head: Node3D
var segs: Array[Node3D] = []
var _eyes: MeshInstance3D
var _phase := 0.0
var _lunge_dir := Vector3.ZERO
var _orbit := 0.0


func _init() -> void:
	kind = &"eel"
	max_hp = 40.0
	hp = 40.0
	hostile = true
	radius = 0.45


func _build_visuals(root: Node3D) -> void:
	head = Node3D.new()
	root.add_child(head)
	var h := Prefabs.Grid.new(4, 3, 5)
	h.box(0, 0, 0, 3, 2, 4, Palette.KELP)
	h.box(0, 0, 3, 3, 0, 4, Palette.SANDSTONE_C)   # pale jaw
	h.setv(0, 2, 3, Palette.GLOW_TEAL)
	h.setv(3, 2, 3, Palette.GLOW_TEAL)
	part(head, h, Vector3(-2, -1.5, -2))
	var eyes := Prefabs.Grid.new(6, 1, 1)
	eyes.setv(0, 0, 0, Palette.GLOW_TEAL)
	eyes.setv(5, 0, 0, Palette.GLOW_TEAL)
	_eyes = part(head, eyes, Vector3(-3, 0.6, 1.5))
	for i in SEGMENTS:
		var s := Node3D.new()
		root.add_child(s)
		var g := Prefabs.Grid.new(3, 3, 3)
		g.box(0, 0, 0, 2, 2, 2, Palette.KELP if i % 2 == 0 else Palette.LEAVES_DARK)
		g.setv(1, 2, 1, Palette.SANDSTONE_B)          # dorsal fleck
		var mi := part(s, g, Vector3(-1.5, -1.5, -1.5))
		mi.scale = Vector3.ONE * (1.0 - float(i) / (SEGMENTS + 2))
		segs.append(s)


func telegraph_height() -> float:
	return 0.9


func hint() -> String:
	return "Cave eels shun light. Set a lamp or lantern by the water, sneak along the ledge (Ctrl), or come back by day."


func drops() -> Array:
	return [[&"lightning_eel", 1]]


func _lit(ctx: Dictionary) -> bool:
	return Perception.is_lit(position, ctx.lights)


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	var water_y: float = ctx.water_y
	if state == State.DEAD:
		position.y -= dt * 0.5
		if state_t > 1.2:
			net.despawn(self)
		return
	# Too shallow here now (tide went out)? Slip back toward home.
	var p := nearest_player(ctx)
	var dist: float = p.get("dist", INF)
	match state:
		State.STAGGER:
			if state_t > CombatMath.STAGGER_TIME:
				set_state(State.RETURN)
			return
		State.ALERT:
			turn_toward(p.pos - position if not p.is_empty() else facing(), 6.0, dt)
			if state_t > 0.35:
				set_state(State.WINDUP)
			return
		State.WINDUP:
			if _lit(ctx):
				set_state(State.REPELLED)
				return
			if not p.is_empty():
				turn_toward(p.pos - position, 8.0, dt)
				_lunge_dir = (p.pos + Vector3.UP * 0.6 - position).normalized()
			swim(-facing(), 0.4, dt, water_y)  # rear back
			if state_t >= CombatMath.windup_time(0.85, ctx.difficulty):
				set_state(State.STRIKE)
			return
		State.STRIKE:
			var moved := swim(_lunge_dir, LUNGE_SPEED, dt, water_y, 0.7)
			if not p.is_empty() and position.distance_to(p.pos + Vector3.UP * 0.6) < 1.3:
				net.hurt_player(p.id, BITE, position, self)
				set_state(State.RECOVER)
			elif not moved or state_t > 0.4:
				set_state(State.RECOVER)
			return
		State.RECOVER:
			swim(home - position, SWIM_SPEED * 1.6, dt, water_y)
			if state_t > 1.1:
				set_state(State.RETURN)
			return
		State.REPELLED:
			var away: Vector3 = position - (ctx.lights[0] if not ctx.lights.is_empty() else position + facing())
			for l: Vector3 in ctx.lights:
				if position.distance_to(l) < away.length():
					away = position - l
			away.y = 0.0
			turn_toward(away, 5.0, dt)
			if not swim(away, SWIM_SPEED * 1.8, dt, water_y):
				swim(home - position, SWIM_SPEED, dt, water_y)
			if state_t > 2.0 and not _lit(ctx):
				set_state(State.RETURN)
			return
	if _lit(ctx):
		set_state(State.REPELLED)
		return
	# Hunting: only someone at the water's edge (or in it) can be reached.
	if not p.is_empty() and CombatMath.hostiles_allowed(ctx.difficulty):
		var near_water: bool = p.pos.y < water_y + 1.3
		var noticed := Perception.detects(position, facing(), 140.0, 9.0, p.pos,
				Perception.noise_radius(p.speed, p.sneaking, p.sprinting, p.in_water), 1.0,
				1.3 if ctx.difficulty == CombatMath.Difficulty.UNDERTOW else 1.0)
		if noticed and near_water and dist < STRIKE_RANGE and not p.has_light:
			target_id = p.id
			set_state(State.ALERT)
			return
		if noticed and dist < 9.0:
			# Shadow the player from below the surface.
			var to: Vector3 = p.pos - position
			to.y = 0.0
			turn_toward(to, 3.0, dt)
			if dist > 2.5 and position.distance_to(home) < 9.0:
				swim(to, SWIM_SPEED, dt, water_y)
			return
	# Lurk: slow loops around home.
	var back := home - position
	if back.length() > 9.0:
		set_state(State.RETURN)
	if state == State.RETURN:
		turn_toward(back, 4.0, dt)
		swim(back, SWIM_SPEED * 1.3, dt, water_y)
		if back.length() < 1.5:
			set_state(State.WANDER)
		return
	set_state(State.WANDER)
	_orbit += dt * 0.4
	var want := home + Vector3(cos(_orbit) * 2.5, -0.3 + sin(_orbit * 1.7) * 0.25, sin(_orbit * 2.0) * 1.5)
	var d := want - position
	turn_toward(d, 3.0, dt)
	if not swim(d, SWIM_SPEED, dt, water_y):
		_orbit += 1.0


func animate(dt: float) -> void:
	var fast := state in [State.STRIKE, State.REPELLED, State.RECOVER]
	_phase += dt * (9.0 if fast else 3.5)
	# Head leads; body segments trail behind along a recorded path (cheap snake).
	head.position = Vector3.ZERO
	head.rotation.x = lerpf(head.rotation.x, -0.6 if state == State.WINDUP else 0.0, 1.0 - exp(-dt * 10.0))
	# Telegraph: eyes flicker while it winds up (plus the head rear and the "!" label).
	_eyes.visible = not (state in [State.WINDUP, State.ALERT]) or fmod(_phase * 2.0, 1.0) > 0.35
	for i in segs.size():
		var s: Node3D = segs[i]
		var back := -(i + 1) * 0.26
		s.position = Vector3(sin(_phase - i * 0.8) * 0.12 * (i + 1) * 0.35, 0.0, back)
		s.rotation.y = cos(_phase - i * 0.8) * 0.3
	if state == State.DEAD:
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, PI, 1.0 - exp(-dt * 4.0))
