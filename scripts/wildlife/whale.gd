class_name MigratingWhale
extends WildAnimal
## A humpback passing far offshore: a long slow track through deep water, surfacing every
## twenty seconds or so with a blow you can see from the cliffs. Just to be watched.

const SPEED := 2.2
const SURFACE_EVERY := 22.0
const SURFACE_FOR := 6.0
const VIEW_DIST := 260.0

var body: Node3D
var tail: Node3D
var heading := Vector3.FORWARD
var _cycle := 0.0
var _blew := false


func _init() -> void:
	super()
	kind = &"whale"
	radius = 3.0


func setup(p_id: int, p_net: Node, pos: Vector3, p_authority: bool) -> void:
	super.setup(p_id, p_net, pos, p_authority)
	_cycle = rng.randf() * SURFACE_EVERY
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = VIEW_DIST


func _build_visuals(root: Node3D) -> void:
	# Built at 4x character scale: about 12 m long.
	body = Node3D.new()
	body.scale = Vector3.ONE * 4.0
	root.add_child(body)
	var g := Prefabs.Grid.new(8, 6, 30)
	g.box(0, 0, 4, 7, 5, 26, Palette.BEDROCK)
	g.box(1, 0, 27, 6, 4, 29, Palette.BEDROCK)       # head
	g.box(1, 0, 6, 6, 0, 27, Palette.WHITEWASH)      # pale throat grooves
	g.box(2, 0, 0, 5, 3, 3, Palette.BEDROCK)         # tail stock
	g.box(-0 + 3, 6 - 1, 15, 4, 5, 17, Palette.STONE) # small dorsal fin
	g.setv(0, 3, 26, Palette.EYE)
	g.setv(7, 3, 26, Palette.EYE)
	for z in [8, 14, 20]:                            # barnacle patches
		g.setv(2, 5, z, Palette.STONE)
		g.setv(5, 5, z + 2, Palette.STONE)
	part(body, g, Vector3(-4, -3, -15))
	var fins := Prefabs.Grid.new(20, 1, 6)
	fins.box(0, 0, 0, 5, 0, 5, Palette.WHITEWASH)    # long white flippers
	fins.box(14, 0, 0, 19, 0, 5, Palette.WHITEWASH)
	part(body, fins, Vector3(-10, -2, 4))
	tail = pivot(body, Vector3(0, -1, -15))
	var flukes := Prefabs.Grid.new(14, 1, 4)
	flukes.box(0, 0, 0, 13, 0, 3, Palette.BEDROCK)
	flukes.box(6, 0, 3, 7, 0, 3, Palette.AIR)
	part(tail, flukes, Vector3(-7, 0, -4))


func hint() -> String:
	return "A whale far out to sea. Watch for its blow."


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	var water_y: float = ctx.water_y
	_cycle += dt
	if _cycle > SURFACE_EVERY + SURFACE_FOR:
		_cycle = 0.0
		_blew = false
	var surfacing := _cycle > SURFACE_EVERY
	var target_y := water_y - (0.9 if surfacing else 5.0)
	position.y = lerpf(position.y, target_y, 1.0 - exp(-dt * 0.8))
	var nxt := position + heading * SPEED * dt
	if depth_at(nxt, water_y) < 6.0:
		heading = heading.rotated(Vector3.UP, 0.8 * dt * 6.0)   # bend away from the shallows
	else:
		position.x = nxt.x
		position.z = nxt.z
	turn_toward(heading, 0.5, dt)
	set_state(State.WANDER if not surfacing else State.RETURN)


func animate(dt: float) -> void:
	tail.rotation.x = sin(Time.get_ticks_msec() * 0.0012 + cid) * 0.35
	body.rotation.x = lerpf(body.rotation.x, -0.08 if state == State.RETURN else 0.05, 1.0 - exp(-dt))
	# The blow: once per surfacing, seen by every peer.
	if state == State.RETURN and not _blew and WildlifeFX.current != null:
		_blew = true
		WildlifeFX.current.spout(position + facing() * 8.0 + Vector3.UP * 0.6)
	elif state != State.RETURN:
		_blew = false
