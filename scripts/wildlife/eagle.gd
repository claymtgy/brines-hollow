class_name SeaEagle
extends Raider
## White-tailed sea eagle: by day it rides the thermals over the island and now and then
## circles a duck left out in the open, then stoops on it.
## Answers (any one is enough):
##   cover      a roof over the pen (or the duck sheltering under anything solid)
##   scarecrow  it won't stoop within ScarecrowEntity.RADIUS of one
##   company    a player within COMPANY_RANGE of the duck when it stoops scares it off
##   striking   hit it and it flees, dropping anything it carries
## Cozy: the stoop only scatters the ducks. Tidewatch / Undertow: it may carry one off.

const CIRCLE_TIME := 7.0
const CIRCLE_R := 9.0
const ALTITUDE := 14.0
const STOOP_SPEED := 13.0
const FLY_SPEED := 8.0
const COMPANY_RANGE := 6.0

var body: Node3D
var wing_l: Node3D
var wing_r: Node3D
var prey: MeshInstance3D
var _angle := 0.0
var _flap := 0.0


func _init() -> void:
	super()
	kind = &"eagle"
	max_hp = 12.0
	hp = 12.0
	radius = 0.5
	leaves_tracks = false
	flee_speed = 10.0


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)
	var g := Prefabs.Grid.new(4, 4, 11)
	g.box(0, 0, 1, 3, 2, 7, Palette.TRUNK)               # dark brown body
	g.box(0, 0, 0, 3, 1, 0, Palette.WHITEWASH)           # white tail
	g.box(1, 1, 8, 2, 3, 10, Palette.SANDSTONE_C)        # pale head
	g.setv(1, 3, 10, Palette.EYE)
	g.setv(2, 3, 10, Palette.EYE)
	g.setv(1, 2, 10, Palette.FLOWER_Y)                   # hooked yellow beak
	g.setv(2, 2, 10, Palette.FLOWER_Y)
	part(body, g, Vector3(-2, -1, -5.5))
	wing_l = pivot(body, Vector3(-2, 1, 0))
	wing_r = pivot(body, Vector3(2, 1, 0))
	var wg := Prefabs.Grid.new(11, 1, 5)
	wg.box(0, 0, 0, 10, 0, 4, Palette.TRUNK)
	wg.box(8, 0, 0, 10, 0, 4, Palette.DARK_WOOD)         # dark primaries
	part(wing_l, wg, Vector3(-11, 0, -2.5))
	part(wing_r, wg, Vector3(0, 0, -2.5))
	var dg := Prefabs.Grid.new(3, 3, 4)
	dg.box(0, 0, 0, 2, 2, 3, Palette.WHITEWASH)
	dg.setv(1, 2, 3, Palette.BUOY)
	prey = part(body, dg, Vector3(-1.5, -4, -1))
	prey.visible = false


func telegraph_height() -> float:
	return 0.4


func hint() -> String:
	return "A sea eagle! Roof the pen, put up a scarecrow, or stay near your ducks."


## Duck is under a roof (anything solid a little above its back).
func _covered(at: Vector3) -> bool:
	var vx := floori(at.x / VS)
	var vz := floori(at.z / VS)
	var vy := floori(at.y / VS)
	for y in range(vy + 3, vy + 24):
		if net.voxel(vx, y, vz) != 0:
			return true
	return false


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	var w := director()
	if state == State.DEAD:
		position.y -= 6.0 * dt
		if state_t > 1.5:
			net.despawn(self)
		return
	if w == null:
		return
	match state:
		State.FLEE, State.REPELLED, State.RETURN:
			_fly_off(dt)
			return
	var tp := target_pos()
	if tp == Vector3.INF:
		_turned_back("nothing")
		return
	# Called off by cover, a scarecrow, nightfall, or someone standing with the flock.
	if ctx.night > 0.5:
		set_state(State.REPELLED)
		return
	if _covered(tp):
		_turned_back("roof")
		return
	if w.near_scarecrow(tp):
		_turned_back("scarecrow")
		return
	for pl: Dictionary in ctx.players:
		if (pl.pos as Vector3).distance_to(tp) < COMPANY_RANGE:
			_turned_back("chased")
			return
	if state == State.STRIKE:
		var to := tp + Vector3.UP * 0.2 - position
		position += to.limit_length(STOOP_SPEED * dt)
		turn_toward(to, 10.0, dt)
		if to.length() < 0.6:
			w.resolve_raid(self)
			if is_carrying():
				set_state(State.RETURN)
			elif state == State.STRIKE:
				set_state(State.REPELLED)
		elif state_t > 6.0:
			set_state(State.REPELLED)
		return
	# Circling high over the target, then the stoop.
	if state != State.WANDER:
		set_state(State.WANDER)
	_angle += dt * 0.7
	var want := tp + Vector3(cos(_angle) * CIRCLE_R, ALTITUDE, sin(_angle) * CIRCLE_R)
	var d := want - position
	position += d.limit_length(FLY_SPEED * dt)
	turn_toward(Vector3(-sin(_angle), 0, cos(_angle)) if d.length() < 3.0 else d, 3.0, dt)
	if state_t > CIRCLE_TIME and d.length() < 4.0:
		set_state(State.STRIKE)


func _fly_off(dt: float) -> void:
	var to := den - position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	position += (dir * FLY_SPEED + Vector3.UP * 2.5) * dt
	turn_toward(dir, 4.0, dt)
	if to.length() < 3.0 or state_t > 22.0:
		if is_carrying():
			director().prey_lost(self)
		net.despawn(self)


func animate(dt: float) -> void:
	_check_grab_fx()
	prey.visible = state == State.RETURN
	var rate := 3.0 if state == State.WANDER else (0.0 if state == State.STRIKE else 9.0)
	_flap += dt * rate
	var a := sin(_flap) * 0.35 + 0.08
	if state == State.STRIKE:
		a = -0.9   # wings folded back in the stoop
	wing_l.rotation.z = lerpf(wing_l.rotation.z, -a, 1.0 - exp(-dt * 10.0))
	wing_r.rotation.z = lerpf(wing_r.rotation.z, a, 1.0 - exp(-dt * 10.0))
	_visual_root.rotation.x = lerpf(_visual_root.rotation.x, 0.7 if state == State.STRIKE else 0.0, 1.0 - exp(-dt * 6.0))
	_visual_root.rotation.z = lerpf(_visual_root.rotation.z, -0.3 if state == State.WANDER else 0.0, 1.0 - exp(-dt * 4.0))
