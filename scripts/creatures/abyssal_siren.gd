class_name AbyssalSiren
extends Creature
## The Abyssal Siren: Biome 2 (The Murk-Reef) Boss.
## A colossal prehistoric coelacanth leviathan stalking the deep 30m kelp trenches.
##
## Mechanics:
##   Direct Combat: Armored deep-sea scales grant heavy damage reduction.
##   Sonic Shriek: Charges an underwater sonic blast that pushes and dazes players.
##   Environmental Stun: Igniting a submerged Phosphor Brazier overloads its eyes,
##                      stunning it for 8 seconds and exposing its underbelly for 2.5x damage!
##   Trapper Netting: Throwing nets or harpoons slows its swim speed.

const SHRIEK_CD := 10.0
const SONIC_RANGE := 16.0
const SWIM_SPEED := 5.5

var lair := Vector3.ZERO
var body_mesh: MeshInstance3D
var tail_lobe: Node3D
var fin_l: Node3D
var fin_r: Node3D
var jaw: Node3D

var _shriek_cd := 4.0
var _swim_phase := 0.0
var _stun_timer := 0.0


func _init() -> void:
	max_hp = 180.0
	hp = max_hp
	radius = 2.4
	damageable = true
	max_poise = 60.0
	poise = max_poise


func is_armored() -> bool:
	return _stun_timer <= 0.0


func _build_visuals(root: Node3D) -> void:
	var g := Prefabs.Grid.new(16, 10, 32)
	# Massive coelacanth torso & deep scale plates
	g.box(3, 2, 8, 12, 8, 26, Palette.COBBLE)           # dark abyssal body
	g.box(4, 3, 2, 11, 7, 7, Palette.STONE)             # armored snout & cranium
	g.box(4, 1, 6, 11, 3, 12, Palette.SANDSTONE_A)      # pale vulnerable underbelly
	g.box(2, 4, 12, 13, 6, 22, Palette.KELP)            # bio-luminescent scale trim

	body_mesh = part(root, g, Vector3(-8, -5, -16))

	# Articulated Lower Jaw (hinges open for sonic shriek)
	jaw = pivot(root, Vector3(0, -2, -10))
	var jg := Prefabs.Grid.new(8, 3, 8)
	jg.box(1, 0, 0, 6, 2, 7, Palette.STONE)
	part(jaw, jg, Vector3(-4, -1.5, -4))

	# Pectoral Paddle Fins
	fin_l = pivot(root, Vector3(-7, -1, -2))
	var fg_l := Prefabs.Grid.new(8, 2, 8)
	fg_l.box(0, 0, 0, 7, 1, 7, Palette.KELP)
	part(fin_l, fg_l, Vector3(-4, -1, -4))

	fin_r = pivot(root, Vector3(7, -1, -2))
	var fg_r := Prefabs.Grid.new(8, 2, 8)
	fg_r.box(0, 0, 0, 7, 1, 7, Palette.KELP)
	part(fin_r, fg_r, Vector3(-4, -1, -4))

	# Triple-Lobed Coelacanth Tail
	tail_lobe = pivot(root, Vector3(0, 0, 16))
	var tg := Prefabs.Grid.new(4, 12, 10)
	tg.box(1, 0, 0, 2, 11, 9, Palette.KELP)
	part(tail_lobe, tg, Vector3(-2, -6, 0))


func drops() -> Array:
	return [
		[&"siren_heart", 1],
		[&"abyssal_chitin", 4],
		[&"sea_glass", 3]
	]


func _on_windup_started() -> void:
	CombatAudio.play_sound("tell_screech", position, 3.0, 0.05)


func on_phosphor_stun() -> void:
	_stun_timer = 8.0
	poise = 0.0
	set_state(State.STAGGER)
	CombatAudio.play_sound("poise_break", position)


func on_hit(dmg: float, from: Vector3, power: float, attacker: int) -> bool:
	if state == State.DEAD:
		return false
	# If stunned by phosphor, takes 2.5x massive vulnerability damage
	var final_dmg := dmg * (2.5 if _stun_timer > 0.0 else 0.45)
	var ok := super.on_hit(final_dmg, from, power * (2.0 if _stun_timer > 0.0 else 0.5), attacker)
	return ok


func simulate(dt: float, ctx: Dictionary) -> void:
	state_t += dt
	_shriek_cd = maxf(0.0, _shriek_cd - dt)

	if _stun_timer > 0.0:
		_stun_timer -= dt
		vel = vel.lerp(Vector3.ZERO, dt * 2.0)
		return

	var target := _nearest_target(ctx.players)
	if target.is_empty():
		_patrol_lair(dt)
		return

	var to_p: Vector3 = target.pos - position
	var dist := to_p.length()
	turn_toward(to_p, 2.5, dt)

	match state:
		State.IDLE, State.ALERT:
			if dist < 8.0 and _shriek_cd <= 0.0:
				set_state(State.WINDUP)
			else:
				var spd := SWIM_SPEED
				vel = facing() * spd
		State.WINDUP:
			vel = vel.lerp(Vector3.ZERO, dt * 3.0)
			if state_t >= 1.2:
				_unleash_sonic_shriek(target)
				set_state(State.STRIKE)
		State.STRIKE:
			if state_t >= 0.8:
				set_state(State.ALERT)
		State.STAGGER:
			if state_t >= CombatMath.STAGGER_TIME and _stun_timer <= 0.0:
				set_state(State.ALERT)


func _unleash_sonic_shriek(target: Dictionary) -> void:
	_shriek_cd = SHRIEK_CD
	CombatAudio.play_sound("plunge_land", position)

	# Sonic pulse hitting nearby players in front
	if net != null and authority:
		for pl: Dictionary in target.get("all_players", [target]):
			var to_pl: Vector3 = pl.pos - position
			if to_pl.length() <= SONIC_RANGE:
				var fwd := facing()
				if fwd.dot(to_pl.normalized()) > 0.35:
					net.hurt_player(pl.id, 24.0, position, self)


func _patrol_lair(dt: float) -> void:
	if lair == Vector3.ZERO:
		lair = position
	var to_lair := lair - position
	if to_lair.length() > 20.0:
		turn_toward(to_lair, 1.5, dt)
	vel = facing() * 3.0


func _nearest_target(players: Array) -> Dictionary:
	var best_d := 45.0
	var best := {}
	for pl in players:
		var d := position.distance_to(pl.pos)
		if d < best_d:
			best_d = d
			best = pl
	if not best.is_empty():
		best["all_players"] = players
	return best


func animate(delta: float) -> void:
	_swim_phase += delta * (2.5 if _stun_timer <= 0.0 else 0.5)

	# Tail undulating stroke
	if tail_lobe != null:
		tail_lobe.rotation.y = sin(_swim_phase) * 0.45

	# Fins paddling
	if fin_l != null and fin_r != null:
		var fin_ang := sin(_swim_phase + 1.2) * 0.35
		fin_l.rotation.z = -fin_ang
		fin_r.rotation.z = fin_ang

	# Jaw gaping during sonic windup
	if jaw != null:
		var target_jaw := 0.75 if state == State.WINDUP else 0.05
		jaw.rotation.x = lerpf(jaw.rotation.x, target_jaw, delta * 8.0)
