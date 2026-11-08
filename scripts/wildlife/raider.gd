class_name Raider
extends WildAnimal
## Shared brain for farm raiders (foxes, stoats). They come from a den at night, go for the
## weakest pen, and leave again. They target livestock and stores, never players.
##
## Every threat has a non-lethal answer:
##   light    a lantern post, a fire or a held lantern within ~6 m of the target turns it back
##   fences   it must find a way in: rail fences have gaps under them, Pen Fence and a
##            closed Pen Gate don't (see TerrainStep). No way in after a while: it gives up
##   chasing  come close and it bolts, dropping anything it's carrying
##   traps    a baited Live-Capture Trap nearby lures it in; carry it off to a far islet
## A turned-back raider remembers the farm is defended for a few days.
## Combat is possible but never needed.

const LIGHT_RADIUS := 6.0
const SPOOK_RANGE := 6.0
const GIVE_UP_AFTER := 30.0

var stalk_speed := 2.6
var flee_speed := 6.0
var carry_speed := 4.0
var den := Vector3.ZERO
var raid_site := Vector3.ZERO
var target_animal_id := 0
var target_coop := Vector3i.MAX
var target_store := Vector3i.MAX   # rats: an open chest or crate with food in it
var carried := {}             # serialized livestock animal, while carrying one off
var _prefer_side := 1.0
var _best_dist := INF
var _stuck_t := 0.0
var _stalled_t := 0.0
var _was_carrying := false


func _init() -> void:
	super()
	damageable = true
	leaves_tracks = true


func director() -> WildlifeDirector:
	return net.wildlife if net != null else null


func is_carrying() -> bool:
	return not carried.is_empty()


## Where we're headed right now (metres), or INF if the target is gone.
func target_pos() -> Vector3:
	var w := director()
	if w == null:
		return Vector3.INF
	if target_animal_id != 0:
		var a: Node3D = w.animal(target_animal_id)
		return a.position if a != null else Vector3.INF
	if target_coop != Vector3i.MAX:
		var c: WorldEntity = w.coop_at(target_coop)
		return c.position if c != null else Vector3.INF
	if target_store != Vector3i.MAX:
		var st: ChestEntity = w.store_at(target_store)
		return st.position if st != null else Vector3.INF
	return Vector3.INF


## How close counts as "got there": a duck, or the side of a coop.
func reach_radius() -> float:
	if (target_coop != Vector3i.MAX or target_store != Vector3i.MAX) and director() != null:
		var c: WorldEntity = director().coop_at(target_coop) if target_coop != Vector3i.MAX 				else director().store_at(target_store)
		if c != null:
			var aabb := c.get_aabb()
			return maxf(aabb.size.x, aabb.size.z) * 0.5 + 0.45
	return 0.75


func on_hit(damage: float, from: Vector3, power: float, attacker: int) -> bool:
	var ok := super.on_hit(damage, from, power, attacker)
	if state != State.DEAD:
		_spooked("struck")
	elif is_carrying():
		director().drop_prey(self)
	return ok


func startle(_from: Vector3) -> void:
	_spooked("startled")


func _spooked(reason: String) -> void:
	var w := director()
	if w != null:
		if is_carrying():
			w.drop_prey(self)
		w.mark_defended(raid_site, reason)
	set_state(State.FLEE)


func _turned_back(reason: String) -> void:
	var w := director()
	if w != null:
		w.mark_defended(raid_site, reason)
	set_state(State.REPELLED)


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	var water_y: float = ctx.water_y
	var w := director()
	if state == State.DEAD:
		if state_t > 0.8:
			net.despawn(self)
		return
	if w == null:
		return
	var p := nearest_player(ctx)
	var dist: float = p.get("dist", INF)
	# Spotted close up: bolt (a sneaking player can get nearer before it notices).
	if state != State.FLEE and not p.is_empty() and dist < SPOOK_RANGE * (0.5 if p.sneaking else 1.0):
		var noticed := Perception.detects(position + Vector3.UP * 0.3, facing(), 240.0, SPOOK_RANGE * 1.5,
				p.pos, Perception.noise_radius(p.speed, p.sneaking, p.sprinting, p.in_water), ctx.darkness)
		if noticed or dist < 2.0:
			_spooked("chased")
			return
	match state:
		State.FLEE, State.REPELLED, State.RETURN:
			_go_home(dt, water_y, flee_speed if state == State.FLEE else (carry_speed if is_carrying() else stalk_speed))
			return
	# A guard dog or dock cat on watch sees us off.
	var guard := w.guard_check(self)
	if guard != "":
		_spooked(guard)
		return
	# Dawn: slink off.
	if ctx.night < 0.25:
		set_state(State.REPELLED)
		return
	# Light near us or the pen turns us back.
	if Perception.is_lit(position, ctx.lights, LIGHT_RADIUS):
		_turned_back("light")
		return
	# Bait beats everything.
	var trap: LiveTrapEntity = w.nearest_baited_trap(position, LiveTrapEntity.LURE_RANGE)
	if trap != null:
		if state != State.LURED:
			set_state(State.LURED)
		var to := trap.position - position
		to.y = 0.0
		if to.length() < 0.45:
			if trap.capture(kind):
				w.on_trapped(self, trap)
				net.despawn(self)
			return
		_move_toward(trap.position, stalk_speed, dt, water_y)
		return
	var tp := target_pos()
	if tp == Vector3.INF:
		if not w.retarget(self):
			_turned_back("nothing")
		return
	if Perception.is_lit(tp, ctx.lights, LIGHT_RADIUS):
		_turned_back("light")
		return
	if state != State.WANDER:
		set_state(State.WANDER)
	var flat := Vector2(tp.x - position.x, tp.z - position.z).length()
	if flat < reach_radius() and absf(tp.y - position.y) < 0.8:
		w.resolve_raid(self)
		if is_carrying():
			set_state(State.RETURN)
		elif state == State.WANDER:
			set_state(State.REPELLED)   # took what it came for
		return
	_move_toward(tp, stalk_speed, dt, water_y)
	# No way in? Circle the other way for a while, then give up.
	if flat < _best_dist - 0.4:
		_best_dist = flat
		_stuck_t = 0.0
	else:
		_stuck_t += dt
		if _stuck_t > 7.0:
			_stuck_t = 0.0
			_prefer_side = -_prefer_side
			_best_dist = flat
	_stalled_t += dt
	if _stalled_t > GIVE_UP_AFTER and flat < 14.0:
		_turned_back("fence")


func _move_toward(to: Vector3, speed: float, dt: float, water_y: float) -> void:
	var dir := to - position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var d := ground_move_around(dir.normalized(), speed, dt, water_y, _prefer_side)
	if d != Vector3.ZERO:
		turn_toward(d, 8.0, dt)


func _go_home(dt: float, water_y: float, speed: float) -> void:
	var to := den - position
	to.y = 0.0
	if to.length() < 1.5 or state_t > 45.0:
		if is_carrying():
			director().prey_lost(self)
		net.despawn(self)
		return
	var d := ground_move_around(to.normalized(), speed, dt, water_y, _prefer_side)
	if d == Vector3.ZERO:
		_prefer_side = -_prefer_side
		# Truly boxed in (e.g. shut inside a pen): squeeze back the way we came.
		if state_t > 20.0:
			if is_carrying():
				director().drop_prey(self)
			net.despawn(self)
	else:
		turn_toward(d, 8.0, dt)


## Clients: feathers fly when a bird is grabbed (seen as the switch to RETURN).
func _check_grab_fx() -> void:
	var carrying_now := state == State.RETURN
	if carrying_now and not _was_carrying and WildlifeFX.current != null:
		WildlifeFX.current.feathers(position)
	_was_carrying = carrying_now
