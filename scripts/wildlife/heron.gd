class_name GreyHeron
extends WildAnimal
## Grey heron: stands motionless in the shallows, stabbing at fish now and then. Patient
## and wary: it lifts off on slow wings if you come too close without sneaking.

const SCARE_RANGE := 10.0

var neck: Node3D
var wing_l: Node3D
var wing_r: Node3D
var _flap := 0.0
var _fly_dir := Vector3.ZERO
var _stab_t := 0.0


func _init() -> void:
	super()
	kind = &"heron"
	radius = 0.3
	clearance = 6


func _build_visuals(root: Node3D) -> void:
	var legs := Prefabs.Grid.new(3, 7, 1)
	legs.box(0, 0, 0, 0, 6, 0, Palette.SANDSTONE_B)
	legs.box(2, 0, 0, 2, 6, 0, Palette.SANDSTONE_B)
	part(root, legs, Vector3(-1.5, 0, -0.5))
	var b := Prefabs.Grid.new(4, 4, 8)
	b.box(0, 0, 0, 3, 3, 6, Palette.STONE)           # grey body
	b.box(0, 0, 4, 3, 1, 7, Palette.WHITEWASH)
	b.box(0, 3, 0, 3, 3, 3, Palette.BEDROCK)         # dark wing edge
	part(root, b, Vector3(-2, 7, -4))
	neck = pivot(root, Vector3(0, 10, 3))
	var n := Prefabs.Grid.new(2, 7, 2)
	n.box(0, 0, 0, 1, 5, 1, Palette.WHITEWASH)
	n.box(0, 5, 0, 1, 6, 1, Palette.WHITEWASH)
	n.setv(0, 6, 1, Palette.EYE)
	n.setv(1, 6, 1, Palette.EYE)
	n.setv(0, 6, 0, Palette.BEDROCK)                 # crest
	part(neck, n, Vector3(-1, 0, -1))
	var bill := Prefabs.Grid.new(1, 1, 4)
	bill.box(0, 0, 0, 0, 0, 3, Palette.BUOY)
	part(neck, bill, Vector3(-0.5, 5.5, 1))
	wing_l = pivot(root, Vector3(-2, 10, 0))
	wing_r = pivot(root, Vector3(2, 10, 0))
	for i in 2:
		var w := Prefabs.Grid.new(8, 1, 5)
		w.box(0, 0, 0, 7, 0, 4, Palette.STONE)
		w.box(5, 0, 0, 7, 0, 4, Palette.BEDROCK)
		var mi := part(wing_l if i == 0 else wing_r, w, Vector3(-8 if i == 0 else 0, 0, -2.5))
		mi.visible = false
		mi.set_meta("wing", true)


func telegraph_height() -> float:
	return 1.5


func hint() -> String:
	return "A heron fishing the shallows. Sneak (Ctrl) to watch it strike."


func startle(from: Vector3) -> void:
	_fly_dir = position - from
	_fly_dir.y = 0.0
	_fly_dir = _fly_dir.normalized() if _fly_dir.length() > 0.01 else facing()
	set_state(State.FLEE)


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	if state == State.FLEE:
		position += (_fly_dir * 4.5 + Vector3.UP * (1.6 if state_t < 3.0 else 0.4)) * dt
		turn_toward(_fly_dir, 4.0, dt)
		if state_t > 10.0:
			net.despawn(self)
		return
	var p := nearest_player(ctx)
	var dist: float = p.get("dist", INF)
	var noise := Perception.noise_radius(p.get("speed", 0.0), p.get("sneaking", false), p.get("sprinting", false), p.get("in_water", false))
	if not p.is_empty() and dist < SCARE_RANGE and (not p.sneaking or dist < 3.0) \
			and (dist < noise * 2.0 or Perception.can_see(position + Vector3.UP * 1.4, facing(), 200.0, SCARE_RANGE, p.pos, ctx.darkness)):
		startle(p.pos)
		return
	if state != State.IDLE:
		set_state(State.IDLE)
	_stab_t -= dt
	if _stab_t <= 0.0:
		_stab_t = rng.randf_range(4.0, 11.0)
		yaw += rng.randf_range(-0.6, 0.6)


func animate(dt: float) -> void:
	var flying := state == State.FLEE
	for w: Node3D in [wing_l, wing_r]:
		for c in w.get_children():
			(c as Node3D).visible = flying
	_flap += dt * (5.0 if flying else 0.0)
	wing_l.rotation.z = sin(_flap) * 0.7 if flying else 0.0
	wing_r.rotation.z = -sin(_flap) * 0.7 if flying else 0.0
	var stab := _stab_t < 0.35 and not flying
	neck.rotation.x = lerpf(neck.rotation.x, 1.1 if stab else (0.0 if not flying else 0.9), 1.0 - exp(-dt * (18.0 if stab else 4.0)))
