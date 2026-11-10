class_name CombatMath
extends RefCounted
## Pure combat rules (no scene access) so they can be unit-tested.
##
## Pillar 3: every threat has a non-combat answer. Combat is optional and the numbers
## here are deliberately forgiving on Tidewatch; Undertow is the "challenge by choice".

enum Difficulty { COZY, TIDEWATCH, UNDERTOW }
const DIFFICULTY_NAMES := ["Cozy", "Tidewatch", "Undertow"]

const DODGE_TIME := 0.38          # i-frames + roll duration (s)
const DODGE_SPEED := 8.5          # m/s during the roll
const DODGE_STAMINA := 14.0
const DODGE_COOLDOWN := 0.45
const PARRY_WINDOW := 0.28        # s after pressing parry in which a hit is deflected
const PARRY_COOLDOWN := 0.6
const PARRY_ARC_DEG := 110.0      # attacker must be roughly in front
const STAGGER_TIME := 1.4         # creature stunned after a parry
const STAGGER_DAMAGE_MULT := 1.5
const UNARMED := {"damage": 4, "attack_rate": 1.4, "reach_m": 1.4, "stamina_per_swing": 6.0, "stagger_power": 0.6}

# Guard arc & stamina mechanics
const GUARD_ARC_DEG := 120.0
const GUARD_STAMINA_RATIO := 1.2
const GUARD_BREAK_DURATION := 0.85

# Riposte mechanics
const RIPOSTE_WINDOW := 1.5
const RIPOSTE_DAMAGE_MULT := 2.5
const RIPOSTE_STAGGER_MULT := 2.5

# Combo mechanics (Light 1 -> Light 2 -> Heavy Finisher)
const COMBO_WINDOW := 0.9
const COMBO_STEP_1_MULT := 1.0
const COMBO_STEP_2_MULT := 1.2
const COMBO_STEP_3_MULT := 1.6
const COMBO_STEP_1_STAGGER := 1.0
const COMBO_STEP_2_STAGGER := 1.3
const COMBO_STEP_3_STAGGER := 2.0
const COMBO_STEP_1_LUNGE := 2.2
const COMBO_STEP_2_LUNGE := 2.8
const COMBO_STEP_3_LUNGE := 4.2

# Charged attack mechanics
const CHARGE_TIME_MIN := 0.45
const CHARGE_DAMAGE_MULT := 2.0
const CHARGE_STAGGER_MULT := 2.5
const CHARGE_LUNGE_SPEED := 5.0
const CHARGE_STAMINA_MULT := 1.8

# Sprint engage cleave
const SPRINT_ENGAGE_MULT := 1.25
const SPRINT_ENGAGE_STAGGER := 1.4
const SPRINT_ENGAGE_LUNGE := 4.2

# Aerial / Plunging attack
const PLUNGE_AOE_RADIUS := 3.5
const PLUNGE_DAMAGE_MULT := 1.75
const PLUNGE_STAGGER_MULT := 2.2

# Poise & Hit-Stop
const HITSTOP_LIGHT := 0.04
const HITSTOP_HEAVY := 0.08
const POISE_PER_STAGGER_POINT := 10.0
const DEFAULT_CREATURE_POISE := 20.0


## Creature damage dealt to players, scaled by difficulty. Cozy never hurts.
static func incoming_damage(base: float, difficulty: int) -> float:
	match difficulty:
		Difficulty.COZY: return 0.0
		Difficulty.UNDERTOW: return base * 1.6
	return base


## Creature health scaled by difficulty.
static func creature_hp(base: float, difficulty: int) -> float:
	return base * (1.5 if difficulty == Difficulty.UNDERTOW else 1.0)


## Windup (telegraph) length: Undertow gives less time to react.
static func windup_time(base: float, difficulty: int) -> float:
	return base * (0.75 if difficulty == Difficulty.UNDERTOW else 1.0)


static func hostiles_allowed(difficulty: int) -> bool:
	return difficulty != Difficulty.COZY


## Weapon stats from an ItemDef (or the unarmed fallback when def is null).
static func weapon_stats(def: ItemDef) -> Dictionary:
	var s := UNARMED.duplicate()
	if def == null:
		return s
	var wd: Dictionary = def.weapon_data if not def.weapon_data.is_empty() else def.tool_data
	s["damage"] = float(wd.get("damage", s.damage))
	s["attack_rate"] = float(wd.get("attack_rate", wd.get("speed", 1.0)))
	s["reach_m"] = float(wd.get("reach_m", wd.get("reach", 2.0)))
	s["stagger_power"] = float(wd.get("stagger_power", 1.0))
	s["underwater_efficiency"] = float(wd.get("underwater_efficiency", 0.5))
	s["stamina_per_swing"] = float(wd.get("stamina_per_swing", 8.0 + float(s.damage) * 0.25))
	s["weapon_type"] = int(wd.get("weapon_type", WeaponDef.WeaponType.CUTLASS))
	return s


## Damage a swing deals to a creature.
static func outgoing_damage(stats: Dictionary, target_staggered: bool, in_water: bool) -> float:
	var d: float = float(stats.damage)
	if stats.has("damage_mult"):
		d *= float(stats.damage_mult)
	if in_water:
		d *= float(stats.get("underwater_efficiency", 0.5))
	if target_staggered:
		d *= STAGGER_DAMAGE_MULT
	return d


## Multiplier for a combo step (1 = Light 1, 2 = Light 2, 3 = Heavy Finisher)
static func combo_multiplier(step: int) -> float:
	match step:
		2: return COMBO_STEP_2_MULT
		3: return COMBO_STEP_3_MULT
		_: return COMBO_STEP_1_MULT


static func combo_stagger_multiplier(step: int) -> float:
	match step:
		2: return COMBO_STEP_2_STAGGER
		3: return COMBO_STEP_3_STAGGER
		_: return COMBO_STEP_1_STAGGER


static func combo_lunge_speed(step: int) -> float:
	match step:
		2: return COMBO_STEP_2_LUNGE
		3: return COMBO_STEP_3_LUNGE
		_: return COMBO_STEP_1_LUNGE


## Does a guard stance facing direction block an attack from attacker?
static func guard_succeeds(defender: Vector3, facing: Vector3, attacker: Vector3, max_arc_deg: float = GUARD_ARC_DEG) -> bool:
	var to := attacker - defender
	to.y = 0.0
	if to.length() < 0.05:
		return true
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	return rad_to_deg(f.angle_to(to.normalized())) <= max_arc_deg * 0.5


## Calculate guard block damage absorption & stamina consumption
static func calculate_guard_block(incoming: float, current_stamina: float, difficulty: int = Difficulty.TIDEWATCH, guard_efficiency: float = 1.0) -> Dictionary:
	if incoming <= 0.0:
		return {"blocked": true, "damage_taken": 0.0, "stamina_cost": 0.0, "guard_broken": false}
	var eff: float = maxf(0.1, guard_efficiency)
	var stamina_needed := maxf(6.0 * eff, incoming * GUARD_STAMINA_RATIO * eff)
	if current_stamina >= stamina_needed:
		var chip: float = incoming * (0.15 if difficulty == Difficulty.UNDERTOW else 0.0) * eff
		return {"blocked": true, "damage_taken": chip, "stamina_cost": stamina_needed, "guard_broken": false}
	# Stamina depleted -> Guard Break!
	var blocked_ratio: float = clampf(current_stamina / stamina_needed, 0.0, 1.0)
	var damage_taken: float = incoming * (1.0 - blocked_ratio * 0.5)
	return {"blocked": false, "damage_taken": damage_taken, "stamina_cost": current_stamina, "guard_broken": true}


## Calculate complete strike parameters based on attack type and modifiers
static func build_strike_stats(base_stats: Dictionary, combo_step: int, is_charged: bool, is_sprint: bool, is_riposte: bool) -> Dictionary:
	var s: Dictionary = base_stats.duplicate()
	var d_mult: float = 1.0
	var s_mult: float = 1.0
	var lunge: float = combo_lunge_speed(combo_step)
	var is_finisher: bool = false

	if is_riposte:
		d_mult = RIPOSTE_DAMAGE_MULT
		s_mult = RIPOSTE_STAGGER_MULT
		lunge = 3.5
	elif is_charged:
		d_mult = CHARGE_DAMAGE_MULT
		s_mult = CHARGE_STAGGER_MULT
		lunge = CHARGE_LUNGE_SPEED
		is_finisher = true
	elif is_sprint:
		d_mult = SPRINT_ENGAGE_MULT
		s_mult = SPRINT_ENGAGE_STAGGER
		lunge = SPRINT_ENGAGE_LUNGE
	else:
		d_mult = combo_multiplier(combo_step)
		s_mult = combo_stagger_multiplier(combo_step)
		is_finisher = (combo_step == 3)

	s["damage_mult"] = d_mult
	s["stagger_mult"] = s_mult
	s["lunge_speed"] = lunge
	s["is_finisher"] = is_finisher
	s["is_charged"] = is_charged
	s["is_riposte"] = is_riposte
	s["effective_damage"] = float(s.get("damage", 4.0)) * d_mult
	s["effective_stagger"] = float(s.get("stagger_power", 1.0)) * s_mult
	return s


## Is `target` inside a melee swing from `origin` facing `forward` (horizontal arc)?
static func in_swing_arc(origin: Vector3, forward: Vector3, target: Vector3, reach: float, arc_deg: float = 120.0, target_radius: float = 0.4) -> bool:
	var to := target - origin
	if absf(to.y) > 1.6:
		return false
	to.y = 0.0
	var dist := to.length()
	if dist > reach + target_radius:
		return false
	if dist < 0.35:
		return true
	var f := Vector3(forward.x, 0.0, forward.z).normalized()
	return rad_to_deg(f.angle_to(to.normalized())) <= arc_deg * 0.5


## Does a parry started `since_press` seconds ago deflect an attack from `attacker`?
static func parry_succeeds(since_press: float, defender: Vector3, facing: Vector3, attacker: Vector3, max_window: float = PARRY_WINDOW) -> bool:
	if since_press < 0.0 or since_press > max_window:
		return false
	var to := attacker - defender
	to.y = 0.0
	if to.length() < 0.05:
		return true
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	return rad_to_deg(f.angle_to(to.normalized())) <= PARRY_ARC_DEG * 0.5


## Is the defender inside dodge i-frames?
static func dodge_protects(dodge_elapsed: float) -> bool:
	return dodge_elapsed >= 0.0 and dodge_elapsed <= DODGE_TIME


const HARPOON_SWEET_SPOT_MIN := 2.5
const HARPOON_SWEET_SPOT_MAX := 4.2
const HARPOON_SWEET_SPOT_MULT := 1.35


static func is_harpoon_sweet_spot(dist: float, weapon_type: int) -> bool:
	return weapon_type == WeaponDef.WeaponType.HARPOON and dist >= HARPOON_SWEET_SPOT_MIN and dist <= HARPOON_SWEET_SPOT_MAX


## Knockback impulse (m/s) away from the source.
static func knockback(from: Vector3, to: Vector3, power: float) -> Vector3:
	var d := to - from
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3.FORWARD
	return d.normalized() * 3.5 * power + Vector3.UP * 1.5 * power


## Returns true if the weapon type is classified as a ranged projectile armament.
static func is_ranged_weapon(weapon_type: int) -> bool:
	return weapon_type == WeaponDef.WeaponType.SPEARGUN or weapon_type == WeaponDef.WeaponType.BOW or weapon_type == WeaponDef.WeaponType.FLINTLOCK or weapon_type == WeaponDef.WeaponType.TRAPPER_NET


## Calculates arrow velocity vector based on aim direction and draw charge fraction (0.2 to 1.0).
static func calc_arrow_launch_velocity(aim_dir: Vector3, draw_charge: float, max_speed: float = 38.0) -> Vector3:
	var power: float = clampf(draw_charge, 0.25, 1.0)
	var speed: float = max_speed * power
	# Slight natural upward loft on long-range release
	var loft: Vector3 = Vector3.UP * (0.08 * (1.0 - power))
	return (aim_dir.normalized() + loft).normalized() * speed


## Flintlock point-blank burst damage scaling with distance falloff.
static func calc_flintlock_damage(base_dmg: float, dist_m: float) -> float:
	if dist_m <= 4.0:
		return base_dmg * 1.5 # Point blank blast bonus
	elif dist_m <= 12.0:
		return base_dmg
	elif dist_m <= 22.0:
		return base_dmg * 0.65 # Medium distance falloff
	return 0.0 # Beyond effective range
