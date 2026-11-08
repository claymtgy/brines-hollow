class_name Puffin
extends WildAnimal
## Puffins: little colonies perched on sea stacks and cliff tops by day. They whirr off out
## to sea if you climb up among them noisily; sneak and they'll let you sit with them.

const SCARE_RANGE := 6.0

var wing_l: Node3D
var wing_r: Node3D
var _flap := 0.0
var _fly_dir := Vector3.ZERO


func _init() -> void:
	super()
	kind = &"puffin"
	clearance = 2
	radius = 0.18


func _build_visuals(root: Node3D) -> void:
	var g := Prefabs.Grid.new(3, 5, 3)
	g.box(0, 0, 0, 2, 3, 2, Palette.BEDROCK)         # black back
	g.box(0, 0, 2, 2, 2, 2, Palette.WHITEWASH)       # white front
	g.box(0, 3, 2, 2, 4, 2, Palette.WHITEWASH)       # white face
	g.box(0, 4, 0, 2, 4, 1, Palette.BEDROCK)         # cap
	g.setv(0, 4, 2, Palette.EYE)
	g.setv(2, 4, 2, Palette.EYE)
	part(root, g, Vector3(-1.5, 0.5, -1.5))
	var beak := Prefabs.Grid.new(1, 2, 2)
	beak.box(0, 0, 0, 0, 1, 1, Palette.BUOY)        # bright orange beak
	beak.setv(0, 1, 1, Palette.ROOF_RED)
	part(root, beak, Vector3(-0.5, 3.0, 1.5))
	var feet := Prefabs.Grid.new(3, 1, 1)
	feet.setv(0, 0, 0, Palette.BUOY)
	feet.setv(2, 0, 0, Palette.BUOY)
	part(root, feet, Vector3(-1.5, 0, 0))
	wing_l = pivot(root, Vector3(-1.5, 3, 0))
	wing_r = pivot(root, Vector3(1.5, 3, 0))
	for i in 2:
		var w := Prefabs.Grid.new(3, 1, 2)
		w.box(0, 0, 0, 2, 0, 1, Palette.BEDROCK)
		var mi := part(wing_l if i == 0 else wing_r, w, Vector3(-3 if i == 0 else 0, 0, -1))
		mi.visible = true


func telegraph_height() -> float:
	return 0.5


func hint() -> String:
	return "A puffin colony. Sneak (Ctrl) and they'll let you sit among them."


func startle(from: Vector3) -> void:
	_fly_dir = (position - from)
	_fly_dir.y = 0.0
	_fly_dir = _fly_dir.normalized() if _fly_dir.length() > 0.01 else facing()
	set_state(State.FLEE)


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	if state == State.FLEE:
		position += (_fly_dir * 7.0 + Vector3.UP * (2.0 if state_t < 1.5 else -0.4)) * dt
		turn_toward(_fly_dir, 8.0, dt)
		if state_t > 7.0:
			net.despawn(self)   # gone out to sea
		return
	if ctx.night > 0.7:
		net.despawn(self)       # into their burrows
		return
	var p := nearest_player(ctx)
	var dist: float = p.get("dist", INF)
	if not p.is_empty() and dist < SCARE_RANGE and not p.sneaking and p.speed > 0.4:
		startle(p.pos)
		# The whole colony goes up together.
		for c: Creature in net.creatures.values():
			if c != self and c is Puffin and c.state != State.FLEE and c.position.distance_to(position) < 6.0:
				(c as Puffin).startle(p.pos)
		return
	if state != State.IDLE:
		set_state(State.IDLE)
	if rng.randf() < dt * 0.3:
		yaw += rng.randf_range(-1.2, 1.2)   # shuffle and look about


func animate(dt: float) -> void:
	var flying := state == State.FLEE
	_flap += dt * (22.0 if flying else 0.0)
	var a := sin(_flap) * 0.9 + 0.2 if flying else 0.0
	wing_l.rotation.z = a
	wing_r.rotation.z = -a
