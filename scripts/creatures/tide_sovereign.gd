class_name TideSovereign
extends Creature
## The Tide Sovereign (World Hydro-Engine): The Final Climax Boss at The Maelstrom Spire.
## An ancient pre-deluge construct governing the global ocean currents and floodwaters.
##
## Mechanics:
##   Hydro-Dynamic Barrier: Surrounded by rotating vortex shields that absorb damage.
##   Cavitation Shockwaves: Emits sonic water rings that push players backward.
##   Deluge Restoration: Defeating the Sovereign recalibrates the world hydro-engine,
##                       calming the perpetual storms across the archipelago!

const CAVITATION_CD := 9.0
const CAVITATION_RANGE := 16.0
const VORTEX_SPEED := 2.6

var lair := Vector3.ZERO
var barrier_active := true
var _barrier_hp := 120.0
var hydro_barrier: float:
	get: return _barrier_hp
	set(v): _barrier_hp = v
var _cavitation_cd := 4.0
var _spin_phase := 0.0

var body: Node3D
var ring_outer: Node3D
var ring_inner: Node3D
var core_crystal: Node3D
var _glow_light: OmniLight3D


func _init() -> void:
	hostile = true
	kind = &"tide_sovereign"
	max_hp = 650.0
	hp = max_hp
	radius = 3.5
	max_poise = 120.0
	poise = max_poise
	damageable = true


func is_armored() -> bool:
	return barrier_active


func drops() -> Array:
	return [
		[&"sovereign_trident", 1],
		[&"deluge_core", 1],
		[&"ancient_weapon_fragment", 4]
	]


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)

	# 1. Monolithic floating ancient core
	var g := Prefabs.Grid.new(16, 24, 16)
	g.box(3, 4, 3, 12, 19, 12, Palette.BEDROCK)
	g.box(5, 7, 5, 10, 16, 10, Palette.GLOW_TEAL)          # hydro core
	g.box(4, 2, 4, 11, 4, 11, Palette.STONE)
	g.box(4, 19, 4, 11, 21, 11, Palette.STONE)
	part(body, g, Vector3(-8, -12, -8))

	# 2. Concentric rotating brass gimbal rings
	ring_outer = pivot(body, Vector3.ZERO)
	var rg1 := Prefabs.Grid.new(22, 2, 22)
	rg1.box(0, 0, 0, 21, 1, 21, Palette.METAL)
	rg1.box(2, 0, 2, 19, 1, 19, Palette.CLEAR)
	part(ring_outer, rg1, Vector3(-11, -1, -11))

	ring_inner = pivot(body, Vector3.ZERO)
	var rg2 := Prefabs.Grid.new(18, 18, 2)
	rg2.box(0, 0, 0, 17, 17, 1, Palette.METAL)
	rg2.box(2, 2, 0, 15, 15, 1, Palette.CLEAR)
	part(ring_inner, rg2, Vector3(-9, -9, -1))

	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(0.1, 0.95, 0.85)
	_glow_light.light_energy = 2.5
	_glow_light.omni_range = 18.0
	body.add_child(_glow_light)


func on_hit(damage: float, hit_origin: Vector3, poise_dmg: float = 1.0, weapon_type: int = 0) -> bool:
	if barrier_active:
		_barrier_hp -= damage
		if _barrier_hp <= 0.0:
			barrier_active = false
			CombatAudio.play_sound("poise_break", position)
			set_state(State.STAGGER)
		return true
	return super.on_hit(damage, hit_origin, poise_dmg, weapon_type)


func _tick_ai(ctx: Dictionary, dt: float) -> void:
	if state == State.DEAD:
		return

	_cavitation_cd -= dt
	var players: Array = ctx.get("players", [])
	if players.is_empty():
		return

	var target := _nearest_target(players)
	if target.is_empty():
		return

	var to_target: Vector3 = target.pos - position
	var dist := to_target.length()

	match state:
		State.IDLE, State.ALERT:
			if dist <= CAVITATION_RANGE and _cavitation_cd <= 0.0:
				set_state(State.WINDUP)
			else:
				vel = facing() * 1.5
		State.WINDUP:
			vel = Vector3.ZERO
			if state_t >= 1.5:
				_unleash_cavitation(ctx)
				set_state(State.STRIKE)
		State.STRIKE:
			if state_t >= 1.0:
				set_state(State.ALERT)
		State.STAGGER:
			if state_t >= CombatMath.STAGGER_TIME and not barrier_active:
				barrier_active = true
				_barrier_hp = 80.0
				set_state(State.ALERT)


func _unleash_cavitation(ctx: Dictionary) -> void:
	_cavitation_cd = CAVITATION_CD
	CombatAudio.play_sound("plunge_land", position)

	if net != null and authority:
		for pl: Dictionary in ctx.get("players", []):
			var to_pl: Vector3 = pl.pos - position
			if to_pl.length() <= CAVITATION_RANGE:
				net.hurt_player(pl.id, 32.0, position, self)


func _nearest_target(players: Array) -> Dictionary:
	var best_d := 75.0
	var best := {}
	for pl in players:
		var d := position.distance_to(pl.pos)
		if d < best_d:
			best_d = d
			best = pl
	return best


func animate(delta: float) -> void:
	_spin_phase += delta * (4.0 if barrier_active else 0.8)

	if ring_outer != null:
		ring_outer.rotation.y = _spin_phase
	if ring_inner != null:
		ring_inner.rotation.x = _spin_phase * 0.75
