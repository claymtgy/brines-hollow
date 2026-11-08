class_name RedFox
extends Raider
## Red fox: dens in the island woods. At dusk and through the night it scouts for an
## unguarded pen, slips through any gap under a fence and carries off a duck. It leaves paw
## tracks you can follow back to its den, and a drift of feathers where it struck.
## See Raider for the answers: light, proper fences and gates, chasing it, live traps.

var body: Node3D
var tail: Node3D
var head: Node3D
var prey: MeshInstance3D
var _phase := 0.0


func _init() -> void:
	super()
	kind = &"fox"
	max_hp = 14.0
	hp = 14.0
	radius = 0.3
	clearance = 3
	body_width = 0.3
	stalk_speed = 2.6
	flee_speed = 6.2
	carry_speed = 4.2
	track_size = 0.075


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	var g := Prefabs.Grid.new(4, 4, 9)
	g.box(0, 2, 0, 3, 4 - 1, 7, Palette.ROOF_RED)    # russet body
	g.box(1, 1, 1, 2, 1, 6, Palette.WHITEWASH)       # pale belly
	for x in [0, 3]:                                 # black stockings
		g.box(x, 0, 1, x, 1, 1, Palette.BEDROCK)
		g.box(x, 0, 6, x, 1, 6, Palette.BEDROCK)
	part(body, g, Vector3(-2, 0, -4.5))
	head = pivot(body, Vector3(0, 3, 4))
	var hg := Prefabs.Grid.new(4, 4, 4)
	hg.box(0, 0, 0, 3, 2, 2, Palette.ROOF_RED)
	hg.box(1, 0, 3, 2, 1, 3, Palette.WHITEWASH)      # muzzle
	hg.setv(1, 1, 3, Palette.BEDROCK)
	hg.setv(0, 2, 2, Palette.EYE)
	hg.setv(3, 2, 2, Palette.EYE)
	hg.setv(0, 3, 0, Palette.BEDROCK)                # ears
	hg.setv(3, 3, 0, Palette.BEDROCK)
	part(head, hg, Vector3(-2, -1, 0))
	tail = pivot(body, Vector3(0, 3, -4.5))
	var tg := Prefabs.Grid.new(3, 3, 6)
	tg.box(0, 0, 0, 2, 2, 5, Palette.ROOF_RED)
	tg.box(0, 0, 0, 2, 2, 1, Palette.WHITEWASH)      # white tip
	part(tail, tg, Vector3(-1.5, -1.5, -6))
	# The duck in its jaws (shown while carrying one off).
	var dg := Prefabs.Grid.new(3, 3, 4)
	dg.box(0, 0, 0, 2, 2, 3, Palette.WHITEWASH)
	dg.setv(1, 2, 3, Palette.BUOY)
	prey = part(head, dg, Vector3(-1.5, -2.5, 3))
	prey.visible = false


func telegraph_height() -> float:
	return 0.7


func hint() -> String:
	return "A fox is about! Lanterns keep it off, Pen Fences and closed gates keep it out, and a baited live trap catches it unharmed."


func animate(dt: float) -> void:
	_check_grab_fx()
	prey.visible = state == State.RETURN
	var moving := is_moving_state()
	var fast := state in [State.FLEE, State.RETURN]
	_phase += dt * (16.0 if fast else 9.0) * (1.0 if moving else 0.0)
	body.position.y = absf(sin(_phase)) * (0.05 if fast else 0.025) if moving else 0.0
	# Stalking: head low and tail straight out. Fleeing: tail streaming.
	var stalking := state in [State.WANDER, State.LURED]
	head.rotation.x = lerpf(head.rotation.x, 0.35 if stalking else -0.1, 1.0 - exp(-dt * 6.0))
	tail.rotation.x = lerpf(tail.rotation.x, 0.2 if stalking else -0.25, 1.0 - exp(-dt * 6.0))
	tail.rotation.y = sin(_phase * 0.5) * 0.25
	if state == State.DEAD:
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, PI * 0.5, 1.0 - exp(-dt * 8.0))
