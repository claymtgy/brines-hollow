class_name Gull
extends Creature
## Gulls: daytime flocks wheeling over the shore and docks. Never hurt anyone.
##
## On Tidewatch/Undertow a bold gull may swoop on a player who stands still holding a
## raw fish and steal it. Non-combat answer: keep moving, or stow the fish. Swinging at
## or running through the flock scatters it (gulls can't be harmed).

const CIRCLE_SPEED := 0.45     # rad/s around the flock centre
const STEAL_PATIENCE := 5.0    # seconds of standing still with a fish before a swoop

var flock_center := Vector3.ZERO
var circle_r := 7.0
var altitude := 7.0
var angle := 0.0
var wing_l: Node3D
var wing_r: Node3D
var _flap := 0.0
var _scatter_dir := Vector3.ZERO
var _swoop_from := Vector3.ZERO
var _flight_phase: float = 0.0
var _glide_timer: float = 2.0
var _is_gliding: bool = false
var _bank_target: float = 0.0


func _init() -> void:
	kind = &"gull"
	max_hp = 1.0
	hp = 1.0
	damageable = false
	radius = 0.35
	_flight_phase = randf() * TAU
	_glide_timer = randf_range(2.0, 5.0)
	circle_r = randf_range(7.0, 13.0)
	altitude = randf_range(6.5, 9.5)


func _build_visuals(root: Node3D) -> void:
	var b := Prefabs.Grid.new(3, 3, 7)
	b.box(0, 0, 1, 2, 2, 5, Palette.WHITEWASH)
	b.box(0, 2, 1, 2, 2, 3, Palette.STONE)          # grey back
	b.box(0, 1, 6, 2, 2, 6, Palette.WHITEWASH)      # head
	b.setv(1, 1, 7 - 1, Palette.WHITEWASH)
	b.box(1, 0, 0, 1, 1, 0, Palette.STONE)          # tail
	part(root, b, Vector3(-1.5, -1.5, -3.5))
	var beak := Prefabs.Grid.new(1, 1, 2)
	beak.box(0, 0, 0, 0, 0, 1, Palette.BUOY)
	part(root, beak, Vector3(-0.5, 0, 3.5))
	var eye := Prefabs.Grid.new(3, 1, 1)
	eye.setv(0, 0, 0, Palette.EYE)
	eye.setv(2, 0, 0, Palette.EYE)
	part(root, eye, Vector3(-1.5, 0.6, 2.6))
	wing_l = pivot(root, Vector3(-1.5, 0.5, 0))
	wing_r = pivot(root, Vector3(1.5, 0.5, 0))
	for i in 2:
		var w := Prefabs.Grid.new(7, 1, 3)
		w.box(0, 0, 0, 6, 0, 2, Palette.WHITEWASH)
		w.box(5, 0, 0, 6, 0, 2, Palette.BEDROCK)    # dark wingtips
		var mi := part(wing_l if i == 0 else wing_r, w, Vector3(-7 if i == 0 else 0, 0, -1.5))
		if i == 0:
			mi.scale.x = -1.0
			mi.position.x = 0.0


func telegraph_height() -> float:
	return 0.5


func hint() -> String:
	return "Gulls eye unattended fish. Keep moving or stow your catch."


func hint_ready(player: Node) -> bool:
	var inv: Inventory = player.get("inventory") if player != null else null
	if inv == null:
		return false
	for s: ItemSlot in inv.slots:
		if s != null and not s.is_empty():
			var d: ItemDef = ItemDB.get_item(s.item_id)
			if d != null and d.has_tag("fish"):
				return true
	return false


func on_hit(_damage: float, from: Vector3, _power: float, _attacker: int) -> bool:
	_scatter_dir = (position - from).normalized()
	set_state(State.FLEE)
	return true


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	if ctx.night > 0.6:
		net.despawn(self)  # gulls roost at night
		return
	var p := nearest_player(ctx)
	match state:
		State.FLEE:
			if _scatter_dir == Vector3.ZERO:
				_scatter_dir = Vector3(rng.randf_range(-1, 1), 0.6, rng.randf_range(-1, 1)).normalized()
			position += (_scatter_dir + Vector3.UP * 0.5).normalized() * 7.0 * dt
			turn_toward(_scatter_dir, 6.0, dt)
			if state_t > 4.0:
				_scatter_dir = Vector3.ZERO
				set_state(State.RETURN)
			return
		State.WINDUP:
			# Hovering cry before the swoop. Moving away calls it off.
			if p.is_empty() or p.speed > 2.0 or not p.holding_fish:
				set_state(State.FLEE)
				return
			var wl: Variant = net.get("wildlife")
			if wl != null and wl.near_scarecrow(p.pos):
				set_state(State.FLEE)   # a scarecrow nearby: not worth the risk
				return
			position = position.lerp(Vector3(p.pos.x, p.pos.y + 3.0, p.pos.z), 1.0 - exp(-dt * 2.0))
			if state_t >= CombatMath.windup_time(0.9, ctx.difficulty):
				_swoop_from = position
				set_state(State.STRIKE)
			return
		State.STRIKE:
			if p.is_empty():
				set_state(State.RETURN)
				return
			var head: Vector3 = p.pos + Vector3.UP * 1.5
			position = position.move_toward(head, 9.0 * dt)
			turn_toward(head - position, 10.0, dt)
			if position.distance_to(head) < 0.6:
				net.steal_fish(p.id, self)
				_scatter_dir = Vector3(rng.randf_range(-1, 1), 1.0, rng.randf_range(-1, 1)).normalized()
				set_state(State.FLEE)
			elif state_t > 2.5:
				set_state(State.FLEE)
			return
	# Natural coastal soaring and gliding path: wide sweeping loops, banking, and thermals
	_flight_phase += (CIRCLE_SPEED * 0.75) * dt
	angle = _flight_phase
	var r_x := circle_r * (1.0 + sin(_flight_phase * 0.45) * 0.35)
	var r_z := (circle_r * 0.8) * (1.0 + cos(_flight_phase * 0.6) * 0.3)
	var alt_thermal := sin(_flight_phase * 1.4) * 0.9 + cos(_flight_phase * 0.6) * 0.6
	var want := flock_center + Vector3(
		cos(_flight_phase) * r_x + sin(_flight_phase * 0.5) * 3.0,
		altitude + alt_thermal,
		sin(_flight_phase) * r_z + cos(_flight_phase * 0.35) * 2.5
	)
	var to := want - position
	var flight_spd: float = 6.5 if state == State.RETURN else (4.2 + sin(_flight_phase * 1.2) * 1.1)
	position += to.limit_length(flight_spd * dt) if state == State.RETURN else to * (1.0 - exp(-dt * 2.6))
	var aim_dir := to.normalized() if to.length_squared() > 0.04 else facing()
	turn_toward(aim_dir, 3.8, dt)

	# Calculate banking angle based on turning sharpness
	var cross_y := facing().cross(aim_dir).y
	_bank_target = clampf(cross_y * 1.8, -0.45, 0.45)

	# Gliding vs flapping cadence
	_glide_timer -= dt
	if _glide_timer <= 0.0:
		_is_gliding = not _is_gliding
		_glide_timer = randf_range(3.5, 6.0) if _is_gliding else randf_range(2.0, 3.5)

	if state == State.RETURN and to.length() < 1.0:
		set_state(State.WANDER)
	elif state != State.RETURN:
		set_state(State.WANDER)
	# Running through the flock scatters it.
	if not p.is_empty() and p.sprinting and p.pos.distance_to(Vector3(position.x, p.pos.y, position.z)) < 3.0:
		_scatter_dir = (position - p.pos).normalized()
		set_state(State.FLEE)


func animate(dt: float) -> void:
	var rate := 14.0 if state in [State.FLEE, State.RETURN] else (6.0 if state != State.WINDUP else 18.0)
	if state == State.WANDER and _is_gliding:
		# Gliding: wings extended flat, slight breeze wobble
		wing_l.rotation.z = 0.05 + sin(_flap * 0.5) * 0.03
		wing_r.rotation.z = -0.05 - sin(_flap * 0.5) * 0.03
	else:
		_flap += dt * rate
		var a := sin(_flap) * (0.7 if rate > 6.0 else 0.25) + 0.15
		wing_l.rotation.z = a
		wing_r.rotation.z = -a

	var bank_dest := _bank_target if state == State.WANDER else (0.0 if state != State.FLEE else -0.3)
	_visual_root.rotation.z = lerpf(_visual_root.rotation.z, bank_dest, 1.0 - exp(-dt * 4.0))
