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
const DODGE_COOLDOWN := 0.55
const PARRY_WINDOW := 0.28        # s after pressing parry in which a hit is deflected
const PARRY_COOLDOWN := 0.8
const PARRY_ARC_DEG := 110.0      # attacker must be roughly in front
const STAGGER_TIME := 1.4         # creature stunned after a parry
const STAGGER_DAMAGE_MULT := 1.5
const UNARMED := {"damage": 4, "attack_rate": 1.4, "reach_m": 1.4, "stamina_per_swing": 6.0, "stagger_power": 0.6}


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
	if in_water:
		d *= float(stats.get("underwater_efficiency", 0.5))
	if target_staggered:
		d *= STAGGER_DAMAGE_MULT
	return d


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
static func parry_succeeds(since_press: float, defender: Vector3, facing: Vector3, attacker: Vector3) -> bool:
	if since_press < 0.0 or since_press > PARRY_WINDOW:
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


## Knockback impulse (m/s) away from the source.
static func knockback(from: Vector3, to: Vector3, power: float) -> Vector3:
	var d := to - from
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3.FORWARD
	return d.normalized() * 3.5 * power + Vector3.UP * 1.5 * power
