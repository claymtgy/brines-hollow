class_name DualSenseManager
extends RefCounted
## Manages DualSense (PS5) adaptive triggers, RGB lightbar,
## and direct HID / UDP report delivery.

signal triggers_updated(left_trigger: DualSenseTrigger, right_trigger: DualSenseTrigger)
signal lightbar_updated(color: Color)

static var instance: DualSenseManager

var left_trigger: DualSenseTrigger = DualSenseTrigger.new()
var right_trigger: DualSenseTrigger = DualSenseTrigger.new()
var lightbar_color: Color = Color(0.2, 0.6, 1.0) # Ocean Azure default

# Connection & Transports
var is_dualsense_active: bool = false
var udp_peer: PacketPeerUDP
var hidraw_path: String = ""
var _hid_file: FileAccess


func _init() -> void:
	instance = self
	_setup_udp()
	_detect_hidraw()


static func get_instance() -> DualSenseManager:
	if instance == null:
		instance = DualSenseManager.new()
	return instance


func _setup_udp() -> void:
	udp_peer = PacketPeerUDP.new()
	udp_peer.set_dest_address("127.0.0.1", DualSenseConstants.DUALSENSEX_UDP_PORT)


## Detects /dev/hidraw nodes on Linux matching Sony DualSense
func _detect_hidraw() -> void:
	for i in range(16):
		var path := "/dev/hidraw%d" % i
		if FileAccess.file_exists(path):
			# Test if writable
			var f := FileAccess.open(path, FileAccess.READ_WRITE)
			if f != null:
				hidraw_path = path
				_hid_file = f
				break


# -------------------------------------------------------------------------
# Adaptive Trigger Methods (Matches godot-dualsense API)
# -------------------------------------------------------------------------

func get_trigger(hand: DualSenseConstants.Hand) -> DualSenseTrigger:
	return left_trigger if hand == DualSenseConstants.Hand.LEFT else right_trigger


func set_trigger_off(hand: DualSenseConstants.Hand) -> void:
	get_trigger(hand).reset()
	send_output()


func set_trigger_resistance(hand: DualSenseConstants.Hand, start_zone: int, strength: int) -> void:
	get_trigger(hand).set_resistance(start_zone, strength)
	send_output()


func set_trigger_weapon(hand: DualSenseConstants.Hand, start_zone: int, end_zone: int, strength: int) -> void:
	get_trigger(hand).set_weapon(start_zone, end_zone, strength)
	send_output()


func set_trigger_bow(hand: DualSenseConstants.Hand, start_zone: int, end_zone: int, start_strength: int, end_strength: int) -> void:
	get_trigger(hand).set_bow(start_zone, end_zone, start_strength, end_strength)
	send_output()


func set_trigger_vibration(hand: DualSenseConstants.Hand, start_zone: int, amplitude: int, frequency: int) -> void:
	get_trigger(hand).set_vibration(start_zone, amplitude, frequency)
	send_output()


func set_trigger_galloping(hand: DualSenseConstants.Hand, start_zone: int, end_zone: int, first: int, second: int, freq: int) -> void:
	get_trigger(hand).set_galloping(start_zone, end_zone, first, second, freq)
	send_output()


func set_lightbar(color: Color) -> void:
	lightbar_color = color
	lightbar_updated.emit(lightbar_color)
	send_output()


func reset_triggers() -> void:
	left_trigger.reset()
	right_trigger.reset()
	send_output()


# -------------------------------------------------------------------------
# Output Dispatcher
# -------------------------------------------------------------------------

## Sends the constructed output packet to DualSense hardware or bridge.
func send_output() -> void:
	triggers_updated.emit(left_trigger, right_trigger)

	# 1. DualSenseX / UDP bridge packet
	if udp_peer != null:
		var packet := _build_udp_packet()
		udp_peer.put_packet(packet)

	# 2. Raw HIDraw on Linux
	if _hid_file != null and _hid_file.is_open():
		var raw_report := _build_usb_report()
		_hid_file.store_buffer(raw_report)
		_hid_file.flush()


## Builds standard USB HID Report ID 0x02 packet (63 bytes).
func _build_usb_report() -> PackedByteArray:
	var report := PackedByteArray()
	report.resize(63)
	report.fill(0)

	report[0] = DualSenseConstants.USB_REPORT_ID
	report[1] = 0x01 | 0x02 # valid_flag0: enable rumble + haptics
	report[2] = 0x04 | 0x08 # valid_flag1: enable right trigger + left trigger effects

	# Right trigger block (bytes 14 to 24)
	var r_bytes := right_trigger.to_bytes()
	for i in r_bytes.size():
		report[14 + i] = r_bytes[i]

	# Left trigger block (bytes 25 to 35)
	var l_bytes := left_trigger.to_bytes()
	for i in l_bytes.size():
		report[25 + i] = l_bytes[i]

	# Lightbar RGB (bytes 45 to 47)
	report[45] = int(clampf(lightbar_color.r, 0.0, 1.0) * 255.0)
	report[46] = int(clampf(lightbar_color.g, 0.0, 1.0) * 255.0)
	report[47] = int(clampf(lightbar_color.b, 0.0, 1.0) * 255.0)

	return report


func _build_udp_packet() -> PackedByteArray:
	var msg: Dictionary = {
		"controllerIndex": 0,
		"LeftTrigger": left_trigger.to_dict(),
		"RightTrigger": right_trigger.to_dict(),
		"RGB": [
			int(lightbar_color.r * 255.0),
			int(lightbar_color.g * 255.0),
			int(lightbar_color.b * 255.0)
		]
	}
	var json_str := JSON.stringify(msg)
	return json_str.to_utf8_buffer()


# -------------------------------------------------------------------------
# Brine's Hollow Contextual Trigger Presets
# -------------------------------------------------------------------------

## Fishing: As player charges cast, trigger pulls back like a bending rod.
func apply_fishing_cast(power_fraction: float) -> void:
	var strength := clampi(int(power_fraction * 7.0) + 1, 1, 8)
	var start_pos := clampi(int((1.0 - power_fraction) * 4.0), 0, 5)
	right_trigger.set_bow(start_pos, 8, 2, strength)
	set_lightbar(Color(0.2, 0.8, 1.0).lerp(Color(1.0, 0.8, 0.2), power_fraction))
	send_output()


## Fishing: Sharp mechanical snap when the hook window telegraphs.
func apply_fishing_bite() -> void:
	right_trigger.set_weapon(1, 4, 8)
	set_lightbar(Color(1.0, 0.2, 0.1)) # Urgent Red alert
	send_output()


## Fishing: Tension pushback & thrashing vibration while reeling.
func apply_fishing_reeling(line_tension: float, is_thrashing: bool) -> void:
	if line_tension >= 0.82:
		# Extreme tension: hard trigger stop at start position to prevent snapping
		right_trigger.set_resistance(1, 8)
		set_lightbar(Color(1.0, 0.05, 0.05)) # Critical red
	elif is_thrashing:
		# Fish fighting: vibrating resistance
		var freq := clampi(int(line_tension * 25.0) + 10, 10, 35)
		right_trigger.set_vibration(2, 6, freq)
		set_lightbar(Color(1.0, 0.5, 0.0)) # Warning amber
	else:
		# Smooth reeling resistance proportional to tension
		var force := clampi(int(line_tension * 6.0) + 1, 1, 7)
		right_trigger.set_resistance(3, force)
		set_lightbar(Color(0.2, 0.7, 0.9)) # Normal sea blue
	send_output()


## Coastal Agriculture: Mechanical break when tilling soil, gentle feel when planting seeds.
func apply_farming_till() -> void:
	right_trigger.set_weapon(2, 5, 7)
	set_lightbar(Color(0.4, 0.8, 0.2)) # Plant green
	send_output()


func apply_farming_sow() -> void:
	left_trigger.set_resistance(4, 3)
	send_output()


## Mining / Building: Heavy limestone resistance vs light sand/mud.
func apply_mining(voxel_mat: int) -> void:
	if voxel_mat == Palette.STONE or voxel_mat == Palette.COBBLE:
		right_trigger.set_weapon(1, 5, 8) # Hard mineral break
	elif voxel_mat == Palette.DIRT or voxel_mat == Palette.GRAVEL:
		right_trigger.set_resistance(3, 4) # Dense soil resistance
	else:
		right_trigger.reset()
	send_output()


## Maritime Rowing: Heavy hydraulic resistance during water stroke, free on recovery.
func apply_rowing(row_power: float, row_phase: float) -> void:
	var stroke := sin(row_phase)
	if row_power > 0.1 and stroke > 0.1:
		# Blade in water: dual trigger hydraulic drag
		var drag := clampi(int(stroke * row_power * 7.0) + 1, 1, 8)
		right_trigger.set_resistance(2, drag)
		left_trigger.set_resistance(2, drag)
		set_lightbar(Color(0.1, 0.4, 0.95))
	else:
		# Blade in air: featherweight recovery
		right_trigger.reset()
		left_trigger.reset()
	send_output()
