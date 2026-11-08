class_name HarbourSeal
extends WildAnimal
## Harbour seal: hauls out on the flats at low tide to doze, humps back into the sea if you
## come stomping up, and lolls at the surface when the tide is in. Sneak to get close.

const SCARE_RANGE := 8.0
const HUMP_SPEED := 1.3
const SWIM_SPEED := 2.4

var body: Node3D
var head: Node3D
var _phase := 0.0
var _swim_dir := Vector3.ZERO


func _init() -> void:
	super()
	kind = &"seal"
	clearance = 3
	radius = 0.5


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	var g := Prefabs.Grid.new(6, 5, 14)
	g.box(0, 0, 2, 5, 3, 10, Palette.STONE)          # torso
	g.box(1, 4, 3, 4, 4, 9, Palette.STONE)
	g.box(1, 0, 0, 4, 2, 1, Palette.STONE)           # tapering tail
	g.box(0, 0, 0, 1, 0, 0, Palette.BEDROCK)         # rear flippers
	g.box(4, 0, 0, 5, 0, 0, Palette.BEDROCK)
	g.box(0, 0, 8, 0, 0, 9, Palette.BEDROCK)         # fore flippers
	g.box(5, 0, 8, 5, 0, 9, Palette.BEDROCK)
	g.box(1, 0, 3, 4, 0, 9, Palette.SANDSTONE_C)     # pale belly
	for z in [3, 5, 7]:                              # mottling
		g.setv(1, 4, z, Palette.BEDROCK)
		g.setv(4, 3, z + 1, Palette.BEDROCK)
	part(body, g, Vector3(-3, 0, -7))
	head = pivot(body, Vector3(0, 2.5, 4))
	var hg := Prefabs.Grid.new(4, 4, 4)
	hg.box(0, 0, 0, 3, 3, 3, Palette.STONE)
	hg.setv(0, 2, 3, Palette.EYE)
	hg.setv(3, 2, 3, Palette.EYE)
	hg.box(1, 0, 3, 2, 1, 3, Palette.BEDROCK)       # muzzle
	part(head, hg, Vector3(-2, -1, 0))


func telegraph_height() -> float:
	return 0.7


func hint() -> String:
	return "A seal hauled out at low tide. Sneak (Ctrl) to get close before it slips back into the sea."


func _in_water(water_y: float) -> bool:
	return depth_at(position, water_y) > 0.4


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	var water_y: float = ctx.water_y
	var p := nearest_player(ctx)
	var dist: float = p.get("dist", INF)
	if _in_water(water_y):
		# Lolling at the surface; drifts away from boats and swimmers.
		if state != State.RETURN:
			set_state(State.RETURN)
		if _swim_dir == Vector3.ZERO or rng.randf() < dt * 0.15:
			_swim_dir = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		if not p.is_empty() and dist < 5.0:
			_swim_dir = (position - p.pos).normalized()
		if not surface_swim(_swim_dir, SWIM_SPEED * (1.6 if dist < 5.0 else 0.5), dt, water_y, 0.4, -0.25):
			_swim_dir = -_swim_dir
		turn_toward(_swim_dir, 3.0, dt)
		# Low tide again and nobody about: haul out on the nearest flat.
		if water_y < VoxelWorld.SEA_MID * VS and dist > 14.0 and state_t > 25.0:
			var g := ground_under(position + _swim_dir * 2.0, 0.6, 1.2)
			if not is_nan(g) and g > water_y - 0.1:
				position = Vector3(position.x + _swim_dir.x * 2.0, g, position.z + _swim_dir.z * 2.0)
				home = position
				set_state(State.IDLE)
		return
	match state:
		State.FLEE:
			# Hump toward the deepest nearby water.
			var best := Vector3.ZERO
			var best_d := 0.0
			for k in 8:
				var d := Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0))
				var dep := depth_at(position + d * 3.0, water_y)
				if dep > best_d:
					best_d = dep
					best = d
			if best == Vector3.ZERO and not p.is_empty():
				best = (position - p.pos).normalized()
			turn_toward(best, 6.0, dt)
			if not ground_move(best, HUMP_SPEED, dt, water_y, 2.0):
				position += best * HUMP_SPEED * dt   # slide off the edge into the water
				position.y = maxf(water_y - 0.25, position.y - dt * 2.0)
			return
	var heard := not p.is_empty() and Perception.detects(position + Vector3.UP * 0.4, facing(), 260.0, 10.0,
			p.pos, Perception.noise_radius(p.speed, p.sneaking, p.sprinting, p.in_water), ctx.darkness)
	if heard and dist < SCARE_RANGE and not (p.sneaking and dist > 2.0):
		set_state(State.FLEE)
		return
	if state != State.IDLE:
		set_state(State.IDLE)   # dozing
	if not p.is_empty() and dist < 12.0:
		turn_toward(p.pos - position, 1.5, dt)


func animate(dt: float) -> void:
	_phase += dt * (8.0 if state == State.FLEE else 1.2)
	if state == State.FLEE:
		body.position.y = absf(sin(_phase)) * 0.08
		body.rotation.x = sin(_phase) * 0.12
	else:
		body.position.y = lerpf(body.position.y, 0.0, 1.0 - exp(-dt * 6.0))
		body.rotation.x = lerpf(body.rotation.x, 0.0, 1.0 - exp(-dt * 6.0))
	# Dozing seals raise head and tail ("banana" pose); swimming ones show just the head.
	head.rotation.x = -0.5 + sin(_phase * 0.7) * 0.15 if state == State.IDLE else -0.2
