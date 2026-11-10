class_name AbyssalAngler
extends Creature
## Deep-Sea Apex Predator: stalks the deep waters of Biome 3 (The Sunken Ruins).
## Uses a bioluminescent glowing esca (lure) to disorient prey in pitch darkness,
## then executes ferocious aquatic ambush lunges.

const SWIM_SPEED := 2.2
const CHARGE_SPEED := 7.0
const ATTACK_RANGE := 3.2
const BITE_DAMAGE := 20.0
const LURE_PULSE_CD := 6.0

var _body: Node3D
var _jaw: Node3D
var _lure_light: OmniLight3D
var _fin_l: Node3D
var _fin_r: Node3D
var _pulse_cd := 0.0
var _charge_dir := Vector3.ZERO
var _swim_phase := 0.0


func _init() -> void:
	kind = &"abyssal_angler"
	max_hp = 55.0
	hp = 55.0
	poise = 30.0
	max_poise = 30.0
	hostile = true
	radius = 0.65


func _build_visuals(root: Node3D) -> void:
	_body = Node3D.new()
	root.add_child(_body)

	# Deep black/obsidian bulbous fish body
	var b := Prefabs.Grid.new(8, 7, 10)
	b.box(1, 1, 1, 6, 5, 8, Palette.BEDROCK)
	# Needle teeth
	b.box(1, 1, 8, 6, 2, 9, Palette.WHITEWASH)
	# Bioluminescent Lure stalk
	b.box(3, 5, 7, 4, 7, 8, Palette.METAL)
	b.setv(3, 7, 9, Palette.GLOW_TEAL)           # Esca bulb
	part(_body, b, Vector3(-4, -3, -5))

	# Lower Jaw
	_jaw = Node3D.new()
	_body.add_child(_jaw)
	var j := Prefabs.Grid.new(8, 2, 6)
	j.box(1, 0, 0, 6, 1, 5, Palette.BEDROCK)
	j.box(2, 1, 4, 5, 1, 5, Palette.WHITEWASH)
	part(_jaw, j, Vector3(-4, -1, 0))
	_jaw.position = Vector3(0, -0.2, 0.4)

	# Esca Lure Light
	_lure_light = OmniLight3D.new()
	_lure_light.light_color = Color(0.2, 0.95, 0.85)
	_lure_light.light_energy = 1.6
	_lure_light.omni_range = 8.0
	_lure_light.position = Vector3(0, 0.6, 0.8)
	_body.add_child(_lure_light)


func drops() -> Array:
	return [
		[&"angler_lure", 1],
		[&"abyssal_pearl", 1],
		[&"raw_fish", 2]
	]


func simulate(dt: float, ctx: Dictionary) -> void:
	if state == State.DEAD:
		return
	_swim_phase += dt * 3.0
	_pulse_cd = maxf(0.0, _pulse_cd - dt)

	var target: Dictionary = _nearest_target(ctx.get("players", []))
	var has_target: bool = not target.is_empty()

	match state:
		State.IDLE, State.WANDER:
			if has_target and position.distance_to(target.pos) <= 14.0:
				set_state(State.ALERT)
			else:
				# Gentle hovering patrol
				vel = vel.lerp(Vector3.ZERO, dt * 1.5)
				_jaw.rotation.x = sin(_swim_phase * 0.5) * 0.1

		State.ALERT:
			if not has_target or position.distance_to(target.pos) > 18.0:
				set_state(State.IDLE)
				return
			var to_target: Vector3 = (target.pos - position).normalized()
			turn_toward(to_target, 2.0, dt)
			vel = vel.lerp(to_target * SWIM_SPEED, dt * 2.0)

			if position.distance_to(target.pos) <= 5.5 and _pulse_cd <= 0.0:
				_charge_dir = to_target
				set_state(State.WINDUP)
				_on_windup_started()

		State.WINDUP:
			vel = vel.lerp(-_charge_dir * 0.5, dt * 3.0) # pull back
			_jaw.rotation.x = lerpf(_jaw.rotation.x, -0.4, dt * 8.0) # open wide
			_lure_light.light_energy = 3.5
			if state_t >= 0.65:
				set_state(State.STRIKE)

		State.STRIKE:
			_pulse_cd = LURE_PULSE_CD
			_lure_light.light_energy = 1.5
			vel = _charge_dir * CHARGE_SPEED
			_jaw.rotation.x = lerpf(_jaw.rotation.x, 0.2, dt * 12.0) # snap shut
			CombatAudio.play_sound("swing_heavy", position)

			if has_target and position.distance_to(target.pos) <= ATTACK_RANGE:
				if net != null and authority:
					net.hurt_player(target.id, BITE_DAMAGE, position, self)
				CombatAudio.play_sound("hit_flesh", position)
				set_state(State.RECOVER)
			elif state_t >= 0.8:
				set_state(State.RECOVER)

		State.RECOVER:
			vel = vel.lerp(Vector3.ZERO, dt * 3.0)
			if state_t >= 1.2:
				set_state(State.ALERT if has_target else State.IDLE)

		State.STAGGER:
			vel = vel.lerp(Vector3.ZERO, dt * 4.0)
			if state_t >= 1.8:
				set_state(State.ALERT)

	position += vel * dt


func _nearest_target(players: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 999.0
	for pl: Dictionary in players:
		var d: float = position.distance_to(pl.pos)
		if d < best_d:
			best_d = d
			best = pl
	return best
