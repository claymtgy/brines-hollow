class_name SeaOtter
extends WildAnimal
## Sea otter: floats on its back in the kelp beds, cracking shells on its chest. Shy at
## first (it dives if you splash about), but stand still nearby holding a raw fish and press
## F to offer it: the otter becomes your friend, follows you along the water, and now and
## then brings you something it found on the seabed.

const SHY_RANGE := 5.0
const SWIM_SPEED := 1.8
const FOLLOW_SPEED := 3.6
const GIFT_EVERY := 150.0
const GIFTS := [[&"kelp_frond", 2], [&"sea_glass", 1], [&"shore_crab", 1], [&"kelp_frond", 3]]

var body: Node3D
var paws: Node3D
var friend_id := 0            # player id who befriended this otter (0 = wild)
var _gift_t := 60.0
var _dive_t := 0.0
var _phase := 0.0
var _swim_dir := Vector3.ZERO


func _init() -> void:
	super()
	kind = &"otter"
	clearance = 2
	radius = 0.3


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	var g := Prefabs.Grid.new(4, 3, 10)
	g.box(0, 0, 0, 3, 2, 7, Palette.TRUNK)           # body (floating belly-up)
	g.box(1, 2, 1, 2, 2, 6, Palette.DRIFTWOOD)       # pale chest
	g.box(1, 0, 0, 2, 1, 0, Palette.TRUNK)
	g.box(1, 1, -1 + 1, 2, 1, 0, Palette.TRUNK)      # tail
	g.box(0, 0, 8, 3, 2, 9, Palette.DRIFTWOOD)       # grizzled head
	g.setv(0, 2, 9, Palette.EYE)
	g.setv(3, 2, 9, Palette.EYE)
	g.setv(1, 1, 9, Palette.BEDROCK)
	g.setv(2, 1, 9, Palette.BEDROCK)                 # nose
	part(body, g, Vector3(-2, -1, -5))
	paws = pivot(body, Vector3(0, 2, 2))
	var pg := Prefabs.Grid.new(4, 1, 1)
	pg.setv(0, 0, 0, Palette.TRUNK)
	pg.setv(3, 0, 0, Palette.TRUNK)
	pg.box(1, 0, 0, 2, 0, 0, Palette.SANDSTONE_C)   # a shell to crack
	part(paws, pg, Vector3(-2, 0, -0.5))


func telegraph_height() -> float:
	return 0.5


func hint() -> String:
	return "A sea otter in the kelp. Stand still holding a raw fish and press F to offer it."


func is_friend() -> bool:
	return friend_id != 0


## Host: player `pid` offers a fish.
func befriend(pid: int) -> void:
	friend_id = pid
	_gift_t = 45.0
	set_state(State.LURED)


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	var water_y: float = ctx.water_y
	var p := nearest_player(ctx)
	var dist: float = p.get("dist", INF)
	if state == State.FLEE:
		# Dived: resurface somewhere else in a few seconds (or vanish for good).
		_dive_t -= dt
		position.y = water_y - 1.2
		if _dive_t <= 0.0:
			if friend_id == 0 and dist < SHY_RANGE * 2.5:
				net.despawn(self)
				return
			position.y = water_y - 0.12
			set_state(State.IDLE)
		return
	if is_friend():
		var f: Dictionary = {}
		for pl: Dictionary in ctx.players:
			if pl.id == friend_id:
				f = pl
		if f.is_empty():
			return
		var to: Vector3 = f.pos - position
		to.y = 0.0
		var fd := to.length()
		if fd > 3.0:
			if not surface_swim(to, FOLLOW_SPEED, dt, water_y, 0.25, -0.12):
				# Our friend went ashore: wait at the water's edge.
				position.y = water_y - 0.12
			turn_toward(to, 6.0, dt)
		else:
			position.y = water_y - 0.12
		_gift_t -= dt
		if _gift_t <= 0.0 and fd < 6.0:
			_gift_t = GIFT_EVERY
			var gift: Array = GIFTS[rng.randi() % GIFTS.size()]
			net.wild_gift(friend_id, [gift], "Your otter friend brings you something from the seabed.")
		return
	# Wild: shy. Splashing or sprinting near it makes it dive.
	if not p.is_empty() and dist < SHY_RANGE and (p.speed > 2.0 or p.sprinting) and not p.sneaking:
		startle(p.pos)
		return
	if state != State.IDLE:
		set_state(State.IDLE)
	if _swim_dir == Vector3.ZERO or rng.randf() < dt * 0.1:
		_swim_dir = (home - position + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))).normalized()
	if not surface_swim(_swim_dir, SWIM_SPEED * 0.3, dt, water_y, 0.3, -0.12):
		_swim_dir = -_swim_dir
	turn_toward(_swim_dir, 1.5, dt)


func startle(_from: Vector3) -> void:
	if friend_id != 0:
		return
	_dive_t = rng.randf_range(4.0, 8.0)
	set_state(State.FLEE)


func animate(dt: float) -> void:
	_phase += dt
	visible = state != State.FLEE
	body.rotation.z = sin(_phase * 0.8) * 0.12
	paws.rotation.x = sin(_phase * 6.0) * 0.4 if state == State.IDLE else 0.0   # crack, crack
