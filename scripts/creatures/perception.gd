class_name Perception
extends RefCounted
## How creatures notice players: sight cone, noise, light. Pure functions.
##
## Sneaking (hold Ctrl / back paddle) shrinks your noise to almost nothing, and in the
## dark creatures see much less far, so you can slip past most things unseen.

const LIGHT_REPEL_RADIUS := 4.5   # metres: lamps and lanterns keep cave eels away


## How far away a player can be heard.
static func noise_radius(speed: float, sneaking: bool, sprinting: bool, in_water: bool) -> float:
	if speed < 0.3:
		return 0.8
	if sneaking:
		return 1.3
	var r := 9.0 if sprinting else 4.0
	if in_water:
		r *= 1.4  # splashing carries
	return r


## Sight cone check. `darkness` 0..1 shortens sight range (night, caves).
static func can_see(eye: Vector3, facing: Vector3, fov_deg: float, sight_range: float,
		target: Vector3, darkness: float = 0.0) -> bool:
	var to := target - eye
	var dist := to.length()
	var rng := sight_range * lerpf(1.0, 0.35, clampf(darkness, 0.0, 1.0))
	if dist > rng:
		return false
	if dist < 0.6:
		return true
	return rad_to_deg(facing.normalized().angle_to(to / dist)) <= fov_deg * 0.5


## Full detection test: heard OR seen.
static func detects(eye: Vector3, facing: Vector3, fov_deg: float, sight_range: float,
		target: Vector3, noise_r: float, darkness: float = 0.0, alertness: float = 1.0) -> bool:
	if eye.distance_to(target) <= noise_r * alertness:
		return true
	return can_see(eye, facing, fov_deg, sight_range * alertness, target, darkness)


## Is `p` lit by any of the light positions (lamps, held lanterns)?
static func is_lit(p: Vector3, lights: Array, radius: float = LIGHT_REPEL_RADIUS) -> bool:
	for l: Vector3 in lights:
		if p.distance_squared_to(l) <= radius * radius:
			return true
	return false
