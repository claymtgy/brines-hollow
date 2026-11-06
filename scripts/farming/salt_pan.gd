class_name SaltPan
extends RefCounted
## Tidal salt evaporation pan.
## Submerged at high tide, evaporates during low tide under sun, yielding Sea Salt.

signal salt_crystallized(pan: SaltPan, count: int)

var pos: Vector3i = Vector3i.ZERO
var brine_level: float = 0.0          ## 0.0 to 1.0 (water volume in the pan)
var evaporation_progress: float = 0.0 ## 0.0 to 1.0
var accumulated_salt: int = 0
const MAX_SALT: int = 20
const EVAPORATION_RATE: float = 0.02  ## per sunny low-tide second


func _init(p_pos: Vector3i = Vector3i.ZERO) -> void:
	pos = p_pos


func tick(delta_sec: float, current_tide_y: float, is_daylight: bool, is_raining: bool) -> void:
	# 1. High tide submergence: fills pan with fresh ocean brine
	if float(pos.y) <= current_tide_y:
		brine_level = 1.0
		evaporation_progress = 0.0
		return

	# 2. Rain dilutes the pan
	if is_raining:
		evaporation_progress = max(0.0, evaporation_progress - 0.05 * delta_sec)
		return

	# 3. Daylight evaporation
	if is_daylight and brine_level > 0.0:
		evaporation_progress += EVAPORATION_RATE * delta_sec
		if evaporation_progress >= 1.0:
			evaporation_progress = 0.0
			brine_level = 0.0 # fully dried
			var yield_amount: int = 2 # 2 sea salt per evaporation cycle
			accumulated_salt = min(MAX_SALT, accumulated_salt + yield_amount)
			salt_crystallized.emit(self, accumulated_salt)


func harvest() -> int:
	var count: int = accumulated_salt
	accumulated_salt = 0
	return count


func serialize() -> Dictionary:
	return {
		"x": pos.x, "y": pos.y, "z": pos.z,
		"brine": brine_level,
		"progress": evaporation_progress,
		"salt": accumulated_salt
	}


static func deserialize(d: Dictionary) -> SaltPan:
	var pan := SaltPan.new(Vector3i(d["x"], d["y"], d["z"]))
	pan.brine_level = float(d.get("brine", 0.0))
	pan.evaporation_progress = float(d.get("progress", 0.0))
	pan.accumulated_salt = int(d.get("salt", 0))
	return pan
