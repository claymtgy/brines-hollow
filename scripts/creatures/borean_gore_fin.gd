class_name BoreanGoreFin
extends Creature
## Borean Gore-Fin (The Glacial Patriarch): Biome 4 (The Frost-Shoals) Boss.
## A colossal armored arctic whale-beast armed with twin forward-swept glacial tusks.
##
## Mechanics:
##   Twin Glacial Tusks: Impaling charge attacks that shatter wooden boats and ice.
##   Tusk Lodging: Dodging its ramming charge causes its tusks to lodge into ice/terrain,
##                 staggering the beast for 8s and exposing its flank for 2.5x damage!
##   Blubber Carapace: Frontal strikes suffer 75% damage deflection.

const CHARGE_SPEED := 8.5
const SWIM_SPEED := 3.4
const RAM_RANGE := 14.0
const LODGE_DURATION := 8.0

var lair := Vector3.ZERO
var lodged := false
var _lodge_t := 0.0
var _charge_cd := 4.0
var _charging := false
var _charge_dir := Vector3.ZERO
var _swim_phase := 0.0

var body: Node3D
var tusk_l: Node3D
var tusk_r: Node3D
var tail: Node3D
var fin_l: Node3D
var fin_r: Node3D


func _init() -> void:
	hostile = true
	kind = &"borean_gore_fin"
	max_hp = 450.0
	hp = max_hp
	radius = 3.0
	max_poise = 90.0
	poise = max_poise
	damageable = true


func is_armored() -> bool:
	return not lodged


func drops() -> Array:
	return [
		[&"glacial_tusk", 2],
		[&"borean_fur", 4],
		[&"ancient_weapon_fragment", 2]
	]


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)

	# 1. Colossal hydrodynamic pale-blue/white whale torso
	var g := Prefabs.Grid.new(18, 12, 34)
	g.box(3, 2, 8, 14, 10, 28, Palette.WHITEWASH)        # thick blubber body
	g.box(4, 3, 2, 13, 9, 8, Palette.STONE)             # armored skull plate
	g.box(4, 1, 6, 13, 3, 24, Palette.SANDSTONE_C)      # ventral grooves
	part(body, g, Vector3(-9, -6, -17))

	# 2. Massive curving Glacial Tusks (ivory)
	tusk_l = pivot(body, Vector3(-5, -2, 16))
	tusk_r = pivot(body, Vector3(5, -2, 16))
	var tg := Prefabs.Grid.new(3, 4, 14)
	tg.box(0, 0, 0, 2, 3, 11, Palette.SANDSTONE_A)
	tg.box(1, 1, 10, 2, 3, 13, Palette.CLEAR)
	tg.setv(1, 2, 13, Palette.WHITEWASH)                # sharp tip
	part(tusk_l, tg, Vector3(-1.5, -2, 0))
	part(tusk_r, tg, Vector3(-1.5, -2, 0))

	# 3. Pectoral steering flippers
	fin_l = pivot(body, Vector3(-9, -2, 4))
	fin_r = pivot(body, Vector3(9, -2, 4))
	var fg := Prefabs.Grid.new(12, 2, 10)
	fg.box(0, 0, 0, 11, 1, 9, Palette.WHITEWASH)
	part(fin_l, fg, Vector3(-12, -1, -5))
	part(fin_r, fg, Vector3(0, -1, -5))

	# 4. Muscular tail & flukes
	tail = pivot(body, Vector3(0, 0, -16))
	var tail_g := Prefabs.Grid.new(16, 3, 12)
	tail_g.box(1, 1, 0, 14, 2, 8, Palette.WHITEWASH)
	tail_g.box(0, 1, 8, 15, 2, 11, Palette.WHITEWASH)    # flukes
	part(tail, tail_g, Vector3(-8, -1.5, -6))


func on_hit(damage: float, hit_origin: Vector3, poise_dmg: float = 1.0, weapon_type: int = 0) -> bool:
	if lodged:
		damage *= 2.50  # 2.5x critical damage when tusks are lodged
	elif is_armored():
		var to_hit := hit_origin - position
		if facing().dot(to_hit.normalized()) > 0.3:
			damage *= 0.25  # 75% deflection on frontal tusk/skull hits
	return super.on_hit(damage, hit_origin, poise_dmg, weapon_type)


func lodge_tusks() -> void:
	if lodged:
		return
	lodged = true
	_charging = false
	_lodge_t = LODGE_DURATION
	vel = Vector3.ZERO
	CombatAudio.play_sound("poise_break", position)
	set_state(State.STAGGER)


func _tick_ai(ctx: Dictionary, dt: float) -> void:
	if state == State.DEAD:
		return

	if lodged:
		_lodge_t -= dt
		if _lodge_t <= 0.0:
			lodged = false
			CombatAudio.play_sound("tell_roar", position)
			set_state(State.ALERT)
		return

	_charge_cd -= dt
	var players: Array = ctx.get("players", [])
	if players.is_empty():
		_patrol(dt)
		return

	var target := _nearest_target(players)
	if target.is_empty():
		_patrol(dt)
		return

	var to_target: Vector3 = target.pos - position
	var dist := to_target.length()

	if _charging:
		vel = _charge_dir * CHARGE_SPEED
		# Check for impact with terrain / ice wall
		if state_t >= 2.2:
			_charging = false
			lodge_tusks()
		return

	turn_toward(to_target, 2.0, dt)

	match state:
		State.IDLE, State.ALERT:
			if dist <= RAM_RANGE and _charge_cd <= 0.0:
				set_state(State.WINDUP)
			else:
				vel = facing() * SWIM_SPEED
		State.WINDUP:
			vel = vel.lerp(Vector3.ZERO, dt * 3.0)
			if state_t >= 1.2:
				_charging = true
				_charge_cd = 7.0
				_charge_dir = facing()
				CombatAudio.play_sound("tell_roar", position)
				set_state(State.STRIKE)
		State.STRIKE:
			if not _charging and state_t >= 1.0:
				set_state(State.ALERT)
		State.STAGGER:
			if state_t >= CombatMath.STAGGER_TIME and not lodged:
				set_state(State.ALERT)


func _patrol(dt: float) -> void:
	if lair == Vector3.ZERO:
		lair = position
	var to_lair := lair - position
	if to_lair.length() > 30.0:
		turn_toward(to_lair, 1.4, dt)
	vel = facing() * 2.2


func _nearest_target(players: Array) -> Dictionary:
	var best_d := 60.0
	var best := {}
	for pl in players:
		var d := position.distance_to(pl.pos)
		if d < best_d:
			best_d = d
			best = pl
	return best


func animate(delta: float) -> void:
	_swim_phase += delta * (3.0 if _charging else (0.4 if lodged else 1.8))

	# Tail flukes stroke
	if tail != null:
		tail.rotation.x = sin(_swim_phase) * (0.45 if not lodged else 0.1)

	# Pectoral flippers roll
	if fin_l != null and fin_r != null:
		var fin_roll := sin(_swim_phase + 1.2) * 0.25
		fin_l.rotation.z = -fin_roll
		fin_r.rotation.z = fin_roll
