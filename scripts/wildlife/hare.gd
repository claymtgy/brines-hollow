class_name CoastalHare
extends WildAnimal
## Coastal hare: grazes the island grass by day and at dusk, bolts in zig-zags when it hears
## you. Sneak (Ctrl) and it may let you watch it from a few metres away.

const GRAZE_SPEED := 0.8
const BOLT_SPEED := 6.5
const SCARE_RANGE := 7.0

var ear_l: Node3D
var ear_r: Node3D
var body: Node3D
var _hop := 0.0
var _zig := 0.0


func _init() -> void:
	super()
	kind = &"hare"
	clearance = 3
	radius = 0.25


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	var g := Prefabs.Grid.new(4, 4, 7)
	g.box(0, 0, 0, 3, 2, 5, Palette.DRIFTWOOD)       # body
	g.box(1, 3, 0, 2, 3, 3, Palette.DRIFTWOOD)
	g.box(0, 1, 5, 3, 3, 6, Palette.DRIFTWOOD)       # head
	g.setv(0, 3, 6, Palette.EYE)
	g.setv(3, 3, 6, Palette.EYE)
	g.box(1, 1, 0, 2, 2, 0, Palette.WHITEWASH)       # tail
	g.box(1, 0, 4, 2, 0, 5, Palette.GRASS_DRY)       # pale belly
	part(body, g, Vector3(-2, 0, -3.5))
	ear_l = pivot(body, Vector3(-1, 3.5, 2))
	ear_r = pivot(body, Vector3(1, 3.5, 2))
	for e: Node3D in [ear_l, ear_r]:
		var eg := Prefabs.Grid.new(1, 4, 1)
		eg.box(0, 0, 0, 0, 3, 0, Palette.DRIFTWOOD)
		eg.setv(0, 3, 0, Palette.BEDROCK)            # black ear tips
		part(e, eg, Vector3(-0.5, 0, -0.5))


func telegraph_height() -> float:
	return 0.5


func hint() -> String:
	return "A coastal hare. It bolts at footsteps; sneak (Ctrl) to watch it graze."


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	var water_y: float = ctx.water_y
	var p := nearest_player(ctx)
	var dist: float = p.get("dist", INF)
	if state == State.FLEE:
		_zig += dt
		var from: Vector3 = p.pos if not p.is_empty() else position - facing()
		var away := (position - from)
		away.y = 0.0
		away = away.normalized().rotated(Vector3.UP, sin(_zig * 5.0) * 0.6)   # zig-zag
		var d := ground_move_around(away, BOLT_SPEED, dt, water_y)
		if d != Vector3.ZERO:
			turn_toward(d, 12.0, dt)
		if state_t > 3.0 and dist > SCARE_RANGE * 1.6:
			home = position
			set_state(State.WANDER)
		return
	var heard := not p.is_empty() and Perception.detects(position + Vector3.UP * 0.3, facing(), 300.0, 9.0,
			p.pos, Perception.noise_radius(p.speed, p.sneaking, p.sprinting, p.in_water), ctx.darkness)
	if heard and dist < SCARE_RANGE and not (p.sneaking and dist > 2.5):
		set_state(State.FLEE)
		return
	if state != State.WANDER:
		set_state(State.WANDER)
	wander(dt, water_y, GRAZE_SPEED, 5.0, 0.6)


func animate(dt: float) -> void:
	var moving := state == State.FLEE or (state == State.WANDER and _wander_dir != Vector3.ZERO)
	_hop += dt * (14.0 if state == State.FLEE else 7.0) * (1.0 if moving else 0.0)
	body.position.y = absf(sin(_hop)) * (0.12 if state == State.FLEE else 0.05) if moving else 0.0
	var ear_back := 0.9 if state == State.FLEE else 0.0
	ear_l.rotation.x = lerpf(ear_l.rotation.x, -ear_back + sin(Time.get_ticks_msec() * 0.003 + cid) * 0.08, 1.0 - exp(-dt * 10.0))
	ear_r.rotation.x = lerpf(ear_r.rotation.x, -ear_back, 1.0 - exp(-dt * 10.0))
