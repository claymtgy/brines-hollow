class_name CalderaShell
extends Creature
## The Caldera Shell (Ignis-Chelon): Biome 3 (The Basalt Skerries & Sunken Ruins) Boss.
## A colossal volcanic sea-turtle that superheats the surrounding waters and vents boiling steam.
##
## Mechanics:
##   Molten Basalt Shell: While molten, shrugs off 80% of incoming damage.
##   Steam Geyser Burst: Vents pressurized boiling steam in an 11m radius.
##   Thermal Shock: Cold benthic currents or high tide water influx thermal-shocks
##                  the shell, cracking the carapace, stunning it for 9s, and opening 2.5x damage!

const STEAM_CD := 8.0
const STEAM_RANGE := 11.0
const SWIM_SPEED := 3.2
const THERMAL_SHOCK_DURATION := 9.0

var lair := Vector3.ZERO
var molten := true
var _thermal_shock_t := 0.0
var _steam_cd := 3.0
var _swim_phase := 0.0

var body: Node3D
var shell_mesh: Node3D
var head_neck: Node3D
var flipper_fl: Node3D
var flipper_fr: Node3D
var flipper_bl: Node3D
var flipper_br: Node3D
var _magma_light: OmniLight3D


func _init() -> void:
	hostile = true
	kind = &"caldera_shell"
	max_hp = 240.0
	hp = max_hp
	radius = 2.8
	max_poise = 80.0
	poise = max_poise
	damageable = true


func is_armored() -> bool:
	return molten and _thermal_shock_t <= 0.0


func drops() -> Array:
	return [
		[&"geothermal_core", 1],
		[&"caldera_basalt_plate", 4],
		[&"ancient_weapon_fragment", 1]
	]


func _build_visuals(root: Node3D) -> void:
	body = Node3D.new()
	root.add_child(body)

	# 1. Massive domed basalt & magma shell
	var g := Prefabs.Grid.new(20, 10, 24)
	g.box(2, 2, 2, 17, 8, 21, Palette.BEDROCK)            # black obsidian/basalt carapace
	g.box(4, 8, 4, 15, 9, 19, Palette.STONE)              # volcanic rim
	g.box(3, 4, 3, 16, 7, 20, Palette.ROOF_RED)           # glowing magma fissures
	shell_mesh = part(body, g, Vector3(-10, -3, -12))

	# Magma ambient glow
	_magma_light = OmniLight3D.new()
	_magma_light.light_color = Color(1.0, 0.45, 0.15)
	_magma_light.light_energy = 2.2
	_magma_light.omni_range = 14.0
	_magma_light.position = Vector3(0, 1.5, 0)
	body.add_child(_magma_light)

	# 2. Armored turtle head & neck
	head_neck = pivot(body, Vector3(0, 0, 12))
	var hg := Prefabs.Grid.new(8, 6, 10)
	hg.box(1, 1, 1, 6, 4, 8, Palette.BEDROCK)
	hg.box(2, 1, 7, 5, 3, 9, Palette.SANDSTONE_A)         # sharp volcanic beak
	part(head_neck, hg, Vector3(-4, -2, 0))

	# 3. Four colossal swimming flippers
	flipper_fl = pivot(body, Vector3(-9, 0, 8))
	flipper_fr = pivot(body, Vector3(9, 0, 8))
	flipper_bl = pivot(body, Vector3(-8, 0, -8))
	flipper_br = pivot(body, Vector3(8, 0, -8))

	var fg := Prefabs.Grid.new(12, 2, 8)
	fg.box(0, 0, 0, 11, 1, 7, Palette.BEDROCK)
	part(flipper_fl, fg, Vector3(-11, -1, -4))
	part(flipper_fr, fg, Vector3(0, -1, -4))
	part(flipper_bl, fg, Vector3(-11, -1, -4))
	part(flipper_br, fg, Vector3(0, -1, -4))


func on_hit(damage: float, hit_origin: Vector3, poise_dmg: float = 1.0, weapon_type: int = 0) -> bool:
	if is_armored():
		damage *= 0.20  # 80% basalt resistance while molten
	elif _thermal_shock_t > 0.0:
		damage *= 2.50  # 2.5x critical damage when thermal-shocked
	return super.on_hit(damage, hit_origin, poise_dmg, weapon_type)


func thermal_shock() -> void:
	if _thermal_shock_t > 0.0:
		return
	_thermal_shock_t = THERMAL_SHOCK_DURATION
	molten = false
	if _magma_light != null:
		_magma_light.light_energy = 0.4
		_magma_light.light_color = Color(0.3, 0.6, 0.9)
	CombatAudio.play_sound("poise_break", position)
	set_state(State.STAGGER)


func _tick_ai(ctx: Dictionary, dt: float) -> void:
	if state == State.DEAD:
		return

	# Handle thermal shock countdown
	if _thermal_shock_t > 0.0:
		_thermal_shock_t -= dt
		if _thermal_shock_t <= 0.0:
			molten = true
			if _magma_light != null:
				_magma_light.light_energy = 2.2
				_magma_light.light_color = Color(1.0, 0.45, 0.15)
			CombatAudio.play_sound("tell_roar", position)
		return

	_steam_cd -= dt
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
	turn_toward(to_target, 1.8, dt)

	# High-tide cold water vulnerability check:
	var water_level: float = ctx.get("water_level", 11.5)
	if position.y < water_level - 12.0 and water_level > 12.0:
		# Influx of cold water at high tide can trigger thermal shock
		if randf() < 0.01:
			thermal_shock()
			return

	match state:
		State.IDLE, State.ALERT:
			if dist <= 8.0 and _steam_cd <= 0.0:
				set_state(State.WINDUP)
			else:
				vel = facing() * SWIM_SPEED
		State.WINDUP:
			vel = vel.lerp(Vector3.ZERO, dt * 4.0)
			if state_t >= 1.4:
				_unleash_steam_geyser(ctx)
				set_state(State.STRIKE)
		State.STRIKE:
			if state_t >= 1.0:
				set_state(State.ALERT)
		State.STAGGER:
			if state_t >= CombatMath.STAGGER_TIME and _thermal_shock_t <= 0.0:
				set_state(State.ALERT)


func _unleash_steam_geyser(ctx: Dictionary) -> void:
	_steam_cd = STEAM_CD
	CombatAudio.play_sound("plunge_land", position)

	if net != null and authority:
		for pl: Dictionary in ctx.get("players", []):
			var to_pl: Vector3 = pl.pos - position
			if to_pl.length() <= STEAM_RANGE:
				net.hurt_player(pl.id, 28.0, position, self)


func _patrol(dt: float) -> void:
	if lair == Vector3.ZERO:
		lair = position
	var to_lair := lair - position
	if to_lair.length() > 22.0:
		turn_toward(to_lair, 1.2, dt)
	vel = facing() * 1.8


func _nearest_target(players: Array) -> Dictionary:
	var best_d := 50.0
	var best := {}
	for pl in players:
		var d := position.distance_to(pl.pos)
		if d < best_d:
			best_d = d
			best = pl
	return best


func animate(delta: float) -> void:
	_swim_phase += delta * (2.0 if _thermal_shock_t <= 0.0 else 0.4)

	# Flipper swimming strokes
	if flipper_fl != null and flipper_fr != null:
		var stroke := sin(_swim_phase) * 0.45
		flipper_fl.rotation.z = -stroke
		flipper_fr.rotation.z = stroke
	if flipper_bl != null and flipper_br != null:
		var rear_stroke := sin(_swim_phase + 1.0) * 0.30
		flipper_bl.rotation.z = -rear_stroke
		flipper_br.rotation.z = rear_stroke

	# Head nodding / steam windup
	if head_neck != null:
		var target_pitch := -0.35 if state == State.WINDUP else sin(_swim_phase * 0.5) * 0.1
		head_neck.rotation.x = lerpf(head_neck.rotation.x, target_pitch, delta * 6.0)
