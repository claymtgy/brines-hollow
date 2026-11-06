class_name DualSenseTrigger
extends RefCounted
## Holds the 11-byte configuration state for a single DualSense adaptive trigger.

var mode: DualSenseConstants.TriggerMode = DualSenseConstants.TriggerMode.OFF
var params: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])


func _init() -> void:
	reset()


func reset() -> void:
	mode = DualSenseConstants.TriggerMode.OFF
	params = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])


## Configures continuous feedback resistance.
## start_pos: 0 (immediate) to 9 (near bottom of trigger pull)
## force: 0 (none) to 8 (maximum resistance)
func set_resistance(start_pos: int, force: int) -> void:
	mode = DualSenseConstants.TriggerMode.FEEDBACK
	params = PackedByteArray([
		clampi(start_pos, 0, 9),
		clampi(force, 0, 8),
		0, 0, 0, 0, 0, 0, 0, 0
	])


## Configures a two-stage weapon trigger with a crisp mechanical break.
## start_pos: position where resistance begins
## end_pos: position where trigger snaps
## force: resistance strength before release
func set_weapon(start_pos: int, end_pos: int, force: int) -> void:
	mode = DualSenseConstants.TriggerMode.WEAPON
	params = PackedByteArray([
		clampi(start_pos, 0, 8),
		clampi(end_pos, start_pos + 1, 9),
		clampi(force, 0, 8),
		0, 0, 0, 0, 0, 0, 0
	])


## Configures a bow-draw resistance curve.
func set_bow(start_pos: int, end_pos: int, start_force: int, end_force: int) -> void:
	mode = DualSenseConstants.TriggerMode.BOW
	params = PackedByteArray([
		clampi(start_pos, 0, 8),
		clampi(end_pos, start_pos + 1, 9),
		clampi(start_force, 0, 8),
		clampi(end_force, start_force, 8),
		0, 0, 0, 0, 0, 0
	])


## Configures high-frequency vibration along trigger pull.
func set_vibration(start_pos: int, amplitude: int, frequency_hz: int) -> void:
	mode = DualSenseConstants.TriggerMode.MACHINE
	params = PackedByteArray([
		clampi(start_pos, 0, 9),
		clampi(amplitude, 0, 8),
		clampi(frequency_hz, 1, 40),
		0, 0, 0, 0, 0, 0, 0
	])


## Configures rhythmic galloping resistance.
func set_galloping(start_pos: int, end_pos: int, first_foot: int, second_foot: int, freq: int) -> void:
	mode = DualSenseConstants.TriggerMode.GALLOPING
	params = PackedByteArray([
		clampi(start_pos, 0, 8),
		clampi(end_pos, start_pos + 1, 9),
		clampi(first_foot, 0, 8),
		clampi(second_foot, 0, 8),
		clampi(freq, 1, 40),
		0, 0, 0, 0, 0
	])


## Formats the 11-byte trigger block according to Sony HID spec.
func to_bytes() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append(mode)
	bytes.append_array(params)
	return bytes


## Formats dictionary description for DualSenseX / network bridges.
func to_dict() -> Dictionary:
	var name_str := "Off"
	match mode:
		DualSenseConstants.TriggerMode.FEEDBACK: name_str = "Resistance"
		DualSenseConstants.TriggerMode.WEAPON: name_str = "Weapon"
		DualSenseConstants.TriggerMode.BOW: name_str = "Bow"
		DualSenseConstants.TriggerMode.MACHINE, DualSenseConstants.TriggerMode.VIBRATION: name_str = "Vibration"
		DualSenseConstants.TriggerMode.GALLOPING: name_str = "Galloping"
	return {
		"mode": name_str,
		"raw_mode": mode,
		"params": Array(params)
	}
